// supabase/functions/analyze-chat/rate_limiter.ts
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface TierLimits {
  monthly: number;
  daily: number;
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

function getSecondsUntilMidnight(): number {
  const now = new Date();
  const midnight = new Date(now);
  midnight.setHours(24, 0, 0, 0);
  return Math.floor((midnight.getTime() - now.getTime()) / 1000);
}

export async function checkRateLimit(
  supabase: ReturnType<typeof createClient>,
  userId: string
): Promise<RateLimitResult> {
  const now = new Date();

  // 1. 取得訂閱資訊
  const { data: sub } = await supabase
    .from("subscriptions")
    .select("tier, monthly_messages_used, daily_messages_used, daily_reset_at")
    .eq("user_id", userId)
    .single();

  if (!sub) {
    throw new Error("Subscription not found");
  }

  const limits = TIER_LIMITS[sub.tier] || TIER_LIMITS.free;

  // 2. 檢查每日重置
  const dailyResetAt = new Date(sub.daily_reset_at);
  const isNewDay = now.toDateString() !== dailyResetAt.toDateString();

  if (isNewDay) {
    await supabase
      .from("subscriptions")
      .update({ daily_messages_used: 0, daily_reset_at: now.toISOString() })
      .eq("user_id", userId);
    sub.daily_messages_used = 0;
  }

  // 3. 取得每分鐘限制狀態
  let { data: rateLimit } = await supabase
    .from("rate_limits")
    .select("minute_count, minute_window_start")
    .eq("user_id", userId)
    .single();

  // 初始化 rate limit 記錄
  if (!rateLimit) {
    await supabase.from("rate_limits").insert({
      user_id: userId,
      minute_count: 0,
      minute_window_start: now.toISOString(),
    });
    rateLimit = { minute_count: 0, minute_window_start: now.toISOString() };
  }

  // 重置每分鐘窗口
  const windowStart = new Date(rateLimit.minute_window_start);
  const secondsSinceWindow = (now.getTime() - windowStart.getTime()) / 1000;
  let minuteCount = rateLimit.minute_count;

  if (secondsSinceWindow >= 60) {
    await supabase
      .from("rate_limits")
      .update({ minute_count: 0, minute_window_start: now.toISOString() })
      .eq("user_id", userId);
    minuteCount = 0;
  }

  // 4. 檢查限制
  if (minuteCount >= MINUTE_LIMIT) {
    return {
      allowed: false,
      reason: "minute_limit",
      retryAfter: 60 - Math.floor(secondsSinceWindow),
      remaining: {
        minute: 0,
        daily: limits.daily - sub.daily_messages_used,
        monthly: limits.monthly - sub.monthly_messages_used,
      },
    };
  }

  if (sub.daily_messages_used >= limits.daily) {
    return {
      allowed: false,
      reason: "daily_limit",
      retryAfter: getSecondsUntilMidnight(),
      remaining: {
        minute: MINUTE_LIMIT - minuteCount,
        daily: 0,
        monthly: limits.monthly - sub.monthly_messages_used,
      },
    };
  }

  if (sub.monthly_messages_used >= limits.monthly) {
    return {
      allowed: false,
      reason: "monthly_limit",
      remaining: {
        minute: MINUTE_LIMIT - minuteCount,
        daily: 0,
        monthly: 0,
      },
    };
  }

  return {
    allowed: true,
    remaining: {
      minute: MINUTE_LIMIT - minuteCount - 1,
      daily: limits.daily - sub.daily_messages_used - 1,
      monthly: limits.monthly - sub.monthly_messages_used - 1,
    },
  };
}

export async function incrementUsage(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  messageCount: number
): Promise<void> {
  // 更新每分鐘計數
  const { data: rateLimit } = await supabase
    .from("rate_limits")
    .select("minute_count")
    .eq("user_id", userId)
    .single();

  if (rateLimit) {
    await supabase
      .from("rate_limits")
      .update({ minute_count: rateLimit.minute_count + 1 })
      .eq("user_id", userId);
  }

  // 更新每日/每月計數
  const { data: sub } = await supabase
    .from("subscriptions")
    .select("daily_messages_used, monthly_messages_used")
    .eq("user_id", userId)
    .single();

  if (sub) {
    await supabase
      .from("subscriptions")
      .update({
        daily_messages_used: sub.daily_messages_used + messageCount,
        monthly_messages_used: sub.monthly_messages_used + messageCount,
      })
      .eq("user_id", userId);
  }
}

export { TIER_LIMITS, MINUTE_LIMIT };
