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
  | "repeated_low_coherence"
  /**
   * Phase 4.5a 刀 3：她「回來但冷」的那一輪——玩家終於給了結構內容，所以既不是
   * 片段、也不是跳題、更不是重複迴圈。獨立一格，`agency_coaching.ts` 的修復輪
   * 帳才不會把它算成又一輪「沒接上」。
   */
  | "cold_return";

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
  | "accept_if_answered"
  // ── Phase 4.5a 刀 3：不收斂階梯（Eric 2026-09-05「真人不會一直陪你耗」）──
  // 收尾格（`hold_position`／`end_low_value_loop`）連續發生時，舊版每一輪都
  // 重新生一則「維持立場」——她永遠站在同一格陪他耗。這三個 act 是那條階梯：
  | "cold_return"
  | "check_out"
  | "read_only";

export const AGENCY_ACTS: readonly AgencyAct[] = Object.keys(
  {
    ask_intent: true,
    challenge_relevance: true,
    return_to_topic: true,
    hold_position: true,
    end_low_value_loop: true,
    accept_if_answered: true,
    cold_return: true,
    check_out: true,
    read_only: true,
  } satisfies Record<AgencyAct, true>,
) as AgencyAct[];

/**
 * forced `read_only` 那一格她送出的整則回覆。**不打生成模型**：省一次呼叫，
 * 而且真人在這一格本來就不會打字。守門鏈的白名單認同一個字面
 * （`visible_text_guard.ts` 的 `READ_ONLY_REPLY_RE`）。
 */
export const READ_ONLY_REPLY_TEXT = "（已讀）";

/**
 * Phase 4.5a 刀 3（CTO 2026-09-05 依 Eric「持續不收斂」原意擴大入口）：
 * 哪些 forced act 算「她又被迫處理了一輪沒收斂的對話」。
 *
 * 原本只認兩個收尾格（`hold_position`／`end_low_value_loop`），離線重建量到
 * 740 輪只觸發 1 次——因為她多半在問問題，玩家那一則就變成 `answer_candidate`，
 * 走的是 4.3 的 `challenge_relevance`（`clarify_ignored_*`），根本進不了收尾格。
 * 現在改成「這一輪 planner **真的強制**了任何一個 agency act」都算，只有
 * `ask_intent` 除外——那是**第一個**沒有前文的裸詞，她還沒被耗到，第一次問清楚
 * 不該被記成不收斂。`accept_if_answered`／`return_to_topic` 只出現在 bounded
 * 清單裡，永遠不會是 `forcedAct`；階梯自己的三格（`cold_return` 走內容輪歸零、
 * `check_out`／`read_only` 已經在門檻上）clamp 之後也不影響結果。
 */
function isLowValueStreakAct(act: PlanAct | null): boolean {
  return act !== null && act !== "ask_intent" &&
    (AGENCY_ACTS as readonly PlanAct[]).includes(act);
}

/** 階梯的門檻：收尾格連續這麼多輪還沒解決，她就先去忙了。 */
export const LOW_VALUE_STREAK_CHECK_OUT = 3;

/**
 * 「結構上有內容」＝階梯的重置條件：問句、第一人稱／解釋標記的分享、明示換題，
 * 或她的是非問句真的被回答（刀 1）。招呼／情緒反應詞**不算**內容——她已經
 * 說要先忙了，他回一句「哈哈」不是把話接回來。
 */
export function isAgencyContentShape(shape: UtteranceShape): boolean {
  return shape === "question" || shape === "self_share" ||
    shape === "explicit_pivot";
}

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
  /**
   * Phase 4.5a 刀 1：她上一則是**是非問句**，而他這一則整則就是一個肯定／
   * 否定短詞＝**他回答了**。這一輪一律不介入，欠債也不因這一句累加。
   */
  readonly answeredYesNo: boolean;
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
  /**
   * Phase 4.3：上一輪分類器對**她實際生成的那一則**的判斷——她是不是真的在
   * 澄清／指出跳題（`ConversationAgencyState.aiClarifiedLastTurn`）。
   * `null`＝沒有可信訊號（standard 沒有分類器、分類器失敗、旗標 off）。
   */
  readonly aiClarifiedLastTurn: boolean | null;
  /**
   * Phase 4.3（Codex R1 建議的顯式閘門）：上一輪分類器判的連貫度。
   * `null`＝沒有持久化狀態（standard／第一輪）。
   */
  readonly priorCoherence: ConversationAgencyState["lastCoherence"] | null;
  /**
   * Phase 4.5a 刀 3：**上一輪為止**收尾格（`hold_position`／
   * `end_low_value_loop`）連續發生了幾輪。只有 assisted 有持久化狀態，
   * standard 一律 0＝階梯整段不生效。
   */
  readonly lowValueStreak: number;
  /** Phase 4.5a 刀 3：她已經說過「先忙了」（`check_out`）。standard 一律 false。 */
  readonly checkedOut: boolean;
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
  /**
   * conversation-agency-v1 Phase 3.8（AGENCY-05 結構刀）：這一場她已經問過他
   * 一件事（planner 強制過一次 `askUserFocus`）。黏住不歸零：一場只強制一次，
   * 之後多常問回到 persona 的 questionHabit。省略＝還沒問過。
   */
  readonly askedAboutUser?: boolean;
  /**
   * Phase 4.3（Codex R1 P1-1）：**她上一則回覆是不是真的在澄清／指出跳題**，
   * 來源是分類器讀完她實際生成文字後的 `aiChallengedThisTurn`（judge prompt：
   * 「assistantReplyAfterUser 是不是真的在問清楚意思或指出跳題／不相關，不是
   * 隨口帶過」）。
   *
   * 為什麼不共用 `priorChallengeIssued`：那個欄位是
   * `forcedAct ∈ {challenge_relevance, hold_position} || 分類器` 的 OR，也就是
   * **planner 強制過**就算數——但「強制過」不等於「她真的照做」，而且它是跨輪
   * 黏住的旗標。`clarify_ignored` 強制格要判的是一件很窄的事實：她**上一則**
   * 到底是在澄清，還是在問一個內容問題。只有分類器讀她實際文字的那個布林算數。
   *
   * **缺席＝沒有可信訊號**（standard 沒有分類器、分類器呼叫失敗、旗標 off），
   * 不是 `false`；`agencyPolicyFor` 對缺席退回保守的 standard 規則。
   */
  readonly aiClarifiedLastTurn?: boolean;
  /**
   * Phase 4.5a 刀 3：收尾格連續幾輪（clamp 在 `LOW_VALUE_STREAK_CHECK_OUT`）。
   * 缺欄位／0 都是「沒有連續」，所以 0 時**不寫這個 key**（舊 row 相容，
   * 也讓等價 harness 的物件形狀不變）。
   */
  readonly lowValueStreak?: number;
  /** Phase 4.5a 刀 3：她已經先去忙了。缺欄位＝false。 */
  readonly checkedOut?: boolean;
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
//
// Phase 4.3 R2（Codex P1-1）：4.3 一度把肯定／否定的純短詞（對／是／不是／
// 沒有）加進來，**已整批撤回**。理由：`utteranceShapeOf` 在看 `previousAiAskedQuestion`
// **之前**就把它們歸成 reaction，等於不管她上一句是「你是說韓國嗎？」還是
// 「你在說什麼？」都一律免疫——但「不是」回得了前者、回不了後者。要分辨那個
// 差別就是語意，本檔不做。撤回後它們回到 `bare_fragment`／`answer_candidate`：
// 她問內容是非題、沒有欠債時走既有的有效短答免疫；她澄清之後再回一個「不是」
// 就是沒回答，照 `clarify_ignored` 強制格處理。契約表見計畫檔 Phase 4.2／4.3。
const REACTION_RE =
  /^(嗨+|哈囉|哈啦|安安|你好|妳好|hi|hello|yo|嗯+|喔+|噢+|哦+|好+(的|喔|啊)?|ok|okay|哈+|呵+|笑死|欸+|蛤+|齁+|唉+|哇+|真的假的|了解|收到|感謝|謝謝|晚安|早安|午安|掰掰|bye|[\p{Emoji_Presentation}\p{Extended_Pictographic}\s]+)$/iu;
// 第一人稱標記：只看有沒有「我」這個結構標記，不判斷他在分享什麼。
const FIRST_PERSON_RE = /(我|咱|俺)/u;
// Phase 4.3 R2（Codex P1-3）：**解釋標記**。她澄清之後他給的完整解釋（「因為
// 下個月要去首爾出差」「我是說剛剛那個」）在句法上沒有第一人稱、也沒有問句
// 標記，舊版會落進 `answer_candidate`，然後被 `clarify_ignored` 強制格當成
// 「又丟一個裸詞」。這幾個是純字面連接詞／後設標記，跟 `FIRST_PERSON_RE` 同
// 一個層級——只看標記在不在，不判斷他解釋得對不對（那是模型的事）。
// 「我是說」含「是說」、「我的意思是」含「意思是」，所以不必逐一列。
const EXPLANATION_RE = /(因為|意思是|就是說|是說)/u;
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
// Phase 4.3（Codex R1 U-9）：`\p{Emoji_Presentation}`／`\p{Extended_Pictographic}`
// **不含** ZWJ（U+200D）、variation selector（U+FE0E／U+FE0F）與 keycap 的
// combining enclosing（U+20E3），所以「👨‍👩‍👧‍👦」「❤️」「1️⃣」這類序列剝不乾淨，
// 只會剝掉最後一個 code point。把這三種零寬／組合字元一起放進字元類即可。
const TAIL_DECORATION_RE =
  /[\s~～!！,，.。、…\u200d\ufe0e\ufe0f\u20e3\p{Emoji_Presentation}\p{Extended_Pictographic}]+$/u;
const SENTENCE_FINAL_PARTICLE_RE = /(嗎|呢|吧)$/u;

/** 剝掉句尾裝飾後的最後一個子句（空字串＝整則只有裝飾）。 */
function finalClauseOf(text: string): string {
  const stripped = text.trim().replace(TAIL_DECORATION_RE, "");
  if (stripped.length === 0) return "";
  return stripped
    .split(CLAUSE_SPLIT_RE)
    .map((clause) => clause.trim().replace(TAIL_DECORATION_RE, ""))
    .filter((clause) => clause.length > 0)
    .at(-1) ?? "";
}

export function aiAskedQuestionStrict(text: string): boolean {
  if (!aiAskedQuestion(text)) return false;
  const stripped = text.trim().replace(TAIL_DECORATION_RE, "");
  if (stripped.length === 0) return false;
  if (/[?？]$/u.test(stripped)) return true;
  return SENTENCE_FINAL_PARTICLE_RE.test(finalClauseOf(text));
}

// ── Phase 4.5a 刀 1：是非問句 ＋ 純肯定／否定短答＝「他回答了」──────────────
// 4.2／4.3 釘下來的契約是「純肯定短詞算內容、前一句是陳述時會被問意思」，那條
// **不動**。這裡補的是它漏掉的一格：她上一則**是是非問句**（剝掉句尾裝飾後
// 句尾是「嗎／吧／嘛」），他回一個整則就是「對」「不是」的短詞——那在句法上
// 就是答案，不是又丟一個裸詞。
//
// 為什麼安全（Codex R2 P1-1 撤回 4.3 那批改動的理由不適用這裡）：4.3 是把
// 肯定／否定短詞**無條件**歸成 reaction，等於「你在說什麼？→ 不是」也一起
// 免疫；這一刀多綁一個**她那一則的句法形狀**，開放問句（「你在說什麼？」）
// 與陳述句都不吃，行為逐字維持 4.3 現況。
const YES_NO_FINAL_PARTICLE_RE = /(嗎|吧|嘛)$/u;
const SECOND_PERSON_RE = /[你妳]/u;
// `CLAUSE_SPLIT_RE`（強制問句判準用的那支）**不切逗號**，所以
// 「你一直丟地名，那我先去忙吧」整則會被當成一個子句，前半的「你」就把後半的
// 自語判成在問他（Codex R2 P1-2）。這一支多切逗號／頓號，只給是非問句判準用，
// 不動 `aiAskedQuestionStrict` 的既有行為。
const YES_NO_CLAUSE_SPLIT_RE = /[。！!？?；;…，,、\n]+/u;

/** 剝掉句尾裝飾、再以標點（含逗號）切開後的最後一個子句。 */
function yesNoFinalClause(text: string): string {
  const stripped = text.trim().replace(TAIL_DECORATION_RE, "");
  if (stripped.length === 0) return "";
  return stripped
    .split(YES_NO_CLAUSE_SPLIT_RE)
    .map((clause) => clause.trim().replace(TAIL_DECORATION_RE, ""))
    .filter((clause) => clause.length > 0)
    .at(-1) ?? "";
}
/**
 * 她上一則是不是**是非問句**。三道都要過（Codex R1 P1-1 之後收緊）：
 *
 * 1. `aiAskedQuestion(text)`＝寬鬆問句判準先成立（「這本來就是韓國嘛」句尾是
 *    「嘛」但整句沒有任何問句標記，這一關就擋掉）；
 * 2. 剝掉句尾裝飾、再以標點（**含逗號**）切開後的最後一個子句以
 *    「嗎／吧／嘛」結尾；
 * 3. 「吧／嘛」**還要在同一個最後子句裡**出現第二人稱（你／妳）。「嗎」不
 *    需要——它在中文裡幾乎只有疑問用法；「吧」同時是**提議／自語**
 *    （「我先去忙吧」），只看句尾會把她自己的收尾句判成在問他，玩家一句
 *    「好」就把 `checkedOut` 解開（Codex R1 P1-3）。第二人稱**只看最後子句**
 *    ——看整則會讓「你一直丟地名，那我先去忙吧」因為前半句有「你」而過關
 *    （Codex R2 P1-2）。
 *
 * **接受的代價**：帶第二人稱的提議句（「你早點睡吧」）仍算是非問句。那一格
 * 玩家回「好」本來就是回答了，方向安全；而 `check_out` 的 act 說明已經明寫
 * 「不問他問題」，她在那一輪本來就不該冒出這種句子。
 */
export function aiAskedYesNoQuestion(text: string): boolean {
  // 第 1 關要對**剝掉句尾裝飾後**的字串做：`AI_QUESTION_RE` 的
  // `(嗎|呢|吧)\s*$` 錨在原字串結尾，「你在報地名嗎😂」「是玩猜謎嗎～」
  // 這種真人寫法會整批判漏（Phase 4.3 `isQuestionTextTolerant` 同一個坑）。
  if (!aiAskedQuestion(text.trim().replace(TAIL_DECORATION_RE, ""))) {
    return false;
  }
  const last = yesNoFinalClause(text);
  if (!YES_NO_FINAL_PARTICLE_RE.test(last)) return false;
  return /嗎$/u.test(last) || SECOND_PERSON_RE.test(last);
}
// 整則錨定，只容忍句尾裝飾（空白／標點／emoji，同 `TAIL_DECORATION_RE`）。
// 刻意不加同義詞：多一個詞就多一次誤判，漏了只是退回 4.3 現況。
const YES_NO_SHORT_ANSWER_RE =
  /^(對|對啊|嗯對|是|是啊|不是|沒有|沒錯|不對|不要|好|好啊)$/u;
export function isYesNoShortAnswer(text: string): boolean {
  return YES_NO_SHORT_ANSWER_RE.test(
    compact(text).replace(TAIL_DECORATION_RE, ""),
  );
}

/**
 * Phase 4.3：容忍句尾裝飾的問句判準。`QUESTION_RE` **錨在句尾**，所以「你在報
 * 地名嗎😂」「是玩猜謎嗎～」在 `isQuestionText` 都判 false——Phase 4.2 的逐泡泡
 * 診斷量到 truncate 因此在 15 筆裡有 12 筆整個失效（README／計畫檔 Phase 4.2）。
 *
 * 這裡重用強制問句判準已經在用的 `TAIL_DECORATION_RE`（空白／emoji／`~～`／
 * `…`／`!！,，.。、`），剝掉之後再走**同一支** `QUESTION_RE`，所以它是
 * `isQuestionText` 的**真超集**（剝掉的字元永遠不是 `QUESTION_RE` 認的標記）。
 *
 * 語助詞「喔／啦／耶」刻意**不**剝：那不是問句標記，剝了會把「好喔」判成問句。
 *
 * **為什麼不直接改 `isQuestionText`**：它同時被 `detectTurnSignals`
 * （`userIsQuestion`／`userQuestionStreak`，`turn_response_plan.ts`）消費，那條
 * 路徑在旗標 off 時也會跑，改了會動 golden。所以新開一支，只給 agency on 才
 * 走得到的 consumer 用（目前是 `truncateAgencyShape`）。`utteranceShapeOf`
 * 也刻意不換——換掉會整批改變玩家訊息的形狀分佈，不在本刀範圍。
 */
export function isQuestionTextTolerant(text: string): boolean {
  return QUESTION_RE.test(text.trim().replace(TAIL_DECORATION_RE, ""));
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
  /**
   * Phase 4.5a 刀 1：她上一則是**是非問句**（`aiAskedYesNoQuestion`）。省略＝
   * false＝逐字沿用 4.3 行為（`contentUserTurnCount` 那個 caller 就是這樣傳）。
   */
  previousAiAskedYesNo = false,
): UtteranceShape {
  const compacted = compact(text);
  if (compacted.length === 0) return "unknown";
  if (hasExplicitPivot(text)) return "explicit_pivot";
  // Phase 4.3（Codex R1 P2-5）：問句判定改用容忍句尾裝飾的那一支。玩家自己打
  // 「所以你是說我很閒嗎😂」以前會判成低資訊形狀（進欠債、可能被質疑），現在
  // 判成問句、直接 NO_OVERRIDE。`utteranceShapeOf` 的每一個 caller 都在
  // agency ≠ off 之後（`computeAgencyDecision` 對 off 提早回 null；
  // `planTurnResponse` 的 `contentUserTurnCount` 雖然無條件計算，但唯一的
  // consumer `forceAskUser` 要求 `agency.enabled === true`），所以 off 路徑
  // 的四面輸出不變——等價 harness 守門。
  if (isQuestionTextTolerant(text)) return "question";
  // Phase 4.5a 刀 1：她問是非題、他整則就回「對／不是」＝答案。放在 reaction
  // 之前，因為「好」「好啊」本來會被 `REACTION_RE` 先接走。
  if (previousAiAskedYesNo && isYesNoShortAnswer(text)) {
    return "answer_candidate";
  }
  // Phase 4.3（Codex R1 P2-4）：反應詞同樣容忍句尾裝飾——「對！」「不是😂」
  // 「沒有。」在真人輸入裡比裸詞常見得多。剝到空字串（整則就是 emoji）時退回
  // 原字串，讓 `REACTION_RE` 既有的純 emoji 分支照樣接得到。
  const reactionCore = compacted.replace(TAIL_DECORATION_RE, "");
  // 整則剝完只剩空字串＝這一則除了裝飾什麼都沒有（純 emoji、純標點），本來就是
  // 反應。這比在 `REACTION_RE` 的 emoji 分支再抄一次 ZWJ／variation selector／
  // keycap 的字元類小，而且對 `👨‍👩‍👧‍👦` 這種多 code point 序列一次到位（U-9）。
  if (reactionCore.length === 0) return "reaction";
  if (REACTION_RE.test(reactionCore)) return "reaction";
  if (FIRST_PERSON_RE.test(text) || EXPLANATION_RE.test(text)) {
    return "self_share";
  }
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
    /** Phase 4.5a 刀 1：她問是非題、他整則回一個肯定／否定短詞。 */
    answeredYesNo: boolean;
  }[] = [];
  let lastAiText: string | null = null;
  for (const turn of turns) {
    if (turn.role === "ai") {
      lastAiText = turn.text;
      continue;
    }
    const previousAiAskedQuestion = lastAiText !== null &&
      aiAskedQuestion(lastAiText);
    const previousAiAskedYesNo = lastAiText !== null &&
      aiAskedYesNoQuestion(lastAiText);
    shapes.push({
      text: turn.text,
      shape: utteranceShapeOf(
        turn.text,
        previousAiAskedQuestion,
        previousAiAskedYesNo,
      ),
      previousAiAskedQuestion,
      previousAiAskedQuestionStrict: lastAiText !== null &&
        aiAskedQuestionStrict(lastAiText),
      answeredYesNo: previousAiAskedYesNo && isYesNoShortAnswer(turn.text),
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
    // Phase 4.5a 刀 1：她的是非問句被回答了——這一句不累加欠債，也不留下
    // 「她已經叫他講清楚而他沒做」的起點（`told`）。既有的欠債**不歸零**：
    // 回答一個是非題不是結構修復，前面沒解決的仍然沒解決。
    if (s.answeredYesNo) {
      told = false;
      continue;
    }
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
    answeredYesNo: current?.answeredYesNo ?? false,
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
    // Phase 4.3：兩個「上一輪的地面真相」原樣帶進 policy（純轉送，不做判斷）。
    aiClarifiedLastTurn: typeof prev?.aiClarifiedLastTurn === "boolean"
      ? prev.aiClarifiedLastTurn
      : null,
    priorCoherence: prev?.lastCoherence ?? null,
    // Phase 3.2 P1-3：`precedingUserContext` 刻意**不**受修復點限制——修復點
    // 之前玩家講清楚過的內容仍然是他給過的前文，砍掉會讓 A07／A09 那種
    // 「先鋪前文再丟短詞」在 assisted 模式反而被判成無前文片段（更嚴，不是更鬆）。
    precedingUserContext: earlier.some((s) =>
      s.shape !== "reaction" && !isLowInformation(s.shape)
    ),
    aiQuestionedInLoop,
    userTurnCount: shapes.length,
    // Phase 4.5a 刀 3：純轉送持久化狀態（standard 的 `prev` 是 null＝0／false）。
    lowValueStreak: prev?.lowValueStreak ?? 0,
    checkedOut: prev?.checkedOut === true,
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
  /**
   * Phase 4.0：這一輪套用的分人強弱（`agencyProfileFor`），只給 telemetry 與
   * planner 讀；null＝呼叫端沒給（門檻逐字沿用難度表）。
   */
  readonly profile: ConversationAgencyProfile | null;
}

const NO_OVERRIDE: Omit<AgencyDecision, "version" | "evidence"> = {
  situation: null,
  policyMode: "forced",
  forcedAct: null,
  allowedActs: [],
  allowedActSetId: "none",
};

/** 分人強弱的量尺（Phase 4.0，報告 §7.3）；0＝最低、4＝最高。 */
export type AgencyLevel = 0 | 1 | 2 | 3 | 4;

/**
 * conversation-agency-v1 Phase 4.0：角色的對話主體強弱（報告 §7.3）。
 *
 * 純資料型別，刻意住在本檔而不是 `agency_profile.ts`：門檻函式要吃它，本檔
 * 又不能 import `reply_style.ts`（依賴單向）。實際的 mapping 表與
 * `agencyProfileFor()` 在 `agency_profile.ts`。
 *
 * 報告 §7.3 列的第五個欄位 `strangerCuriosity` 不在這裡——它就是既有的
 * `ReplyStyleProfile.turnTaking.questionHabit`（值域相同，Phase 3.8 已經在
 * 消費），理由寫在 `agency_profile.ts` 檔頭。
 */
export interface ConversationAgencyProfile {
  /** 主動開自己的題（不是替玩家救場）：`planTurnResponse` 的 optionalAct。 */
  readonly initiative: AgencyLevel;
  /** 把話拉回未聊完的那件事：欠債輪候選 act 多一個 `return_to_topic`。 */
  readonly topicPersistence: AgencyLevel;
  /** 第一次模糊時澄清還是先短接一次：`firstFragmentActs`。 */
  readonly ambiguityTolerance: AgencyLevel;
  /** 多早停止供應解讀：`holdAt`。 */
  readonly skepticism: AgencyLevel;
}

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
  /**
   * Phase 4.5a（Codex R2 P3-1）：這一場允許**強制結束**（`check_out`／
   * `read_only`）。值目前恆等於 `forceEndLoopBeforeChallenge`，但那是「收尾格
   * 要收掉還是維持立場」，跟「她可不可以直接先去忙」是兩件事——共用一支具名
   * predicate（`allowsCheckOut`）讓 policy 與 planner 不會各自漂移。
   */
  readonly allowsCheckOut: boolean;
}

/**
 * 允許強制結束的場：挑戰難度或 Game。planner 的「（已讀）」開關與 policy 的
 * `check_out`／`read_only` 閘門共用這一支（Codex R2 P3-1）。
 */
export function allowsCheckOut(
  difficulty: "easy" | "normal" | "challenge",
  isGame: boolean,
): boolean {
  return difficulty === "challenge" || isGame;
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
    allowsCheckOut: false,
  },
  // 一般（Eric 的基準）：第一個片段 bounded {接住, 問意思}；第二個未解片段就要
  // 二選一（真的回答了就接受，沒回答就直說他跳題）；第三個以後維持立場。
  normal: {
    firstFragmentActs: ["acknowledge", "ask_intent"],
    debtAnswerActs: ["accept_if_answered", "challenge_relevance"],
    holdAt: 2,
    forceEndLoopBeforeChallenge: false,
    allowsCheckOut: false,
  },
  // 挑戰／Game：早一步——她已經問過的話，第二個未解片段就直接收掉這串。
  challenge: {
    firstFragmentActs: ["acknowledge", "ask_intent"],
    debtAnswerActs: ["accept_if_answered", "challenge_relevance"],
    holdAt: 1,
    forceEndLoopBeforeChallenge: true,
    allowsCheckOut: true,
  },
};

/**
 * Game 模式套挑戰難度門檻（既有 Game FSM 的修復優先／越界／邀約方向不受影響，
 * 由呼叫端保留原優先權）。
 *
 * Phase 4.0：難度表是 base，`profile` 只做三個位移（報告 §7.3 每個欄位都要有
 * consumer）。省略 `profile`＝逐字沿用難度表（off 路徑與接線前相同）。
 */
export function agencyThresholdsFor(
  difficulty: "easy" | "normal" | "challenge",
  isGame: boolean,
  profile?: ConversationAgencyProfile | null,
): AgencyThresholds {
  const base = isGame
    ? AGENCY_THRESHOLDS.challenge
    : AGENCY_THRESHOLDS[difficulty];
  if (!profile) {
    return { ...base, allowsCheckOut: allowsCheckOut(difficulty, isGame) };
  }
  // ambiguityTolerance：第一個無前文裸片段要澄清還是先短接一次。
  // Phase 2.7 把三個難度的第一個片段全部降成 bounded {acknowledge, ask_intent}
  // （forced 只留同詞重複與欠債到門檻）；這裡**只有低容忍的人**把 forced 收回來，
  // 而且範圍不變——仍然只有「沒有前文、沒有欠債」的裸片段那一輪，有效短答的
  // 免疫（`answer_candidate` + unresolvedCount 0）在 `agencyPolicyFor` 上游就
  // 已經 NO_OVERRIDE 接走，不受影響。
  const firstFragmentActs: readonly PlanAct[] = profile.ambiguityTolerance <= 1
    ? ["ask_intent"]
    : base.firstFragmentActs;
  // skepticism：多早停止供應解讀。高懷疑早一步、低懷疑晚一步；上下界維持 1–3，
  // `forceEndLoopBeforeChallenge`（維持立場還是直接收掉）仍然只由難度決定。
  const holdAt = profile.skepticism >= 3
    ? Math.max(1, base.holdAt - 1)
    : profile.skepticism <= 1
    ? Math.min(3, base.holdAt + 1)
    : base.holdAt;
  // topicPersistence：高持續度的人在欠債輪多一個「直接把話拉回上一題」的選項。
  const debtAnswerActs: readonly PlanAct[] = profile.topicPersistence >= 3
    ? [...base.debtAnswerActs, "return_to_topic"]
    : base.debtAnswerActs;
  return {
    ...base,
    firstFragmentActs,
    holdAt,
    debtAnswerActs,
    // 難度表的 base 已經帶對值（challenge 才 true），這裡再用同一支 predicate
    // 算一次，`isGame` 的路徑就不必依賴「base 剛好被換成 challenge」這件事。
    allowsCheckOut: allowsCheckOut(difficulty, isGame),
  };
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
  // ── Phase 4.5a 刀 3：不收斂階梯 ──────────────────────────────────────
  // 三格都**只吃持久化狀態**（`lowValueStreak`／`checkedOut`），所以 standard
  // （`prev === null`）永遠是 0／false＝這一段整個走不到，逐字沿用 4.4 行為。
  // 放在最前面：一旦她已經先去忙了，任何形狀判斷都不該再把她拉回原本的格子。
  //
  // Codex R1 P1-2：**強制結束（`check_out`／`read_only`）只給挑戰難度或 Game**
  // ——`thresholds.allowsCheckOut`（`allowsCheckOut(difficulty, isGame)`，與
  // planner 的「（已讀）」開關共用同一支 predicate；Codex R2 P3-1）恰好就是那個條件
  // （`AGENCY_THRESHOLDS.challenge` 是唯一 true 的一格，`agencyThresholdsFor`
  // 對 `isGame` 直接套 challenge，profile 位移也不動這個欄位）。beginner 的
  // easy／normal streak 照算、`cold_return` 照走，但到 3 不結束，留在既有的
  // `hold_position`／`end_low_value_loop`（她冷但會回）。這一道是**防禦性**
  // 的：就算 thread row 被直接種成 `lowValueStreak: 3`／`checkedOut: true`，
  // 輕鬆難度也不得強制結束。
  if (isAgencyContentShape(shape) || evidence.answeredYesNo) {
    // 他終於給了內容：階梯歸零，但這一輪她是「回來但冷」，不補回剛才的落差。
    if (evidence.checkedOut || evidence.lowValueStreak > 0) {
      return {
        ...base,
        situation: "cold_return",
        policyMode: "forced",
        forcedAct: "cold_return",
        allowedActs: ["cold_return"],
        allowedActSetId: "cold_return_v1",
      };
    }
  } else if (evidence.checkedOut && thresholds.allowsCheckOut) {
    // 她說過先忙了，他又丟一個沒內容的東西 → 直接一則「（已讀）」，不打模型。
    return {
      ...base,
      situation: "repeated_low_coherence",
      policyMode: "forced",
      forcedAct: "read_only",
      allowedActs: ["read_only"],
      allowedActSetId: "read_only_v1",
    };
  } else if (
    evidence.lowValueStreak >= LOW_VALUE_STREAK_CHECK_OUT &&
    thresholds.allowsCheckOut
  ) {
    return {
      ...base,
      situation: "repeated_low_coherence",
      policyMode: "forced",
      forcedAct: "check_out",
      allowedActs: ["check_out"],
      allowedActSetId: "check_out_v1",
    };
  }
  if (!isLowInformation(shape)) return { ...base, ...NO_OVERRIDE };
  // Phase 4.5a 刀 1：她問是非題、他整則回「對／不是」＝回答了，任何欠債都
  // 不得把它翻成質疑（同詞重複也不行——連兩題是非題答「對」是正常對話）。
  if (evidence.answeredYesNo) return { ...base, ...NO_OVERRIDE };
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
    // ── Phase 4.3（Eric 2026-09-05 定調；Codex R1 P1-1／P1-2 後重寫）────────
    //
    // Eric 的原話界線：「第二、三輪對方打很奇怪無關的東西，正常女生會回『？』
    // 『你在講什麼』或直接冷淡，不可能尬聊。這條邊界要死守。」
    //
    // **要補的洞**：上面的強制格有一道 `bare_fragment` 閘門（Codex round-1
    // P1-c）——她剛問完、他回一句沒有結構線索的話時結構層分不出那是不是答案，
    // 所以永遠不 forced。Phase 4.2 的 15 筆跨輪立場失敗全部落在這裡。
    //
    // **不能只看結構**（Codex R1 P1-1）：同樣是「她問了 → 他回一句沒有第一
    // 人稱標記的短句」，「想去日本」是對內容問題的正當回答、「清邁」是又跳題，
    // 兩者在句法上**完全同形**。硬判就是拿純函式判語意（踩坑「純函式訊號層硬
    // 判高語意會被獨立審查逐條打」），所以判斷交給讀得到全文的模型，結構層只
    // 消費它已經吐出來的結構化欄位。
    //
    // **可用的地面真相**：`aiClarifiedLastTurn` ＝分類器讀完**她實際生成的那
    // 一則**之後回報的 `aiChallengedThisTurn`（「是不是真的在問清楚意思或指出
    // 跳題／不相關」）。她上一則是澄清 → 再丟一個沒線索的詞就不是答案；她上
    // 一則是內容問題 → 短句很可能就是答案，交給 bounded 的條件式。
    //
    // **已查證的時序限制（Codex R1 追問）**：production 的分類器
    // （`buildTurnClassifierMessages`）吃 `assistantReply`，在 `handler.ts` 裡
    // 於 chat 生成**之後**才呼叫（`buildChatPromptBundle` 早於
    // `judgeLearningState`），所以**當輪**的 coherence 在 `agencyPolicyFor`
    // 時拿不到。這裡用的是**上一輪**已經持久化的判斷，這是可得的最近似訊號。
    // 差距：他這一輪的正當回答要到**下一輪**才會被分類器判成 connected 並
    // 歸零欠債，所以第一次仍可能被質疑一次（見計畫檔 Phase 4.3「殘留成本」）。
    //
    // 條件（全部是既有／持久化欄位，沒有新偵測器、沒有語意判斷）：
    if (
      shape === "answer_candidate" && evidence.aiQuestionedInLoop &&
      // Codex R1 建議的顯式閘門：上一輪分類器判 connected 就不強制。
      // **實測今天恆真**（分類器判 connected 會寫下 `repairedAtUserTurns`／
      // 走舊 row 退路把欠債歸零，`unresolvedCount` 因此是 0，上面的免疫格就
      // 已經接走了），留著是為了讓「connected 不強制」寫在條件式裡而不是靠
      // 另一個檔案的副作用；有測試證明它今天是冗餘的。
      evidence.priorCoherence !== "connected" &&
      // R2（Codex P1-2）：**只認分類器明確說「她上一則真的在澄清」**。
      // `null`（standard 沒有分類器、分類器呼叫或解析失敗）一律**不強制**，
      // 維持 4.3 之前的 bounded 二選一——4.3 一度用 `!precedingUserContext`
      // 當退路，但那讓同一份逐字稿只因為 mode 或分類器可用性就改變安全邊界，
      // 兩個方向的誤判（R1 的 P1-1 與 P1-2）都會從那條退路漏回來。
      // 代價：**死守邊界只在 assisted（beginner／game）成立**；standard 沒有
      // 分類器，維持既有的「接得上就接受、接不上就直說」二選一。
      evidence.aiClarifiedLastTurn === true
    ) {
      return {
        ...base,
        situation: "abrupt_topic_shift",
        policyMode: "forced",
        forcedAct: "challenge_relevance",
        allowedActs: ["challenge_relevance"],
        // 難度口氣分三檔（報告 §7.4「難度只調門檻與口氣」）。從 thresholds 推，
        // 不新增參數：easy 的 `debtAnswerActs` 是唯一含無條件 `acknowledge` 的，
        // challenge／Game 是唯一 `forceEndLoopBeforeChallenge` 的。
        allowedActSetId: thresholds.forceEndLoopBeforeChallenge
          ? "clarify_ignored_cold_v1"
          : thresholds.debtAnswerActs.includes("acknowledge")
          ? "clarify_ignored_easy_v1"
          : "clarify_ignored_v1",
      };
    }
    const acts = thresholds.debtAnswerActs;
    return {
      ...base,
      situation: "abrupt_topic_shift",
      policyMode: "bounded",
      forcedAct: null,
      allowedActs: acts,
      // Phase 4.0：高 topicPersistence 多一個 `return_to_topic`，telemetry 上
      // 要看得出來是哪一組候選（`persist` 變體），不能借用原本的 id。
      allowedActSetId: acts.includes("return_to_topic")
        ? (acts.includes("acknowledge")
          ? "answer_or_challenge_persist_easy_v1"
          : "answer_or_challenge_persist_v1")
        : (acts.includes("acknowledge")
          ? "answer_or_challenge_easy_v1"
          : "answer_or_challenge_v1"),
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
  if (
    r.askedAboutUser !== undefined && typeof r.askedAboutUser !== "boolean"
  ) return null;
  // R2 U-8：`null` 字面值視同缺席。JSONB round-trip、RPC 或 client 都可能把
  // 省略的欄位補成 JSON null，那不該讓**整份** state 解析失敗（欠債、修復點、
  // askedAboutUser 會一起丟掉）。只有真的型別不對才整份作廢。
  if (
    r.aiClarifiedLastTurn !== undefined && r.aiClarifiedLastTurn !== null &&
    typeof r.aiClarifiedLastTurn !== "boolean"
  ) return null;
  // Phase 4.5a 刀 3：舊 row 缺這兩個欄位＝0／false（不是解析失敗）；
  // `null` 字面值同 U-8 規則視同缺席。型別真的不對才整份作廢。
  if (
    r.lowValueStreak !== undefined && r.lowValueStreak !== null &&
    !(typeof r.lowValueStreak === "number" &&
      Number.isInteger(r.lowValueStreak) && r.lowValueStreak >= 0)
  ) return null;
  if (
    r.checkedOut !== undefined && r.checkedOut !== null &&
    typeof r.checkedOut !== "boolean"
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
    ...(r.askedAboutUser === true ? { askedAboutUser: true } : {}),
    // Phase 4.3：`false` 與缺席**意思不同**（見型別註解），所以兩種布林都要
    // 原樣帶回，只有真的缺席才不放這個 key。
    ...(typeof r.aiClarifiedLastTurn === "boolean"
      ? { aiClarifiedLastTurn: r.aiClarifiedLastTurn }
      : {}),
    // 0／false 是預設值，不寫 key（同 `repairedAtUserTurns`／`askedAboutUser`）。
    // Codex R1 P2-2：state 宣稱 clamp 在 `LOW_VALUE_STREAK_CHECK_OUT`，讀回來
    // 也要照做（舊 row／外部寫入的 4、999 一律當 3），不然「clamp 3」只在
    // 寫入端成立。
    ...(typeof r.lowValueStreak === "number" && r.lowValueStreak > 0
      ? {
        lowValueStreak: Math.min(LOW_VALUE_STREAK_CHECK_OUT, r.lowValueStreak),
      }
      : {}),
    ...(r.checkedOut === true ? { checkedOut: true } : {}),
  };
}

const COHERENCE_BY_SITUATION: Record<
  AgencySituation,
  ConversationAgencyState["lastCoherence"]
> = {
  ambiguous_fragment: "ambiguous",
  // Phase 4.5a 刀 3：他確實給了內容，不該記成 disconnected／repetitive；
  // 但這一輪她仍然是冷的，也不是「連上了」——`ambiguous`＝不獎不罰。
  cold_return: "ambiguous",
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
  /** Phase 3.8：這一輪 planner 有沒有強制她問他一件事（`plan.askUserFocus`）。 */
  askedAboutUserThisTurn = false,
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
  // ── Phase 4.5a 刀 3：階梯的狀態推進 ───────────────────────────────────
  // 只認**這一輪 planner 真的下的 forced act**（跟 `priorChallengeIssued` 同一
  // 個規則：允許過 ≠ 做過）。玩家給了結構內容就整條歸零並解除 checkedOut。
  const ladderContent =
    isAgencyContentShape(decision.evidence.utteranceShape) ||
    decision.evidence.answeredYesNo;
  const lowValueStreak = ladderContent
    ? 0
    : isLowValueStreakAct(forced)
    ? Math.min(LOW_VALUE_STREAK_CHECK_OUT, (base.lowValueStreak ?? 0) + 1)
    : base.lowValueStreak ?? 0;
  const checkedOut = ladderContent
    ? false
    : base.checkedOut === true || forced === "check_out";
  return {
    version: 1,
    lastCoherence: classifierSignal?.coherence ?? structuralCoherence,
    unresolvedCount: decision.evidence.unresolvedCount,
    priorChallengeIssued: (repaired ? false : base.priorChallengeIssued ||
      decision.evidence.priorChallengeIssued) ||
      challengedThisTurn,
    lastAgencyAct,
    ...(repairedAtUserTurns === undefined ? {} : { repairedAtUserTurns }),
    ...(base.askedAboutUser === true || askedAboutUserThisTurn
      ? { askedAboutUser: true }
      : {}),
    // Phase 4.3：**不黏住**——這是「她上一則」的事實，每一輪重寫。只有分類器
    // 真的給了布林才落欄位；缺席（standard、分類器失敗）就不留，下一輪的
    // `agencyPolicyFor` 會退回保守的 standard 規則。
    ...(typeof classifierSignal?.aiChallengedThisTurn === "boolean"
      ? { aiClarifiedLastTurn: classifierSignal.aiChallengedThisTurn }
      : {}),
    ...(lowValueStreak > 0 ? { lowValueStreak } : {}),
    ...(checkedOut ? { checkedOut: true } : {}),
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

// ── Phase 4.4：混合模型路由（PRACTICE_CHAT_MODEL_ROUTING）──────────────────
/**
 * 女生回覆這一輪要打哪一支模型。`"mixed"`＝她要介入的輪次換 Claude Haiku 4.5、
 * 其餘維持 DeepSeek（Phase 4.3 三臂黑箱：頭條 3.4%、陪玩 1.7%，且比全 Haiku 便宜）。
 *
 * 條件與黑箱 runner 的 `--chat-model=mixed` 臂**逐字相同**（runner 的選模入口
 * 直接呼叫本函式）：agency 解析成 `on` 且這一輪 `agencyDecision.applied === true`
 * （planner 真的注入了 guidance）。旗標不是 `"mixed"`（未設／`off`／亂填）、
 * agency `off`／`shadow`、或這一輪沒介入，一律 `"deepseek"`＝與接線前逐字相同。
 *
 * Codex R1 P1（範圍）：**`standard` 一律 deepseek**。Phase 4.3 三臂黑箱只量過
 * `beginner ＋ --state=1`，而 standard 連分類器都沒有（4.3 的死守邊界在
 * standard 本來就不成立），介入輪的分佈與品質都沒量過——證據涵蓋不到的模式
 * 不進路由。game 併入前要先跑小黑箱。
 *
 * 2026-09-05（Eric 拍板）：除了介入輪，**越界輪**（`situation === "boundary"`
 * ——既有 planner 的最高優先權，強制 `direct_boundary`）也走 Haiku：劃界線是
 * 最不能出錯的一輪。越界輪的 `applied` 恆為 false（`computeAgencyDecision` 只
 * 在 `neutral` 保留決策），所以這是**獨立**的第二個入口，不是 applied 的子集。
 */
export type PracticeChatModel = "deepseek" | "haiku";

export function chatModelFor(
  routingFlag: string | undefined,
  agencyMode: AgencyMode,
  agencyDecision: { readonly applied: boolean } | null | undefined,
  practiceMode: string | null | undefined,
  situation?: string | null,
): PracticeChatModel {
  if (routingFlag !== "mixed") return "deepseek";
  if (agencyMode !== "on") return "deepseek";
  if (practiceMode !== "beginner" && practiceMode !== "game") return "deepseek";
  if (situation === "boundary") return "haiku";
  return agencyDecision?.applied === true ? "haiku" : "deepseek";
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
  // R1（Codex）：`situation !== null` 明寫出來，不靠 `applied` 的定義隱含。
  // 有效短答免疫、明示換題、問句、分享那些輪次的 situation 就是 null，
  // 呼叫端若自己組了一個 `applied: true` 的 application（測試、未來的呼叫端）
  // 也不得因此被截斷。
  if (!agency?.applied || agency.decision.situation === null) return false;
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
  // Phase 4.3：句尾 emoji／語尾裝飾不影響「第一顆是不是問句」（見
  // `isQuestionTextTolerant`）。她的回覆幾乎都帶 emoji，用錨句尾的判準等於
  // 讓這把刀在中文口語上大量失效。
  if (bubbles.length <= 1 || !isQuestionTextTolerant(bubbles[0])) {
    return { text: reply, dropped: 0 };
  }
  return { text: bubbles[0], dropped: bubbles.length - 1 };
}
