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

// ── 本檔用到的 regex：只認「句法標記」，不認語意（Codex round-2 Important 6
// 的明確界線）────────────────────────────────────────────────────────────
// `QUESTION_RE`、`REACTION_RE`、`FIRST_PERSON_RE`、`AI_QUESTION_RE` 四支都會
// 影響 `UtteranceShape`／`previousAiAskedQuestion`，因此也會影響 agency 是不是
// 介入。它們**留著**，而且這就是本檔宣稱的界線：
//
//   - 它們比對的是標點與語尾助詞這類**句法標記**（問號、「嗎／呢／吧」、
//     招呼詞、第一人稱代名詞、疑問詞），不是「這句話跟前一句有沒有關聯」。
//   - 本檔沒有、也不會有 topic-relevance regex（「東京一定與韓國無關」）。
//     語意關聯一律交給看得到完整逐字稿的生成模型，在 bounded 候選裡決定。
//   - 已知的過寬處：`AI_QUESTION_RE` 沒有完整錨定，陳述句「我不知道為什麼會
//     這樣」含「為什麼」會被判成她問過問題。這個方向對 `previousAiAskedQuestion`
//     是**安全**的——判成「她問過」只會讓玩家的短答被當成有效短答（不質疑）；
//     判漏才會誤傷。但同一支訊號餵進**強制停止解讀**的閘門時方向剛好相反，
//     所以那裡改用 `aiAskedQuestionStrict`（Phase 3.2 P1-1，見下面的判準）。
//   - 字數不參與任何 agency 判斷：`utteranceShapeOf` 沒有長度條件；
//     `detectTurnSignals` 那個 12 code unit 的 `userQuestionStreak` 是
//     `7f1d6d6c` 就在的既有 interrogation 判準，而問句形狀本來就不是低資訊
//     形狀，所以它證明性地影響不到 agency 的結果（有回歸測試釘住）。
//
// 玩家問句判準原本住在 turn_response_plan.ts；搬到這裡讓依賴單向（planner →
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
  | "end_low_value_loop"
  // Phase 3.0：**條件式**接受。結構層分不出「他這句到底有沒有回答你上一題」，
  // 但看得到全文的她分得出——所以欠債輪不再給一個無條件的「接住」（那正是
  // Eric 回報的「她把不相干的新詞當成答案順著聊」），改成一句二選一的指示：
  // 真的回答了就接受，沒回答就直接說他沒回答又跳題。渲染成一行（見
  // `AGENCY_SET_LINE`），不是清單裡的一個選項。
  | "accept_if_answered";

export const AGENCY_ACTS: readonly AgencyAct[] = Object.keys(
  {
    ask_intent: true,
    challenge_relevance: true,
    return_to_topic: true,
    hold_position: true,
    end_low_value_loop: true,
    accept_if_answered: true,
  } satisfies Record<AgencyAct, true>,
) as AgencyAct[];

/**
 * 「順著聊是合法選項」的 act。清單裡只要有一個，這一輪就不是「只做澄清」的
 * 輪次（`isAgencyClarifyOnlyTurn` 用它決定要不要把回覆形狀壓成一則）。
 */
const ACCEPTING_PLAN_ACTS: readonly PlanAct[] = [
  "acknowledge",
  "accept_if_answered",
];

export function isAcceptingPlanAct(act: PlanAct): boolean {
  return ACCEPTING_PLAN_ACTS.includes(act);
}

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
  /**
   * Phase 3.0：**這一段未解迴圈裡**，她實際送出的回覆有沒有問過問題
   * （`aiAskedQuestion`，逐字稿裡看得見的地面真相，不是 planner 的允許清單）。
   *
   * 為什麼需要它：欠債計數只看玩家這一邊的形狀（連續幾則沒有結構線索），
   * 那對「他在亂丟」是對的訊號，但對「她該不該停止供應解讀」還不夠——如果
   * 她從頭到尾都笑著接、一次都沒問，那她根本沒有立場可以「維持」，
   * `hold_position`（「維持你剛才的保留」）會變成一句自相矛盾的指示。
   *
   * 所以強制格（holdAt）多這一道閘門：她真的問過，才強制停止解讀；沒問過就
   * 留在 bounded 的條件式（接得上就接受，接不上就直說），仍然由她判。
   * 這同時保住 Codex round-1（新項）P1-2 的界線——連貫的第三人稱敘事（她一路
   * 「真的欸」沒問過任何東西）不會被 deterministic 地收掉。
   */
  readonly aiQuestionedInLoop: boolean;
  /**
   * 這次逐字稿裡的玩家訊息則數。它**不影響這一輪的 policy**（`agencyPolicyFor`
   * 一個字都沒讀它），但它會被寫進下一輪的狀態：assisted 模式在分類器判
   * `connected` 時把這個數字存成 `ConversationAgencyState.repairedAtUserTurns`
   * ＝修復點（Phase 3.2 P1-3），而修復點會直接改變**下一輪**算出來的欠債、
   * 「她問過」與重複視窗。所以它不是純觀測值，是狀態機的輸入之一
   * （R1 P1-4c：舊註解寫「不參與任何 policy 判斷」是錯的）。不進 telemetry。
   */
  readonly userTurnCount: number;
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
  /**
   * Phase 3.2 P1-3（assisted 專用）：分類器判 `connected` 的那一輪，逐字稿裡
   * 有幾則玩家訊息。`detectAgencyEvidence` 把這個位置當成結構修復點——欠債
   * 計數、「她問過」旗標、同詞重複視窗都從它之後才開始算。
   *
   * 為什麼需要持久化：舊版只有 `if (prev?.lastCoherence === "connected")
   * unresolved = 0;`，那只清掉**當輪**算出來的值；下一輪同一批逐字稿被重走，
   * 除非分類器又說 connected，舊片段就整批復活。
   *
   * 缺欄位＝沒有修復點（舊 row、standard 模式的 `prev=null`）；壞值一律讓
   * `parseConversationAgencyState()` 整份回 null，跟其餘欄位同一個規則。
   *
   * **前提（2026-09-04 實查，R1 P1-4b）**：這個數字是「第 N 則玩家訊息」的
   * 絕對序號，只有在同一場的逐字稿起點不變時才指得到同一個位置。實際情況：
   *   - thread row 以 session 為 key（見 `parseConversationAgencyState` 上面
   *     那段註解），所以跨場不會沿用；
   *   - client 會截窗：`_turnDtosForPrompt()`／`kPracticePromptRecentTurns = 80`
   *     （`lib/features/practice_chat/data/providers/practice_chat_providers.dart`）
   *     只送最後 80 則訊息，更早的靠 `memorySummary` 承接；server 另有
   *     `MAX_TURNS = 130`。一場練習約 20 回合（≈40 則）遠低於 80，所以現行
   *     產品路徑上這個截窗**不會發生**，但它不是結構保證。
   *   - 萬一真的截掉了 D 則玩家訊息：舊 marker 會比真實位置**偏右** D 則，
   *     也就是把更多輪當成已修復＝少算欠債（安全方向，不會製造假強制停）；
   *     偏到超出這次逐字稿的則數時，`detectAgencyEvidence` 不採用它，
   *     `nextConversationAgencyState` 也不再把它往下傳（R1 P1-4a）。
   */
  readonly repairedAtUserTurns?: number;
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

// ── 強制格專用的**嚴格**問句判準（Phase 3.2 P1-1）────────────────────────
// `AI_QUESTION_RE` 刻意過寬，那對 `previousAiAskedQuestion` 是安全方向——判成
// 「她問過」只會讓玩家的短答被當成有效短答（免疫）。但 Phase 3.0 把同一支訊號
// 也餵進 `aiQuestionedInLoop`，而那裡它反過來是**強制停止解讀**的閘門：陳述句
// 「我不知道為什麼會這樣」含「為什麼」就算她問過 → 假強制停（Codex 3.0 P1-1）。
//
// 迴圈閘門改用這一支。它是寬鬆判準的**真子集**：
//
//   `aiAskedQuestionStrict(t) === aiAskedQuestion(t) && 句尾有問句標記`
//
// R1 P1-1（Codex）：先前的版本自己列了一組疑問詞頭尾條件，結果不是子集——
// 「誰都可以」「如何都行」寬鬆判 false、嚴格反而 true，等於自己造出一組新的
// 假強制停。現在一律先過寬鬆那一支，再加句尾標記，永遠不可能比它寬。
//
// 句尾標記只有兩種，都是純標點／語尾助詞：
//   - 整句（剝掉句尾裝飾後）以 `?`／`？` 結尾；或
//   - 最後一個子句以「嗎／呢／吧」結尾。
// 「疑問詞在子句開頭／結尾」那兩條規則整組拿掉：「我知道他是誰」「誰都可以」
// 這種形態沒有任何句法出路，硬判只會製造誤判。
//
// **接受的代價**：中文很常見的無標記問句（「東東是誰」「你最想去哪」
// 「怎麼突然講韓國」）從此拿不到強制格。這是安全方向——判漏只會退回 bounded
// 條件式，由看得到全文的她自己判「他這句到底有沒有回答我」；判多才會在她根本
// 沒問的時候強制停止解讀。`previousAiAskedQuestion`（有效短答免疫）與
// Phase 3.2 放寬用的「她問過」都還是寬鬆那一支，一字不動。
const CLAUSE_SPLIT_RE = /[。！!？?；;…\n]+/u;
const TAIL_DECORATION_RE =
  /[\s~～!！,，.。、…\p{Emoji_Presentation}\p{Extended_Pictographic}]+$/u;
const SENTENCE_FINAL_PARTICLE_RE = /(嗎|呢|吧)$/u;

export function aiAskedQuestionStrict(text: string): boolean {
  if (!aiAskedQuestion(text)) return false;
  const stripped = text.trim().replace(TAIL_DECORATION_RE, "");
  if (stripped.length === 0) return false;
  if (/[?？]$/u.test(stripped)) return true;
  const last = stripped
    .split(CLAUSE_SPLIT_RE)
    .map((clause) => clause.trim().replace(TAIL_DECORATION_RE, ""))
    .filter((clause) => clause.length > 0)
    .at(-1);
  return last !== undefined && SENTENCE_FINAL_PARTICLE_RE.test(last);
}

/** 只往回看這麼多則玩家訊息（短期工作記憶，不是長期記憶）。 */
const RECENT_USER_WINDOW = 8;
/** 「同一個詞原樣再丟一次」最多往回看幾則玩家訊息（Codex round-2 P1-3）。 */
const REPEAT_LOOKBACK = 3;

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
    /** 同一則 AI 訊息的**嚴格**問句判準，只給強制格的迴圈閘門用（P1-1）。 */
    previousAiAskedQuestionStrict: boolean;
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
      previousAiAskedQuestionStrict: lastAiText !== null &&
        aiAskedQuestionStrict(lastAiText),
    });
    lastAiText = null;
  }
  // Phase 3.2 P1-3：assisted 持久化下來的修復點（分類器判 connected 的那一輪
  // 有幾則玩家訊息）。位置超出這次逐字稿的則數（逐字稿被截短）就當成沒有——
  // 定位不到的修復點寧可不用，也不要指到錯的地方。standard 傳 null＝一律 0。
  const repairStart = prev?.repairedAtUserTurns !== undefined &&
      prev.repairedAtUserTurns <= shapes.length
    ? prev.repairedAtUserTurns
    : 0;
  const windowed = shapes.slice(-RECENT_USER_WINDOW);
  const current = windowed.at(-1);
  const earlier = windowed.slice(0, -1);
  // 修復點在 `windowed`／`earlier` 座標系裡的位置（已經滑出窗口就是 0）。
  const windowRepairStart = Math.max(
    0,
    repairStart - (shapes.length - windowed.length),
  );

  // ── 未解片段計數（Phase 3.0 改寫）────────────────────────────────────
  // 舊版是「連續低資訊形狀就累加」，而且只算到**這一句之前**。兩個問題：
  //   (1) 她從頭到尾沒問過任何東西、只是一路順著接，也會累出「欠債」；
  //   (2) 這一句本身不算，所以「她問了一次 → 他又丟一個裸詞」這個 Eric 回報
  //       的核心形態，在第二則上算出來是 0／1 的邊界值，落到「有效短答」那格。
  //
  // 欠債的意思只有一個：**她已經要求他講清楚了，而他又丟了一個沒有結構線索的
  // 片段**。所以只在這個條件成立時 +1：
  //   - 這一則玩家訊息是低資訊形狀（不是問句、分享、明示換題、招呼），而且
  //   - 上一則玩家訊息那一輪，planner 真的叫她問或質疑（下面的 `told`）。
  //
  // `told` 不重打模型、不看 AI 生成的文字（standard 沒有分類器，只有逐字稿
  // ——工作項 B），只認一件結構事實：**上一則玩家訊息是不是一個她得自己想辦法
  // 處理的低資訊片段**。只有一個例外——「她剛問完問題、他答了、而且前面沒有
  // 欠債」是正常一問一答（有效短答免疫格），那一輪她沒有被迫做任何事，所以不
  // 算欠債的起點（Phase 3.2 給這個例外再加一個條件，見下面那段）。其餘每一個低資訊片段（含「前面有真實內容所以放行一次」的
  // 那格）都算她已經給過一次通融，下一則再來就是欠債。
  // 這一句自己也走同一個迴圈，所以「第二個裸片段」算出來就是 1。
  //
  // 結構修復（問句／第一人稱分享／明示換題）一律歸零並清掉 `told`；招呼／情緒
  // 反應不動（「嗯」「喔」不是修復，也不是新的欠債）。
  // 一律從逐字稿重算，不把 `prev.unresolvedCount` 當起點——同一批 turn 會被重走，
  // 兩者相加會重複計數；逐字稿本來就帶著這一場的全部片段。
  //
  // Phase 3.2（Eric 2026-09-04 拍板的放寬）：免疫只給**這一段迴圈裡的第一組**
  // 一問一答。她問過一次之後，他再丟一個沒有結構線索的片段，就算她上一則又是
  // 問句也算欠債——否則她只要一直問，他就可以一直丟無標記句而永遠不進欠債格
  // （Phase 3.1 的負面結果指出這才是下一個槓桿，不是磨強制停的後檢查）。
  // R1 P1-2（Codex）：這裡的「她問過」用**寬鬆**判準（`previousAiAskedQuestion`，
  // 跟 shape／免疫同一支），不是強制格那支嚴格的。這一格的結果只是 bounded 的
  // 二選一條件式（真的回答了就接受），過度偵測只會多送一次「他有沒有回答你」
  // 給看得到全文的她判，是安全方向；用嚴格判準反而會讓中文最常見的無標記問句
  // 整組拿不到放寬。嚴格判準只留給真正 deterministic 的強制格
  // （`aiQuestionedInLoop`）。
  // 這個旗標是**逐則遞增**的：處理到某一則時只看它自己與它之前，所以第一組
  // 一問一答（A01／A03／A07／A09）在自己那一輪仍然是 `unresolvedCount === 0`
  // 的免疫格。這裡不能改用下面算好的 `aiQuestionedInLoop`（那是整段的終值，
  // 會回頭把第一組的免疫也拿掉）。
  let unresolved = 0;
  let told = false;
  let askedInLoop = false;
  for (const s of windowed.slice(windowRepairStart)) {
    if (!isLowInformation(s.shape)) {
      if (s.shape !== "reaction") {
        unresolved = 0;
        told = false;
        askedInLoop = false;
        continue;
      }
      // 招呼／情緒反應不是修復也不是新的欠債，但「她問過」要留著（同 P1-2）。
      if (s.previousAiAskedQuestion) askedInLoop = true;
      continue;
    }
    if (s.previousAiAskedQuestion) askedInLoop = true;
    if (told) unresolved = clamp3(unresolved + 1);
    told = !(s.shape === "answer_candidate" && unresolved === 0 &&
      !askedInLoop);
  }
  // 「她這段迴圈裡問過沒有」不吃 RECENT_USER_WINDOW：迴圈本身已經是邊界
  // （任何結構修復都會把它清掉），再套 8 則的窗口只會讓「連丟第 11 個片段」
  // 因為最早那兩句問話滑出窗口而退回 bounded——欠債沒解決，她的立場卻自己
  // 消失了。計數仍然照舊只看最後 8 則（短期工作記憶，clamp 在 3）。
  // Phase 3.2 P1-1：這裡用 `previousAiAskedQuestionStrict`（見上面的判準），
  // 不是餵給 shape／免疫的那支寬鬆 regex——這個旗標是**強制停止解讀**的閘門，
  // 過寬會變成假強制停。
  // Phase 3.2 P1-2：每一則玩家訊息都要先讀「她上一則有沒有問」，再看形狀。
  // 舊版對 `reaction`（「嗯」「喔」）先 `continue` 才讀，所以「她問 → 他回嗯 →
  // 她講了句不是問句的話 → 他丟片段」這個形態整段都不算她問過，該停不停。
  // 只有結構修復（非低資訊、非 reaction）才把旗標清掉。
  let aiQuestionedInLoop = false;
  for (const s of shapes.slice(repairStart)) {
    if (!isLowInformation(s.shape) && s.shape !== "reaction") {
      aiQuestionedInLoop = false;
      continue;
    }
    if (s.previousAiAskedQuestionStrict) aiQuestionedInLoop = true;
  }
  // assisted：分類器讀完她這一輪的回覆後判 `connected`＝玩家上一輪真的接上了。
  // 那是結構層看不到的修復（他這句話對不對得上是語意問題），所以拿它把逐字稿
  // 推出來的欠債歸零；standard 傳 null，這條不生效。
  // Phase 3.2 P1-3：這一行留著當**舊 row 的相容退路**（`repairedAtUserTurns`
  // 還沒被寫進去的 thread）。真正跨輪有效的是上面的 `repairStart`——它讓修復點
  // 之前的片段不再被重算回來，而不是只清掉當輪的值。
  // R2 P2（Codex）：所以它必須**只**對沒有 marker 的 row 生效。有 marker 時
  // `unresolved` 已經是「修復點之後」的新欠債，再無條件歸零等於把它擦掉。
  if (
    prev?.lastCoherence === "connected" &&
    prev.repairedAtUserTurns === undefined
  ) {
    unresolved = 0;
  }
  const compactedCurrent = current ? compact(current.text) : "";
  // Codex round-2 P1-3：舊版拿整個八則 window 比對，等於「玩家較早講過『貓』、
  // 中間完整聊完別的事、稍後她問『你最喜歡什麼動物』他再答『貓』」也會被
  // forced `end_low_value_loop`。重複要成立必須是**同一段沒解決的迴圈裡**：
  //   - 起點＝最後一次「玩家自己把話講清楚了」（非低資訊、非 reaction）之後，
  //     也就是 unresolved 歸零的那個 repair／connected 點；
  //   - 再往回最多 3 則（短期工作記憶，不是長期記憶）。
  // Phase 3.2 P1-3：重複視窗同樣不得越過持久化的修復點。
  // R2 P1（Codex）：只給初始值不夠——修復點**之前**的一則結構訊息會把
  // `repairedAt` 覆寫成更小的 index，視窗又跨回修復點之前。取最大值即可
  // （`forEach` 的 i 遞增，所以最大值仍然是最後一次結構修復的位置）。
  let repairedAt = windowRepairStart;
  earlier.forEach((s, i) => {
    if (!isLowInformation(s.shape) && s.shape !== "reaction") {
      repairedAt = Math.max(repairedAt, i + 1);
    }
  });
  const repeatWindow = earlier.slice(
    Math.max(repairedAt, earlier.length - REPEAT_LOOKBACK),
  );
  const repeatedExactToken = compactedCurrent.length > 0 &&
    repeatWindow.some((s) => compact(s.text) === compactedCurrent);
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
    // Phase 3.2 P1-3：`precedingUserContext` 刻意**不**受修復點限制——修復點
    // 之前玩家講清楚過的內容仍然是他給過的前文，砍掉會讓 A07／A09 那種
    // 「先鋪前文再丟短詞」在 assisted 模式反而被判成無前文片段（更嚴，不是更鬆）。
    precedingUserContext: earlier.some((s) =>
      s.shape !== "reaction" && !isLowInformation(s.shape)
    ),
    aiQuestionedInLoop,
    userTurnCount: shapes.length,
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
  /**
   * 旗標本身是不是 `on`（不是「這一輪有沒有介入」）。`applied` 額外要求
   * `situation !== null`，所以問句／分享／有效短答那些輪次是 false——但
   * Phase 3.0 的兩條**常設**指示（先看整段邏輯、他抱怨時不要軟化）正好要在
   * 那些輪次也印出來，所以需要一個跟 situation 無關的旗標。
   * `shadow` 一律 false：shadow 的契約是「只算 telemetry，輸出逐字與 off 相同」
   * （`agency_flag_off_equivalence_test.ts` 守門）。
   */
  readonly enabled: boolean;
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
  /**
   * Phase 3.0：有欠債（她已經問過、他又丟片段）那一輪的候選 act。
   * 一般／挑戰／Game 只有二選一的條件式接受＋質疑，**沒有無條件的「接住」**；
   * easy 多給一個 `acknowledge`（同一步比較晚才收緊，報告 §7.4）。
   */
  readonly debtAnswerActs: readonly PlanAct[];
  /**
   * unresolvedCount 累到這個數字就不再供應解讀，強制維持立場／收掉迴圈。
   * Eric 2026-09-04 的真機體感定義：一般難度第 2 個未解片段要指出他沒回答
   * （＝欠債 1，走 `debtAnswerActs`），第 3 個以後停止解讀（＝欠債 2 → hold）。
   * easy 晚一步（3）、challenge／Game 早一步（1）。
   */
  readonly holdAt: number;
  /** 到了 holdAt 時強制收掉迴圈（challenge／Game），而不是維持立場。 */
  readonly forceEndLoopBeforeChallenge: boolean;
}

export const AGENCY_THRESHOLDS: Record<
  "easy" | "normal" | "challenge",
  AgencyThresholds
> = {
  // 輕鬆：第一次模糊給「接住」或「問清楚」；有欠債時仍留一個無條件的「接住」；
  // 要到第 3 個未解片段才停止解讀。
  easy: {
    firstFragmentActs: ["acknowledge", "ask_intent"],
    debtAnswerActs: [
      "acknowledge",
      "accept_if_answered",
      "challenge_relevance",
    ],
    holdAt: 3,
    forceEndLoopBeforeChallenge: false,
  },
  // 一般（Eric 的基準）：第一個片段 bounded {接住, 問意思}；第二個未解片段就要
  // 二選一（真的回答了就接受，沒回答就直說他跳題）；第三個以後維持立場。
  normal: {
    firstFragmentActs: ["acknowledge", "ask_intent"],
    debtAnswerActs: ["accept_if_answered", "challenge_relevance"],
    holdAt: 2,
    forceEndLoopBeforeChallenge: false,
  },
  // 挑戰／Game：早一步——她已經問過的話，第二個未解片段就直接收掉這串。
  challenge: {
    firstFragmentActs: ["acknowledge", "ask_intent"],
    debtAnswerActs: ["accept_if_answered", "challenge_relevance"],
    holdAt: 1,
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
  // ── Phase 3.0：欠債輪（她已經問過／質疑過，他又丟一個沒有結構線索的片段）──
  //
  // Eric 2026-09-04 回報的核心失敗：「我一直傳不連貫的地名，她只是一直回應，
  // 邏輯說不通但沒質疑。」她問過一次「怎麼突然講韓國」之後，他再丟一個不相干的
  // 詞，舊版把它路由到 `answer_candidate_with_debt_v1`（bounded {acknowledge,
  // return_to_topic}）或 `topic_shift_v1`（含 acknowledge 的四選一）——兩者都
  // 留著一個**無條件**的「接住」，於是她把新詞當成答案順著聊。
  //
  // 這裡的修法不是「禁止接受」（那會把 A01／A05／A15 那種真的回答了的短答
  // 誤殺，false_challenge 直接破功），而是把「接受」變成**有條件的**：
  // `accept_if_answered` ＋ `challenge_relevance` 渲染成同一句二選一的指示，
  // 由看得到完整逐字稿的她判「他這句到底有沒有回答我上一題」。結構層仍然
  // 不判語意——它只保證「無條件順著新名詞聊」不在候選清單裡。
  //
  // 這條同時吃 `answer_candidate`（她上一則在問問題）與 `bare_fragment`
  // （她上一則沒問），因為兩者在「他這句沒有任何結構線索」這件事上是同一種。
  // `unresolvedCount === 0` 的 `answer_candidate`（有效短答）在上面就被
  // NO_OVERRIDE 接走了，不會落到這裡。
  if (unresolvedCount >= 1) {
    if (
      unresolvedCount >= thresholds.holdAt && evidence.aiQuestionedInLoop &&
      shape === "bare_fragment"
    ) {
      // 停止供應解讀：維持立場（一般／輕鬆）或直接收掉這串（挑戰／Game）。
      // 回覆形狀由 planner 壓成最少則數（`planTurnResponse`）。
      // 兩道閘門：
      //   `aiQuestionedInLoop`＝她這段迴圈裡真的問過（見 AgencyEvidence 註解）；
      //   `bare_fragment`＝她上一則**沒有**在問問題。她剛問完、他回了一句沒有
      //     結構線索的話（`answer_candidate`），結構層就分不出那是不是答案
      //     （「你喜歡什麼動物」→「貓」），這種輪次永遠不得 forced——Codex
      //     round-1 P1-c 的界線，Phase 3.0 一字不動地保留。
      // 任一不成立就留在下面的 bounded 條件式，由看得到全文的她判。
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
          : "low_value_loop_v1",
      };
    }
    const acts = thresholds.debtAnswerActs;
    return {
      ...base,
      situation: "abrupt_topic_shift",
      policyMode: "bounded",
      forcedAct: null,
      allowedActs: acts,
      allowedActSetId: acts.includes("acknowledge")
        ? "answer_or_challenge_easy_v1"
        : "answer_or_challenge_v1",
    };
  }
  // 走到這裡＝`unresolvedCount === 0` 的裸片段（沒有欠債，她也沒問過）。
  // 前面已經有真實內容可對照時，給一次善意的合理懷疑，不介入（Codex P1：A07／
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
  // 三種難度目前都給兩個選項（接住／問）；`firstFragmentActs` 留成表格欄位是
  // 為了讓「哪個難度收窄第一則」是一行資料改動，不是散在條件式裡。
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
    r.repairedAtUserTurns !== undefined &&
    !(typeof r.repairedAtUserTurns === "number" &&
      Number.isInteger(r.repairedAtUserTurns) && r.repairedAtUserTurns >= 0)
  ) return null;
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
    // 缺欄位就**不要**放這個 key（省略 ≠ undefined：整包覆寫 recent_facts 時
    // 兩者等價，但物件相等比對會不同，等價 harness 與既有測試都在對拍形狀）。
    ...(r.repairedAtUserTurns === undefined
      ? {}
      : { repairedAtUserTurns: r.repairedAtUserTurns as number }),
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
  // Codex round-2 P1-5：舊版是永久 OR，一次質疑會污染同一個 thread 上之後
  // 每一段不相干的 episode（新片段一出現就直接 forced hold_position）。
  // 「這段已經修好了」有兩個結構化的地面真相：
  //   (1) 分類器讀完她這一輪的回覆後判 `connected`＝玩家真的接上了；
  //   (2) 她剛問完問題、玩家答了、而且前面沒有欠債（`answer_candidate` ＋
  //       `unresolvedCount === 0` → 本檔的「有效短答」免疫格，situation=null）。
  // 任何一個成立就把旗標歸零；這一輪自己真的又質疑了才會重新變 true。
  //
  // Codex R1（新項）P1-1：分類器訊號缺失（null／沒有 coherence 欄位）或
  // parseCoherence() 把壞值修成 "ambiguous" 時，都不是「分類器判斷 connected」
  // 也不是「分類器判斷 disconnected/repetitive」——是**沒有可信訊號**。
  // `AgencyClassifierSignal` 自己就宣稱這種情況「一律退回純結構近似」，所以這裡
  // 退回上面已經算好的 `structuralCoherence`，而不是讓缺失訊號直接判定不修復。
  const classifierCoherence = classifierSignal?.coherence;
  const coherenceForRepair =
    classifierCoherence === undefined || classifierCoherence === "ambiguous"
      ? structuralCoherence
      : classifierCoherence;
  const repaired = coherenceForRepair === "connected" ||
    (decision.evidence.utteranceShape === "answer_candidate" &&
      decision.evidence.unresolvedCount === 0 && decision.situation === null);
  const challengedThisTurn = forced === "challenge_relevance" ||
    forced === "hold_position" ||
    classifierSignal?.aiChallengedThisTurn === true;
  // Phase 3.2 P1-3：只有**分類器明確判 connected**才落新的修復點。結構修復
  // （問句／第一人稱分享／明示換題）本來就會在 `detectAgencyEvidence` 的迴圈
  // 裡把欠債清乾淨，不需要持久化；有效短答免疫格更不能算修復點，否則
  // 「她問 → 他丟片段」每一輪都會自己把位置往前推，等於抵銷 Phase 3.2 的放寬。
  // 沒有新的修復點就沿用上一個（那一段還沒被修好，欠債要繼續從它之後算）。
  // R1 P1-4a：沿用舊修復點之前先確認它在這次逐字稿裡定位得到——定位不到
  // （逐字稿比記錄當時短）就直接丟掉，不要把一個指不到任何位置的數字一路傳下去。
  const locatable = base.repairedAtUserTurns !== undefined &&
      base.repairedAtUserTurns <= decision.evidence.userTurnCount
    ? base.repairedAtUserTurns
    : undefined;
  const repairedAtUserTurns = classifierSignal?.coherence === "connected"
    ? decision.evidence.userTurnCount
    : locatable;
  return {
    version: 1,
    lastCoherence: classifierSignal?.coherence ?? structuralCoherence,
    unresolvedCount: decision.evidence.unresolvedCount,
    priorChallengeIssued: (repaired ? false : base.priorChallengeIssued ||
      decision.evidence.priorChallengeIssued) ||
      challengedThisTurn,
    lastAgencyAct,
    ...(repairedAtUserTurns === undefined ? {} : { repairedAtUserTurns }),
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

// ── Phase 3.3：形狀實驗旋鈕（PRACTICE_AGENCY_SHAPE_EXPERIMENT）──────────────
/**
 * `truncate`＝生成後結構性截斷（第一則是問句就只留第一則），在 handler 的
 * 生成迴圈與黑箱 runner 的同序後處理生效；預設 `off`＝與今日逐字相同。
 *
 * 只在 agency 旗標解析成 `on` **且**這一輪真的介入（`applied`）時有效果；
 * off／shadow／未介入的輪次一律零改動（`agency_flag_off_equivalence_test.ts`）。
 *
 * 2026-09-04（Eric 拍板）：另一個 `prompt` 臂（把形狀行換成條件式）黑箱量到
 * 零效果，已整條刪除；`truncate` 臂把 `sequenceHoldBlindFollow` 從 20.6%
 * 壓到 12.5%（20 位 × repeat 3，信賴區間分開），所以留在旋鈕後面。
 */
export type AgencyShapeExperiment = "off" | "truncate";

/** 旗標字串 → 實驗臂。認不得的值一律 `off`（與 `agencyModeFor` 同樣 fail-closed）。 */
export function agencyShapeExperimentFor(
  flag: string | undefined,
): AgencyShapeExperiment {
  return flag === "truncate" ? flag : "off";
}

/**
 * 這一輪「接受仍然合法」的三個候選組——`isAgencyClarifyOnlyTurn` 壓不到它們
 * （清單裡有 `acknowledge`／`accept_if_answered`），而 Eric 2026-09-04 回報的
 * `accommodating_invention`／`asked_with_guess` 正好都落在這裡。
 */
export const AGENCY_SHAPE_EXPERIMENT_SET_IDS: readonly string[] = [
  "answer_or_challenge_v1",
  "answer_or_challenge_easy_v1",
  "fragment_no_context_v1",
];

/**
 * truncate 臂的適用格：三個實驗候選組，或這一輪的 act（forced 或 bounded）
 * 全部是 agency act（＝`isAgencyClarifyOnlyTurn` 那一類，形狀本來就該壓成一則，
 * 這裡多一道生成後的保險）。
 */
export function isAgencyShapeExperimentTurn(
  agency: AgencyApplication | null,
): boolean {
  if (!agency?.applied) return false;
  const decision = agency.decision;
  if (AGENCY_SHAPE_EXPERIMENT_SET_IDS.includes(decision.allowedActSetId)) {
    return true;
  }
  const acts = decision.forcedAct ? [decision.forcedAct] : decision.allowedActs;
  return acts.length > 0 &&
    acts.every((a) => (AGENCY_ACTS as readonly PlanAct[]).includes(a));
}

/**
 * 泡泡切法與 client（`practice_chat_screen.dart` 的 `_splitBubbles`，上限 4）
 * 及黑箱 runner（`tools/practice-agency-eval/run_agency.ts`）同一套：換行切、
 * 去空白、超過上限就不拆（使用者眼裡那是一顆泡，沒有「後面幾則」可以丟）。
 */
const MAX_BUBBLE_SPLIT = 4;

function agencyBubbles(text: string): string[] {
  const parts = text.split("\n").map((p) => p.trim()).filter((p) =>
    p.length > 0
  );
  return parts.length <= 1 || parts.length > MAX_BUBBLE_SPLIT
    ? [text.trim()]
    : parts;
}

/**
 * truncate 臂：她第一則就是問句時，只留第一則、丟掉後面全部。
 *
 * 純結構——判準只有 `isQuestionText`（既有問句形狀）與換行，不看字數、不看
 * 語意。不重試、不再打模型：後面那幾則正是「同一則裡順口講自己跟這個詞有關
 * 的經歷」的落點，丟掉就沒了。
 */
export function truncateAgencyShape(
  reply: string,
  agency: AgencyApplication | null,
): { text: string; dropped: number } {
  if (!isAgencyShapeExperimentTurn(agency)) return { text: reply, dropped: 0 };
  const bubbles = agencyBubbles(reply);
  if (bubbles.length <= 1 || !isQuestionText(bubbles[0])) {
    return { text: reply, dropped: 0 };
  }
  return { text: bubbles[0], dropped: bubbles.length - 1 };
}
