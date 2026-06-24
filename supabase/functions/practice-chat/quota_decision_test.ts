// practice-chat 額度決策測試。
// 跑法：deno test supabase/functions/practice-chat/quota_decision_test.ts

import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  decideDeduction,
  isSessionComplete,
  MAX_AI_REPLIES,
} from "./quota_decision.ts";

// ── 扣點時機：一場只在第一則 AI 回覆扣 1 ──────────────────────────────

Deno.test("chat 第一則 AI 回覆（aiTurnCount=0）→ 扣 1", () => {
  assertEquals(
    decideDeduction({ mode: "chat", aiTurnCount: 0, isTestAccount: false }),
    { shouldDeduct: true },
  );
});

Deno.test("chat 後續回覆（aiTurnCount>=1）→ 同場不再扣", () => {
  for (const n of [1, 2, 5, 9]) {
    assertEquals(
      decideDeduction({ mode: "chat", aiTurnCount: n, isTestAccount: false }),
      { shouldDeduct: false },
    );
  }
});

Deno.test("debrief → 永不扣（同場已付）", () => {
  assertEquals(
    decideDeduction({ mode: "debrief", aiTurnCount: 0, isTestAccount: false }),
    { shouldDeduct: false },
  );
  assertEquals(
    decideDeduction({ mode: "debrief", aiTurnCount: 5, isTestAccount: false }),
    { shouldDeduct: false },
  );
});

Deno.test("測試帳號 → 任何情況都不扣", () => {
  assertEquals(
    decideDeduction({ mode: "chat", aiTurnCount: 0, isTestAccount: true }),
    { shouldDeduct: false },
  );
});

// ── 10 則上限 ────────────────────────────────────────────────────────

Deno.test("isSessionComplete：< 10 未滿、>= 10 已滿", () => {
  assertEquals(isSessionComplete(0), false);
  assertEquals(isSessionComplete(9), false);
  assertEquals(isSessionComplete(10), true);
  assertEquals(isSessionComplete(11), true);
  assertEquals(MAX_AI_REPLIES, 10);
});
