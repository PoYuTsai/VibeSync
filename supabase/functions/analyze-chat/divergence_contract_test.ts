import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  anchorBranchOf,
  BRANCH_METHOD_REPAIRS,
  DIVERGENCE_BRANCH_ID_PATTERN,
  DIVERGENCE_METHODS,
  MAX_STYLE_INTENSITY,
  parseDivergencePlanEvent,
  parseDivergencePlanV1,
  parseReplyOptionBranchFields,
  REPLY_OPTION_BRANCH_FIELDS,
  resolveStyleBranch,
  RHETORICAL_MOVES,
  rhetoricalMovesForStyle,
  stripClientHiddenFinalResult,
  STYLE_RHETORICAL_MOVES,
} from "./divergence_contract.ts";

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

const { type: _eventType, ...VALID_SNAPSHOT } = VALID_PLAN;

Deno.test("event parser needs the exact type and yields a type-less snapshot; snapshot parser rejects type", () => {
  const plan = parseDivergencePlanEvent(VALID_PLAN);
  assert(plan);
  assertEquals(plan.schemaVersion, 1);
  assertEquals(plan.anchorSourceIndex, 1);
  assertEquals(plan.branchPool.length, 2);
  assertEquals(plan.styleBranchIds, { extend: "br_1", humor: "br_2" });
  assertEquals("type" in plan, false);
  // wire event：缺 type 或錯 type 都整份作廢。
  assertEquals(parseDivergencePlanEvent(VALID_SNAPSHOT), null);
  assertEquals(
    parseDivergencePlanEvent({ ...VALID_PLAN, type: "analysis.done" }),
    null,
  );
  // server 快照：沒有 type 才合法；帶 type 是別人塞進來的。
  assert(parseDivergencePlanV1(VALID_SNAPSHOT));
  assertEquals(parseDivergencePlanV1(VALID_PLAN), null);
  // 沒有 styleBranchIds 也合法。
  const { styleBranchIds: _ignored, ...withoutStyles } = VALID_PLAN;
  assert(parseDivergencePlanEvent(withoutStyles));
});

Deno.test("divergence plan parser rejects any malformed field instead of repairing it", () => {
  const cases: Record<string, unknown>[] = [
    { ...VALID_PLAN, schemaVersion: 2 },
    { ...VALID_PLAN, threadFrame: "   " },
    { ...VALID_PLAN, anchorSourceIndex: 0 },
    { ...VALID_PLAN, supportSourceIndices: [3, 3] },
    { ...VALID_PLAN, semanticDistanceCap: 3 },
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
      branchPool: Array.from({ length: 9 }, (_, index) => ({
        ...VALID_PLAN.branchPool[0],
        id: `br_${index}`,
      })),
    },
    // prompt 說 2-8 枝；parser 同源，1 枝也拒。
    { ...VALID_PLAN, branchPool: [VALID_PLAN.branchPool[0]] },
    // 未知欄位不接受：模型多塞的欄位可能是內部推理或訊息原文。
    { ...VALID_PLAN, reasoning: "leak" },
    {
      ...VALID_PLAN,
      branchPool: [
        { ...VALID_PLAN.branchPool[0], sourceMessage: "leak" },
        VALID_PLAN.branchPool[1],
      ],
    },
  ];
  for (const [index, candidate] of cases.entries()) {
    assertEquals(parseDivergencePlanEvent(candidate), null, `case ${index}`);
    const { type: _type, ...snapshot } = candidate;
    assertEquals(parseDivergencePlanV1(snapshot), null, `snapshot ${index}`);
  }
  assertEquals(parseDivergencePlanEvent(null), null);
  assertEquals(parseDivergencePlanV1("plan"), null);
});

Deno.test("stripClientHiddenFinalResult removes only the divergence plan and leaves other values untouched", () => {
  const input = {
    replies: { extend: "x" },
    analysisDivergencePlan: VALID_PLAN,
  };
  const stripped = stripClientHiddenFinalResult(input) as Record<
    string,
    unknown
  >;
  assertEquals(Object.keys(stripped), ["replies"]);
  // 原物件不被改動；沒有隱藏 key 時原樣回傳。
  assert("analysisDivergencePlan" in input);
  const plain = { replies: {} };
  assert(stripClientHiddenFinalResult(plain) === plain);
  assertEquals(stripClientHiddenFinalResult(null), null);
});

// ---- Phase 2b：reply_option 歸因 ----

const PLAN = parseDivergencePlanEvent(VALID_PLAN)!;

Deno.test("rhetorical moves are the six methods plus each style's own moves (§6.3 union), unique, and attribution fields are the three documented keys", () => {
  for (const method of DIVERGENCE_METHODS) {
    assert((RHETORICAL_MOVES as readonly string[]).includes(method));
  }
  assertEquals(new Set(RHETORICAL_MOVES).size, RHETORICAL_MOVES.length);
  for (const [style, moves] of Object.entries(STYLE_RHETORICAL_MOVES)) {
    const allowed = rhetoricalMovesForStyle(style as "extend");
    for (const move of moves) {
      assert(allowed.includes(move), `${style}:${move}`);
    }
    for (const method of DIVERGENCE_METHODS) assert(allowed.includes(method));
  }
  // 別的風格的專屬手法不在自己的值域裡。
  assert(!rhetoricalMovesForStyle("extend").includes("exaggeration"));
  assertEquals(REPLY_OPTION_BRANCH_FIELDS, [
    "selectedBranchIds",
    "rhetoricalMove",
    "styleIntensity",
  ]);
  assertEquals(MAX_STYLE_INTENSITY, 3);
});

Deno.test("branch ids must be opaque br_N; free text in id voids the plan", () => {
  assert(DIVERGENCE_BRANCH_ID_PATTERN.test("br_1"));
  assert(DIVERGENCE_BRANCH_ID_PATTERN.test("br_12"));
  for (
    const bad of [
      "br_",
      "br_123",
      "br_0",
      "br_01",
      "她說的那句",
      "branch-1",
      "BR_1",
      "",
    ]
  ) {
    assert(!DIVERGENCE_BRANCH_ID_PATTERN.test(bad), bad);
  }
  assertEquals(
    parseDivergencePlanEvent({
      ...VALID_PLAN,
      branchPool: [
        VALID_PLAN.branchPool[0],
        { ...VALID_PLAN.branchPool[1], id: "她的原話" },
      ],
      styleBranchIds: { extend: "br_1" },
    }),
    null,
  );
});

Deno.test("anchor branch is the first pool branch on the anchor ball; none means null, never another ball's branch", () => {
  assertEquals(anchorBranchOf(PLAN)?.id, "br_1");
  const noAnchorBranch = parseDivergencePlanV1({
    ...snapshotOf(VALID_PLAN),
    anchorSourceIndex: 4,
  })!;
  assertEquals(anchorBranchOf(noAnchorBranch), null);
  const anchorSecond = parseDivergencePlanV1({
    ...snapshotOf(VALID_PLAN),
    anchorSourceIndex: 3,
  })!;
  assertEquals(anchorBranchOf(anchorSecond)?.id, "br_2");
});

Deno.test("reply option attribution parses only a complete valid triple for that style; anything else is absent", () => {
  const good = {
    selectedBranchIds: ["br_2", "br_1"],
    rhetoricalMove: "playful_contrast",
    styleIntensity: 2,
  } as const;
  assertEquals(parseReplyOptionBranchFields(good, PLAN, "tease"), good);
  // 六法對任何風格都合法。
  assert(
    parseReplyOptionBranchFields(
      { ...good, rhetoricalMove: "drill_down" },
      PLAN,
      "tease",
    ),
  );
  const bad: unknown[] = [
    { ...good, selectedBranchIds: ["br_9"] },
    { ...good, selectedBranchIds: [] },
    { ...good, selectedBranchIds: ["br_1", "br_1"] },
    { ...good, selectedBranchIds: "br_1" },
    { ...good, rhetoricalMove: "sarcasm" },
    { ...good, rhetoricalMove: "exaggeration" }, // humor 的手法，tease 不收
    { ...good, styleIntensity: MAX_STYLE_INTENSITY + 1 },
    { ...good, styleIntensity: -1 },
    { ...good, styleIntensity: 1.5 },
    { selectedBranchIds: ["br_2"], rhetoricalMove: "playful_contrast" },
    { selectedBranchIds: ["br_2"] },
    {},
    null,
    "br_2",
  ];
  for (const value of bad) {
    assertEquals(
      parseReplyOptionBranchFields(value, PLAN, "tease"),
      null,
      JSON.stringify(value),
    );
  }
});

Deno.test("style branch resolution: option wins, then the plan's styleBranchIds, then the anchor, else unresolved; invalid option fields are flagged", () => {
  assertEquals(
    resolveStyleBranch(PLAN, "extend", {
      selectedBranchIds: ["br_2"],
      rhetoricalMove: "new_angle",
      styleIntensity: 1,
    }),
    {
      selectedBranchIds: ["br_2"],
      rhetoricalMove: "new_angle",
      styleIntensity: 1,
      source: "option",
      invalid: false,
    },
  );
  // 缺 → 計畫指定（extend→br_1）。
  assertEquals(resolveStyleBranch(PLAN, "extend", { style: "extend" }), {
    selectedBranchIds: ["br_1"],
    source: "plan",
    invalid: false,
  });
  // 缺且計畫沒指定 → anchor（br_1）。
  assertEquals(resolveStyleBranch(PLAN, "tease", { style: "tease" }), {
    selectedBranchIds: ["br_1"],
    source: "anchor",
    invalid: false,
  });
  // 帶了但不合法 → 退回下一層並標 invalid。
  assertEquals(
    resolveStyleBranch(PLAN, "humor", { selectedBranchIds: ["br_9"] }),
    { selectedBranchIds: ["br_2"], source: "plan", invalid: true },
  );
  assertEquals(
    resolveStyleBranch(PLAN, "coldRead", {
      selectedBranchIds: ["br_1"],
      styleIntensity: 0,
    }),
    {
      selectedBranchIds: ["br_1"],
      source: "anchor",
      invalid: true,
      styleIntensity: 0,
    },
  );
  // 缺枝但手法／強度合法 → 補 anchor、標 invalid、手法與強度保留；跨風格手法不留。
  assertEquals(
    resolveStyleBranch(PLAN, "tease", {
      rhetoricalMove: "playful_challenge",
      styleIntensity: 1,
    }),
    {
      selectedBranchIds: ["br_1"],
      source: "anchor",
      invalid: true,
      rhetoricalMove: "playful_challenge",
      styleIntensity: 1,
    },
  );
  assertEquals(
    resolveStyleBranch(PLAN, "tease", {
      rhetoricalMove: "exaggeration",
      styleIntensity: 9,
    }),
    { selectedBranchIds: ["br_1"], source: "anchor", invalid: true },
  );
  // anchor 球沒有枝、計畫也沒指定 → unresolved，不拿別球的枝冒充。
  const noAnchor = parseDivergencePlanV1({
    ...snapshotOf(VALID_PLAN),
    anchorSourceIndex: 4,
  })!;
  assertEquals(resolveStyleBranch(noAnchor, "tease", {}), {
    selectedBranchIds: [],
    source: "unresolved",
    invalid: false,
  });
});

Deno.test("branch sourceIndex<N> glitch is repaired only when N and the value equal sourceIndex; anything else still voids the plan", () => {
  const glitched = {
    ...VALID_PLAN,
    branchPool: [
      VALID_PLAN.branchPool[0],
      { ...VALID_PLAN.branchPool[1], sourceIndex3: 3 },
    ],
  };
  const repairs: string[] = [];
  const plan = parseDivergencePlanEvent(glitched, repairs);
  assert(plan);
  assertEquals(plan.branchPool[1].sourceIndex, 3);
  assertEquals("sourceIndex3" in plan.branchPool[1], false);
  assertEquals(repairs, ["br_2:sourceIndex3"]);
  // 沒傳 repairs 也一樣修得回來。
  assert(parseDivergencePlanEvent(glitched));
  // 取代型：沒有 sourceIndex，只有 sourceIndex3: 3 → 補回 sourceIndex 3。
  const { sourceIndex: _dropped, ...withoutSourceIndex } =
    VALID_PLAN.branchPool[1];
  const replaced: string[] = [];
  const replacedPlan = parseDivergencePlanEvent({
    ...VALID_PLAN,
    branchPool: [
      VALID_PLAN.branchPool[0],
      { ...withoutSourceIndex, sourceIndex3: 3 },
    ],
  }, replaced);
  assert(replacedPlan);
  assertEquals(replacedPlan.branchPool[1].sourceIndex, 3);
  assertEquals(replaced, ["br_2:sourceIndex3"]);

  for (
    const bad of [
      { ...VALID_PLAN.branchPool[1], sourceIndex1: 3 }, // N ≠ sourceIndex
      { ...VALID_PLAN.branchPool[1], sourceIndex3: 1 }, // 值 ≠ sourceIndex
      { ...VALID_PLAN.branchPool[1], sourceIndex3: "3" }, // 不是數字
      { ...VALID_PLAN.branchPool[1], sourceIndexes: 3 }, // 不是這個形態
      { ...withoutSourceIndex, sourceIndex3: 1 }, // 取代型但值≠N
      { ...withoutSourceIndex, sourceIndex3: 3, sourceIndex1: 1 }, // 兩個矛盾
    ]
  ) {
    assertEquals(
      parseDivergencePlanEvent({
        ...VALID_PLAN,
        branchPool: [VALID_PLAN.branchPool[0], bad],
      }),
      null,
      JSON.stringify(bad),
    );
  }
});

Deno.test("a rhetorical move written as a branch method is repaired to its mapped divergence method and recorded; unknown words still void the plan", () => {
  for (const [move, method] of Object.entries(BRANCH_METHOD_REPAIRS)) {
    assert((DIVERGENCE_METHODS as readonly string[]).includes(method), move);
    assert((RHETORICAL_MOVES as readonly string[]).includes(move), move);
  }
  const repairs: string[] = [];
  const plan = parseDivergencePlanEvent({
    ...VALID_PLAN,
    branchPool: [
      VALID_PLAN.branchPool[0],
      { ...VALID_PLAN.branchPool[1], method: "exaggeration" },
    ],
  }, repairs);
  assert(plan);
  assertEquals(plan.branchPool[1].method, "association");
  assertEquals(repairs, ["br_2:method:exaggeration->association"]);
  assertEquals(
    parseDivergencePlanEvent({
      ...VALID_PLAN,
      branchPool: [
        VALID_PLAN.branchPool[0],
        { ...VALID_PLAN.branchPool[1], method: "sarcasm" },
      ],
    }),
    null,
  );
});

function snapshotOf(event: typeof VALID_PLAN): Record<string, unknown> {
  const { type: _type, ...snapshot } = event;
  return snapshot;
}
