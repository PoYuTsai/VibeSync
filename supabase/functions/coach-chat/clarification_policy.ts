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

// 全域首輪固定決策閘門（2026-08-31 決策分岔案）：global scope、完全沒有
// 對話脈絡、非 forceAnswer 時，「要先釐清還是直接回答」不再交給模型擲骰
// ——必定先免費釐清一次。global schema 已保證 summary/snapshot/partnerHint
// 缺席，所以脈絡只看本輪 turns 與 recentMessages。「直接看正式建議」
// （forceAnswer）逃生門保留原樣。
export function mustClarifyFirstRound(opts: {
  forceAnswer?: boolean;
  scope?: { type?: string } | null;
  activeSessionTurns?: readonly CoachSessionTurnLike[];
  recentMessages?: readonly unknown[];
}): boolean {
  return opts.forceAnswer !== true &&
    opts.scope?.type === "global" &&
    (opts.activeSessionTurns ?? []).length === 0 &&
    (opts.recentMessages ?? []).length === 0;
}

export function shouldForceCoachAnswerAfterClarifications(opts: {
  forceAnswer?: boolean;
  activeSessionTurns?: readonly CoachSessionTurnLike[];
}): boolean {
  return opts.forceAnswer === true ||
    countCoachClarifications(opts.activeSessionTurns ?? []) >=
      MAX_NO_CHARGE_CLARIFICATION_TURNS;
}
