// SubscriptionAccess：訂閱列讀取、缺列 self-heal、日/月 UTC reset。
//
// Reset 用 CAS 條件化（WHERE reset_at = 舊值，null 用 IS NULL）：只有第一個
// 跨窗口的請求能歸零；後到者 CAS 匹配 0 rows＝別人已 reset，放棄覆寫，才不
// 會抹掉並發請求剛扣的額度。呼叫端拿到的 sub 是 reset 後的本地視圖。

import { sameUtcDay, sameUtcMonth } from "../_shared/quota.ts";
import { resolveSourceAwareSubscriptionRow } from "../_shared/subscription_store_state.ts";
import { logError, logInfo, logWarn, summarizeUser } from "./logger.ts";

export interface SubscriptionRow {
  tier: string;
  status?: string | null;
  expires_at?: string | null;
  active_product_id?: string | null;
  store?: string | null;
  revenuecat_environment?: string | null;
  monthly_messages_used: number;
  daily_messages_used: number;
  daily_reset_at: string | null;
  monthly_reset_at: string | null;
}

export type SubscriptionAccessResult =
  | { ok: true; sub: SubscriptionRow }
  | { ok: false; reason: "self_heal_failed" };

const SUBSCRIPTION_COLUMNS =
  "tier, status, expires_at, active_product_id, store, revenuecat_environment, " +
  "monthly_messages_used, daily_messages_used, daily_reset_at, monthly_reset_at";

export async function loadSubscriptionAccess({
  supabase,
  userId,
}: {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  userId: string;
}): Promise<SubscriptionAccessResult> {
  let { data: sub, error: subError } = await supabase
    .from("subscriptions")
    .select(SUBSCRIPTION_COLUMNS)
    .eq("user_id", userId)
    .maybeSingle();

  logInfo("subscription_lookup", {
    user: summarizeUser(userId),
    hasSubscription: !!sub,
    tier: sub?.tier ?? null,
    subscriptionErrorCode: subError?.code ?? null,
  });

  if (!sub) {
    logWarn("subscription_missing_self_heal", {
      user: summarizeUser(userId),
      error: subError?.message ?? null,
    });

    const nowIso = new Date().toISOString();
    const { data: insertedSub, error: insertSubError } = await supabase
      .from("subscriptions")
      .insert({
        user_id: userId,
        tier: "free",
        monthly_messages_used: 0,
        daily_messages_used: 0,
        daily_reset_at: nowIso,
        monthly_reset_at: nowIso,
        started_at: nowIso,
      })
      .select(SUBSCRIPTION_COLUMNS)
      .single();

    if (insertSubError || !insertedSub) {
      logError("subscription_self_heal_failed", {
        user: summarizeUser(userId),
        error: insertSubError?.message ?? null,
      });
      return { ok: false, reason: "self_heal_failed" };
    }

    sub = insertedSub;
  }

  // Read store rows again at this request's clock. An event may have expired
  // since the last write, and an empty/error source read must conservatively
  // retain the legacy row rather than inventing a downgrade.
  const sourceAware = await resolveSourceAwareSubscriptionRow(
    supabase,
    userId,
    sub as Record<string, unknown>,
    new Date(),
  );
  sub = sourceAware.row as unknown as SubscriptionRow;

  const now = new Date();
  // 安全處理 null 值
  const dailyResetAt = sub.daily_reset_at
    ? new Date(sub.daily_reset_at)
    : new Date(0);
  if (!sameUtcDay(now, dailyResetAt)) {
    let dailyResetQuery = supabase
      .from("subscriptions")
      .update({ daily_messages_used: 0, daily_reset_at: now.toISOString() })
      .eq("user_id", userId);
    dailyResetQuery = sub.daily_reset_at === null
      ? dailyResetQuery.is("daily_reset_at", null)
      : dailyResetQuery.eq("daily_reset_at", sub.daily_reset_at);
    await dailyResetQuery;
    sub.daily_messages_used = 0;
    logInfo("daily_quota_reset", { user: summarizeUser(userId) });
  }

  const monthlyResetAt = sub.monthly_reset_at
    ? new Date(sub.monthly_reset_at)
    : new Date(0);
  if (!sameUtcMonth(now, monthlyResetAt)) {
    let monthlyResetQuery = supabase
      .from("subscriptions")
      .update({
        monthly_messages_used: 0,
        monthly_reset_at: now.toISOString(),
      })
      .eq("user_id", userId);
    monthlyResetQuery = sub.monthly_reset_at === null
      ? monthlyResetQuery.is("monthly_reset_at", null)
      : monthlyResetQuery.eq("monthly_reset_at", sub.monthly_reset_at);
    await monthlyResetQuery;
    sub.monthly_messages_used = 0;
    logInfo("monthly_quota_reset", { user: summarizeUser(userId) });
  }

  return { ok: true, sub: sub as SubscriptionRow };
}
