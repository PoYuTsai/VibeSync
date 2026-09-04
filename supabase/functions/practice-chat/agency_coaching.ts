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
  aiAskedQuestion,
  type ConversationAgencyState,
  detectAgencyEvidence,
  nextConversationAgencyState,
} from "./conversation_agency.ts";

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
): HintAgencyCoaching {
  const evidence = detectAgencyEvidence(turns, agencyState);
  const decision = agencyPolicyFor(evidence);
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
}

const MAX_REPAIR_TURNS = 10;

/**
 * 結構回放：逐則玩家訊息重走 `detectAgencyEvidence → agencyPolicyFor`，
 * 狀態用 `nextConversationAgencyState` 推進。
 *
 * **近似的界線**（跟 `tools/practice-agency-eval/replay_plan.ts --state=1`
 * 同一種）：`classifierSignal` 一律傳 null，因為 debrief 手上沒有每一輪當時的
 * 分類器輸出；所以「分類器判 connected 的修復點」在這裡不存在，只有逐字稿看得
 * 到的結構修復（問句／第一人稱分享／明示換題）會歸零。方向是**偏保守**——
 * 少掉一種修復來源只會讓欠債留得比正式路徑久，不會憑空多出介入輪。
 * 難度門檻一律用預設的一般難度：這份帳只是給教練當觀察素材，不是守門。
 */
export function debriefAgencyLedgerFor(
  turns: readonly PracticeTurn[],
): DebriefAgencyLedger {
  let state: ConversationAgencyState | null = null;
  let fragmentTurns = 0;
  let topicShiftTurns = 0;
  let loopTurns = 0;
  const repairTurns: number[] = [];
  let userTurnOrdinal = 0;
  for (let i = 0; i < turns.length; i++) {
    if (turns[i].role !== "user") continue;
    userTurnOrdinal += 1;
    const decision = agencyPolicyFor(
      detectAgencyEvidence(turns.slice(0, i + 1), state),
    );
    state = nextConversationAgencyState(state, decision, null);
    if (decision.situation === null) continue;
    if (decision.situation === "ambiguous_fragment") fragmentTurns += 1;
    else if (decision.situation === "abrupt_topic_shift") topicShiftTurns += 1;
    else loopTurns += 1;
    if (repairTurns.length < MAX_REPAIR_TURNS) {
      repairTurns.push(userTurnOrdinal);
    }
  }
  return { fragmentTurns, topicShiftTurns, loopTurns, repairTurns };
}
