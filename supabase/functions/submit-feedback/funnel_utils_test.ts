import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { buildFunnelRow, FUNNEL_EVENT_PROPS } from "./funnel_utils.ts";

Deno.test("buildFunnelRow accepts a dictionary event and forces server user_id", () => {
  const result = buildFunnelRow("user-abc", {
    event: "onboarding_page_view",
    properties: { page_index: 2 },
    clientTs: "2026-08-01T03:00:00.000Z",
    user_id: "SPOOFED",
  });
  assert(result.ok);
  if (!result.ok) return;
  assertEquals(result.row.user_id, "user-abc");
  assertEquals(result.row.event, "onboarding_page_view");
  assertEquals(result.row.properties, { page_index: 2 });
  assertEquals(result.row.client_ts, "2026-08-01T03:00:00.000Z");
});

Deno.test("buildFunnelRow rejects events outside the dictionary", () => {
  const result = buildFunnelRow("user-abc", {
    event: "totally_made_up",
    properties: {},
  });
  assert(!result.ok);
});

Deno.test("buildFunnelRow rejects non-object or missing event", () => {
  assert(!buildFunnelRow("u", "str").ok);
  assert(!buildFunnelRow("u", null).ok);
  assert(!buildFunnelRow("u", { properties: {} }).ok);
});

Deno.test("buildFunnelRow strips keys outside the per-event whitelist", () => {
  const result = buildFunnelRow("user-abc", {
    event: "coach_entry_tap",
    properties: {
      has_partner: true,
      partnerName: "小美",
      conversationText: "對話原文絕不落庫",
      page_index: 3,
    },
  });
  assert(result.ok);
  if (!result.ok) return;
  assertEquals(result.row.properties, { has_partner: true });
});

Deno.test("buildFunnelRow drops out-of-range ints and non-bool bools", () => {
  const badIndex = buildFunnelRow("u", {
    event: "onboarding_page_view",
    properties: { page_index: 999 },
  });
  assert(badIndex.ok);
  if (badIndex.ok) assertEquals(badIndex.row.properties, {});

  const fractional = buildFunnelRow("u", {
    event: "onboarding_page_view",
    properties: { page_index: 1.5 },
  });
  assert(fractional.ok);
  if (fractional.ok) assertEquals(fractional.row.properties, {});

  const nonBool = buildFunnelRow("u", {
    event: "onboarding_branch_answer",
    properties: { has_partner: "yes" },
  });
  assert(nonBool.ok);
  if (nonBool.ok) assertEquals(nonBool.row.properties, {});
});

Deno.test("buildFunnelRow keeps only known checklist item enum values", () => {
  const ok = buildFunnelRow("u", {
    event: "checklist_item_done",
    properties: { item: "profile" },
  });
  assert(ok.ok);
  if (ok.ok) assertEquals(ok.row.properties, { item: "profile" });

  const bad = buildFunnelRow("u", {
    event: "checklist_item_done",
    properties: { item: "任意自由文字".repeat(20) },
  });
  assert(bad.ok);
  if (bad.ok) assertEquals(bad.row.properties, {});
});

Deno.test("buildFunnelRow omits invalid clientTs instead of failing", () => {
  const result = buildFunnelRow("u", {
    event: "quota_strip_tap",
    clientTs: "not-a-date",
  });
  assert(result.ok);
  if (!result.ok) return;
  assertEquals(result.row.client_ts, undefined);
});

Deno.test("questionnaire_submit accepts style_set bool and goals_count in range", () => {
  const result = buildFunnelRow("u", {
    event: "onboarding_questionnaire_submit",
    properties: { style_set: true, goals_count: 2 },
  });
  assert(result.ok);
  if (!result.ok) return;
  assertEquals(result.row.properties, { style_set: true, goals_count: 2 });

  const outOfRange = buildFunnelRow("u", {
    event: "onboarding_questionnaire_submit",
    properties: { style_set: false, goals_count: 9 },
  });
  assert(outOfRange.ok);
  if (outOfRange.ok) {
    assertEquals(outOfRange.row.properties, { style_set: false });
  }
});

// 鍵級對齊鎖（Grok 審查 F5）：整張 event → property keys map 與字典逐字鎖死。
// client 端 funnel_tracker_test.dart 有同一張表的對等測試；任一側單邊改動
// 都會讓該側測試轉紅（鍵盤案白名單漂移的防回歸網）。
Deno.test("dictionary stays aligned with docs/integrations/funnel-events-v1.md", () => {
  assertEquals(FUNNEL_EVENT_PROPS, {
    onboarding_page_view: ["page_index"],
    onboarding_skip: ["page_index"],
    onboarding_branch_answer: ["has_partner"],
    onboarding_questionnaire_submit: ["style_set", "goals_count"],
    quota_strip_tap: [],
    opener_entry_tap: [],
    coach_entry_tap: ["has_partner"],
    first_analysis_completed: [],
    first_practice_completed: [],
    keyboard_setup_shown: [],
    keyboard_setup_completed: [],
    checklist_item_done: ["item"],
  });
});
