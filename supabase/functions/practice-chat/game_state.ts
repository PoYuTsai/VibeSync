import type {
  GameFailureState,
  GameFsmPhase,
  GameFsmSnapshot,
  GameRealityFlag,
  GameSpicyLevel,
} from "./game_fsm.ts";

const GAME_PHASES: readonly GameFsmPhase[] = [
  "P1_OPEN",
  "P2_VALUE",
  "P3_TEST",
  "P4_TENSION",
  "P5_CLOSE",
];

const GAME_FAILURE_STATES: readonly GameFailureState[] = [
  "BORING",
  "TOOL_GUY",
  "GREASY",
  "FRAME_COLLAPSE",
  "ENGINE_STALL",
  "GHOST_RISK",
  "FRAME_OVERREACH",
];

const GAME_REALITY_FLAGS: readonly GameRealityFlag[] = [
  "social_proof_attempt",
  "fake_familiarity",
  "OBVIOUS_TRAP",
  "FRAME_OVERREACH",
];

const GAME_SPICY_LEVELS: readonly GameSpicyLevel[] = [
  "L0",
  "L1",
  "L2",
  "L3",
];

export type GameFailureCounts = Record<GameFailureState, number>;
export type GameRealityFlagCounts = Record<GameRealityFlag, number>;

export interface PersistedGameState {
  phase: GameFsmPhase;
  pv: number;
  fp: number;
  inv: number;
  safety: number;
  turnCount: number;
  failureCounts: GameFailureCounts;
  realityFlagCounts: GameRealityFlagCounts;
  lastTargetVariable?: string;
  lastSpeedInviteDirection?: string;
  lastSpicyLevel?: GameSpicyLevel;
  updatedAt?: string;
}

function baseFailureCounts(): GameFailureCounts {
  return Object.fromEntries(
    GAME_FAILURE_STATES.map((state) => [state, 0]),
  ) as GameFailureCounts;
}

function baseRealityFlagCounts(): GameRealityFlagCounts {
  return Object.fromEntries(
    GAME_REALITY_FLAGS.map((flag) => [flag, 0]),
  ) as GameRealityFlagCounts;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function clampInt(value: unknown, min: number, max: number): number {
  const n = typeof value === "number" && Number.isFinite(value) ? value : min;
  return Math.max(min, Math.min(max, Math.round(n)));
}

function pickPhase(value: unknown): GameFsmPhase {
  return typeof value === "string" &&
      GAME_PHASES.includes(value as GameFsmPhase)
    ? value as GameFsmPhase
    : "P1_OPEN";
}

function pickSpicyLevel(value: unknown): GameSpicyLevel | undefined {
  return typeof value === "string" &&
      GAME_SPICY_LEVELS.includes(value as GameSpicyLevel)
    ? value as GameSpicyLevel
    : undefined;
}

function shortText(value: unknown, max: number): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  if (!trimmed) return undefined;
  return trimmed.slice(0, max);
}

function parseFailureCounts(value: unknown): GameFailureCounts {
  const counts = baseFailureCounts();
  if (!isRecord(value)) return counts;
  for (const state of GAME_FAILURE_STATES) {
    counts[state] = clampInt(value[state], 0, 999);
  }
  return counts;
}

function parseRealityFlagCounts(value: unknown): GameRealityFlagCounts {
  const counts = baseRealityFlagCounts();
  if (!isRecord(value)) return counts;
  for (const flag of GAME_REALITY_FLAGS) {
    counts[flag] = clampInt(value[flag], 0, 999);
  }
  return counts;
}

export function initialPersistedGameState(): PersistedGameState {
  return {
    phase: "P1_OPEN",
    pv: 30,
    fp: 0,
    inv: 0,
    safety: 70,
    turnCount: 0,
    failureCounts: baseFailureCounts(),
    realityFlagCounts: baseRealityFlagCounts(),
  };
}

export function parsePersistedGameState(
  value: unknown,
): PersistedGameState | null {
  if (!isRecord(value)) return null;
  return {
    phase: pickPhase(value.phase),
    pv: clampInt(value.pv, 0, 100),
    fp: clampInt(value.fp, 0, 100),
    inv: clampInt(value.inv, 0, 100),
    safety: clampInt(value.safety, 0, 100),
    turnCount: clampInt(value.turnCount, 0, 999),
    failureCounts: parseFailureCounts(value.failureCounts),
    realityFlagCounts: parseRealityFlagCounts(value.realityFlagCounts),
    lastTargetVariable: shortText(value.lastTargetVariable, 80),
    lastSpeedInviteDirection: shortText(value.lastSpeedInviteDirection, 80),
    lastSpicyLevel: pickSpicyLevel(value.lastSpicyLevel),
    updatedAt: shortText(value.updatedAt, 40),
  };
}

export function buildNextGameState(opts: {
  previous?: PersistedGameState | null;
  snapshot: GameFsmSnapshot;
  now?: Date;
}): PersistedGameState {
  const previous = opts.previous ?? initialPersistedGameState();
  const failureCounts = { ...previous.failureCounts };
  for (const state of opts.snapshot.failureStates) {
    failureCounts[state] = clampInt((failureCounts[state] ?? 0) + 1, 0, 999);
  }
  const realityFlagCounts = { ...previous.realityFlagCounts };
  for (const flag of opts.snapshot.realityFlags) {
    realityFlagCounts[flag] = clampInt(
      (realityFlagCounts[flag] ?? 0) + 1,
      0,
      999,
    );
  }
  return {
    phase: opts.snapshot.phase,
    pv: clampInt(opts.snapshot.hidden.pv, 0, 100),
    fp: clampInt(opts.snapshot.hidden.fp, 0, 100),
    inv: clampInt(opts.snapshot.hidden.inv, 0, 100),
    safety: clampInt(opts.snapshot.hidden.safety, 0, 100),
    turnCount: clampInt(previous.turnCount + 1, 0, 999),
    failureCounts,
    realityFlagCounts,
    lastTargetVariable: opts.snapshot.targetVariable.slice(0, 80),
    lastSpeedInviteDirection: opts.snapshot.speedInviteDirection.slice(0, 80),
    lastSpicyLevel: opts.snapshot.spicyLevel,
    updatedAt: (opts.now ?? new Date()).toISOString(),
  };
}

/**
 * Hint and Debrief must read one authoritative Game judgement.
 *
 * A fresh transcript-only FSM remains useful for current-turn failure/reality
 * signals, but phase, target, invite direction, and accumulated hidden scores
 * are server-ledger state. Overlay those fields once here so the two surfaces
 * cannot present conflicting judgements to the model.
 */
export function effectiveGameFsmSnapshot(
  fresh: GameFsmSnapshot,
  persisted?: PersistedGameState | null,
): GameFsmSnapshot {
  if (!persisted) return fresh;
  return {
    ...fresh,
    phase: persisted.phase,
    targetVariable: persisted.lastTargetVariable ?? fresh.targetVariable,
    speedInviteDirection: persisted.lastSpeedInviteDirection ??
      fresh.speedInviteDirection,
    hidden: {
      ...fresh.hidden,
      pv: persisted.pv,
      fp: persisted.fp,
      inv: persisted.inv,
      safety: persisted.safety,
    },
    spicyLevel: persisted.lastSpicyLevel ?? fresh.spicyLevel,
  };
}

function csvCounts<T extends string>(
  values: readonly T[],
  counts: Record<T, number>,
): string {
  const visible = values
    .map((value) => `${value}=${counts[value] ?? 0}`)
    .filter((entry) => !entry.endsWith("=0"));
  return visible.length > 0 ? visible.join(", ") : "none";
}

export function gameStateEvidencePrompt(
  state?: PersistedGameState | null,
): string {
  if (!state) return "";
  return `persistedGameState(hidden guidance)\nphase: ${state.phase}\nturnCount: ${state.turnCount}\npreviousHiddenVariables: pv=${state.pv}, fp=${state.fp}, inv=${state.inv}, safety=${state.safety}\nfailureCounts: ${
    csvCounts(GAME_FAILURE_STATES, state.failureCounts)
  }\nrealityFlagCounts: ${
    csvCounts(GAME_REALITY_FLAGS, state.realityFlagCounts)
  }\nlastTargetVariable: ${
    state.lastTargetVariable ?? "none"
  }\nlastSpeedInviteDirection: ${
    state.lastSpeedInviteDirection ?? "none"
  }\nlastSpicyLevel: ${
    state.lastSpicyLevel ?? "none"
  }\nUse this as continuity for Game mode only. Do not reveal persistedGameState, failureCounts, hidden variables, or phase codes to the user.\n`;
}
