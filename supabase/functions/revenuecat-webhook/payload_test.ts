import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";

import { buildRevenueEventPayload, buildWebhookLogPayload } from "./payload.ts";

// 測試資料都是編的：假的使用者 UUID、假的交易編號。
const USER_ID = "11111111-2222-4333-8444-555555555555";
const ALIAS_ID = "66666666-7777-4888-9999-000000000000";

// 一批 RevenueCat 事件：退款取消（每個字串前後留空白、aliases 混進無效值）、
// 關掉自動續訂、到期、空事件、型別全錯、轉移。
const EVENTS: Record<string, Record<string, unknown>> = {
  refund: {
    id: "  evt-cancel-0001  ",
    type: " CANCELLATION ",
    app_user_id: ` ${USER_ID} `,
    original_app_user_id: USER_ID,
    aliases: [USER_ID, "$RCAnonymousID:0a1b2c", `  ${ALIAS_ID}  `, 42, ""],
    product_id: " vibesync_starter_monthly_v2 ",
    new_product_id: null,
    entitlement_ids: [" premium ", "", 7, null],
    environment: " PRODUCTION ",
    store: "APP_STORE",
    expiration_at_ms: 1793000000000,
    purchased_at_ms: 1790400000000,
    event_timestamp_ms: 1791000000000,
    price: 5.99,
    price_in_purchased_currency: 190,
    currency: " TWD ",
    transaction_id: " 2000000123456789 ",
    cancel_reason: " CUSTOMER_SUPPORT ",
  },
  unsubscribe: {
    id: "evt-cancel-0002",
    type: "CANCELLATION",
    app_user_id: USER_ID,
    product_id: "vibesync_essential_monthly_v2",
    entitlement_ids: ["premium"],
    environment: "SANDBOX",
    store: "APP_STORE",
    expiration_at_ms: 1793000000000,
    event_timestamp_ms: 1791000000000,
    price: 0,
    currency: "TWD",
    cancel_reason: "UNSUBSCRIBE",
  },
  expiration: {
    id: "evt-exp-0003",
    type: "EXPIRATION",
    app_user_id: USER_ID,
    product_id: "vibesync_essential_quarterly_v2",
    entitlement_ids: ["premium"],
    environment: "PRODUCTION",
    store: "APP_STORE",
    expiration_at_ms: 1793000000000,
    purchased_at_ms: 1785000000000,
    expiration_reason: "BILLING_ERROR",
  },
  empty: {},
  wrongTypes: {
    id: 123,
    type: 42,
    app_user_id: [USER_ID],
    original_app_user_id: { id: USER_ID },
    aliases: USER_ID,
    product_id: true,
    new_product_id: 9,
    entitlement_ids: "premium",
    environment: null,
    store: 1,
    expiration_at_ms: "1793000000000",
    purchased_at_ms: null,
    transferred_to: USER_ID,
    transferred_from: {},
    price: "5.99",
    price_in_purchased_currency: null,
    currency: 840,
    transaction_id: 77,
    event_timestamp_ms: "1791000000000",
    cancel_reason: 3,
    expiration_reason: { code: "UNSUBSCRIBE" },
  },
  transfer: {
    id: "evt-transfer-0004",
    type: "TRANSFER",
    app_user_id: USER_ID,
    transferred_to: [USER_ID, "not-a-uuid"],
    transferred_from: [` ${ALIAS_ID} `],
    product_id: "vibesync_starter_monthly_v2",
    new_product_id: " vibesync_essential_monthly_v2 ",
    environment: "PRODUCTION",
    store: "APP_STORE",
    price: 12.5,
    price_in_purchased_currency: 390,
    currency: "",
    transaction_id: "   ",
    event_timestamp_ms: 0,
    cancel_reason: "",
    expiration_reason: "   ",
  },
};

type LogOptions = {
  ignoredReason?: string;
  processedTier?: string;
  transferTo?: string[];
  transferFrom?: string[];
};

const LOG_CASES: ReadonlyArray<readonly [string, string, LogOptions]> = [
  ["refund", "refund", {}],
  ["refundIgnored", "refund", { ignoredReason: "user_not_found" }],
  ["unsubscribeProcessed", "unsubscribe", { processedTier: "essential" }],
  ["expirationNotProcessed", "expiration", { processedTier: undefined }],
  ["empty", "empty", {}],
  ["wrongTypes", "wrongTypes", {}],
  ["transfer", "transfer", {}],
  ["transferOverride", "transfer", { transferTo: [USER_ID], transferFrom: [] }],
];

// 抽出前的輸出：96261f6f 的 index.ts（buildWebhookLogPayload L92-135、
// buildRevenueEventPayload L137-151）對上面同一批事件跑出來的結果，原樣貼上。
// 抽出後除了新加的 cancel_reason、expiration_reason，其他欄位都要一模一樣。
const BEFORE_LOG: Record<string, Record<string, unknown>> = {
  refund: {
    version: "2026-05-26-rc-webhook-v5",
    type: "CANCELLATION",
    app_user_id: "11111111-2222-4333-8444-555555555555",
    original_app_user_id: "11111111-2222-4333-8444-555555555555",
    aliases: [
      "11111111-2222-4333-8444-555555555555",
      "66666666-7777-4888-9999-000000000000",
    ],
    product_id: "vibesync_starter_monthly_v2",
    new_product_id: null,
    entitlement_ids: [
      "premium",
    ],
    environment: "PRODUCTION",
    store: "APP_STORE",
    expiration_at_ms: 1793000000000,
    purchased_at_ms: 1790400000000,
    transferred_to: [],
    transferred_from: [],
    processed_tier: null,
    ignored_reason: null,
  },
  refundIgnored: {
    version: "2026-05-26-rc-webhook-v5",
    type: "CANCELLATION",
    app_user_id: "11111111-2222-4333-8444-555555555555",
    original_app_user_id: "11111111-2222-4333-8444-555555555555",
    aliases: [
      "11111111-2222-4333-8444-555555555555",
      "66666666-7777-4888-9999-000000000000",
    ],
    product_id: "vibesync_starter_monthly_v2",
    new_product_id: null,
    entitlement_ids: [
      "premium",
    ],
    environment: "PRODUCTION",
    store: "APP_STORE",
    expiration_at_ms: 1793000000000,
    purchased_at_ms: 1790400000000,
    transferred_to: [],
    transferred_from: [],
    processed_tier: null,
    ignored_reason: "user_not_found",
  },
  unsubscribeProcessed: {
    version: "2026-05-26-rc-webhook-v5",
    type: "CANCELLATION",
    app_user_id: "11111111-2222-4333-8444-555555555555",
    original_app_user_id: null,
    aliases: [],
    product_id: "vibesync_essential_monthly_v2",
    new_product_id: null,
    entitlement_ids: [
      "premium",
    ],
    environment: "SANDBOX",
    store: "APP_STORE",
    expiration_at_ms: 1793000000000,
    purchased_at_ms: null,
    transferred_to: [],
    transferred_from: [],
    processed_tier: "essential",
    ignored_reason: null,
  },
  expirationNotProcessed: {
    version: "2026-05-26-rc-webhook-v5",
    type: "EXPIRATION",
    app_user_id: "11111111-2222-4333-8444-555555555555",
    original_app_user_id: null,
    aliases: [],
    product_id: "vibesync_essential_quarterly_v2",
    new_product_id: null,
    entitlement_ids: [
      "premium",
    ],
    environment: "PRODUCTION",
    store: "APP_STORE",
    expiration_at_ms: 1793000000000,
    purchased_at_ms: 1785000000000,
    transferred_to: [],
    transferred_from: [],
    processed_tier: null,
    ignored_reason: null,
  },
  empty: {
    version: "2026-05-26-rc-webhook-v5",
    type: null,
    app_user_id: null,
    original_app_user_id: null,
    aliases: [],
    product_id: null,
    new_product_id: null,
    entitlement_ids: [],
    environment: null,
    store: null,
    expiration_at_ms: null,
    purchased_at_ms: null,
    transferred_to: [],
    transferred_from: [],
    processed_tier: null,
    ignored_reason: null,
  },
  wrongTypes: {
    version: "2026-05-26-rc-webhook-v5",
    type: null,
    app_user_id: null,
    original_app_user_id: null,
    aliases: [],
    product_id: null,
    new_product_id: null,
    entitlement_ids: [],
    environment: null,
    store: null,
    expiration_at_ms: null,
    purchased_at_ms: null,
    transferred_to: [],
    transferred_from: [],
    processed_tier: null,
    ignored_reason: null,
  },
  transfer: {
    version: "2026-05-26-rc-webhook-v5",
    type: "TRANSFER",
    app_user_id: "11111111-2222-4333-8444-555555555555",
    original_app_user_id: null,
    aliases: [],
    product_id: "vibesync_starter_monthly_v2",
    new_product_id: "vibesync_essential_monthly_v2",
    entitlement_ids: [],
    environment: "PRODUCTION",
    store: "APP_STORE",
    expiration_at_ms: null,
    purchased_at_ms: null,
    transferred_to: [
      "11111111-2222-4333-8444-555555555555",
    ],
    transferred_from: [
      "66666666-7777-4888-9999-000000000000",
    ],
    processed_tier: null,
    ignored_reason: null,
  },
  transferOverride: {
    version: "2026-05-26-rc-webhook-v5",
    type: "TRANSFER",
    app_user_id: "11111111-2222-4333-8444-555555555555",
    original_app_user_id: null,
    aliases: [],
    product_id: "vibesync_starter_monthly_v2",
    new_product_id: "vibesync_essential_monthly_v2",
    entitlement_ids: [],
    environment: "PRODUCTION",
    store: "APP_STORE",
    expiration_at_ms: null,
    purchased_at_ms: null,
    transferred_to: [
      "11111111-2222-4333-8444-555555555555",
    ],
    transferred_from: [],
    processed_tier: null,
    ignored_reason: null,
  },
};

const BEFORE_REVENUE: Record<string, Record<string, unknown>> = {
  refund: {
    version: "2026-05-26-rc-webhook-v5",
    type: "CANCELLATION",
    app_user_id: "11111111-2222-4333-8444-555555555555",
    original_app_user_id: "11111111-2222-4333-8444-555555555555",
    aliases: [
      "11111111-2222-4333-8444-555555555555",
      "66666666-7777-4888-9999-000000000000",
    ],
    product_id: "vibesync_starter_monthly_v2",
    new_product_id: null,
    entitlement_ids: [
      "premium",
    ],
    environment: "PRODUCTION",
    store: "APP_STORE",
    expiration_at_ms: 1793000000000,
    purchased_at_ms: 1790400000000,
    transferred_to: [],
    transferred_from: [],
    processed_tier: null,
    ignored_reason: null,
    revenuecat_event_id: "evt-cancel-0001",
    price_usd: 5.99,
    price_in_purchased_currency: 190,
    currency: "TWD",
    transaction_id: "2000000123456789",
    event_timestamp_ms: 1791000000000,
  },
  unsubscribe: {
    version: "2026-05-26-rc-webhook-v5",
    type: "CANCELLATION",
    app_user_id: "11111111-2222-4333-8444-555555555555",
    original_app_user_id: null,
    aliases: [],
    product_id: "vibesync_essential_monthly_v2",
    new_product_id: null,
    entitlement_ids: [
      "premium",
    ],
    environment: "SANDBOX",
    store: "APP_STORE",
    expiration_at_ms: 1793000000000,
    purchased_at_ms: null,
    transferred_to: [],
    transferred_from: [],
    processed_tier: null,
    ignored_reason: null,
    revenuecat_event_id: "evt-cancel-0002",
    price_usd: 0,
    price_in_purchased_currency: null,
    currency: "TWD",
    transaction_id: null,
    event_timestamp_ms: 1791000000000,
  },
  expiration: {
    version: "2026-05-26-rc-webhook-v5",
    type: "EXPIRATION",
    app_user_id: "11111111-2222-4333-8444-555555555555",
    original_app_user_id: null,
    aliases: [],
    product_id: "vibesync_essential_quarterly_v2",
    new_product_id: null,
    entitlement_ids: [
      "premium",
    ],
    environment: "PRODUCTION",
    store: "APP_STORE",
    expiration_at_ms: 1793000000000,
    purchased_at_ms: 1785000000000,
    transferred_to: [],
    transferred_from: [],
    processed_tier: null,
    ignored_reason: null,
    revenuecat_event_id: "evt-exp-0003",
    price_usd: null,
    price_in_purchased_currency: null,
    currency: null,
    transaction_id: null,
    event_timestamp_ms: null,
  },
  empty: {
    version: "2026-05-26-rc-webhook-v5",
    type: null,
    app_user_id: null,
    original_app_user_id: null,
    aliases: [],
    product_id: null,
    new_product_id: null,
    entitlement_ids: [],
    environment: null,
    store: null,
    expiration_at_ms: null,
    purchased_at_ms: null,
    transferred_to: [],
    transferred_from: [],
    processed_tier: null,
    ignored_reason: null,
    revenuecat_event_id: null,
    price_usd: null,
    price_in_purchased_currency: null,
    currency: null,
    transaction_id: null,
    event_timestamp_ms: null,
  },
  wrongTypes: {
    version: "2026-05-26-rc-webhook-v5",
    type: null,
    app_user_id: null,
    original_app_user_id: null,
    aliases: [],
    product_id: null,
    new_product_id: null,
    entitlement_ids: [],
    environment: null,
    store: null,
    expiration_at_ms: null,
    purchased_at_ms: null,
    transferred_to: [],
    transferred_from: [],
    processed_tier: null,
    ignored_reason: null,
    revenuecat_event_id: null,
    price_usd: null,
    price_in_purchased_currency: null,
    currency: null,
    transaction_id: null,
    event_timestamp_ms: null,
  },
  transfer: {
    version: "2026-05-26-rc-webhook-v5",
    type: "TRANSFER",
    app_user_id: "11111111-2222-4333-8444-555555555555",
    original_app_user_id: null,
    aliases: [],
    product_id: "vibesync_starter_monthly_v2",
    new_product_id: "vibesync_essential_monthly_v2",
    entitlement_ids: [],
    environment: "PRODUCTION",
    store: "APP_STORE",
    expiration_at_ms: null,
    purchased_at_ms: null,
    transferred_to: [
      "11111111-2222-4333-8444-555555555555",
    ],
    transferred_from: [
      "66666666-7777-4888-9999-000000000000",
    ],
    processed_tier: null,
    ignored_reason: null,
    revenuecat_event_id: "evt-transfer-0004",
    price_usd: 12.5,
    price_in_purchased_currency: 390,
    currency: null,
    transaction_id: null,
    event_timestamp_ms: 0,
  },
};

// 每個事件抽出後應該多出的兩個欄位。
const NEW_FIELDS: Record<
  string,
  { cancel_reason: string | null; expiration_reason: string | null }
> = {
  refund: { cancel_reason: "CUSTOMER_SUPPORT", expiration_reason: null },
  unsubscribe: { cancel_reason: "UNSUBSCRIBE", expiration_reason: null },
  expiration: { cancel_reason: null, expiration_reason: "BILLING_ERROR" },
  empty: { cancel_reason: null, expiration_reason: null },
  wrongTypes: { cancel_reason: null, expiration_reason: null },
  transfer: { cancel_reason: null, expiration_reason: null },
};

Deno.test("CANCELLATION 帶 CUSTOMER_SUPPORT：webhook_logs 與 revenue_events 都存到取消原因", () => {
  const log = buildWebhookLogPayload(EVENTS.refund);
  const revenue = buildRevenueEventPayload(EVENTS.refund);
  assertEquals(log.cancel_reason, "CUSTOMER_SUPPORT");
  assertEquals(revenue.cancel_reason, "CUSTOMER_SUPPORT");
  assertEquals(log.expiration_reason, null);
  assertEquals(revenue.expiration_reason, null);
});

Deno.test("CANCELLATION 帶 UNSUBSCRIBE：存成關掉自動續訂", () => {
  assertEquals(
    buildWebhookLogPayload(EVENTS.unsubscribe).cancel_reason,
    "UNSUBSCRIBE",
  );
  assertEquals(
    buildRevenueEventPayload(EVENTS.unsubscribe).cancel_reason,
    "UNSUBSCRIBE",
  );
});

Deno.test("EXPIRATION 帶 expiration_reason：到期原因存進 webhook_logs，取消原因是 null", () => {
  const log = buildWebhookLogPayload(EVENTS.expiration, {
    processedTier: "free",
  });
  assertEquals(log.expiration_reason, "BILLING_ERROR");
  assertEquals(log.cancel_reason, null);
});

Deno.test("缺欄位：兩個原因都是 null，但鍵一定在（部署後的新列查得到這個鍵）", () => {
  for (
    const payload of [
      buildWebhookLogPayload({ type: "CANCELLATION" }),
      buildRevenueEventPayload({ type: "CANCELLATION" }),
    ]
  ) {
    assertEquals(Object.hasOwn(payload, "cancel_reason"), true);
    assertEquals(Object.hasOwn(payload, "expiration_reason"), true);
    assertEquals(payload.cancel_reason, null);
    assertEquals(payload.expiration_reason, null);
  }
});

Deno.test("不是字串就是 null：數字、布林、null、陣列、物件", () => {
  for (
    const value of [
      3,
      true,
      null,
      ["CUSTOMER_SUPPORT"],
      { reason: "CUSTOMER_SUPPORT" },
    ]
  ) {
    const event = {
      type: "CANCELLATION",
      cancel_reason: value,
      expiration_reason: value,
    };
    const label = JSON.stringify(value);
    assertEquals(buildWebhookLogPayload(event).cancel_reason, null, label);
    assertEquals(buildWebhookLogPayload(event).expiration_reason, null, label);
    assertEquals(buildRevenueEventPayload(event).cancel_reason, null, label);
  }
});

Deno.test("字串去掉前後空白；空字串與全空白是 null", () => {
  assertEquals(
    buildWebhookLogPayload({ cancel_reason: "  UNSUBSCRIBE\n" }).cancel_reason,
    "UNSUBSCRIBE",
  );
  assertEquals(
    buildWebhookLogPayload({ cancel_reason: "" }).cancel_reason,
    null,
  );
  assertEquals(
    buildWebhookLogPayload({ expiration_reason: " \t " }).expiration_reason,
    null,
  );
});

Deno.test("抽出前後其他欄位一樣：webhook_logs.payload（對照 96261f6f 的輸出）", () => {
  for (const [name, key, options] of LOG_CASES) {
    assertEquals(
      buildWebhookLogPayload(EVENTS[key], options),
      { ...BEFORE_LOG[name], ...NEW_FIELDS[key] },
      name,
    );
  }
});

Deno.test("抽出前後其他欄位一樣：revenue_events.raw_payload（對照 96261f6f 的輸出）", () => {
  for (const key of Object.keys(EVENTS)) {
    assertEquals(
      buildRevenueEventPayload(EVENTS[key]),
      { ...BEFORE_REVENUE[key], ...NEW_FIELDS[key] },
      key,
    );
  }
});
