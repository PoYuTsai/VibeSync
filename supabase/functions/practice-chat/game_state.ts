import type {
  GameFailureState,
  GameFsmPhase,
  GameFsmSnapshot,
  GameRealityFlag,
  GameSpicyLevel,
} from "./game_fsm.ts";
import { maxGameFsmPhase, targetVariableFor } from "./game_fsm.ts";

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
  // WP1 回合下限只准抬 phase，不准整包用 fresh.phase：fresh 的 P5_CLOSE 來自
  // 軟邀約訊號，直接 max 會做出 `P5_CLOSE + no_invite_build_investment` 這種
  // 不可能快照——prompt 一邊叫模型開邀約窗口、一邊說這輪先別約，模型照 P5
  // 戰術出手就被 hint_quality_invalid_invite_route 打回重試。
  // 下限最高只到 P4_TENSION，抬 phase 不會反過來改速約階梯；targetVariable
  // 則跟著新 phase 重算，保持三者同源。
  // ⚠️ 這裡沿用 ledger 的 speedInviteDirection，**前提是落帳端有帶
  // inviteStage**（`evaluateGameFsmForLedger`）。2026-08-11 之前落帳漏帶，
  // 這一行就把 hint 端算對的階梯蓋成「這輪不約」，邀約路線整條走不到。
  // 改落帳端的人請一起看 handler 的 persistGameStateFailOpen。
  // 修復優先時 ledger 的目標與速約階梯一律讓位給 fresh：舊帳可能停在
  // P5_CLOSE/明確邀約，配上本輪的修復戰術就變成「先修安全感、不邊修邊約」
  // 和「本輪階梯位置：明確邀約」同時出現。階段進度（phase）保留，
  // 免得一句越界就把整場打回開場。
  const repairPriority = fresh.repairPriority;
  const phase = repairPriority
    ? persisted.phase
    : maxGameFsmPhase(persisted.phase, fresh.turnFloorPhase);
  const targetVariable = repairPriority
    ? fresh.targetVariable
    : phase === persisted.phase
    ? persisted.lastTargetVariable ?? fresh.targetVariable
    : targetVariableFor(phase, fresh.failureStates);
  return {
    ...fresh,
    phase,
    targetVariable,
    speedInviteDirection: repairPriority
      ? fresh.speedInviteDirection
      : persisted.lastSpeedInviteDirection ?? fresh.speedInviteDirection,
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

/**
 * Debrief 專用的整場帳緊湊版。gameDebriefPrompt 只注入單句視角的
 * compactGameFsmEvidencePrompt（fresh 只反映最後一句），第 3 輪炸過 GREASY、
 * 最後一句乾淨的局會讓模型看到 failureStates: none 卻被要求寫 failureState。
 * server 有整場帳（failureCounts＋每變數 ledger），這裡挑「誰最常炸」與
 * 「哪個變數最弱」兩行給 debrief 模型，變數用 debrief 契約的標準名。
 * 鐵則：注入的內部詞（gameLedger/failureCounts/lowestVariable）必同步列入
 * visible_text_guard 的 INTERNAL_VISIBLE_LABELS。
 * lowestVariable 刻意不帶分數（Codex 首審 P1）：模型只抄「Investment=22」
 * 時標籤詞表攔不到，判最弱變數也不需要數值——不注入就沒有材料可洩。
 */
export function compactGameLedgerPrompt(
  state?: PersistedGameState | null,
): string {
  if (!state) return "";
  const contractNames = {
    pv: "Value",
    fp: "Frame",
    inv: "Investment",
    safety: "Safety",
  } as const;
  const [lowestKey] = (["pv", "fp", "inv", "safety"] as const)
    .map((key) => [key, state[key]] as const)
    .reduce((lowest, entry) => (entry[1] < lowest[1] ? entry : lowest));
  return `gameLedger(hidden evidence)\nfailureCounts: ${
    csvCounts(GAME_FAILURE_STATES, state.failureCounts)
  }\nlowestVariable: ${
    contractNames[lowestKey]
  }\n整場帳優先於單句判定：failureState 選次數最高者，missedVariable 對應最弱變數；這些內部詞與數值不可見。\n`;
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
