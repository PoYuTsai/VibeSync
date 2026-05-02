// supabase/functions/coach-follow-up/quota.ts
//
// Quota machinery — pure helpers that mirror the analyze-chat contract WITHOUT
// importing from analyze-chat (Codex Plan-Review §A5 OCR isolation rule).
//
// The DB-touching wrappers (selfHealSubscription / persistResets /
// maybeRefreshTierFromRevenueCat) live in index.ts so this module stays
// trivially unit-testable without Supabase mocks. The full edge-case matrix
// (Codex P1 #3) is covered in quota_test.ts.
//
// Limits / test-account list / RC payload shape MUST match analyze-chat
// (CLAUDE.md pricing table @ 2026-04-22). If pricing changes, both functions
// have to update — there's no shared module by design.

export type TierName = "free" | "starter" | "essential";

export const TIER_MONTHLY_LIMITS: Record<string, number> = {
  free: 30,
  starter: 300,
  essential: 800,
};

export const TIER_DAILY_LIMITS: Record<string, number> = {
  free: 15,
  starter: 50,
  essential: 120,
};

export const TEST_EMAILS = ["vibesync.test@gmail.com"];

// ---------------------------------------------------------------------------
// Type discriminator + tier helpers
// ---------------------------------------------------------------------------

export function isPlainObject(
  value: unknown,
): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function normalizeTier(value: unknown): TierName {
  if (typeof value !== "string") return "free";
  const normalized = value.trim().toLowerCase();
  if (normalized === "starter" || normalized === "essential") {
    return normalized;
  }
  return "free";
}

export function tierRank(value: TierName): number {
  switch (value) {
    case "essential":
      return 2;
    case "starter":
      return 1;
    case "free":
    default:
      return 0;
  }
}

export function resolveLimits(
  tier: string | null | undefined,
): { monthly: number; daily: number } {
  const t = normalizeTier(tier);
  return { monthly: TIER_MONTHLY_LIMITS[t], daily: TIER_DAILY_LIMITS[t] };
}

// ---------------------------------------------------------------------------
// Subscription row + reset detection
// ---------------------------------------------------------------------------

export interface SubscriptionRow {
  tier: string | null;
  monthly_messages_used: number;
  daily_messages_used: number;
  daily_reset_at: string | null;
  monthly_reset_at: string | null;
}

export interface ResetResult {
  sub: SubscriptionRow;
  dailyReset: boolean;
  monthlyReset: boolean;
}

function sameUtcDay(a: Date, b: Date): boolean {
  return (
    a.getUTCFullYear() === b.getUTCFullYear() &&
    a.getUTCMonth() === b.getUTCMonth() &&
    a.getUTCDate() === b.getUTCDate()
  );
}

function sameUtcMonth(a: Date, b: Date): boolean {
  return (
    a.getUTCFullYear() === b.getUTCFullYear() &&
    a.getUTCMonth() === b.getUTCMonth()
  );
}

/**
 * Returns a NEW SubscriptionRow with daily / monthly counters zeroed if the
 * corresponding reset window crossed. Caller is responsible for persisting
 * the returned sub back to Supabase when either flag is true.
 *
 * Comparison is in UTC (Supabase Edge runs UTC; using getUTC* keeps the helper
 * deterministic across test environments and matches production semantics).
 *
 * Null timestamps are treated as "never reset" → both resets fire (matches
 * analyze-chat's `new Date(0)` fallback behaviour).
 */
export function applyResetsIfNeeded(
  sub: SubscriptionRow,
  now: Date,
): ResetResult {
  const out: SubscriptionRow = { ...sub };
  let dailyReset = false;
  let monthlyReset = false;

  const dailyResetAt = sub.daily_reset_at
    ? new Date(sub.daily_reset_at)
    : new Date(0);
  if (!sameUtcDay(now, dailyResetAt)) {
    out.daily_messages_used = 0;
    out.daily_reset_at = now.toISOString();
    dailyReset = true;
  }

  const monthlyResetAt = sub.monthly_reset_at
    ? new Date(sub.monthly_reset_at)
    : new Date(0);
  if (!sameUtcMonth(now, monthlyResetAt)) {
    out.monthly_messages_used = 0;
    out.monthly_reset_at = now.toISOString();
    monthlyReset = true;
  }

  return { sub: out, dailyReset, monthlyReset };
}

// ---------------------------------------------------------------------------
// Quota check
// ---------------------------------------------------------------------------

export type QuotaCheckResult =
  | { ok: true }
  | {
    ok: false;
    reason: "monthly_limit_exceeded" | "daily_limit_exceeded";
    used: number;
    limit: number;
  };

/**
 * Pure quota gate. Test accounts bypass entirely. Monthly check precedes daily
 * (so a user at both caps gets the monthly error, matching analyze-chat).
 */
export function checkQuota(opts: {
  sub: SubscriptionRow;
  cost: number;
  isTestAccount: boolean;
  monthlyLimit: number;
  dailyLimit: number;
}): QuotaCheckResult {
  if (opts.isTestAccount) return { ok: true };

  const monthlyAfter = opts.sub.monthly_messages_used + opts.cost;
  if (monthlyAfter > opts.monthlyLimit) {
    return {
      ok: false,
      reason: "monthly_limit_exceeded",
      used: opts.sub.monthly_messages_used,
      limit: opts.monthlyLimit,
    };
  }

  const dailyAfter = opts.sub.daily_messages_used + opts.cost;
  if (dailyAfter > opts.dailyLimit) {
    return {
      ok: false,
      reason: "daily_limit_exceeded",
      used: opts.sub.daily_messages_used,
      limit: opts.dailyLimit,
    };
  }

  return { ok: true };
}

// ---------------------------------------------------------------------------
// RevenueCat subscriber payload parser
// ---------------------------------------------------------------------------

function parseRcDate(value: unknown): Date | null {
  if (typeof value !== "string" || !value.trim()) return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function isActiveAt(expiresDate: unknown): boolean {
  const parsed = parseRcDate(expiresDate);
  if (parsed == null) return true; // no expiry → treat as active
  return parsed.getTime() > Date.now();
}

function tierFromProductId(productId: unknown): TierName {
  if (typeof productId !== "string") return "free";
  const normalized = productId.trim().toLowerCase();
  if (normalized.includes("essential")) return "essential";
  if (normalized.includes("starter")) return "starter";
  return "free";
}

function highestTier(tiers: Iterable<TierName>): TierName {
  const all = Array.from(tiers);
  if (all.includes("essential")) return "essential";
  if (all.includes("starter")) return "starter";
  return "free";
}

/**
 * Parse a RevenueCat /subscribers/{user_id} payload.subscriber object and
 * extract the highest currently-active tier + the latest expiration timestamp.
 * Returns null when input is not an object.
 */
export function parseRevenueCatSubscriber(
  subscriber: unknown,
): { tier: TierName; expiresAt: string | null } | null {
  if (!isPlainObject(subscriber)) return null;

  const activeTiers: TierName[] = [];
  let latestTimestamp: number | null = null;
  let latestIso: string | null = null;

  const considerExpiration = (raw: unknown) => {
    const parsed = parseRcDate(raw);
    if (parsed == null) return;
    const ts = parsed.getTime();
    if (latestTimestamp == null || ts > latestTimestamp) {
      latestTimestamp = ts;
      latestIso = parsed.toISOString();
    }
  };

  const entitlements = isPlainObject(subscriber.entitlements)
    ? subscriber.entitlements
    : {};
  for (const value of Object.values(entitlements)) {
    if (!isPlainObject(value)) continue;
    if (!isActiveAt(value.expires_date)) continue;
    activeTiers.push(tierFromProductId(value.product_identifier));
    considerExpiration(value.expires_date);
  }

  const subscriptions = isPlainObject(subscriber.subscriptions)
    ? subscriber.subscriptions
    : {};
  for (const [productId, value] of Object.entries(subscriptions)) {
    if (!isPlainObject(value)) continue;
    if (!isActiveAt(value.expires_date)) continue;
    activeTiers.push(tierFromProductId(productId));
    considerExpiration(value.expires_date);
  }

  return { tier: highestTier(activeTiers), expiresAt: latestIso };
}
