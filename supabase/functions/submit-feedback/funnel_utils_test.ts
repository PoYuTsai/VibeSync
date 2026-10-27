import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { buildFunnelRow, FUNNEL_EVENT_PROPS } from "./funnel_utils.ts";

// 購買事件要帶發起購買的帳號（登入帳號的 UUID），伺服器比對後才收。
const BUYER = "8f14e45f-ceea-4c6b-9a8e-3e4d4b5c6a7f";
const OTHER_ACCOUNT = "2b7c1d3e-4f5a-4b6c-8d7e-9f0a1b2c3d4e";

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
    onboarding_intent: ["intent"],
    onboarding_quiz_answer: ["correct"],
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
    paywall_purchase_completed: ["tier", "entry", "purchaser"],
    locked_cards_upgrade_tap: ["locked_count"],
    quota_block_shown: ["feature", "scope", "block_source"],
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
Deno.test("paywall_opened：entry 只收四種入口，其他值剝除整鍵", () => {
  // practice_draw：練習室翻牌撞牆（Onboarding 第 2 步）。
  for (
    const entry of [
      "general",
      "locked_cards",
      "quota_exhausted",
      "practice_draw",
    ]
  ) {
    const ok = buildFunnelRow("u", {
      event: "paywall_opened",
      properties: { entry },
    });
    assert(ok.ok);
    if (ok.ok) assertEquals(ok.row.properties, { entry });
  }

  for (
    const bad of ["lockedCards", "practiceDraw", "home", "", 1, true, null]
  ) {
    const result = buildFunnelRow("u", {
      event: "paywall_opened",
      properties: { entry: bad },
    });
    assert(result.ok, `entry=${String(bad)} 只剝鍵，事件照收`);
    if (result.ok) assertEquals(result.row.properties, {});
  }
});

Deno.test("paywall_purchase_completed：只留 tier 與 entry，價格、商品 id、收據都剝除", () => {
  const result = buildFunnelRow(BUYER, {
    event: "paywall_purchase_completed",
    properties: {
      tier: "essential",
      entry: "locked_cards",
      purchaser: BUYER,
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

  const starter = buildFunnelRow(BUYER, {
    event: "paywall_purchase_completed",
    properties: { tier: "starter", entry: "general", purchaser: BUYER },
  });
  assert(starter.ok);
  if (starter.ok) {
    assertEquals(starter.row.properties, { tier: "starter", entry: "general" });
  }
});

Deno.test("paywall_purchase_completed：tier 不是 starter／essential 就剝掉 tier，entry 照留", () => {
  for (const bad of ["free", "premium", "Essential", 2]) {
    const result = buildFunnelRow(BUYER, {
      event: "paywall_purchase_completed",
      properties: { tier: bad, entry: "quota_exhausted", purchaser: BUYER },
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

// 原型上的名字不是字典裡的事件（主審 r1 P2）：用 in 判斷時 toString、constructor、
// __proto__ 會過關，接著取到函式或原型而丟錯，端點回 500。要走拒絕路徑
// （ok:false → index.ts 回 400），不能丟錯。
Deno.test("原型上的名字當事件名：一律拒絕，不丟錯", () => {
  for (
    const event of [
      "toString",
      "constructor",
      "__proto__",
      "hasOwnProperty",
      "valueOf",
      "isPrototypeOf",
      "propertyIsEnumerable",
      "toLocaleString",
      "__defineGetter__",
    ]
  ) {
    let result: ReturnType<typeof buildFunnelRow> | undefined;
    try {
      result = buildFunnelRow("u", { event, properties: {} });
    } catch (error) {
      throw new Error(`${event} 丟錯了（會變 500）：${error}`);
    }
    assertEquals(
      result,
      { ok: false, error: "Unknown funnel event" },
      `${event} 應該走拒絕路徑`,
    );
  }
});

Deno.test("JSON 解出來的 __proto__ 事件名也走拒絕路徑", () => {
  const raw = JSON.parse('{"event":"__proto__","properties":{}}');
  assertEquals(buildFunnelRow("u", raw), {
    ok: false,
    error: "Unknown funnel event",
  });
});

Deno.test("properties 只認自己的鍵：原型上的名字與 __proto__ 鍵都不帶進來", () => {
  // JSON.parse 會把 __proto__ 當成一般的鍵，裡面就算放了 entry 也不能算數。
  const raw = JSON.parse(
    '{"event":"paywall_opened","properties":{"__proto__":{"entry":"general"},"constructor":"x","toString":"y"}}',
  );
  const result = buildFunnelRow("u", raw);
  assert(result.ok);
  if (result.ok) assertEquals(result.row.properties, {});

  const inherited = Object.create({ entry: "locked_cards" });
  const fromPrototype = buildFunnelRow("u", {
    event: "paywall_opened",
    properties: inherited,
  });
  assert(fromPrototype.ok);
  if (fromPrototype.ok) {
    assertEquals(fromPrototype.row.properties, {}, "原型鏈上的 entry 不算");
  }
});

// 購買事件綁定發起購買的帳號（主審 r2 P2；Eric 2026-10-18 核准的第 3 輪範圍）：
// 認證權杖在送出當下才取，付款確認期間換了帳號，事件會用到別人的登入。purchaser
// 是開始購買時的帳號，跟登入的不同就整筆拒絕（ok:false → index.ts 回 400，不寫入）。
Deno.test("paywall_purchase_completed：purchaser 等於登入帳號才收，而且不落庫", () => {
  const result = buildFunnelRow(BUYER, {
    event: "paywall_purchase_completed",
    properties: { tier: "essential", entry: "general", purchaser: BUYER },
  });
  assert(result.ok);
  if (!result.ok) return;
  assertEquals(result.row.user_id, BUYER);
  assertEquals(result.row.properties, { tier: "essential", entry: "general" });
  assert(!("purchaser" in result.row.properties), "purchaser 只拿來比對");
});

Deno.test("paywall_purchase_completed：purchaser 跟登入的不同、缺少或格式不對，整筆拒絕", () => {
  const cases: Record<string, Record<string, unknown>> = {
    "別的帳號": { purchaser: OTHER_ACCOUNT },
    "缺少": {},
    "空字串": { purchaser: "" },
    "不是 UUID": { purchaser: "user-a" },
    "數字": { purchaser: 42 },
    "null": { purchaser: null },
    "前後有空白": { purchaser: ` ${BUYER} ` },
    "後面多字": { purchaser: `${BUYER}0` },
    "大寫（跟登入的字串不同）": { purchaser: BUYER.toUpperCase() },
  };
  for (const [name, extra] of Object.entries(cases)) {
    const result = buildFunnelRow(BUYER, {
      event: "paywall_purchase_completed",
      properties: { tier: "essential", entry: "locked_cards", ...extra },
    });
    assertEquals(
      result,
      { ok: false, error: "Funnel purchaser mismatch" },
      `${name} 應該整筆拒絕`,
    );
    assert(!("row" in result), `${name} 不該有可寫入的 row`);
  }
});

Deno.test("paywall_purchase_completed：登入帳號本身不是 UUID 時，purchaser 照抄也不收", () => {
  const result = buildFunnelRow("u", {
    event: "paywall_purchase_completed",
    properties: { tier: "essential", entry: "general", purchaser: "u" },
  });
  assertEquals(result, { ok: false, error: "Funnel purchaser mismatch" });
});

Deno.test("其他事件帶了 purchaser：剝掉，事件照收", () => {
  const opened = buildFunnelRow(BUYER, {
    event: "paywall_opened",
    properties: { entry: "locked_cards", purchaser: BUYER },
  });
  assert(opened.ok);
  if (opened.ok) assertEquals(opened.row.properties, { entry: "locked_cards" });

  const tap = buildFunnelRow(BUYER, {
    event: "locked_cards_upgrade_tap",
    properties: { locked_count: 2, purchaser: OTHER_ACCOUNT },
  });
  assert(tap.ok);
  if (tap.ok) assertEquals(tap.row.properties, { locked_count: 2 });

  const quota = buildFunnelRow(BUYER, {
    event: "quota_strip_tap",
    properties: { purchaser: "not-a-uuid" },
  });
  assert(quota.ok);
  if (quota.ok) assertEquals(quota.row.properties, {});
});

// 額度不足事件（onboarding 轉換第 6 步）：三個鍵都是固定選項，值域在 server 強制，
// 不合就剝掉那個鍵、事件照收。「誰先擋下」叫 block_source 不叫 source：PROP_SPECS
// 以鍵名全域共用值域，source 已經是 about_me_opened 的鍵（checklist／card／settings）。
const QUOTA_FEATURES = [
  "analyze",
  "opener",
  "new_topic",
  "coach",
  "practice",
  "keyboard",
];
const QUOTA_SCOPES = ["daily", "monthly", "unknown"];
const QUOTA_SOURCES = ["precheck", "server"];

Deno.test("quota_block_shown：feature、scope、block_source 都在值域內就照收", () => {
  for (const feature of QUOTA_FEATURES) {
    for (const scope of QUOTA_SCOPES) {
      for (const block_source of QUOTA_SOURCES) {
        const result = buildFunnelRow("u", {
          event: "quota_block_shown",
          properties: { feature, scope, block_source },
        });
        assert(result.ok);
        if (result.ok) {
          assertEquals(result.row.properties, { feature, scope, block_source });
        }
      }
    }
  }
});

Deno.test("quota_block_shown：值域外的值剝掉那個鍵，事件照收", () => {
  const cases: Array<[Record<string, unknown>, Record<string, unknown>]> = [
    [
      { feature: "paywall", scope: "daily", block_source: "server" },
      { scope: "daily", block_source: "server" },
    ],
    [
      { feature: "analyze", scope: "weekly", block_source: "server" },
      { feature: "analyze", block_source: "server" },
    ],
    [
      { feature: "analyze", scope: "daily", block_source: "client" },
      { feature: "analyze", scope: "daily" },
    ],
    [
      { feature: "newTopic", scope: "Daily", block_source: "SERVER" },
      {},
    ],
    [{ feature: 1, scope: true, block_source: null }, {}],
    [{ feature: "任意自由文字".repeat(20), scope: "", block_source: "" }, {}],
  ];
  for (const [properties, expected] of cases) {
    const result = buildFunnelRow("u", {
      event: "quota_block_shown",
      properties,
    });
    assert(result.ok, `${JSON.stringify(properties)} 只剝鍵，事件照收`);
    if (result.ok) assertEquals(result.row.properties, expected);
  }
});

Deno.test("quota_block_shown：剩幾則、方案、對話等白名單外的鍵一律剝掉", () => {
  const result = buildFunnelRow("u", {
    event: "quota_block_shown",
    properties: {
      feature: "opener",
      scope: "monthly",
      block_source: "precheck",
      remaining: 2,
      tier: "free",
      entry: "quota_exhausted",
      conversationText: "對話原文絕不落庫",
    },
  });
  assert(result.ok);
  if (result.ok) {
    assertEquals(result.row.properties, {
      feature: "opener",
      scope: "monthly",
      block_source: "precheck",
    });
  }
});

// 兩個鍵名分開，值域互不相通：額度不足事件帶 source 會被剝掉，關於我帶
// precheck／server 也照樣剝掉（關於我的值域沒有被放寬）。
Deno.test("block_source 與關於我的 source 互不相通", () => {
  const quotaWithSource = buildFunnelRow("u", {
    event: "quota_block_shown",
    properties: { feature: "coach", scope: "unknown", source: "server" },
  });
  assert(quotaWithSource.ok);
  if (quotaWithSource.ok) {
    assertEquals(quotaWithSource.row.properties, {
      feature: "coach",
      scope: "unknown",
    });
  }

  for (const value of QUOTA_SOURCES) {
    const aboutMe = buildFunnelRow("u", {
      event: "about_me_opened",
      properties: { source: value, block_source: value },
    });
    assert(aboutMe.ok);
    if (aboutMe.ok) assertEquals(aboutMe.row.properties, {});
  }

  for (const value of ["checklist", "card", "settings"]) {
    const quota = buildFunnelRow("u", {
      event: "quota_block_shown",
      properties: { feature: "coach", scope: "unknown", block_source: value },
    });
    assert(quota.ok);
    if (quota.ok) {
      assertEquals(quota.row.properties, {
        feature: "coach",
        scope: "unknown",
      });
    }
  }
});

Deno.test("feature、scope、block_source 只有 quota_block_shown 收：其他事件帶了剝掉", () => {
  const result = buildFunnelRow("u", {
    event: "paywall_opened",
    properties: {
      entry: "quota_exhausted",
      feature: "analyze",
      scope: "daily",
      block_source: "server",
    },
  });
  assert(result.ok);
  if (result.ok) {
    assertEquals(result.row.properties, { entry: "quota_exhausted" });
  }
});

Deno.test("quota_block_shown 的 properties 鍵名是原型上的名字：不帶進來、不丟錯", () => {
  const raw = JSON.parse(
    '{"event":"quota_block_shown","properties":{"__proto__":{"block_source":"server"},"constructor":"x","feature":"keyboard"}}',
  );
  const result = buildFunnelRow("u", raw);
  assert(result.ok);
  if (result.ok) assertEquals(result.row.properties, { feature: "keyboard" });
});

// onboarding 轉換第 12 步：4 頁版 onboarding 的兩個新事件。intent 是第 1 頁選的
// 路徑（固定四個值），correct 是第 2 頁那一題答對沒有（只收布林）。
const ONBOARDING_INTENTS = ["analyze", "opener", "practice", "browse"];

Deno.test("onboarding_intent：四種路徑照收，其他值剝掉 intent、事件照收", () => {
  for (const intent of ONBOARDING_INTENTS) {
    const result = buildFunnelRow("u", {
      event: "onboarding_intent",
      properties: { intent },
    });
    assert(result.ok);
    if (result.ok) assertEquals(result.row.properties, { intent });
  }

  for (
    const intent of ["Analyze", "has_partner", "", 1, true, null, "她回我了"]
  ) {
    const result = buildFunnelRow("u", {
      event: "onboarding_intent",
      properties: { intent },
    });
    assert(result.ok, `${JSON.stringify(intent)} 只剝鍵，事件照收`);
    if (result.ok) assertEquals(result.row.properties, {});
  }
});

Deno.test("onboarding_quiz_answer：correct 只收布林", () => {
  for (const correct of [true, false]) {
    const result = buildFunnelRow("u", {
      event: "onboarding_quiz_answer",
      properties: { correct },
    });
    assert(result.ok);
    if (result.ok) assertEquals(result.row.properties, { correct });
  }

  for (const correct of ["true", 1, 0, null, "q-1-1-01-a"]) {
    const result = buildFunnelRow("u", {
      event: "onboarding_quiz_answer",
      properties: { correct },
    });
    assert(result.ok);
    if (result.ok) assertEquals(result.row.properties, {});
  }
});

Deno.test("onboarding 新事件：題號、選項、目標等白名單外的鍵一律剝掉", () => {
  const quiz = buildFunnelRow("u", {
    event: "onboarding_quiz_answer",
    properties: {
      correct: false,
      questionId: "q-1-1-01",
      choiceId: "q-1-1-01-b",
      page_index: 1,
    },
  });
  assert(quiz.ok);
  if (quiz.ok) assertEquals(quiz.row.properties, { correct: false });

  const intent = buildFunnelRow("u", {
    event: "onboarding_intent",
    properties: {
      intent: "practice",
      has_partner: false,
      goals: ["softInvite"],
      route: "/practice-collection?guide=1",
    },
  });
  assert(intent.ok);
  if (intent.ok) assertEquals(intent.row.properties, { intent: "practice" });
});

Deno.test("intent、correct 只有 onboarding 新事件收：其他事件帶了剝掉", () => {
  const result = buildFunnelRow("u", {
    event: "onboarding_branch_answer",
    properties: { has_partner: true, intent: "analyze", correct: true },
  });
  assert(result.ok);
  if (result.ok) assertEquals(result.row.properties, { has_partner: true });
});

Deno.test("4 頁版 onboarding 的 page_index 0–3 照收", () => {
  for (const page_index of [0, 1, 2, 3]) {
    const result = buildFunnelRow("u", {
      event: "onboarding_page_view",
      properties: { page_index },
    });
    assert(result.ok);
    if (result.ok) assertEquals(result.row.properties, { page_index });
  }
});
