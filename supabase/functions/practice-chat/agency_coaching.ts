// 練習室「對話主體意識」Phase 4.1：Hint／Debrief 的結構化教練證據。
//
// 計畫 `docs/plans/2026-09-03-practice-conversation-agency-plan.md` Phase 4
// 「Hint／Debrief P2：教練能指出『沒有回答她、連續丟詞』，且角色的 repair 不算
// 玩家得分」；夥伴報告 §P0-7、§11 表格 P2 那列。
//
// 界線（與 `conversation_agency.ts` 檔頭同一條）：本檔**只消費**該檔已經算好的
// 結構證據（`detectAgencyEvidence` → `agencyPolicyFor`）與持久化狀態，自己不做
// 任何語意判斷、不加 regex、不看字數。輸出是 enum 與整數，渲染由 hint.ts／
// prompt.ts 負責——所以本檔不 import 那兩個檔（依賴單向）。
//
// 旗標：呼叫端只在 `agencyMode === "on"` 時把結果餵進 prompt；`off`／`shadow`
// 傳 undefined＝prompt 逐字不變（`agency_flag_off_equivalence_test.ts` 守門）。

import type { PracticeTurn } from "./validate.ts";
import {
  agencyPolicyFor,
  type AgencyThresholds,
  agencyThresholdsFor,
  aiAskedQuestion,
  type ConversationAgencyState,
  detectAgencyEvidence,
  INITIAL_CONVERSATION_AGENCY_STATE,
  nextConversationAgencyState,
} from "./conversation_agency.ts";
import { agencyProfileFor } from "./agency_profile.ts";

/**
 * 門檻的來源必須與 chat 路徑**同源**（`prompt.ts` 的
 * `agencyThresholdsFor(profile.difficulty, practiceMode === "game",
 * agencyProfileFor(profile.girl.profileId))`）。用預設的一般難度會讓同一場
 * 對話在 chat 與 hint／debrief 兩層算出不同的介入輪。刻意**沒有預設值**：
 * 呼叫端一定要交出這一場的難度、是不是 Game、以及角色 id。
 */
export interface AgencyCoachingContext {
  readonly difficulty: "easy" | "normal" | "challenge";
  readonly isGame: boolean;
  readonly profileId: string;
}

function thresholdsFor(ctx: AgencyCoachingContext): AgencyThresholds {
  return agencyThresholdsFor(
    ctx.difficulty,
    ctx.isGame,
    agencyProfileFor(ctx.profileId),
  );
}

// ── A. Hint：這一輪教練要不要點出「你還沒回答她」──────────────────────────
export type HintAgencyCoachingKind =
  | "answer_her_question"
  | "stop_dropping_words"
  | "none";

export interface HintAgencyCoaching {
  readonly kind: HintAgencyCoachingKind;
  readonly unresolvedCount: 0 | 1 | 2 | 3;
}

/** hint 的逐字稿最後一則一定是她（`invalid_hint_last_turn_must_be_ai`）。 */
function lastAiText(turns: readonly PracticeTurn[]): string | null {
  const last = turns.at(-1);
  return last?.role === "ai" ? last.text : null;
}

/**
 * 只在**結構層真的認定玩家上一則沒接上**時點火：`agencyPolicyFor` 這一輪有
 * situation（片段／跳題／低連貫迴圈）。有效短答（她剛問完、他答了、沒有欠債）
 * 在 `agencyPolicyFor` 上游就已經 NO_OVERRIDE，所以永遠回 `none`——否則她每問
 * 一句，教練就多印一行「你還沒回答她」，正常對話全部被誤判。
 *
 * 兩個 kind 的順序刻意是「嚴重的先」：欠債 ≥2 或同詞重複時，「連續丟詞」的建議
 * 本來就含「接回她的問題」，而那種局面她幾乎一定剛問過話，answer 先判會讓
 * `stop_dropping_words` 實質上是死碼。
 */
export function hintAgencyCoachingFor(
  turns: readonly PracticeTurn[],
  agencyState: ConversationAgencyState | null,
  ctx: AgencyCoachingContext,
): HintAgencyCoaching {
  const evidence = detectAgencyEvidence(turns, agencyState);
  // 門檻走 `ctx`（與 chat 同源）。今天 `situation !== null` 這道閘門其實**證明性地
  // 不吃門檻**——`agencyPolicyFor` 的三個 NO_OVERRIDE 出口（非低資訊形狀、有效
  // 短答、有前文的零欠債片段）與其餘全部非 null 的分支都與 thresholds 無關，
  // 所以今天換難度不會改變 kind。仍然照傳，是為了讓這兩層永遠不可能各自帶一
  // 份預設值漂掉（踩坑：同一道守門在兩端各自帶預設值會漂成確定性全滅）。
  const decision = agencyPolicyFor(evidence, thresholdsFor(ctx));
  const unresolvedCount = evidence.unresolvedCount;
  if (decision.situation === null) return { kind: "none", unresolvedCount };
  if (unresolvedCount >= 2 || evidence.repeatedExactToken) {
    return { kind: "stop_dropping_words", unresolvedCount };
  }
  const act = agencyState?.lastAgencyAct;
  // 「她剛問了」用**寬鬆**判準（`aiAskedQuestion`），不是強制格那支嚴格的。
  // 計畫 brief 原本寫 `aiAskedQuestionStrict`，但那一支是寬鬆的真子集，且刻意
  // 只認句尾標記——中文最常見的無標記問句（「東東是誰」「阿布達比？那是哪裡」
  // 的最後一個子句）全部判 false，這一格會直接變死碼。方向也不同：強制格判多
  // ＝她根本沒問就被強制停止解讀；這裡判多只是多印一行「先回答她」的教練指引，
  // 而且上面的 `situation !== null` 已經先確定玩家上一則結構上就沒接上。
  const sheAsked = aiAskedQuestion(lastAiText(turns) ?? "") ||
    act === "ask_intent" || act === "challenge_relevance" ||
    act === "return_to_topic";
  return sheAsked
    ? { kind: "answer_her_question", unresolvedCount }
    : { kind: "none", unresolvedCount };
}

// ── B. Debrief：哪些輪次是她在補救（不算玩家得分）────────────────────────
export interface DebriefAgencyLedger {
  readonly fragmentTurns: number;
  readonly topicShiftTurns: number;
  readonly loopTurns: number;
  /** 她介入的玩家輪序號（第 N 則玩家訊息，1-based），最多列 10 個。 */
  readonly repairTurns: readonly number[];
  /**
   * 介入輪的**真實總數**（＝三個計數之和）。刻意不讓呼叫端用
   * `repairTurns.length` 代替：那一欄被 `MAX_REPAIR_TURNS` 截過，超過 10 輪的
   * 場會把 12 記成 10（Codex R1 P2）。prompt 只列前 10 個序號，telemetry 記總數。
   */
  readonly repairTurnCount: number;
}

const MAX_REPAIR_TURNS = 10;

/**
 * 結構回放：逐則玩家訊息重走 `detectAgencyEvidence → agencyPolicyFor`，
 * 狀態用 `nextConversationAgencyState` 推進。
 *
 * **Phase 4.5c 刀 2**：第三個參數是這一場 thread 上的持久化 agency 狀態。
 * 給了就把它的 `repairedAtUserTurns`（分類器判 `connected` 的最後一個修復點）
 * 注回回放，讓那個位置之前的片段不再被重算成介入輪——這是回放與正式 chat
 * 路徑之間唯一補得回來的分類器事實。4.5b 之後 standard 也會寫這一格
 * （`PRACTICE_STANDARD_AGENCY_CLASSIFIER=true`），所以 standard 與 beginner
 * 從此**同源**：同一份 `turns`＋`ctx`＋`agencyState` 一定算出同一份帳，
 * 本函式沒有任何 practiceMode 分支。省略／`null`＝維持 4.1 的純結構近似。
 *
 * **近似的界線**（跟 `tools/practice-agency-eval/replay_plan.ts --state=1`
 * 同一種）：`classifierSignal` 一律傳 null，因為 debrief 手上沒有每一輪當時的
 * 分類器輸出；所以「分類器判 connected 的修復點」在這裡不存在，只有逐字稿看得
 * 到的結構修復（問句／第一人稱分享／明示換題）會歸零。
 *
 * **風險方向是雙向的，不是偏保守**（Codex R2 P3；舊註解的「不會憑空多出介入輪」
 * 是沒有差分證據的宣稱，已撤回）：少掉一次 live classifier 的 `connected` 修復，
 * 欠債會留得比正式路徑久，**後續輪次因此可能被判成介入輪**（`unresolvedCount`
 * 跨過 `holdAt`／落進 `abrupt_topic_shift`），也就是有機會**多扣分**；另一方面
 * 沒有 `repairedAtUserTurns` 時，`detectAgencyEvidence` 的舊 row 相容退路
 * （上一輪結構 coherence 是 `connected` 就把欠債歸零）又會把帳斷開，方向相反。
 * 兩股力道誰大沒有量過——要證明得跑「中途 classifier=connected 的正式狀態回放」
 * 對「全 null 回放」的 repair-turn 差集，既有 artifact 沒記逐輪分類器輸出。
 *
 * 另外，這份帳記的是「結構層判定**需要**她介入」，**不保證她真的補救了**
 * （沒有檢查下一則 AI 回覆），渲染文字因此寫「需要她補救的輪次」。
 * 難度門檻與 chat 路徑同源（`ctx` → `agencyThresholdsFor` ＋ `agencyProfileFor`），
 * 所以高懷疑角色／挑戰難度的 `holdAt` 位移會如實反映在 loop 與 shift 的分帳上。
 */
export function debriefAgencyLedgerFor(
  turns: readonly PracticeTurn[],
  ctx: AgencyCoachingContext,
  agencyState: ConversationAgencyState | null = null,
): DebriefAgencyLedger {
  const thresholds = thresholdsFor(ctx);
  // Phase 4.5c 刀 2：持久化狀態裡唯一能用在「從第 1 則重走」的欄位是
  // `repairedAtUserTurns`——它是**絕對序號**（第 N 則玩家訊息），不是累積量。
  // 其餘欄位（`unresolvedCount`／`lastCoherence`／`lastAgencyAct`…）是這一場
  // **結尾**的值，拿去當第 1 則的 prev 會整份算錯，所以刻意只取這一格。
  //
  // 為什麼不能直接把它塞進初始 state：`detectAgencyEvidence`／
  // `nextConversationAgencyState` 都會把「定位不到（marker > 這次的玩家則數）」
  // 的 marker 丟掉（R1 P1-4a），在第 1 則就會被丟掉且不再傳下去。所以改成
  // 走到那個序號時才注入，之後由 `locatable` 自然沿用。
  const persistedRepairAt = agencyState?.repairedAtUserTurns;
  let state: ConversationAgencyState | null = null;
  // R1 P1-2：注入判斷**不能**要求 `state !== null`——第 1 則玩家訊息時 state
  // 一定是 null，`repairedAtUserTurns: 1` 會永遠被跳過。改用
  // `INITIAL_CONVERSATION_AGENCY_STATE` 當底（`nextConversationAgencyState`
  // 對 `prev = null` 用的就是它，所以注入與否的 base 完全同一份）。
  let fragmentTurns = 0;
  let topicShiftTurns = 0;
  let loopTurns = 0;
  const repairTurns: number[] = [];
  let userTurnOrdinal = 0;
  for (let i = 0; i < turns.length; i++) {
    if (turns[i].role !== "user") continue;
    userTurnOrdinal += 1;
    const base = state ?? INITIAL_CONVERSATION_AGENCY_STATE;
    // 沒有注入時**原樣**傳 `state`（含 null），讓「不注入」這條路逐位元組
    // 等於 4.1 的回放。
    const prev = persistedRepairAt !== undefined &&
        persistedRepairAt <= userTurnOrdinal &&
        (base.repairedAtUserTurns ?? 0) < persistedRepairAt
      ? { ...base, repairedAtUserTurns: persistedRepairAt }
      : state;
    const decision = agencyPolicyFor(
      detectAgencyEvidence(turns.slice(0, i + 1), prev),
      thresholds,
    );
    state = nextConversationAgencyState(prev, decision, null);
    if (decision.situation === null) continue;
    // Phase 4.5a 刀 3：`cold_return` 是「他終於給了內容、她冷冷接一句」，不是
    // 又一輪沒接上——不進修復輪的帳（否則 Hint／Debrief 會多算一輪）。
    if (decision.situation === "cold_return") continue;
    if (decision.situation === "ambiguous_fragment") fragmentTurns += 1;
    else if (decision.situation === "abrupt_topic_shift") topicShiftTurns += 1;
    else loopTurns += 1;
    if (repairTurns.length < MAX_REPAIR_TURNS) {
      repairTurns.push(userTurnOrdinal);
    }
  }
  return {
    fragmentTurns,
    topicShiftTurns,
    loopTurns,
    repairTurns,
    repairTurnCount: fragmentTurns + topicShiftTurns + loopTurns,
  };
}
