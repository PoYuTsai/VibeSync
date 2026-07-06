import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { buildOutcomeRow } from "./outcome_utils.ts";

const validEvent = () => ({
  id: "evt-123",
  source: "opener",
  adviceType: "playful",
  adviceId: "adv-9",
  userAction: "sentAsIs",
  outcome: "engaged",
  suggestedMoveSummary: "先誇對方的貓再約週末咖啡",
  userTier: "starter",
  createdAt: "2026-07-06T03:00:00.000Z",
});

Deno.test("buildOutcomeRow maps whitelist fields and forces server user_id", () => {
  const result = buildOutcomeRow("user-abc", {
    ...validEvent(),
    user_id: "SPOOFED",
  });
  assert(result.ok);
  if (!result.ok) return;
  assertEquals(result.row.user_id, "user-abc");
  assertEquals(result.row.id, "evt-123");
  assertEquals(result.row.source, "opener");
  assertEquals(result.row.advice_type, "playful");
  assertEquals(result.row.advice_id, "adv-9");
  assertEquals(result.row.user_action, "sentAsIs");
  assertEquals(result.row.outcome, "engaged");
  assertEquals(result.row.user_tier, "starter");
  assertEquals(result.row.client_created_at, "2026-07-06T03:00:00.000Z");
});

Deno.test("buildOutcomeRow never leaks sensitive fields", () => {
  const result = buildOutcomeRow("user-abc", {
    ...validEvent(),
    outcomeTextPreview: "對方回覆的原文不該上傳",
    userNote: "我的私密筆記",
    partnerId: "partner-secret",
    conversationId: "conv-secret",
  });
  assert(result.ok);
  if (!result.ok) return;
  const serialized = JSON.stringify(result.row);
  assert(!serialized.includes("對方回覆的原文不該上傳"));
  assert(!serialized.includes("我的私密筆記"));
  assert(!serialized.includes("partner-secret"));
  assert(!serialized.includes("conv-secret"));
  assertEquals(Object.keys(result.row).includes("outcomeTextPreview"), false);
  assertEquals(Object.keys(result.row).includes("userNote"), false);
});

Deno.test("buildOutcomeRow rejects missing required fields", () => {
  for (const key of ["id", "source", "userAction", "outcome", "suggestedMoveSummary"]) {
    const event = validEvent() as Record<string, unknown>;
    delete event[key];
    const result = buildOutcomeRow("user-abc", event);
    assertEquals(result.ok, false, `expected reject when ${key} missing`);
  }
});

Deno.test("buildOutcomeRow rejects blank required strings", () => {
  const result = buildOutcomeRow("user-abc", {
    ...validEvent(),
    suggestedMoveSummary: "   ",
  });
  assertEquals(result.ok, false);
});

Deno.test("buildOutcomeRow rejects invalid createdAt", () => {
  const result = buildOutcomeRow("user-abc", {
    ...validEvent(),
    createdAt: "not-a-date",
  });
  assertEquals(result.ok, false);
});

Deno.test("buildOutcomeRow rejects non-object event", () => {
  assertEquals(buildOutcomeRow("user-abc", null).ok, false);
  assertEquals(buildOutcomeRow("user-abc", "string").ok, false);
  assertEquals(buildOutcomeRow("user-abc", [1, 2]).ok, false);
});

Deno.test("buildOutcomeRow truncates oversized summary", () => {
  const long = "字".repeat(200);
  const result = buildOutcomeRow("user-abc", {
    ...validEvent(),
    suggestedMoveSummary: long,
  });
  assert(result.ok);
  if (!result.ok) return;
  assertEquals(result.row.suggested_move_summary.length, 160);
});

Deno.test("buildOutcomeRow omits optional fields when absent", () => {
  const event = validEvent() as Record<string, unknown>;
  delete event.adviceType;
  delete event.adviceId;
  delete event.userTier;
  const result = buildOutcomeRow("user-abc", event);
  assert(result.ok);
  if (!result.ok) return;
  assertEquals(result.row.advice_type, undefined);
  assertEquals(result.row.advice_id, undefined);
  assertEquals(result.row.user_tier, undefined);
});
