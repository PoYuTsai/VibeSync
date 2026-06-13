import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  type BallInventory,
  parseBallInventory,
  validateSelectedSegments,
} from "./ball_inventory.ts";

function inventoryOf(
  entries: Array<[number, "接" | "併" | "略"]>,
): BallInventory {
  const dispositions = new Map<number, "接" | "併" | "略">();
  let catchableCount = 0;
  for (const [idx, disp] of entries) {
    dispositions.set(idx, disp);
    if (disp === "接" || disp === "併") catchableCount += 1;
  }
  return { dispositions, catchableCount };
}

function seg(sourceIndex: number): Record<string, unknown> {
  return { sourceIndex, sourceMessage: `m${sourceIndex}`, reply: "r", reason: "x" };
}

Deno.test("parseBallInventory builds disposition map and counts catchable balls", () => {
  const inv = parseBallInventory({
    type: "analysis.inventory",
    balls: [
      { sourceIndex: 1, sourceMessage: "只喜歡江果先", disposition: "略", reason: "語境不明" },
      { sourceIndex: 2, sourceMessage: "在比賽", disposition: "併", reason: "與晚餐同片段" },
      { sourceIndex: 3, sourceMessage: "剛來吃晚餐", disposition: "接", reason: "生活分享" },
      { sourceIndex: 4, sourceMessage: "[Photo]晚餐照", disposition: "接", reason: "可埋邀約" },
      { sourceIndex: 5, sourceMessage: "到家了", disposition: "接", reason: "可順勢" },
      { sourceIndex: 6, sourceMessage: "[Missed call]視訊", disposition: "接", reason: "最高價值" },
    ],
  });

  assert(inv !== null);
  assertEquals(inv!.dispositions.get(1), "略");
  assertEquals(inv!.dispositions.get(2), "併");
  assertEquals(inv!.dispositions.get(6), "接");
  assertEquals(inv!.dispositions.size, 6);
  // 接 idx 3,4,5,6 ＋ 併 idx 2 ＝ 5 顆可接球。
  assertEquals(inv!.catchableCount, 5);
});

Deno.test("parseBallInventory returns null for non-inventory events", () => {
  assertEquals(
    parseBallInventory({ type: "analysis.decision", selectedStyle: "coldRead" }),
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
      { sourceIndex: 1, sourceMessage: "[Photo]", disposition: "略", reason: "純貼圖" },
      { sourceIndex: 2, sourceMessage: "[Sticker]", disposition: "略", reason: "純表情貼" },
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
});

Deno.test("validateSelectedSegments rejects below-floor count (4接, 2段) — failure matrix row1", () => {
  const inv = inventoryOf([[3, "接"], [4, "接"], [5, "接"], [6, "接"]]);
  const result = validateSelectedSegments(inv, [seg(5), seg(6)]);
  assert(!result.ok);
  assert((result as { reason: string }).reason.includes("下限"));
});

Deno.test("validateSelectedSegments passes 3 catchable segments (4接, 3段) — failure matrix row2", () => {
  const inv = inventoryOf([[3, "接"], [4, "接"], [5, "接"], [6, "接"]]);
  assertEquals(validateSelectedSegments(inv, [seg(4), seg(5), seg(6)]), { ok: true });
});

Deno.test("validateSelectedSegments rejects a segment sourced from a 略 ball — failure matrix row3", () => {
  const inv = inventoryOf([[1, "略"], [3, "接"], [4, "接"], [5, "接"], [6, "接"]]);
  const result = validateSelectedSegments(inv, [seg(1), seg(4), seg(5)]);
  assert(!result.ok);
  assert((result as { reason: string }).reason.includes("略"));
});

Deno.test("validateSelectedSegments floor caps at real ball count (2接, 2段) — failure matrix row4", () => {
  const inv = inventoryOf([[3, "接"], [5, "接"]]);
  assertEquals(validateSelectedSegments(inv, [seg(3), seg(5)]), { ok: true });
});

// Codex adversarial P2：下限必須數「不同的接/併球」，否則重複/盤點外索引可灌水
// 過關卻沒真接到球。下面四個 case 鎖住 INV-H6'。

Deno.test("validateSelectedSegments counts DISTINCT catchable balls — duplicates do not satisfy the floor", () => {
  const inv = inventoryOf([[3, "接"], [4, "接"], [5, "接"], [6, "接"]]);
  const result = validateSelectedSegments(inv, [seg(5), seg(5), seg(5)]);
  assert(!result.ok);
  assert((result as { reason: string }).reason.includes("下限"));
});

Deno.test("validateSelectedSegments rejects a floor met only by indices absent from the inventory", () => {
  const inv = inventoryOf([[3, "接"], [4, "接"], [5, "接"], [6, "接"]]);
  // idx 9,10,11 不在盤點 → 不算真接球 → 達不到下限。
  const result = validateSelectedSegments(inv, [seg(9), seg(10), seg(11)]);
  assert(!result.ok);
  assert((result as { reason: string }).reason.includes("下限"));
});

Deno.test("validateSelectedSegments rejects when distinct real catches fall below the floor even with a phantom segment", () => {
  const inv = inventoryOf([[3, "接"], [4, "接"], [5, "接"], [6, "接"]]);
  // 只真接 4,5 兩顆，idx 9 是盤點外 → 2 < 3，REJECT（非誤殺：確實只接 2 顆）。
  const result = validateSelectedSegments(inv, [seg(4), seg(5), seg(9)]);
  assert(!result.ok);
});

Deno.test("validateSelectedSegments does not 誤殺: an extra absent-index segment rides along once the floor is met", () => {
  const inv = inventoryOf([[3, "接"], [4, "接"], [5, "接"], [6, "接"]]);
  // 已用 3 顆真球達標，第 4 段 idx 9 盤點外 → 不算分也不致 REJECT。
  assertEquals(
    validateSelectedSegments(inv, [seg(3), seg(4), seg(5), seg(9)]),
    { ok: true },
  );
});
