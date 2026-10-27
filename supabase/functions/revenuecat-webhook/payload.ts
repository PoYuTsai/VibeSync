// RevenueCat webhook 存進 `webhook_logs.payload` 與 `revenue_events.raw_payload`
// 的內容（只留白名單欄位，不存原始 body 與 headers）。
//
// 從 index.ts 抽出來（Onboarding 第 7 步）：index.ts 在模組頂層 `Deno.serve`，
// 測試沒辦法 import。這裡只放純函式，不碰 DB、不讀 env；函式本體照搬，
// 只多了 `cancel_reason`、`expiration_reason` 兩個欄位。

export const DEPLOY_VERSION = "2026-05-26-rc-webhook-v5";

export function isValidUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}

export function normalizeNumber(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return null;
  }

  return value;
}

export function optionalString(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function extractStringList(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .filter((item): item is string => typeof item === "string")
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
}

export function extractValidUuidList(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .filter((item): item is string => typeof item === "string")
    .map((item) => item.trim())
    .filter((item) => item.length > 0 && isValidUuid(item));
}

export function buildWebhookLogPayload(
  event: Record<string, unknown>,
  options: {
    ignoredReason?: string;
    processedTier?: string;
    transferTo?: string[];
    transferFrom?: string[];
  } = {},
): Record<string, unknown> {
  return {
    version: DEPLOY_VERSION,
    type: typeof event.type === "string" ? event.type.trim() : null,
    app_user_id: typeof event.app_user_id === "string"
      ? event.app_user_id.trim()
      : null,
    original_app_user_id: typeof event.original_app_user_id === "string"
      ? event.original_app_user_id.trim()
      : null,
    aliases: extractValidUuidList(event.aliases),
    product_id: typeof event.product_id === "string"
      ? event.product_id.trim()
      : null,
    new_product_id: typeof event.new_product_id === "string"
      ? event.new_product_id.trim()
      : null,
    entitlement_ids: extractStringList(event.entitlement_ids),
    environment: typeof event.environment === "string"
      ? event.environment.trim()
      : null,
    store: typeof event.store === "string" ? event.store.trim() : null,
    expiration_at_ms: typeof event.expiration_at_ms === "number"
      ? event.expiration_at_ms
      : null,
    purchased_at_ms: typeof event.purchased_at_ms === "number"
      ? event.purchased_at_ms
      : null,
    // CANCELLATION 靠 cancel_reason 分辨「關掉自動續訂」與「退款」；
    // EXPIRATION 的到期原因放 expiration_reason。值照 RevenueCat 原字串存，
    // 沒有、不是字串或只有空白就是 null。
    cancel_reason: optionalString(event.cancel_reason),
    expiration_reason: optionalString(event.expiration_reason),
    transferred_to: options.transferTo ??
      extractValidUuidList(event.transferred_to),
    transferred_from: options.transferFrom ??
      extractValidUuidList(event.transferred_from),
    processed_tier: options.processedTier ?? null,
    ignored_reason: options.ignoredReason ?? null,
  };
}

export function buildRevenueEventPayload(
  event: Record<string, unknown>,
): Record<string, unknown> {
  return {
    ...buildWebhookLogPayload(event),
    revenuecat_event_id: optionalString(event.id),
    price_usd: normalizeNumber(event.price),
    price_in_purchased_currency: normalizeNumber(
      event.price_in_purchased_currency,
    ),
    currency: optionalString(event.currency),
    transaction_id: optionalString(event.transaction_id),
    event_timestamp_ms: normalizeNumber(event.event_timestamp_ms),
  };
}
