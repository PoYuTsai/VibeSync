import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  type BallInventory,
  coveredIndependentBalls,
  independentMoveSourceIndices,
  parseBallInventory,
  validateReplySegments,
} from "./ball_inventory.ts";

function inventoryOf(
  entries: Array<[number, "接" | "併" | "略"]>,
): BallInventory {
  const dispositions = new Map<number, "接" | "併" | "略">();
  let catchableCount = 0;
  let independentCount = 0;
  for (const [idx, disp] of entries) {
    dispositions.set(idx, disp);
    if (disp === "接" || disp === "併") catchableCount += 1;
    if (disp === "接") independentCount += 1;
  }
  return { dispositions, catchableCount, independentCount };
}

function seg(sourceIndex: number): Record<string, unknown> {
  return {
    sourceIndex,
    sourceMessage: `m${sourceIndex}`,
    reply: "r",
    reason: "x",
  };
}

Deno.test("parseBallInventory builds disposition map and counts catchable balls", () => {
  const inv = parseBallInventory({
    type: "analysis.inventory",
    balls: [
      {
        sourceIndex: 1,
        sourceMessage: "只喜歡江果先",
        disposition: "略",
        reason: "語境不明",
      },
      {
        sourceIndex: 2,
        sourceMessage: "在比賽",
        disposition: "併",
        reason: "與晚餐同片段",
      },
      {
        sourceIndex: 3,
        sourceMessage: "剛來吃晚餐",
        disposition: "接",
        reason: "生活分享",
      },
      {
        sourceIndex: 4,
        sourceMessage: "[Photo]晚餐照",
        disposition: "接",
        reason: "可埋邀約",
      },
      {
        sourceIndex: 5,
        sourceMessage: "到家了",
        disposition: "接",
        reason: "可順勢",
      },
      {
        sourceIndex: 6,
        sourceMessage: "[Missed call]視訊",
        disposition: "接",
        reason: "最高價值",
      },
    ],
  });

  assert(inv !== null);
  assertEquals(inv!.dispositions.get(1), "略");
  assertEquals(inv!.dispositions.get(2), "併");
  assertEquals(inv!.dispositions.get(6), "接");
  assertEquals(inv!.dispositions.size, 6);
  // 接 idx 3,4,5,6 ＋ 併 idx 2 ＝ 5 顆可接球。
  assertEquals(inv!.catchableCount, 5);
  assertEquals(inv!.independentCount, 4);
});

Deno.test("parseBallInventory returns null for non-inventory events", () => {
  assertEquals(
    parseBallInventory({
      type: "analysis.decision",
      selectedStyle: "coldRead",
    }),
    null,
  );
});

Deno.test("parseBallInventory returns null when balls is missing or not an array", () => {
  assertEquals(parseBallInventory({ type: "analysis.inventory" }), null);
  assertEquals(
    parseBallInventory({ type: "analysis.inventory", balls: "nope" }),
    null,
  );
  assertEquals(
    parseBallInventory({ type: "analysis.inventory", balls: [] }),
    null,
  );
});

Deno.test("parseBallInventory returns null when no ball is catchable (all 略) — soft fallback", () => {
  const inv = parseBallInventory({
    type: "analysis.inventory",
    balls: [
      {
        sourceIndex: 1,
        sourceMessage: "[Photo]",
        disposition: "略",
        reason: "純貼圖",
      },
      {
        sourceIndex: 2,
        sourceMessage: "[Sticker]",
        disposition: "略",
        reason: "純表情貼",
      },
    ],
  });
  assertEquals(inv, null);
});

Deno.test("parseBallInventory skips malformed entries but keeps valid ones", () => {
  const inv = parseBallInventory({
    type: "analysis.inventory",
    balls: [
      { sourceIndex: 1, disposition: "接", reason: "ok" },
      { sourceIndex: "two", disposition: "接", reason: "bad index" },
      { sourceIndex: 3, disposition: "丟", reason: "bad disposition" },
      { disposition: "併", reason: "missing index" },
      { sourceIndex: 5, disposition: "併", reason: "ok" },
    ],
  });

  assert(inv !== null);
  assertEquals(inv!.dispositions.size, 2);
  assertEquals(inv!.dispositions.get(1), "接");
  assertEquals(inv!.dispositions.get(5), "併");
  assert(!inv!.dispositions.has(3));
  assertEquals(inv!.catchableCount, 2);
  assertEquals(inv!.independentCount, 1);
});

Deno.test("parseBallInventory counts duplicate source indices only once", () => {
  const inv = parseBallInventory({
    type: "analysis.inventory",
    balls: [
      { sourceIndex: 1, disposition: "接" },
      { sourceIndex: 1, disposition: "接" },
      { sourceIndex: 2, disposition: "併" },
      { sourceIndex: 2, disposition: "併" },
    ],
  });

  assert(inv !== null);
  assertEquals(inv.dispositions.size, 2);
  assertEquals(inv.catchableCount, 2);
  assertEquals(inv.independentCount, 1);
});

Deno.test("併 balls enrich context without becoming an independent segment", () => {
  const inv = inventoryOf([
    [1, "接"],
    [2, "併"],
    [3, "併"],
    [4, "併"],
  ]);
  assertEquals(validateReplySegments(inv, [seg(1)]), { ok: true });
  const mergedOnly = validateReplySegments(inv, [seg(2)]);
  assert(!mergedOnly.ok);
  assert(
    (mergedOnly as { reason: string }).reason.includes(
      "標「併」的背景獨立成段",
    ),
  );
});

Deno.test("validateReplySegments allows a real two-move option", () => {
  const inv = inventoryOf([[3, "接"], [4, "接"], [5, "接"], [6, "接"]]);
  assertEquals(validateReplySegments(inv, [seg(5), seg(6)]), { ok: true });
});

Deno.test("validateReplySegments allows a three-move option", () => {
  const inv = inventoryOf([[3, "接"], [4, "接"], [5, "接"], [6, "接"]]);
  assertEquals(validateReplySegments(inv, [seg(4), seg(5), seg(6)]), {
    ok: true,
  });
});

Deno.test("validateReplySegments rejects a segment sourced from a 略 ball", () => {
  const inv = inventoryOf([[1, "略"], [3, "接"], [4, "接"], [5, "接"], [
    6,
    "接",
  ]]);
  const result = validateReplySegments(inv, [seg(1), seg(4), seg(5)]);
  assert(!result.ok);
  assert((result as { reason: string }).reason.includes("略"));
});

Deno.test("validateReplySegments accepts all real independent moves", () => {
  const inv = inventoryOf([[3, "接"], [5, "接"]]);
  assertEquals(validateReplySegments(inv, [seg(3), seg(5)]), { ok: true });
});

// Exact coverage telemetry still exposes duplicate/order drift; source validation
// rejects duplicate independent moves but never rejects an option for being short.
Deno.test("validateReplySegments rejects duplicate independent moves", () => {
  const inv = inventoryOf([[3, "接"], [4, "接"], [5, "接"], [6, "接"]]);
  const result = validateReplySegments(inv, [seg(5), seg(5), seg(5)]);
  assert(!result.ok);
  assert((result as { reason: string }).reason.includes("重複"));
});

Deno.test("validateReplySegments is fail-soft for absent source indices", () => {
  const inv = inventoryOf([[3, "接"], [4, "接"], [5, "接"], [6, "接"]]);
  // Unknown indices are observable in the option/source telemetry but do not
  // turn the soft validator into a hard reject.
  assertEquals(validateReplySegments(inv, [seg(9), seg(10), seg(11)]), {
    ok: true,
  });
});

Deno.test("validateReplySegments keeps a phantom source fail-soft", () => {
  const inv = inventoryOf([[3, "接"], [4, "接"], [5, "接"], [6, "接"]]);
  assertEquals(validateReplySegments(inv, [seg(4), seg(5), seg(9)]), {
    ok: true,
  });
});

Deno.test("validateReplySegments allows an extra absent-index segment", () => {
  const inv = inventoryOf([[3, "接"], [4, "接"], [5, "接"], [6, "接"]]);
  assertEquals(
    validateReplySegments(inv, [seg(3), seg(4), seg(5), seg(9)]),
    { ok: true },
  );
});

// coveredIndependentBalls remains the distinct-count view for diagnostics;
// exact coverage uses independentMoveSourceIndices to preserve order/count.

Deno.test("coveredIndependentBalls counts distinct 接 only — duplicates, 併/略, absent index all excluded", () => {
  const inv = inventoryOf([[1, "略"], [2, "併"], [3, "接"], [4, "接"]]);
  const covered = coveredIndependentBalls(inv, [
    seg(3),
    seg(3), // 重複只算一次
    seg(4),
    seg(1), // 略：不算
    seg(2), // 併：不算
    seg(9), // 盤點外：不算
  ]);
  assertEquals([...covered].sort((a, b) => a - b), [3, 4]);
});

Deno.test("coveredIndependentBalls ignores segments without a numeric sourceIndex", () => {
  const inv = inventoryOf([[3, "接"]]);
  const covered = coveredIndependentBalls(inv, [
    { sourceIndex: "3" },
    { sourceIndex: Number.NaN },
    {},
  ]);
  assertEquals(covered.size, 0);
});

Deno.test("reply segment validation follows authored move count", () => {
  const inv = inventoryOf([[3, "接"], [4, "接"], [5, "接"], [6, "接"]]);

  assertEquals(validateReplySegments(inv, [seg(5), seg(6)]), { ok: true });
  assertEquals(validateReplySegments(inv, [seg(5)]), { ok: true });
});

Deno.test("independent move source indices preserve exact option order and count", () => {
  const inv = inventoryOf([[3, "接"], [4, "併"], [5, "接"], [6, "略"]]);

  assertEquals(
    independentMoveSourceIndices(inv, [seg(5), seg(3)]),
    [5, 3],
  );
  assertEquals(
    independentMoveSourceIndices(inv, [seg(5), seg(5)]),
    [5, 5],
  );
});
