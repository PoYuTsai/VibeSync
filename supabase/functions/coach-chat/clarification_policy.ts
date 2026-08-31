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

// 首輪固定決策閘門（2026-08-31 決策分岔案；Batch A 擴為證據制）：
// 完全沒有個案證據、非 forceAnswer 時，「要先釐清還是直接回答」不再交給
// 模型擲骰——必定先免費釐清一次。「直接看正式建議」（forceAnswer）逃生門
// 保留原樣。
// - global：schema 已保證 summary/snapshot/partnerHint 缺席，脈絡只看
//   本輪 turns 與 recentMessages。
// - partner（Batch A）：client 現況不送逐字對話，首輪零證據時模型只能
//   憑 traits 腦補個案戰術（G-01/G-03 病灶）——比照 global 強制先釐清，
//   引導使用者切對話視窗或貼對方原話。conversation scope 不動。
export function mustClarifyFirstRound(opts: {
  forceAnswer?: boolean;
  scope?: { type?: string } | null;
  activeSessionTurns?: readonly CoachSessionTurnLike[];
  recentMessages?: readonly unknown[];
  conversationSummary?: string | null;
  analysisSnapshot?: unknown | null;
}): boolean {
  if (opts.forceAnswer === true) return false;
  const noTurnContext = (opts.activeSessionTurns ?? []).length === 0 &&
    (opts.recentMessages ?? []).length === 0;
  if (opts.scope?.type === "global") return noTurnContext;
  if (opts.scope?.type === "partner") {
    return noTurnContext &&
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
