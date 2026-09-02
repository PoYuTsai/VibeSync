import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { parseDivergencePlanV1 } from "./divergence_contract.ts";

export const VALID_PLAN = {
  type: "analysis.divergence_plan",
  schemaVersion: 1,
  threadFrame: "接住她健身後的累，再玩去吃火鍋的反差",
  anchorSourceIndex: 1,
  supportSourceIndices: [3],
  mergeContextSourceIndices: [2],
  semanticDistanceCap: 1,
  newTopicBudget: 0,
  questionBudget: 1,
  branchPool: [
    {
      id: "br_1",
      sourceIndex: 1,
      method: "affect_evaluation",
      idea: "練完後身體像下班",
      associationPath: ["健身完", "累", "身體下班"],
      semanticDistance: 1,
    },
    {
      id: "br_2",
      sourceIndex: 3,
      method: "association",
      idea: "健身與火鍋是熱量進出帳",
      associationPath: ["健身", "消耗", "火鍋", "補回"],
      semanticDistance: 1,
    },
  ],
  styleBranchIds: { extend: "br_1", humor: "br_2" },
};

Deno.test("divergence plan parser accepts the §5.12 shape and strips the event type", () => {
  const plan = parseDivergencePlanV1(VALID_PLAN);
  assert(plan);
  assertEquals(plan.schemaVersion, 1);
  assertEquals(plan.anchorSourceIndex, 1);
  assertEquals(plan.branchPool.length, 2);
  assertEquals(plan.styleBranchIds, { extend: "br_1", humor: "br_2" });
  assertEquals("type" in plan, false);
  // 沒有 styleBranchIds 也合法。
  const { styleBranchIds: _ignored, ...withoutStyles } = VALID_PLAN;
  assert(parseDivergencePlanV1(withoutStyles));
});

Deno.test("divergence plan parser rejects any malformed field instead of repairing it", () => {
  const cases: Record<string, unknown>[] = [
    { ...VALID_PLAN, schemaVersion: 2 },
    { ...VALID_PLAN, threadFrame: "   " },
    { ...VALID_PLAN, anchorSourceIndex: 0 },
    { ...VALID_PLAN, supportSourceIndices: [3, 3] },
    { ...VALID_PLAN, semanticDistanceCap: 4 },
    { ...VALID_PLAN, questionBudget: 2 },
    { ...VALID_PLAN, branchPool: [] },
    {
      ...VALID_PLAN,
      branchPool: [VALID_PLAN.branchPool[0], VALID_PLAN.branchPool[0]],
    },
    {
      ...VALID_PLAN,
      branchPool: [{ ...VALID_PLAN.branchPool[0], method: "mind_reading" }],
    },
    {
      ...VALID_PLAN,
      branchPool: [{ ...VALID_PLAN.branchPool[0], semanticDistance: 3.5 }],
    },
    {
      ...VALID_PLAN,
      branchPool: [{ ...VALID_PLAN.branchPool[0], associationPath: "健身" }],
    },
    { ...VALID_PLAN, styleBranchIds: { extend: "br_missing" } },
    { ...VALID_PLAN, styleBranchIds: { bold: "br_1" } },
    {
      ...VALID_PLAN,
      branchPool: Array.from({ length: 13 }, (_, index) => ({
        ...VALID_PLAN.branchPool[0],
        id: `br_${index}`,
      })),
    },
  ];
  for (const [index, candidate] of cases.entries()) {
    assertEquals(parseDivergencePlanV1(candidate), null, `case ${index}`);
  }
  assertEquals(parseDivergencePlanV1(null), null);
  assertEquals(parseDivergencePlanV1("plan"), null);
});
