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
// Codex P1：純 regex 會把「先不要換個話題」（否定）、「你每次都說到一半」
// （「說到一半」是抱怨被打斷，不是宣告轉場）跟引號內引用他人的話也判成轉場。
// 用小函式逐一檢查每個詞前面有沒有否定詞、詞後面是不是「一半」、詞是不是被
// 引號包住，寧可漏（漏了只是不觸發 explicit_pivot，仍走其餘 shape 判斷）。
const PIVOT_MARKERS: readonly string[] = [
  "對了",
  "講到",
  "說到",
  "換個話題",
  "欸我想到",
  "突然想到",
  "話說",
];
const PIVOT_NEGATION_RE = /(不要|不想|不用|先不|別|别|沒有要|哪有)$/u;
const QUOTE_PAIRS: readonly (readonly [string, string])[] = [
  ["「", "」"],
  ["『", "』"],
  ['"', '"'],
];

function isQuotedAt(text: string, idx: number): boolean {
  for (const [open, close] of QUOTE_PAIRS) {
    let from = 0;
    while (true) {
      const start = text.indexOf(open, from);
      if (start === -1 || start >= idx) break;
      const end = text.indexOf(close, start + 1);
      if (end === -1) break;
      if (idx > start && idx < end) return true;
      from = end + 1;
    }
  }
  return false;
}

function hasExplicitPivot(text: string): boolean {
  for (const marker of PIVOT_MARKERS) {
    let from = 0;
    while (true) {
      const idx = text.indexOf(marker, from);
      if (idx === -1) break;
      from = idx + marker.length;
      const before = text.slice(Math.max(0, idx - 6), idx);
      if (PIVOT_NEGATION_RE.test(before)) continue;
      if (marker === "說到" && text.slice(idx, idx + 4).includes("一半")) {
        continue;
      }
      if (isQuotedAt(text, idx)) continue;
      return true;
    }
  }
  return false;
}
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

/** 只往回看這麼多則玩家訊息（短期工作記憶，不是長期記憶）。 */
const RECENT_USER_WINDOW = 8;

function compact(text: string): string {
  return text.trim().replace(/\s+/g, "");
}

/**
 * 單則玩家訊息的形狀（不看前後文，除了「上一則是不是 AI 問句」）。
 * 順序即優先權：明示換題 > 問句 > 招呼／反應 > 第一人稱分享 > 短答候選 > 裸片段。
 *
 * Codex round-2 P1-1：**這裡一個字數條件都沒有**。舊版用「去空白後 ≤8 code
 * units」當裸片段的必要條件，等於用長度斷語意——四十個字的「路上那間店招牌
 * 換了新的顏色看起來怪怪的」一樣沒有任何結構線索，卻只因為長就被放行；兩個字
 * 的「韓國」在她剛問完問題時是有效短答，卻只因為短而被算進片段家族。
 *
 * 現在 `bare_fragment` 的定義是**每一個結構線索都不存在**：不是明示換題、
 * 沒有問句標記、不是招呼／情緒反應、沒有第一人稱分享標記、而且她上一則沒有在
 * 問問題。`answer_candidate` 的唯一判準是「她上一則在問問題」。長度不參與。
 */
export function utteranceShapeOf(
  text: string,
  previousAiAskedQuestion: boolean,
): UtteranceShape {
  const compacted = compact(text);
  if (compacted.length === 0) return "unknown";
  if (hasExplicitPivot(text)) return "explicit_pivot";
  if (isQuestionText(text)) return "question";
  if (REACTION_RE.test(compacted)) return "reaction";
  if (FIRST_PERSON_RE.test(text)) return "self_share";
  if (previousAiAskedQuestion) return "answer_candidate";
  return "bare_fragment";
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
  // Codex P1：舊版先用「則數 × 2」window 再過濾角色，隱含嚴格交替假設；連續
  // 同角色（例如同一輪送出多則玩家訊息、或 ai/user 比例不對稱的長逐字稿）會
  // 讓實際取到的玩家則數偏多或偏少。改成先掃全部 turns 取出每則玩家訊息的
  // shape，最後再取最後 RECENT_USER_WINDOW 則——不管中間角色怎麼交錯，
  // 永遠是「最後 N 則玩家訊息」。
  const shapes: {
    text: string;
    shape: UtteranceShape;
    previousAiAskedQuestion: boolean;
  }[] = [];
  let lastAiText: string | null = null;
  for (const turn of turns) {
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
  const windowed = shapes.slice(-RECENT_USER_WINDOW);
  const current = windowed.at(-1);
  const earlier = windowed.slice(0, -1);

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
    // Codex round-2 P1-2：舊版在 standard 用「連續兩則未解＝一定質疑過」當近似
    // 值，那是拿一個計數假裝成一件事實。standard 沒有持久化的 lastAgencyAct，
    // 結構上就是**不知道**她上一輪有沒有真的質疑——所以這裡只認 assisted 模式
    // 持久化下來的旗標，standard 一律 false。standard 的跨輪立場改由逐字稿裡
    // **看得見**的東西撐：她上一則是不是在問問題（`previousAiAskedQuestion`），
    // 那個訊號在 renderTurnPlan 會變成「你上一句已經在問他了，他沒回答就別放過」。
    priorChallengeIssued: prev?.priorChallengeIssued ?? false,
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

/**
 * 一輪的 agency 決策＋是否真的套用（`applied=false`＝shadow 或這一輪不介入，
 * 只記 telemetry）。這是 `ChatPromptBundle.agencyDecision` 與（旗標開時）
 * `TurnResponsePlan` 的 caller 之間共用的形狀——`TurnResponsePlan` 本身只管
 * style，不擁有這個型別（報告 §7.1；Codex P1「與 reply-style 解耦」）。
 */
export interface AgencyApplication {
  readonly decision: AgencyDecision;
  readonly applied: boolean;
}

const NO_OVERRIDE: Omit<AgencyDecision, "version" | "evidence"> = {
  situation: null,
  policyMode: "forced",
  forcedAct: null,
  allowedActs: [],
  allowedActSetId: "none",
};

/**
 * 難度只調門檻與第一個片段的候選 act，不關掉 agency、不動有效短答的免疫
 * （報告 §7.4：「難度只調門檻與口氣，不關掉 agency」）。字面值對應
 * `PracticeDifficulty`（"easy"|"normal"|"challenge"，practice_persona.ts）；
 * 這裡刻意不 import 那個型別，維持本檔「依賴單向」——呼叫端自己轉換。
 */
export interface AgencyThresholds {
  /**
   * 第一個沒有前文的模糊片段，允許的候選 act（難度愈高愈不給「接住」這個選項）。
   * **只有一個元素時就是 forced**（Codex round-2 P1-1：單元素的「bounded」是在
   * telemetry 上說謊，policyMode 要照實記 forced）。
   */
  readonly firstFragmentActs: readonly PlanAct[];
  /** unresolvedCount 累積到這個數字才開始「指出跳題」（topic_shift_v1 bounded）。 */
  readonly topicShiftAt: number;
  /** unresolvedCount 累積到這個數字才進入「repeated_low_coherence」。 */
  readonly lowCoherenceAt: number;
  /** 到了 lowCoherenceAt 又還沒質疑過時，challenge／game 直接強制收尾，不用先走一輪 bounded 質疑。 */
  readonly forceEndLoopBeforeChallenge: boolean;
}

export const AGENCY_THRESHOLDS: Record<
  "easy" | "normal" | "challenge",
  AgencyThresholds
> = {
  // 輕鬆：第一次模糊給「接住」或「問清楚」兩個選項；連續模糊要到第 2–3 則
  // 才開始指出跳題，門檻整體晚一步。
  easy: {
    firstFragmentActs: ["acknowledge", "ask_intent"],
    topicShiftAt: 2,
    lowCoherenceAt: 3,
    forceEndLoopBeforeChallenge: false,
  },
  // 一般：第一個沒前文的片段直接問，不供應「接住」當退路；第 2 則就指出跳題。
  normal: {
    firstFragmentActs: ["ask_intent"],
    topicShiftAt: 1,
    lowCoherenceAt: 2,
    forceEndLoopBeforeChallenge: false,
  },
  // 挑戰：第一則就強制只問意思（跟 normal 同一條 forced，不供應解讀也不供應
  // 「接住」）；連續模糊到第 2 則就可以直接收掉，不用先走一輪「再給一次機會」
  // 的 bounded 質疑。質疑的火力差異放在後面的門檻，不放在第一則。
  challenge: {
    firstFragmentActs: ["ask_intent"],
    topicShiftAt: 1,
    lowCoherenceAt: 2,
    forceEndLoopBeforeChallenge: true,
  },
};

/** Game 模式套挑戰難度門檻（既有 Game FSM 的修復優先／越界／邀約方向不受影響，由呼叫端保留原優先權）。 */
export function agencyThresholdsFor(
  difficulty: "easy" | "normal" | "challenge",
  isGame: boolean,
): AgencyThresholds {
  return isGame ? AGENCY_THRESHOLDS.challenge : AGENCY_THRESHOLDS[difficulty];
}

/**
 * 證據 → 這一輪的 act 政策。
 *
 * 強制（forced）只給高信心結構：同一個詞原樣再丟一次、或已經質疑過又連續未解
 * 到門檻。其餘全部是 bounded choice——她看得到完整逐字稿，「這句到底有沒有
 * 關聯」由她判。省略 `thresholds`＝一般難度（呼叫端不接難度時逐字沿用舊行為）。
 */
export function agencyPolicyFor(
  evidence: AgencyEvidence,
  thresholds: AgencyThresholds = AGENCY_THRESHOLDS.normal,
): AgencyDecision {
  const base = { version: CONVERSATION_AGENCY_VERSION, evidence } as const;
  const { utteranceShape: shape, unresolvedCount } = evidence;
  // 只介入「低資訊形狀」。問句、第一人稱分享、明示換題、招呼、長句一律不動；
  // 她剛問完問題而且前面沒有未解片段的短答＝有效短答，永遠不得被質疑（報告 §6）
  // ——這條與難度無關，任何難度都不會翻轉。
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
  // Codex round-1 P1-c：她上一則在問問題，這一句就**有可能是答案**——不管前面
  // 累積了多少未解片段。舊版把「有欠債的 answer_candidate」丟進 topic_shift_v1
  // （ask_intent／challenge_relevance／return_to_topic，一個「接住」都沒有），
  // 等於她問完「你喜歡什麼動物」、他答「貓」，只因為前面有一則亂丟就被結構
  // 保證質疑——那正是 false_challenge 的定義。
  //
  // 這裡不判「貓算不算動物」（語意交模型），只保證候選清單裡永遠有「接住」，
  // 同時保留「拉回你剛才問的那件事」給他其實沒回答的情況（A04 的
  // 「東東是誰」→「阿布達比」）。結構層分不出這兩者，所以兩個都放進候選、
  // 由看得到全文的她挑；不進 forced，也不會落到下面的 lowCoherence 分支。
  //
  // **唯一的例外在上面那條 `repeatedExactToken`**（刻意排在這條之前）：
  // 同一個字串原樣再丟一次是這一層信心最高的結構事實，而且它的 forced act 是
  // 「短短收掉」不是質疑。她問「？」他又貼一次「好市多」時仍然收掉迴圈。
  if (shape === "answer_candidate") {
    return {
      ...base,
      situation: "ambiguous_fragment",
      policyMode: "bounded",
      forcedAct: null,
      allowedActs: ["acknowledge", "return_to_topic"],
      allowedActSetId: "answer_candidate_with_debt_v1",
    };
  }
  if (unresolvedCount >= thresholds.lowCoherenceAt) {
    // Codex round-2 P1-2 之後 standard 的 priorChallengeIssued 一律 false，
    // 所以 standard 走的是下面這個三選一的 bounded 分支（真的是三個選項，不是
    // 假裝的）；assisted 帶著持久化旗標回來時才會落到 forced。
    // forceEndLoopBeforeChallenge（挑戰／game）獨立於 priorChallengeIssued
    // 判斷，不然「2 則未解就收掉」在真實流量下永遠選不到。
    if (
      !evidence.priorChallengeIssued && !thresholds.forceEndLoopBeforeChallenge
    ) {
      return {
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
    const forcedAct: AgencyAct = thresholds.forceEndLoopBeforeChallenge
      ? "end_low_value_loop"
      : "hold_position";
    return {
      ...base,
      situation: "repeated_low_coherence",
      policyMode: "forced",
      forcedAct,
      allowedActs: [forcedAct],
      allowedActSetId: forcedAct === "hold_position"
        ? "hold_after_challenge_v1"
        : "repeated_token_v1",
    };
  }
  if (unresolvedCount >= thresholds.topicShiftAt) {
    // 前一題還沒解決：不供應新解讀，但也不強制質疑。
    // （`answer_candidate` 在上面就被接走了，不會落到這裡——Codex R1 P1-c。）
    return {
      ...base,
      situation: "abrupt_topic_shift",
      policyMode: "bounded",
      forcedAct: null,
      allowedActs: ["ask_intent", "challenge_relevance", "return_to_topic"],
      allowedActSetId: "topic_shift_v1",
    };
  }
  // 還沒到「指出跳題」的門檻（依難度）：跟第一個片段一樣寬容——前面已經有真實
  // 內容可對照時，給一次善意的合理懷疑，當成有效短答，不介入（Codex P1：A07／
  // A09 這類前文豐富的片段，結構上就不該進入質疑型 act 的候選清單）。
  if (evidence.precedingUserContext) {
    return { ...base, ...NO_OVERRIDE };
  }
  // 無前文片段（context-free fragment）：這裡是**結構線索的全空集合**——
  //   不是明示換題、沒有問句標記、沒有第一人稱分享標記、她上一則沒在問問題、
  //   不是同一個詞再丟一次、前面沒有任何她講清楚過的內容、未解計數是 0。
  // 七個條件全部是「某個結構線索不存在」，沒有任何一個是字數（Codex round-2
  // 對「這是換皮的長度啟發式」的回應：`utteranceShapeOf` 已經沒有字數條件，
  // 四十個字的裸敘述照樣是 fragment，兩個字的「韓國」在她剛問完問題時不是）。
  // 這個全空集合信心夠高，所以 normal／challenge／game 直接 forced「只問意思」；
  // easy 仍給兩個選項（接住／問），維持難度差。
  const acts = thresholds.firstFragmentActs;
  const forced = acts.length === 1;
  return {
    ...base,
    situation: "ambiguous_fragment",
    policyMode: forced ? "forced" : "bounded",
    forcedAct: forced ? acts[0] : null,
    allowedActs: acts,
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

/**
 * Phase 2：本輪回合分類器讀完整逐字稿後給的地面真相訊號（temperature.ts
 * `TurnClassification.coherence`／`aiChallengedThisTurn`）。省略＝旗標關閉、
 * classifier 失敗 fallback，或 Phase 1 呼叫端還沒接——一律退回純結構近似。
 */
export interface AgencyClassifierSignal {
  readonly coherence?: ConversationAgencyState["lastCoherence"];
  /**
   * **她這一輪剛送出的回覆**是否真的問了澄清或指出跳題（Codex round-1 P1-d：
   * 舊版判的是玩家這句之前那一則，卻被存成「下一輪的 priorChallengeIssued」，
   * 差了一輪）。
   */
  readonly aiChallengedThisTurn?: boolean;
}

/**
 * 這一輪的決策決定下一個狀態；只存 enum／布林／小整數，不存玩家原句。
 *
 * Codex P1：`priorChallengeIssued` 舊版只要 `allowedActs` 包含質疑型 act 就
 * 記成「已質疑」——bounded choice 是給模型的候選清單，不代表模型真的選了它，
 * 「允許過」不等於「做過」。現在只認兩種地面真相：(1) planner **強制**
 * 質疑／維持立場（`forcedAct`，不是 allowed）；(2)（Phase 2）分類器讀了
 * 她這一輪實際生成的文字後回報 `aiChallengedThisTurn`。
 */
export function nextConversationAgencyState(
  prev: ConversationAgencyState | null,
  decision: AgencyDecision,
  classifierSignal: AgencyClassifierSignal | null = null,
): ConversationAgencyState {
  const base = prev ?? INITIAL_CONVERSATION_AGENCY_STATE;
  const forced = decision.forcedAct;
  const lastAgencyAct = forced !== null &&
      (AGENCY_ACTS as readonly PlanAct[]).includes(forced)
    ? forced as AgencyAct
    : base.lastAgencyAct;
  const structuralCoherence = decision.situation
    ? COHERENCE_BY_SITUATION[decision.situation]
    : "connected";
  return {
    version: 1,
    lastCoherence: classifierSignal?.coherence ?? structuralCoherence,
    unresolvedCount: decision.evidence.unresolvedCount,
    priorChallengeIssued: base.priorChallengeIssued ||
      decision.evidence.priorChallengeIssued ||
      forced === "challenge_relevance" || forced === "hold_position" ||
      classifierSignal?.aiChallengedThisTurn === true,
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
