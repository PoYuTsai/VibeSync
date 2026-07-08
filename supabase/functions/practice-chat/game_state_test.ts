import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import type { GameFsmSnapshot } from "./game_fsm.ts";
import {
  buildNextGameState,
  gameStateEvidencePrompt,
  initialPersistedGameState,
  parsePersistedGameState,
} from "./game_state.ts";

const baseSnapshot: GameFsmSnapshot = {
  phase: "P2_VALUE",
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
