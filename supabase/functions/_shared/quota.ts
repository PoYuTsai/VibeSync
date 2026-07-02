// supabase/functions/_shared/quota.ts
//
// Quota machinery — pure helpers that mirror the analyze-chat contract WITHOUT
// importing from analyze-chat (Codex Plan-Review §A5 OCR isolation rule).
//
// The DB-touching wrappers (selfHealSubscription / persistResets /
// maybeRefreshTierFromRevenueCat / increment_usage RPC) live in each function's
// index.ts so this module stays
// trivially unit-testable without Supabase mocks. The full edge-case matrix
// (Codex P1 #3) is covered in quota_test.ts.
//
// Limits / test-account list / RC payload shape MUST match analyze-chat
// (CLAUDE.md pricing table @ 2026-04-22). If pricing changes, update this
// shared helper once so coach-follow-up / coach-chat stay in lockstep.

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
  /**
   * Batch C#4 — reset 持久化改 CAS（UPDATE ... WHERE reset_at = 舊值）用的
   * 比對值。null＝該欄從未 reset 過（CAS 用 IS NULL）。CAS 失敗代表別的並發
   * 請求已跨窗口歸零，後到者必須放棄覆寫，才不會抹掉它剛扣的額度。
   */
  previousDailyResetAt: string | null;
  previousMonthlyResetAt: string | null;
}

export function sameUtcDay(a: Date, b: Date): boolean {
  return (
    a.getUTCFullYear() === b.getUTCFullYear() &&
    a.getUTCMonth() === b.getUTCMonth() &&
    a.getUTCDate() === b.getUTCDate()
  );
}

export function sameUtcMonth(a: Date, b: Date): boolean {
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

  return {
    sub: out,
    dailyReset,
    monthlyReset,
    previousDailyResetAt: sub.daily_reset_at,
    previousMonthlyResetAt: sub.monthly_reset_at,
  };
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

/**
 * Batch C#1 — increment_usage（4-arg 版）鎖內超限 RAISE 的 Edge 側偵測。
 * PostgREST 會把 RAISE 訊息包進較長字串，用 includes 抓（同 practice draw
 * 的 PRACTICE_DRAW_QUOTA_EXCEEDED_* 慣例）。非超限錯誤回 null，呼叫端走
 * 既有 credit_deduct_failed 路徑。
 */
export function classifyQuotaRpcError(
  message: string | null | undefined,
): "monthly_limit_exceeded" | "daily_limit_exceeded" | null {
  if (!message) return null;
  if (message.includes("QUOTA_EXCEEDED_MONTHLY")) {
    return "monthly_limit_exceeded";
  }
  if (message.includes("QUOTA_EXCEEDED_DAILY")) {
    return "daily_limit_exceeded";
  }
  return null;
}

export function quotaExceededMessage(
  reason: "monthly_limit_exceeded" | "daily_limit_exceeded",
): string {
  return reason === "monthly_limit_exceeded"
    ? "本月額度已用完，升級方案可取得更多分析與教練額度。"
    : "今日額度已用完，每天早上 8 點恢復；也可以升級取得更多額度。";
}

export function buildQuotaExceededPayload(opts: {
  sub: SubscriptionRow;
  cost: number;
  reason: "monthly_limit_exceeded" | "daily_limit_exceeded";
  monthlyLimit: number;
  dailyLimit: number;
}) {
  const monthlyRemaining = Math.max(
    0,
    opts.monthlyLimit - opts.sub.monthly_messages_used,
  );
  const dailyRemaining = Math.max(
    0,
    opts.dailyLimit - opts.sub.daily_messages_used,
  );
  const isMonthly = opts.reason === "monthly_limit_exceeded";

  return {
    error: isMonthly ? "Monthly limit exceeded" : "Daily limit exceeded",
    message: quotaExceededMessage(opts.reason),
    quotaNeeded: opts.cost,
    used: isMonthly
      ? opts.sub.monthly_messages_used
      : opts.sub.daily_messages_used,
    limit: isMonthly ? opts.monthlyLimit : opts.dailyLimit,
    monthlyLimit: opts.monthlyLimit,
    dailyLimit: opts.dailyLimit,
    monthlyUsed: opts.sub.monthly_messages_used,
    dailyUsed: opts.sub.daily_messages_used,
    monthlyRemaining,
    dailyRemaining,
  };
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
