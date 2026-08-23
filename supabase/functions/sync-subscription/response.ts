export type SyncSubscriptionTier = "free" | "starter" | "essential";

export interface AuthoritativeSubscriptionAggregate {
  readonly tier: SyncSubscriptionTier;
  readonly monthlyMessagesUsed: number;
  readonly dailyMessagesUsed: number;
  readonly monthlyResetAt: string | null;
  readonly dailyResetAt: string | null;
  readonly expiresAt: string | null;
  readonly activeProductId: string | null;
  readonly billingPeriod: string | null;
  readonly store: "app_store" | "play_store" | null;
  readonly revenueCatEnvironment: "sandbox" | "production" | null;
}

function normalizeTier(value: unknown): SyncSubscriptionTier | null {
  return value === "starter" || value === "essential" || value === "free"
    ? value
    : null;
}

function nullableString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value : null;
}

function nonNegativeInteger(value: unknown): number {
  return typeof value === "number" && Number.isInteger(value) && value >= 0
    ? value
    : 0;
}

function store(value: unknown): "app_store" | "play_store" | null {
  return value === "app_store" || value === "play_store" ? value : null;
}

function environment(value: unknown): "sandbox" | "production" | null {
  return value === "sandbox" || value === "production" ? value : null;
}

/**
 * Reads only the row returned after the atomic store-state RPC. Snapshot
 * fields are intentionally absent: callers must not report a guessed tier or
 * product when the legacy aggregate cannot be read.
 */
export function readAuthoritativeSubscriptionAggregate(
  row: Record<string, unknown> | null,
): AuthoritativeSubscriptionAggregate | null {
  if (row == null) return null;
  const tier = normalizeTier(row.tier);
  if (tier == null) return null;
  return {
    tier,
    monthlyMessagesUsed: nonNegativeInteger(row.monthly_messages_used),
    dailyMessagesUsed: nonNegativeInteger(row.daily_messages_used),
    monthlyResetAt: nullableString(row.monthly_reset_at),
    dailyResetAt: nullableString(row.daily_reset_at),
    expiresAt: nullableString(row.expires_at),
    activeProductId: nullableString(row.active_product_id),
    billingPeriod: nullableString(row.billing_period),
    store: store(row.store),
    revenueCatEnvironment: environment(row.revenuecat_environment),
  };
}
