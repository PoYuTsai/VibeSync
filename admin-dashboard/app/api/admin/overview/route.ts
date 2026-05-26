import { NextResponse } from "next/server";
import { getAdminSession } from "@/lib/server/admin-supabase";

export const dynamic = "force-dynamic";

type Tier = "free" | "starter" | "essential";

interface UserRow {
  id: string;
}

interface TestUserRow {
  user_id: string | null;
}

interface SubscriptionRow {
  user_id: string;
  tier: string | null;
  status: string | null;
  expires_at: string | null;
}

interface RevenueEventRow {
  event_type: string;
  price_usd: number | string | null;
}

interface AiLogRow {
  status: string;
}

function normalizeTier(tier: string | null | undefined): Tier {
  return tier === "starter" || tier === "essential" ? tier : "free";
}

function hasFutureExpiration(subscription: SubscriptionRow): boolean {
  if (!subscription.expires_at) return false;
  const expiresAt = new Date(subscription.expires_at).getTime();
  return Number.isFinite(expiresAt) && expiresAt > Date.now();
}

function hasPaidEntitlement(subscription: SubscriptionRow): boolean {
  const tier = normalizeTier(subscription.tier);
  if (tier === "free") return false;
  if (subscription.status === "active") return true;
  return subscription.status === "cancelled" && hasFutureExpiration(subscription);
}

function monthStartIso() {
  const now = new Date();
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1))
    .toISOString();
}

export async function GET() {
  const admin = await getAdminSession();
  if (!admin.ok) {
    return NextResponse.json({ error: admin.error }, { status: admin.status });
  }

  const { supabase } = admin.session;

  const [
    testUsersResult,
    usersResult,
    subscriptionsResult,
    revenueResult,
    aiLogsResult,
  ] = await Promise.all([
    supabase.from("test_users").select("user_id"),
    supabase.from("users").select("id").limit(1000),
    supabase.from("subscriptions").select("user_id, tier, status, expires_at"),
    supabase
      .from("revenue_events")
      .select("event_type, price_usd")
      .gte("event_timestamp", monthStartIso()),
    supabase
      .from("ai_logs")
      .select("status")
      .gte(
        "created_at",
        new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString()
      ),
  ]);

  const firstError =
    testUsersResult.error ??
    usersResult.error ??
    subscriptionsResult.error ??
    revenueResult.error ??
    aiLogsResult.error;

  if (firstError) {
    return NextResponse.json({ error: firstError.message }, { status: 500 });
  }

  const testUserIds = new Set(
    ((testUsersResult.data ?? []) as TestUserRow[])
      .map((row) => row.user_id)
      .filter((id): id is string => Boolean(id))
  );
  const realUserIds = new Set(
    ((usersResult.data ?? []) as UserRow[])
      .filter((user) => !testUserIds.has(user.id))
      .map((user) => user.id)
  );

  const activeSubscriptions = ((subscriptionsResult.data ?? []) as SubscriptionRow[])
    .filter((subscription) => realUserIds.has(subscription.user_id))
    .filter(hasPaidEntitlement).length;

  const monthlyRevenue = ((revenueResult.data ?? []) as RevenueEventRow[])
    .filter((event) =>
      event.event_type === "INITIAL_PURCHASE" || event.event_type === "RENEWAL"
    )
    .reduce((sum, event) => sum + Number(event.price_usd ?? 0), 0);

  const aiLogs = (aiLogsResult.data ?? []) as AiLogRow[];
  const aiSuccessRate = aiLogs.length > 0
    ? Math.round(
        (aiLogs.filter((log) => log.status === "success").length /
          aiLogs.length) *
          10000
      ) / 100
    : null;

  return NextResponse.json({
    stats: {
      totalUsers: realUserIds.size,
      activeSubscriptions,
      monthlyRevenue,
      aiSuccessRate,
    },
    sources: {
      totalUsers: "users - test_users",
      activeSubscriptions: "subscriptions entitlement status",
      monthlyRevenue: "revenue_events",
      aiSuccessRate: "ai_logs last 7 days",
    },
  });
}
