// practice-chat 每日翻牌決策測試（純函式）。
// 跑法：deno test supabase/functions/practice-chat/draw_decision_test.ts

import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  drawAllowanceForTier,
  paidExtraDrawAllowedForTier,
  PRACTICE_DRAW_EXTRA_COST,
  taipeiNoonResetWindow,
} from "./draw_decision.ts";

// ── 免費額度 ───────────────────────────────────────────────────────────

Deno.test("免費額度：free=1 / starter=3 / essential=5", () => {
  assertEquals(drawAllowanceForTier("free"), 1);
  assertEquals(drawAllowanceForTier("starter"), 3);
  assertEquals(drawAllowanceForTier("essential"), 5);
});

Deno.test("免費額度：未知/缺 tier → normalizeTier→free（fail-closed=1）", () => {
  assertEquals(drawAllowanceForTier("pro"), 1);
  assertEquals(drawAllowanceForTier(null), 1);
  assertEquals(drawAllowanceForTier(undefined), 1);
});

Deno.test("付費額外：free 不可、starter/essential 可，未知→free 不可", () => {
  assertEquals(paidExtraDrawAllowedForTier("free"), false);
  assertEquals(paidExtraDrawAllowedForTier("starter"), true);
  assertEquals(paidExtraDrawAllowedForTier("essential"), true);
  assertEquals(paidExtraDrawAllowedForTier("garbage"), false);
});

Deno.test("額外翻牌成本鎖死為 5", () => {
  assertEquals(PRACTICE_DRAW_EXTRA_COST, 5);
});

// ── Asia/Taipei 中午 12:00 重置視窗 ────────────────────────────────────
// 中午 12:00 Taipei = 04:00 UTC，故 windowStart ISO 應為 ...T04:00:00.000Z。

Deno.test("Taipei 正好 12:00 → 用今日中午", () => {
  // 2026-06-26T04:00Z = Taipei 2026-06-26 12:00。
  const w = taipeiNoonResetWindow(new Date("2026-06-26T04:00:00.000Z"));
  assertEquals(w.resetWindowStartAt, "2026-06-26T04:00:00.000Z");
  assertEquals(w.nextResetAt, "2026-06-27T04:00:00.000Z");
});

Deno.test("Taipei 11:59（未過中午）→ 用昨日中午", () => {
  // 2026-06-26T03:59Z = Taipei 2026-06-26 11:59。
  const w = taipeiNoonResetWindow(new Date("2026-06-26T03:59:00.000Z"));
  assertEquals(w.resetWindowStartAt, "2026-06-25T04:00:00.000Z");
  assertEquals(w.nextResetAt, "2026-06-26T04:00:00.000Z");
});

Deno.test("Taipei 下午（過中午）→ 用今日中午", () => {
  // 2026-06-26T10:00Z = Taipei 2026-06-26 18:00。
  const w = taipeiNoonResetWindow(new Date("2026-06-26T10:00:00.000Z"));
  assertEquals(w.resetWindowStartAt, "2026-06-26T04:00:00.000Z");
});

Deno.test("Taipei 凌晨（跨日、未過中午）→ 用前一日中午", () => {
  // 2026-06-25T17:00Z = Taipei 2026-06-26 01:00（凌晨，未過中午）。
  const w = taipeiNoonResetWindow(new Date("2026-06-25T17:00:00.000Z"));
  assertEquals(w.resetWindowStartAt, "2026-06-25T04:00:00.000Z");
  assertEquals(w.nextResetAt, "2026-06-26T04:00:00.000Z");
});

Deno.test("nextResetAt 永遠 = windowStart + 24h", () => {
  const w = taipeiNoonResetWindow(new Date("2026-12-31T20:00:00.000Z"));
  const start = new Date(w.resetWindowStartAt).getTime();
  const next = new Date(w.nextResetAt).getTime();
  assertEquals(next - start, 24 * 60 * 60 * 1000);
});
