// supabase/functions/analyze-chat/rate_limiter.ts
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface TierLimits {
  monthly: number;
  daily: number;
}

interface SubscriptionRow {
  tier: string;
  monthly_messages_used: number;
  daily_messages_used: number;
  daily_reset_at: string | null;
  monthly_reset_at: string | null;
}

interface RateLimitRow {
  minute_count: number;
  minute_window_start: string | null;
}

const TIER_LIMITS: Record<string, TierLimits> = {
  free: { monthly: 30, daily: 15 },
  starter: { monthly: 300, daily: 50 },
  essential: { monthly: 1000, daily: 150 },
};

const MINUTE_LIMIT = 5;

export interface RateLimitResult {
  allowed: boolean;
  reason?: "minute_limit" | "daily_limit" | "monthly_limit";
  retryAfter?: number;
  remaining: {
    minute: number;
    daily: number;
    monthly: number;
  };
}

function clampRemaining(value: number): number {
  return value < 0 ? 0 : value;
}

function getSecondsUntilMidnight(now: Date): number {
  const midnight = new Date(now);
  midnight.setHours(24, 0, 0, 0);
  return Math.max(
    0,
    Math.floor((midnight.getTime() - now.getTime()) / 1000),
  );
}

async function getOrCreateSubscription(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  now: Date,
): Promise<SubscriptionRow> {
  const subscriptions = supabase.from("subscriptions") as any;

  const { data: existingSub, error: subError } = await subscriptions
    .select(
      "tier, monthly_messages_used, daily_messages_used, daily_reset_at, monthly_reset_at",
    )
    .eq("user_id", userId)
    .maybeSingle();

  if (subError) {
    throw new Error(`Failed to load subscription: ${subError.message}`);
  }

  if (existingSub) {
    return existingSub;
  }

  const freshRow = {
    user_id: userId,
    tier: "free",
    monthly_messages_used: 0,
    daily_messages_used: 0,
    daily_reset_at: now.toISOString(),
    monthly_reset_at: now.toISOString(),
    started_at: now.toISOString(),
    status: "active",
  };

  const { data: insertedSub, error: insertError } = await subscriptions
    .insert(freshRow)
    .select(
      "tier, monthly_messages_used, daily_messages_used, daily_reset_at, monthly_reset_at",
    )
    .single();

  if (insertError || !insertedSub) {
    throw new Error(
      `Failed to create subscription: ${insertError?.message ?? "unknown error"}`,
    );
  }

  return insertedSub;
}

async function getOrCreateRateLimit(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  now: Date,
): Promise<RateLimitRow> {
  const rateLimits = supabase.from("rate_limits") as any;

  const { data: existingRateLimit, error: rateLimitError } = await rateLimits
    .select("minute_count, minute_window_start")
    .eq("user_id", userId)
    .maybeSingle();

  if (rateLimitError) {
    throw new Error(`Failed to load rate limit: ${rateLimitError.message}`);
  }

  if (existingRateLimit) {
    return existingRateLimit;
  }

  const { error: insertError } = await rateLimits
    .upsert({
      user_id: userId,
      minute_count: 0,
      minute_window_start: now.toISOString(),
    }, { onConflict: "user_id" });

  if (insertError) {
    throw new Error(`Failed to create rate limit: ${insertError.message}`);
  }

  return {
    minute_count: 0,
    minute_window_start: now.toISOString(),
  };
}

export async function checkRateLimit(
  supabase: ReturnType<typeof createClient>,
  userId: string,
): Promise<RateLimitResult> {
  const now = new Date();

  const sub = await getOrCreateSubscription(supabase, userId, now);
  const limits = TIER_LIMITS[sub.tier] ?? TIER_LIMITS.free;

  const dailyResetAt = sub.daily_reset_at ? new Date(sub.daily_reset_at) : null;
  if (!dailyResetAt || now.toDateString() !== dailyResetAt.toDateString()) {
    const { error } = await (supabase.from("subscriptions") as any)
      .update({ daily_messages_used: 0, daily_reset_at: now.toISOString() })
      .eq("user_id", userId);

    if (error) {
      throw new Error(`Failed to reset daily usage: ${error.message}`);
    }
    sub.daily_messages_used = 0;
    sub.daily_reset_at = now.toISOString();
  }

  const monthlyResetAt = sub.monthly_reset_at
    ? new Date(sub.monthly_reset_at)
    : null;
  if (
    !monthlyResetAt ||
    monthlyResetAt.getMonth() !== now.getMonth() ||
      monthlyResetAt.getFullYear() !== now.getFullYear()
  ) {
    const { error } = await (supabase.from("subscriptions") as any)
      .update({
        monthly_messages_used: 0,
        monthly_reset_at: now.toISOString(),
      })
      .eq("user_id", userId);

    if (error) {
      throw new Error(`Failed to reset monthly usage: ${error.message}`);
    }
    sub.monthly_messages_used = 0;
    sub.monthly_reset_at = now.toISOString();
  }

  const rateLimit = await getOrCreateRateLimit(supabase, userId, now);
  const windowStart = rateLimit.minute_window_start
    ? new Date(rateLimit.minute_window_start)
    : now;
  const secondsSinceWindow = (now.getTime() - windowStart.getTime()) / 1000;
  let minuteCount = rateLimit.minute_count;

  if (secondsSinceWindow >= 60) {
    const { error } = await (supabase.from("rate_limits") as any)
      .update({ minute_count: 0, minute_window_start: now.toISOString() })
      .eq("user_id", userId);

    if (error) {
      throw new Error(`Failed to reset minute usage: ${error.message}`);
    }
    minuteCount = 0;
  }

  if (minuteCount >= MINUTE_LIMIT) {
    return {
      allowed: false,
      reason: "minute_limit",
      retryAfter: Math.max(0, 60 - Math.floor(secondsSinceWindow)),
      remaining: {
        minute: 0,
        daily: clampRemaining(limits.daily - sub.daily_messages_used),
        monthly: clampRemaining(limits.monthly - sub.monthly_messages_used),
      },
    };
  }

  if (sub.daily_messages_used >= limits.daily) {
    return {
      allowed: false,
      reason: "daily_limit",
      retryAfter: getSecondsUntilMidnight(now),
      remaining: {
        minute: clampRemaining(MINUTE_LIMIT - minuteCount),
        daily: 0,
        monthly: clampRemaining(limits.monthly - sub.monthly_messages_used),
      },
    };
  }

  if (sub.monthly_messages_used >= limits.monthly) {
    return {
      allowed: false,
      reason: "monthly_limit",
      remaining: {
        minute: clampRemaining(MINUTE_LIMIT - minuteCount),
        daily: 0,
        monthly: 0,
      },
    };
  }

  return {
    allowed: true,
    remaining: {
      minute: clampRemaining(MINUTE_LIMIT - minuteCount - 1),
      daily: clampRemaining(limits.daily - sub.daily_messages_used - 1),
      monthly: clampRemaining(limits.monthly - sub.monthly_messages_used - 1),
    },
  };
}

export async function incrementUsage(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  messageCount: number,
): Promise<void> {
  const now = new Date();
  const rateLimit = await getOrCreateRateLimit(supabase, userId, now);
  const nextMinuteCount = Math.max(0, rateLimit.minute_count) + 1;

  const { error: rateLimitUpdateError } = await (supabase.from("rate_limits") as any)
    .update({ minute_count: nextMinuteCount })
    .eq("user_id", userId);

  if (rateLimitUpdateError) {
    throw new Error(
      `Failed to increment minute usage: ${rateLimitUpdateError.message}`,
    );
  }

  const { error: usageError } = await (supabase as any).rpc("increment_usage", {
    p_user_id: userId,
    p_messages: messageCount,
  });

  if (usageError) {
    throw new Error(`Failed to increment usage: ${usageError.message}`);
  }
}

export { MINUTE_LIMIT, TIER_LIMITS };
