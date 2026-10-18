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

Deno.test("questionnaire_submit accepts goals_count in range, drops out-of-range value", () => {
  const result = buildFunnelRow("u", {
    event: "onboarding_questionnaire_submit",
    properties: { goals_count: 2 },
  });
  assert(result.ok);
  if (!result.ok) return;
  assertEquals(result.row.properties, { goals_count: 2 });

  const outOfRange = buildFunnelRow("u", {
    event: "onboarding_questionnaire_submit",
    properties: { goals_count: 9 },
  });
  assert(outOfRange.ok);
  if (outOfRange.ok) {
    assertEquals(outOfRange.row.properties, {});
  }
});

Deno.test("about_me_opened accepts known source enum, drops unknown source", () => {
  const known = buildFunnelRow("u", {
    event: "about_me_opened",
    properties: { source: "checklist" },
  });
  assert(known.ok);
  if (known.ok) assertEquals(known.row.properties, { source: "checklist" });

  const unknown = buildFunnelRow("u", {
    event: "about_me_opened",
    properties: { source: "made_up" },
  });
  assert(unknown.ok);
  if (unknown.ok) assertEquals(unknown.row.properties, {});
});

Deno.test("about_me_saved accepts has_style/goals_count/seeds_count/has_notes/has_custom_topics", () => {
  const result = buildFunnelRow("u", {
    event: "about_me_saved",
    properties: {
      has_style: true,
      goals_count: 3,
      seeds_count: 5,
      has_notes: false,
      has_custom_topics: true,
    },
  });
  assert(result.ok);
  if (!result.ok) return;
  assertEquals(result.row.properties, {
    has_style: true,
    goals_count: 3,
    seeds_count: 5,
    has_notes: false,
    has_custom_topics: true,
  });

  const outOfRange = buildFunnelRow("u", {
    event: "about_me_saved",
    properties: { seeds_count: 6 },
  });
  assert(outOfRange.ok);
  if (outOfRange.ok) assertEquals(outOfRange.row.properties, {});
});

Deno.test("about_me_cleared carries no properties", () => {
  const result = buildFunnelRow("u", {
    event: "about_me_cleared",
    properties: { anything: "stripped" },
  });
  assert(result.ok);
  if (!result.ok) return;
  assertEquals(result.row.properties, {});
});

// 鍵級對齊鎖（Grok 審查 F5）：整張 event → property keys map 與字典逐字鎖死。
// client 端 funnel_tracker_test.dart 有同一張表的對等測試；任一側單邊改動
// 都會讓該側測試轉紅（鍵盤案白名單漂移的防回歸網）。
Deno.test("dictionary stays aligned with docs/integrations/funnel-events-v1.md", () => {
  assertEquals(FUNNEL_EVENT_PROPS, {
    onboarding_page_view: ["page_index"],
    onboarding_skip: ["page_index"],
    onboarding_branch_answer: ["has_partner"],
    onboarding_questionnaire_submit: ["goals_count"],
    quota_strip_tap: [],
    opener_entry_tap: [],
    coach_entry_tap: ["has_partner"],
    first_analysis_completed: [],
    first_practice_completed: [],
    keyboard_setup_shown: [],
    keyboard_setup_completed: [],
    checklist_item_done: ["item"],
    about_me_opened: ["source"],
    about_me_saved: [
      "has_style",
      "goals_count",
      "seeds_count",
      "has_notes",
      "has_custom_topics",
    ],
    about_me_cleared: [],
    new_topic_copied: ["is_recommended"],
    paywall_opened: ["entry"],
    paywall_purchase_completed: ["tier", "entry"],
    locked_cards_upgrade_tap: ["locked_count"],
  });
});

Deno.test("new_topic_copied：只收 is_recommended 布林，字串或其他鍵剝除", () => {
  const ok = buildFunnelRow("u1", {
    event: "new_topic_copied",
    properties: { is_recommended: true, openingLine: "不該上傳的句子" },
  });
  assertEquals(ok.ok, true);
  if (!ok.ok) return;
  assertEquals(ok.row.properties, { is_recommended: true });
  const bad = buildFunnelRow("u1", {
    event: "new_topic_copied",
    properties: { is_recommended: "true" },
  });
  assertEquals(bad.ok, true);
  if (!bad.ok) return;
  assertEquals(bad.row.properties, {});
});

// 付費頁與鎖卡的漏斗（Eric 2026-10-18：量從哪裡打開付費頁、買了哪個方案、
// 鎖卡區塊被點時鎖了幾張）。值域在 server 強制，不合就剝掉那個鍵、事件照收。
Deno.test("paywall_opened：entry 只收三種入口，其他值剝除整鍵", () => {
  for (const entry of ["general", "locked_cards", "quota_exhausted"]) {
    const ok = buildFunnelRow("u", {
      event: "paywall_opened",
      properties: { entry },
    });
    assert(ok.ok);
    if (ok.ok) assertEquals(ok.row.properties, { entry });
  }

  for (const bad of ["lockedCards", "home", "", 1, true, null]) {
    const result = buildFunnelRow("u", {
      event: "paywall_opened",
      properties: { entry: bad },
    });
    assert(result.ok, `entry=${String(bad)} 只剝鍵，事件照收`);
    if (result.ok) assertEquals(result.row.properties, {});
  }
});

Deno.test("paywall_purchase_completed：只留 tier 與 entry，價格、商品 id、收據都剝除", () => {
  const result = buildFunnelRow("u", {
    event: "paywall_purchase_completed",
    properties: {
      tier: "essential",
      entry: "locked_cards",
      price: 590,
      productId: "vibesync_essential_monthly",
      receipt: "MIIT...",
      partnerName: "小美",
    },
  });
  assert(result.ok);
  if (!result.ok) return;
  assertEquals(result.row.properties, {
    tier: "essential",
    entry: "locked_cards",
  });

  const starter = buildFunnelRow("u", {
    event: "paywall_purchase_completed",
    properties: { tier: "starter", entry: "general" },
  });
  assert(starter.ok);
  if (starter.ok) {
    assertEquals(starter.row.properties, { tier: "starter", entry: "general" });
  }
});

Deno.test("paywall_purchase_completed：tier 不是 starter／essential 就剝掉 tier，entry 照留", () => {
  for (const bad of ["free", "premium", "Essential", 2]) {
    const result = buildFunnelRow("u", {
      event: "paywall_purchase_completed",
      properties: { tier: bad, entry: "quota_exhausted" },
    });
    assert(result.ok);
    if (result.ok) {
      assertEquals(result.row.properties, { entry: "quota_exhausted" });
    }
  }
});

Deno.test("locked_cards_upgrade_tap：locked_count 只收 1–5 的整數", () => {
  for (const count of [1, 3, 5]) {
    const ok = buildFunnelRow("u", {
      event: "locked_cards_upgrade_tap",
      properties: { locked_count: count, slot: 3, task: "push" },
    });
    assert(ok.ok);
    if (ok.ok) assertEquals(ok.row.properties, { locked_count: count });
  }

  for (const bad of [0, 6, -1, 2.5, "3", null]) {
    const result = buildFunnelRow("u", {
      event: "locked_cards_upgrade_tap",
      properties: { locked_count: bad },
    });
    assert(result.ok, `locked_count=${String(bad)} 只剝鍵，事件照收`);
    if (result.ok) assertEquals(result.row.properties, {});
  }
});

Deno.test("其他鍵的下限不受 locked_count 影響：page_index 0 照收", () => {
  const result = buildFunnelRow("u", {
    event: "onboarding_page_view",
    properties: { page_index: 0 },
  });
  assert(result.ok);
  if (result.ok) assertEquals(result.row.properties, { page_index: 0 });
});

Deno.test("字典外的付費頁事件名照樣拒絕", () => {
  for (
    const event of [
      "paywall_closed",
      "purchase_completed",
      "paywall_purchase_cancelled",
      "locked_card_tap",
      "PAYWALL_OPENED",
    ]
  ) {
    const result = buildFunnelRow("u", { event, properties: {} });
    assert(!result.ok, `${event} 應該被拒`);
  }
});
