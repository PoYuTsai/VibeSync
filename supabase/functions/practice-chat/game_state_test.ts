import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import type { GameFsmSnapshot } from "./game_fsm.ts";
import {
  buildNextGameState,
  compactGameLedgerPrompt,
  effectiveGameFsmSnapshot,
  gameStateEvidencePrompt,
  initialPersistedGameState,
  parsePersistedGameState,
} from "./game_state.ts";

const baseSnapshot: GameFsmSnapshot = {
  phase: "P2_VALUE",
  turnFloorPhase: null,
  repairPriority: false,
  targetVariable: "Value + Emotion",
  speedInviteDirection: "no_invite_build_investment",
  hidden: { pv: 46, fp: 62, inv: 35, safety: 80, heatBias: 4 },
  failureStates: ["BORING"],
  realityFlags: [],
  spicyLevel: "L1",
};

Deno.test("initialPersistedGameState starts with two visible and four hidden game variables", () => {
  const state = initialPersistedGameState();

  assertEquals(state.phase, "P1_OPEN");
  assertEquals(state.pv, 30);
  assertEquals(state.fp, 0);
  assertEquals(state.inv, 0);
  assertEquals(state.safety, 70);
  assertEquals(state.turnCount, 0);
  assertEquals(state.failureCounts.BORING, 0);
  assertEquals(state.realityFlagCounts.OBVIOUS_TRAP, 0);
});

Deno.test("parsePersistedGameState clamps numbers and rejects non-object payloads", () => {
  assertEquals(parsePersistedGameState(null), null);
  assertEquals(parsePersistedGameState("bad"), null);

  const parsed = parsePersistedGameState({
    phase: "P4_TENSION",
    pv: 150,
    fp: -10,
    inv: 42.4,
    safety: 99,
    turnCount: 3,
    failureCounts: { BORING: 2 },
    realityFlagCounts: { fake_familiarity: 1 },
  });

  assert(parsed);
  assertEquals(parsed.phase, "P4_TENSION");
  assertEquals(parsed.pv, 100);
  assertEquals(parsed.fp, 0);
  assertEquals(parsed.inv, 42);
  assertEquals(parsed.safety, 99);
  assertEquals(parsed.turnCount, 3);
  assertEquals(parsed.failureCounts.BORING, 2);
  assertEquals(parsed.realityFlagCounts.fake_familiarity, 1);
});

Deno.test("buildNextGameState merges a snapshot and accumulates failure and reality counts", () => {
  const next = buildNextGameState({
    previous: {
      ...initialPersistedGameState(),
      turnCount: 2,
      failureCounts: {
        ...initialPersistedGameState().failureCounts,
        BORING: 1,
      },
      realityFlagCounts: {
        ...initialPersistedGameState().realityFlagCounts,
        fake_familiarity: 1,
      },
    },
    snapshot: {
      ...baseSnapshot,
      phase: "P3_TEST",
      failureStates: ["BORING", "FRAME_OVERREACH"],
      realityFlags: ["fake_familiarity", "OBVIOUS_TRAP"],
      hidden: { pv: 51, fp: 20, inv: 44, safety: 30, heatBias: -5 },
    },
  });

  assertEquals(next.phase, "P3_TEST");
  assertEquals(next.pv, 51);
  assertEquals(next.fp, 20);
  assertEquals(next.inv, 44);
  assertEquals(next.safety, 30);
  assertEquals(next.turnCount, 3);
  assertEquals(next.failureCounts.BORING, 2);
  assertEquals(next.failureCounts.FRAME_OVERREACH, 1);
  assertEquals(next.realityFlagCounts.fake_familiarity, 2);
  assertEquals(next.realityFlagCounts.OBVIOUS_TRAP, 1);
  assertEquals(next.lastTargetVariable, "Value + Emotion");
  assertEquals(next.lastSpeedInviteDirection, "no_invite_build_investment");
  assertEquals(next.lastSpicyLevel, "L1");
});

Deno.test("effectiveGameFsmSnapshot makes persisted judgement authoritative without losing current-turn signals", () => {
  const effective = effectiveGameFsmSnapshot(baseSnapshot, {
    ...initialPersistedGameState(),
    phase: "P5_CLOSE",
    pv: 81,
    fp: 73,
    inv: 66,
    safety: 58,
    lastTargetVariable: "Investment + close",
    lastSpeedInviteDirection: "direct_invite_window",
    lastSpicyLevel: "L2",
  });

  assertEquals(effective.phase, "P5_CLOSE");
  assertEquals(effective.targetVariable, "Investment + close");
  assertEquals(effective.speedInviteDirection, "direct_invite_window");
  assertEquals(effective.hidden, {
    pv: 81,
    fp: 73,
    inv: 66,
    safety: 58,
    heatBias: 4,
  });
  assertEquals(effective.spicyLevel, "L2");
  assertEquals(effective.failureStates, ["BORING"]);
});

Deno.test("effectiveGameFsmSnapshot keeps fresh turn-pressure phase from being washed back to persisted P1", () => {
  const effective = effectiveGameFsmSnapshot(
    {
      ...baseSnapshot,
      phase: "P3_TEST",
      turnFloorPhase: "P3_TEST",
      targetVariable: "Frame + safety",
      failureStates: [],
    },
    {
      ...initialPersistedGameState(),
      phase: "P1_OPEN",
      lastTargetVariable: "familiarity",
    },
  );

  assertEquals(effective.phase, "P3_TEST");
  // 抬 phase 就必須連 targetVariable 一起重算，不能留 ledger 的 P1 目標——
  // 那會做出「階段說去測試、目標卻說先熟悉」的矛盾快照。
  assertEquals(effective.targetVariable, "Frame + safety");
});

Deno.test("effectiveGameFsmSnapshot never lets a fresh soft-invite P5 outrun the ledger invite ladder", () => {
  const effective = effectiveGameFsmSnapshot(
    {
      ...baseSnapshot,
      // 使用者本輪自己丟軟邀約：fresh 會判 P5_CLOSE，但那不是回合下限。
      phase: "P5_CLOSE",
      turnFloorPhase: "P2_VALUE",
      targetVariable: "Investment + invite",
      speedInviteDirection: "direct_invite_low_pressure",
      failureStates: [],
    },
    {
      ...initialPersistedGameState(),
      phase: "P1_OPEN",
      lastTargetVariable: "familiarity",
      lastSpeedInviteDirection: "no_invite_build_investment",
    },
  );

  assertEquals(effective.phase, "P2_VALUE");
  assertEquals(effective.targetVariable, "Value + Emotion");
  assertEquals(effective.speedInviteDirection, "no_invite_build_investment");
});

Deno.test("effectiveGameFsmSnapshot lets a repair turn override a stale invite-ready ledger", () => {
  const effective = effectiveGameFsmSnapshot(
    {
      ...baseSnapshot,
      phase: "P1_OPEN",
      turnFloorPhase: null,
      targetVariable: "safety + Frame",
      repairPriority: true,
      speedInviteDirection: "repair_before_invite",
      failureStates: ["GREASY"],
    },
    {
      ...initialPersistedGameState(),
      // 舊帳停在收尾／明確邀約：不讓位的話，本輪修復戰術會和
      // 「本輪階梯位置：明確邀約」同時出現在同一份 prompt。
      phase: "P5_CLOSE",
      lastTargetVariable: "Investment + invite",
      lastSpeedInviteDirection: "direct_invite_low_pressure",
    },
  );

  assertEquals(effective.phase, "P5_CLOSE");
  assertEquals(effective.targetVariable, "safety + Frame");
  assertEquals(effective.speedInviteDirection, "repair_before_invite");
});

Deno.test("gameStateEvidencePrompt exposes persisted evidence only as hidden prompt context", () => {
  const prompt = gameStateEvidencePrompt({
    ...initialPersistedGameState(),
    phase: "P5_CLOSE",
    turnCount: 4,
    failureCounts: { ...initialPersistedGameState().failureCounts, GREASY: 2 },
    lastTargetVariable: "Investment + invite",
  });

  assert(prompt.includes("persistedGameState(hidden guidance)"));
  assert(prompt.includes("phase: P5_CLOSE"));
  assert(prompt.includes("turnCount: 4"));
  assert(prompt.includes("GREASY=2"));
  assert(prompt.includes("Investment + invite"));
  assertEquals(prompt.includes("L4"), false);
});

Deno.test("compactGameLedgerPrompt 給整場 failureCounts 與契約名的最弱變數", () => {
  const prompt = compactGameLedgerPrompt({
    ...initialPersistedGameState(),
    pv: 60,
    fp: 55,
    inv: 22,
    safety: 80,
    failureCounts: {
      ...initialPersistedGameState().failureCounts,
      GREASY: 2,
      BORING: 1,
    },
  });

  assert(prompt.includes("gameLedger(hidden evidence)"));
  assert(prompt.includes("GREASY=2"));
  assert(prompt.includes("BORING=1"));
  // 變數用 debrief 契約標準名（不是 inv 縮寫），模型不用自己猜對照；
  // 刻意不帶分數（Codex 首審 P1）：不注入數值就沒有材料可洩。
  assert(prompt.includes("lowestVariable: Investment\n"));
  assertEquals(/lowestVariable[^\n]*\d/.test(prompt), false);
});

Deno.test("compactGameLedgerPrompt 無整場帳（新局）時整塊不注入", () => {
  assertEquals(compactGameLedgerPrompt(null), "");
  assertEquals(compactGameLedgerPrompt(undefined), "");
});
