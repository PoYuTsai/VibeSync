// 練習室「對話主體意識」（conversation-agency-v1）：結構證據層與 agency policy。
//
// 計畫 `docs/plans/2026-09-03-practice-conversation-agency-plan.md` Phase 1；
// 夥伴報告 §7.1–7.2、§7.5。
//
// 這一層只做「可安全確定」的事：明示換題詞、完全相同 token 重複、上一則是不是 AI
// 問句、連續幾輪都是低資訊形狀。**不用 regex 斷言語意關聯**（「東京一定與韓國無關」
// 「四個字以下一定是亂碼」都不做）——commit d1b3dc5 已經證明廣泛 heuristic 會在
// 記憶、拒絕、界線上 false positive。語意關聯一律交給看得到完整逐字稿的生成模型，
// 在 planner 給的受限選項（bounded choice）裡決定，不多打一次 LLM。
//
// 因此本檔的輸出只有兩種形態：
// - `forced`：高信心結構（同一個詞再丟一次、已質疑過又連續未解）→ 指定一個 act；
// - `bounded`：其餘模糊片段 → 列 2–3 個允許的 act，由同一次生成呼叫挑。
// 玩家這一句只要是問句、第一人稱分享、明示換題、招呼語，或是她剛問完問題而且前面
// 沒有未解片段的短答，本檔一律回 `situation: null`＝不介入，走原本的路徑。

import type { PracticeTurn } from "./validate.ts";
import type { ResponseMode } from "./reply_style.ts";

// 玩家問句判準。原本住在 turn_response_plan.ts；搬到這裡讓依賴單向（planner →
// agency），避免兩個檔互相 import。判準與字面**一字未改**，旗標關閉行為零改動。
// 問句：問號、句尾疑問助詞、或「有沒／了沒」這類台灣口語；「我還沒」不算。
const QUESTION_RE =
  /[?？]$|(嗎|呢|吧|有沒|了沒|飽沒|完沒|好沒|幹嘛|做什麼|做啥|在哪|住哪|幾歲|如何|怎樣|怎麼樣)(裡|啊|呀|喔|哦|啦)?[?？]?$/u;

export function isQuestionText(text: string): boolean {
  return QUESTION_RE.test(text.trim());
}

export const CONVERSATION_AGENCY_VERSION = 1;
export const CONVERSATION_AGENCY_STATE_KEY = "conversationAgency";

/** 旗標解析結果：`off`＝完全不算；`shadow`＝只算證據與 telemetry，不改 prompt。 */
export type AgencyMode = "off" | "shadow" | "on";

export type UtteranceShape =
  | "question"
  | "self_share"
  | "answer_candidate"
  | "bare_fragment"
  | "reaction"
  | "explicit_pivot"
  | "unknown";

export type AgencySituation =
  | "ambiguous_fragment"
  | "abrupt_topic_shift"
  | "repeated_low_coherence";

export type AgencyAct =
  | "ask_intent"
  | "challenge_relevance"
  | "return_to_topic"
  | "hold_position"
  | "end_low_value_loop";

export const AGENCY_ACTS: readonly AgencyAct[] = Object.keys(
  {
    ask_intent: true,
    challenge_relevance: true,
    return_to_topic: true,
    hold_position: true,
    end_low_value_loop: true,
  } satisfies Record<AgencyAct, true>,
) as AgencyAct[];

/** planner 允許清單裡可以出現的 act：既有 ReplyAct ＋ 本層新增的 AgencyAct。 */
export type PlanAct = ResponseMode | AgencyAct;

/** 澄清型 act：不吃「首輪不反問／她剛問過就不再問」的問題預算（報告 §P0-2）。 */
const CLARIFYING_ACTS: readonly PlanAct[] = [
  "ask_intent",
  "challenge_relevance",
  "return_to_topic",
  "clarify",
];

export function isClarifyingAct(act: PlanAct): boolean {
  return CLARIFYING_ACTS.includes(act);
}

export interface AgencyEvidence {
  readonly utteranceShape: UtteranceShape;
  readonly previousAiAskedQuestion: boolean;
  readonly explicitPivot: boolean;
  readonly repeatedExactToken: boolean;
  readonly unresolvedCount: 0 | 1 | 2 | 3;
  readonly priorChallengeIssued: boolean;
  /** 這一句之前，玩家有沒有給過任何非片段內容（分享、問句、明示換題、長句）。 */
  readonly precedingUserContext: boolean;
}

export interface ConversationAgencyState {
  readonly version: 1;
  readonly lastCoherence:
    | "connected"
    | "ambiguous"
    | "disconnected"
    | "repetitive";
  readonly unresolvedCount: 0 | 1 | 2 | 3;
  readonly priorChallengeIssued: boolean;
  readonly lastAgencyAct: AgencyAct | null;
}

export const INITIAL_CONVERSATION_AGENCY_STATE: ConversationAgencyState = {
  version: 1,
  lastCoherence: "connected",
  unresolvedCount: 0,
  priorChallengeIssued: false,
  lastAgencyAct: null,
};

const COHERENCES: readonly ConversationAgencyState["lastCoherence"][] = [
  "connected",
  "ambiguous",
  "disconnected",
  "repetitive",
];

// ── 結構訊號 ──────────────────────────────────────────────────────────────
// 明示換題詞：小型 allowlist，只收台灣人真的會用來宣告轉場的固定詞。多一個詞就多
// 一次誤判，寧可漏（漏了只是走 bounded choice，模型仍看得到全文）。
const EXPLICIT_PIVOT_RE = /(對了|講到|說到|換個話題|欸我想到|突然想到|話說)/u;
// 招呼／情緒反應：短且只由這些構成時算 reaction，不當成需要澄清的片段。
const REACTION_RE =
  /^(嗨+|哈囉|哈啦|安安|你好|妳好|hi|hello|yo|嗯+|喔+|噢+|哦+|好+(的|喔|啊)?|ok|okay|哈+|呵+|笑死|欸+|蛤+|齁+|唉+|哇+|真的假的|了解|收到|感謝|謝謝|晚安|早安|午安|掰掰|bye|[\p{Emoji_Presentation}\p{Extended_Pictographic}\s]+)$/iu;
// 第一人稱標記：只看有沒有「我」這個結構標記，不判斷他在分享什麼。
const FIRST_PERSON_RE = /(我|咱|俺)/u;
// 她自己這一則是不是在問問題。中文問句常常不帶問號（「東東是誰」「你最想去哪」），
// 只看標點會 systematically 判漏。這裡刻意寬鬆：判成「她問過」只會讓玩家的短答被
// 當成有效短答（不質疑），是安全的方向；判漏才會誤傷有效短答。
const AI_QUESTION_RE =
  /[?？]|(嗎|呢|吧)\s*$|(哪|什麼|甚麼|怎樣|怎麼|為何|為什麼|幾點|幾歲|多少|是誰|誰啊|有沒有|要不要|好不好|可不可以)/mu;

export function aiAskedQuestion(text: string): boolean {
  return AI_QUESTION_RE.test(text.trim());
}

/** 短片段長度上限（去空白後的 UTF-16 code units）。超過就不當「裸片段」。 */
const BARE_FRAGMENT_MAX = 8;
/** 只往回看這麼多則玩家訊息（短期工作記憶，不是長期記憶）。 */
const RECENT_USER_WINDOW = 8;

function compact(text: string): string {
  return text.trim().replace(/\s+/g, "");
}

/**
 * 單則玩家訊息的形狀（不看前後文，除了「上一則是不是 AI 問句」）。
 * 順序即優先權：明示換題 > 問句 > 招呼／反應 > 第一人稱分享 > 短答候選 > 裸片段。
 */
export function utteranceShapeOf(
  text: string,
  previousAiAskedQuestion: boolean,
): UtteranceShape {
  const compacted = compact(text);
  if (compacted.length === 0) return "unknown";
  if (EXPLICIT_PIVOT_RE.test(text)) return "explicit_pivot";
  if (isQuestionText(text)) return "question";
  if (REACTION_RE.test(compacted)) return "reaction";
  if (FIRST_PERSON_RE.test(text)) return "self_share";
  const short = compacted.length <= BARE_FRAGMENT_MAX;
  if (previousAiAskedQuestion && short) return "answer_candidate";
  if (short) return "bare_fragment";
  return "unknown";
}

/** 低資訊形狀＝會累積「未解片段」的形狀。 */
function isLowInformation(shape: UtteranceShape): boolean {
  return shape === "bare_fragment" || shape === "answer_candidate";
}

function clamp3(n: number): 0 | 1 | 2 | 3 {
  return Math.max(0, Math.min(3, n)) as 0 | 1 | 2 | 3;
}

/**
 * 從近期逐字稿推導證據。`prev` 是 assisted 模式持久化的狀態（standard 傳 null，
 * 短期狀態全部從逐字稿現推——這一場的片段本來就都在 turns 裡）。
 */
export function detectAgencyEvidence(
  turns: readonly PracticeTurn[],
  prev: ConversationAgencyState | null = null,
): AgencyEvidence {
  const recent = turns.slice(-(RECENT_USER_WINDOW * 2));
  const shapes: {
    text: string;
    shape: UtteranceShape;
    previousAiAskedQuestion: boolean;
  }[] = [];
  let lastAiText: string | null = null;
  for (const turn of recent) {
    if (turn.role === "ai") {
      lastAiText = turn.text;
      continue;
    }
    const previousAiAskedQuestion = lastAiText !== null &&
      aiAskedQuestion(lastAiText);
    shapes.push({
      text: turn.text,
      shape: utteranceShapeOf(turn.text, previousAiAskedQuestion),
      previousAiAskedQuestion,
    });
    lastAiText = null;
  }
  const current = shapes.at(-1);
  const earlier = shapes.slice(0, -1);

  // 未解片段計數：低資訊形狀累加，任何「講得完整」的一則（分享、問句、明示換題、
  // 長句）就是玩家自己把話講清楚了，歸零（報告 §7.5「玩家成功解釋就清零」）。
  // 一律從逐字稿重算，不把 `prev.unresolvedCount` 當起點——同一批 turn 會被重走，
  // 兩者相加會重複計數；逐字稿本來就帶著這一場的全部片段。
  let unresolved = 0;
  for (const s of earlier) {
    if (isLowInformation(s.shape)) unresolved = clamp3(unresolved + 1);
    else if (s.shape !== "reaction") unresolved = 0;
  }
  const compactedCurrent = current ? compact(current.text) : "";
  const repeatedExactToken = compactedCurrent.length > 0 &&
    earlier.some((s) => compact(s.text) === compactedCurrent);
  return {
    utteranceShape: current?.shape ?? "unknown",
    previousAiAskedQuestion: current?.previousAiAskedQuestion ?? false,
    explicitPivot: current?.shape === "explicit_pivot",
    repeatedExactToken,
    unresolvedCount: clamp3(unresolved),
    // standard 沒有持久化狀態，用結構近似：連續兩則未解＝上一輪 planner 一定已經
    // 給過質疑型 act。assisted 有持久化的實際 act 就以它為準。
    // ponytail: 近似值，Phase 3 把 lastAgencyAct 持久化到 standard 就能改成實測。
    priorChallengeIssued: (prev?.priorChallengeIssued ?? false) ||
      unresolved >= 2,
    precedingUserContext: earlier.some((s) =>
      s.shape !== "reaction" && !isLowInformation(s.shape)
    ),
  };
}

// ── policy ────────────────────────────────────────────────────────────────
export interface AgencyDecision {
  readonly version: typeof CONVERSATION_AGENCY_VERSION;
  readonly evidence: AgencyEvidence;
  /** null＝這一輪不介入，走既有 planner 路徑（有效短答、明示換題、分享、問句…）。 */
  readonly situation: AgencySituation | null;
  readonly policyMode: "forced" | "bounded";
  readonly forcedAct: PlanAct | null;
  readonly allowedActs: readonly PlanAct[];
  readonly allowedActSetId: string;
}

const NO_OVERRIDE: Omit<AgencyDecision, "version" | "evidence"> = {
  situation: null,
  policyMode: "forced",
  forcedAct: null,
  allowedActs: [],
  allowedActSetId: "none",
};

/**
 * 證據 → 這一輪的 act 政策。
 *
 * 強制（forced）只給高信心結構：同一個詞原樣再丟一次、或已經質疑過又連續兩則未解。
 * 其餘全部是 bounded choice——她看得到完整逐字稿，「這句到底有沒有關聯」由她判。
 */
export function agencyPolicyFor(evidence: AgencyEvidence): AgencyDecision {
  const base = { version: CONVERSATION_AGENCY_VERSION, evidence } as const;
  const { utteranceShape: shape, unresolvedCount } = evidence;
  // 只介入「低資訊形狀」。問句、第一人稱分享、明示換題、招呼、長句一律不動；
  // 她剛問完問題而且前面沒有未解片段的短答＝有效短答，永遠不得被質疑（報告 §6）。
  if (!isLowInformation(shape)) return { ...base, ...NO_OVERRIDE };
  if (shape === "answer_candidate" && unresolvedCount === 0) {
    return { ...base, ...NO_OVERRIDE };
  }
  if (evidence.repeatedExactToken) {
    return {
      ...base,
      situation: "repeated_low_coherence",
      policyMode: "forced",
      forcedAct: "end_low_value_loop",
      allowedActs: ["end_low_value_loop"],
      allowedActSetId: "repeated_token_v1",
    };
  }
  if (unresolvedCount >= 2) {
    return evidence.priorChallengeIssued
      ? {
        ...base,
        situation: "repeated_low_coherence",
        policyMode: "forced",
        forcedAct: "hold_position",
        allowedActs: ["hold_position"],
        allowedActSetId: "hold_after_challenge_v1",
      }
      : {
        ...base,
        situation: "repeated_low_coherence",
        policyMode: "bounded",
        forcedAct: null,
        allowedActs: [
          "challenge_relevance",
          "return_to_topic",
          "hold_position",
        ],
        allowedActSetId: "low_coherence_v1",
      };
  }
  if (unresolvedCount === 1 || shape === "answer_candidate") {
    // 前一題還沒解決，或她剛問的問題沒被回答：不供應新解讀，但也不強制質疑。
    return {
      ...base,
      situation: "abrupt_topic_shift",
      policyMode: "bounded",
      forcedAct: null,
      allowedActs: ["ask_intent", "challenge_relevance", "return_to_topic"],
      allowedActSetId: "topic_shift_v1",
    };
  }
  // 第一個模糊片段：有前文可對照時「接住」是合理選項，完全沒有前文時把問清楚排前面
  // （報告 §6：沒有前文突然說「韓國」→ 第一次可問意圖／關聯，不先假定）。
  return evidence.precedingUserContext
    ? {
      ...base,
      situation: "ambiguous_fragment",
      policyMode: "bounded",
      forcedAct: null,
      allowedActs: ["acknowledge", "ask_intent"],
      allowedActSetId: "fragment_with_context_v1",
    }
    : {
      ...base,
      situation: "ambiguous_fragment",
      policyMode: "bounded",
      forcedAct: null,
      allowedActs: ["ask_intent", "acknowledge"],
      allowedActSetId: "fragment_no_context_v1",
    };
}

// ── 跨回合狀態（assisted 模式：recent_facts.conversationAgency）──────────
/**
 * 壞資料一律整份 null（Codex：不得靜默轉成有效狀態）。缺 key＝null（舊 thread）。
 * 新 sessionId 天然重置：thread 以 visiblePracticeThreadId／sessionId 為 key，
 * 新一場就是新的 row，沒有上一場的 oddity debt。
 */
export function parseConversationAgencyState(
  recentFacts: unknown,
): ConversationAgencyState | null {
  if (typeof recentFacts !== "object" || recentFacts === null) return null;
  const raw = (recentFacts as Record<string, unknown>)[
    CONVERSATION_AGENCY_STATE_KEY
  ];
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    return null;
  }
  const r = raw as Record<string, unknown>;
  if (r.version !== 1) return null;
  if (
    typeof r.lastCoherence !== "string" ||
    !(COHERENCES as readonly string[]).includes(r.lastCoherence)
  ) return null;
  if (
    typeof r.unresolvedCount !== "number" ||
    !Number.isInteger(r.unresolvedCount) ||
    r.unresolvedCount < 0 || r.unresolvedCount > 3
  ) return null;
  if (typeof r.priorChallengeIssued !== "boolean") return null;
  if (
    r.lastAgencyAct !== null &&
    !(typeof r.lastAgencyAct === "string" &&
      (AGENCY_ACTS as readonly string[]).includes(r.lastAgencyAct))
  ) return null;
  return {
    version: 1,
    lastCoherence: r.lastCoherence as ConversationAgencyState["lastCoherence"],
    unresolvedCount: r.unresolvedCount as 0 | 1 | 2 | 3,
    priorChallengeIssued: r.priorChallengeIssued,
    lastAgencyAct: r.lastAgencyAct as AgencyAct | null,
  };
}

const COHERENCE_BY_SITUATION: Record<
  AgencySituation,
  ConversationAgencyState["lastCoherence"]
> = {
  ambiguous_fragment: "ambiguous",
  abrupt_topic_shift: "disconnected",
  repeated_low_coherence: "repetitive",
};

/** 這一輪的決策決定下一個狀態；只存 enum／布林／小整數，不存玩家原句。 */
export function nextConversationAgencyState(
  prev: ConversationAgencyState | null,
  decision: AgencyDecision,
): ConversationAgencyState {
  const base = prev ?? INITIAL_CONVERSATION_AGENCY_STATE;
  const forced = decision.forcedAct;
  const lastAgencyAct = forced !== null &&
      (AGENCY_ACTS as readonly PlanAct[]).includes(forced)
    ? forced as AgencyAct
    : base.lastAgencyAct;
  return {
    version: 1,
    lastCoherence: decision.situation
      ? COHERENCE_BY_SITUATION[decision.situation]
      : "connected",
    unresolvedCount: decision.evidence.unresolvedCount,
    priorChallengeIssued: base.priorChallengeIssued ||
      decision.evidence.priorChallengeIssued ||
      decision.allowedActs.some((a) =>
        a === "challenge_relevance" || a === "hold_position"
      ),
    lastAgencyAct,
  };
}

/** 旗標字串 → 模式。`test` 只對 TEST_EMAILS 帳號生效。 */
export function agencyModeFor(
  flag: string | undefined,
  accountIsTest: boolean,
): AgencyMode {
  if (flag === "true") return "on";
  if (flag === "shadow") return "shadow";
  if (flag === "test") return accountIsTest ? "on" : "off";
  return "off";
}
