export const MAX_NO_CHARGE_CLARIFICATION_TURNS = 3;

export type CoachSessionTurnLike = {
  role?: unknown;
  kind?: unknown;
};

export function countCoachClarifications(
  turns: readonly CoachSessionTurnLike[] = [],
): number {
  return turns.filter((turn) =>
    turn.role === "coach" && turn.kind === "clarification"
  ).length;
}

// 「這一題」＝最後一張正式答案之後的 turns。client 會把上一題的問答
// （24h resume）或跨天摘要種回 activeSessionTurns 當教練記憶，那些是前一題
// 的東西，不是本題的個案證據（2026-09-07 Eric 真機：同一題零證據卻直接給
// 捏造建議句，閘門因為「turns 非空」沒觸發）。
export function currentThreadTurns<T extends CoachSessionTurnLike>(
  turns: readonly T[] = [],
): readonly T[] {
  let start = 0;
  turns.forEach((turn, index) => {
    if (turn.role === "coach" && turn.kind === "answer") start = index + 1;
  });
  return turns.slice(start);
}

/// 本題已經釐清過（教練問過、使用者有機會補充）——之後才輪到模型自己判斷
/// 要不要再問或直接答。
export function clarifiedInCurrentThread(
  turns: readonly CoachSessionTurnLike[] = [],
): boolean {
  return currentThreadTurns(turns).some((turn) =>
    turn.role === "coach" && turn.kind === "clarification"
  );
}

// 固定決策閘門（2026-08-31 決策分岔案；Batch A 擴為證據制；2026-09-07 改
// 看「這一題」）：本題還沒釐清過、又沒有對方原話、非 forceAnswer 時，「要先
// 釐清還是直接回答」不交給模型擲骰——必定先免費釐清一次。「直接看正式建議」
// （forceAnswer）逃生門保留原樣。
// - global：schema 已保證 summary/snapshot/partnerHint 缺席；client 在
//   global 永遠送空 recentMessages，證據只能靠釐清後使用者貼／補。
// - partner（Batch A）：client 現況不送逐字對話，零證據時模型只能憑 traits
//   腦補個案戰術（G-01/G-03 病灶）——比照 global 強制先釐清。conversation
//   scope 不動。
export function mustClarifyFirstRound(opts: {
  forceAnswer?: boolean;
  scope?: { type?: string } | null;
  activeSessionTurns?: readonly CoachSessionTurnLike[];
  recentMessages?: readonly unknown[];
  conversationSummary?: string | null;
  analysisSnapshot?: unknown | null;
}): boolean {
  if (opts.forceAnswer === true) return false;
  const noThreadEvidence = !clarifiedInCurrentThread(opts.activeSessionTurns) &&
    (opts.recentMessages ?? []).length === 0;
  if (opts.scope?.type === "global") return noThreadEvidence;
  if (opts.scope?.type === "partner") {
    return noThreadEvidence &&
      opts.conversationSummary == null &&
      opts.analysisSnapshot == null;
  }
  return false;
}

export function shouldForceCoachAnswerAfterClarifications(opts: {
  forceAnswer?: boolean;
  activeSessionTurns?: readonly CoachSessionTurnLike[];
}): boolean {
  return opts.forceAnswer === true ||
    countCoachClarifications(opts.activeSessionTurns ?? []) >=
      MAX_NO_CHARGE_CLARIFICATION_TURNS;
}
