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

export function shouldForceCoachAnswerAfterClarifications(opts: {
  forceAnswer?: boolean;
  activeSessionTurns?: readonly CoachSessionTurnLike[];
}): boolean {
  return opts.forceAnswer === true ||
    countCoachClarifications(opts.activeSessionTurns ?? []) >=
      MAX_NO_CHARGE_CLARIFICATION_TURNS;
}
