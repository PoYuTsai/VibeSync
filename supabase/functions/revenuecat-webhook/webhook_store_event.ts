import {
  extractRevenueCatBasePlanId,
  normalizeRevenueCatEnvironment,
  normalizeRevenueCatStore,
  type StoreSubscriptionEventInput,
} from "../_shared/subscription_store_state.ts";
import { getTierFromProductId } from "./tiers.ts";

export type WebhookStoreEventResult =
  | { readonly kind: "event"; readonly event: StoreSubscriptionEventInput }
  | {
    readonly kind: "ignored";
    readonly reason:
      | "product_change_downgrade"
      | "billing_error_cancellation";
  }
  | { readonly kind: "invalid"; readonly reason: string };

export type RevenueCatExpirationReason =
  | "UNSUBSCRIBE"
  | "BILLING_ERROR"
  | "DEVELOPER_INITIATED"
  | "PRICE_INCREASE"
  | "CUSTOMER_SUPPORT"
  | "UNKNOWN"
  | "SUBSCRIPTION_PAUSED";

const EXPIRATION_REASONS: ReadonlySet<RevenueCatExpirationReason> = new Set([
  "UNSUBSCRIBE",
  "BILLING_ERROR",
  "DEVELOPER_INITIATED",
  "PRICE_INCREASE",
  "CUSTOMER_SUPPORT",
  "UNKNOWN",
  "SUBSCRIPTION_PAUSED",
]);

/**
 * Normalizes a RevenueCat terminal reason for logging/idempotency metadata.
 * The state row intentionally stores only the terminal EXPIRATION signal; no
 * schema field is introduced for this forward-compatible reason string.
 */
export function normalizeRevenueCatExpirationReason(
  value: unknown,
): RevenueCatExpirationReason {
  if (typeof value !== "string") return "UNKNOWN";
  const normalized = value.trim().toUpperCase();
  return EXPIRATION_REASONS.has(normalized as RevenueCatExpirationReason)
    ? normalized as RevenueCatExpirationReason
    : "UNKNOWN";
}

function text(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function dateFrom(value: unknown): Date | null {
  if (typeof value === "number" && Number.isFinite(value) && value > 0) {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  if (typeof value === "string" && value.trim()) {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  return null;
}

function firstDate(
  event: Record<string, unknown>,
  keys: string[],
): Date | null {
  for (const key of keys) {
    if (!(key in event)) continue;
    const parsed = dateFrom(event[key]);
    if (parsed != null) return parsed;
  }
  return null;
}

function supportedType(type: string): boolean {
  return type === "INITIAL_PURCHASE" || type === "RENEWAL" ||
    type === "UNCANCELLATION" || type === "SUBSCRIPTION_EXTENDED" ||
    type === "PRODUCT_CHANGE" || type === "EXPIRATION" ||
    type === "BILLING_ISSUE" || type === "CANCELLATION" ||
    type === "TRANSFER" || type === "SUBSCRIPTION_PAUSED";
}

function isBillingErrorCancellation(
  type: string,
  event: Record<string, unknown>,
): boolean {
  return type === "CANCELLATION" &&
    text(event.cancel_reason)?.toUpperCase() === "BILLING_ERROR";
}

/**
 * Builds exactly one per-store state event from one webhook payload. No legacy
 * aggregate tier/expiry is accepted as an input: ordering and replay safety
 * belong to the per-store atomic RPC.
 */
export function buildRevenueCatWebhookStoreEvent(
  type: string,
  event: Record<string, unknown>,
): WebhookStoreEventResult {
  if (!supportedType(type)) {
    return { kind: "invalid", reason: "unsupported_event_type" };
  }

  // RevenueCat emits BILLING_ISSUE and CANCELLATION(cancel_reason=BILLING_ERROR)
  // for the same payment failure. Treat the cancellation as a duplicate
  // signal so its delivery order cannot hide the authoritative grace window.
  if (isBillingErrorCancellation(type, event)) {
    return { kind: "ignored", reason: "billing_error_cancellation" };
  }

  const store = normalizeRevenueCatStore(event.store);
  if (store == null) return { kind: "invalid", reason: "missing_store" };

  const oldProductId = type === "PRODUCT_CHANGE"
    ? text(event.product_id)
    : null;
  const newProductId = type === "PRODUCT_CHANGE"
    ? text(event.new_product_id)
    : null;
  if (
    type === "PRODUCT_CHANGE" && (oldProductId == null || newProductId == null)
  ) {
    return { kind: "invalid", reason: "missing_product_change_product" };
  }
  const productId = type === "PRODUCT_CHANGE"
    ? newProductId
    : text(event.product_id);
  if (productId == null) return { kind: "invalid", reason: "missing_product" };

  const normalizedExpirationReason = type === "EXPIRATION"
    ? normalizeRevenueCatExpirationReason(event.expiration_reason)
    : null;

  const derivedTier = getTierFromProductId(productId);
  if (derivedTier == null) {
    return { kind: "invalid", reason: "unsupported_product" };
  }
  if (type === "PRODUCT_CHANGE") {
    const oldTier = getTierFromProductId(oldProductId!);
    if (oldTier == null) {
      return { kind: "invalid", reason: "unsupported_product" };
    }
    const rank = (tier: string): number => tier === "essential" ? 2 : 1;
    if (rank(derivedTier!) <= rank(oldTier)) {
      return { kind: "ignored", reason: "product_change_downgrade" };
    }
  }

  const status = type === "EXPIRATION"
    ? "expired"
    : type === "CANCELLATION"
    ? "cancelled"
    : type === "BILLING_ISSUE"
    ? "billing_issue"
    : "active";
  const eventAt = firstDate(
    event,
    type === "CANCELLATION"
      ? [
        "cancelled_at_ms",
        "cancelled_at",
        "unsubscribe_detected_at",
        "event_timestamp_ms",
        "purchased_at_ms",
      ]
      : type === "BILLING_ISSUE"
      ? [
        "billing_issues_detected_at_ms",
        "billing_issues_detected_at",
        "event_timestamp_ms",
        "purchased_at_ms",
      ]
      : type === "EXPIRATION"
      ? ["event_timestamp_ms", "expiration_at_ms", "purchased_at_ms"]
      : ["event_timestamp_ms", "purchased_at_ms"],
  );
  if (eventAt == null) return { kind: "invalid", reason: "missing_event_at" };

  const expirationAt = dateFrom(event.expiration_at_ms) ??
    dateFrom(event.expiration_at) ?? null;
  const gracePeriodKey = type === "BILLING_ISSUE"
    ? Object.hasOwn(event, "grace_period_expiration_at_ms")
      ? "grace_period_expiration_at_ms"
      : Object.hasOwn(event, "grace_period_expiration_at")
      ? "grace_period_expiration_at"
      : null
    : null;
  const gracePeriodRaw = gracePeriodKey == null ? null : event[gracePeriodKey];
  const gracePeriodExpirationAt = gracePeriodRaw == null
    ? null
    : dateFrom(gracePeriodRaw);
  if (
    gracePeriodKey != null && gracePeriodRaw != null &&
    gracePeriodExpirationAt == null
  ) {
    return { kind: "invalid", reason: "invalid_grace_period_expiration" };
  }
  const expiresAt = gracePeriodExpirationAt ?? expirationAt;
  const requiresAuthoritativeExpiration = type !== "EXPIRATION";
  const hasMalformedExpiration = [
    "expiration_at_ms",
    "expiration_at",
  ].some((key) =>
    Object.hasOwn(event, key) && event[key] != null &&
    dateFrom(event[key]) == null
  );
  if (requiresAuthoritativeExpiration && expiresAt == null) {
    return {
      kind: "invalid",
      reason: hasMalformedExpiration
        ? "invalid_authoritative_expiration"
        : "missing_authoritative_expiration",
    };
  }
  const explicitEventId = text(event.id);
  const eventId = explicitEventId ?? [
    text(event.transaction_id) ?? `${store}:${productId}`,
    type,
    productId,
    status,
    eventAt.toISOString(),
    expiresAt?.toISOString() ?? "none",
    normalizedExpirationReason ?? "none",
  ].join(":");

  return {
    kind: "event",
    event: {
      store,
      source: "revenuecat_webhook",
      productId,
      basePlanId: extractRevenueCatBasePlanId(
        store,
        productId,
        event.product_plan_identifier ?? event.base_plan_id,
      ),
      tier: type === "EXPIRATION" ? "free" : derivedTier,
      status,
      expiresAt,
      eventAt: eventAt.toISOString(),
      eventId,
      verificationStatus: "verified",
      revenueCatEnvironment: normalizeRevenueCatEnvironment(event.environment),
    },
  };
}
