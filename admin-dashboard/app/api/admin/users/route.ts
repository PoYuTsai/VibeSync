import { NextResponse } from "next/server";
import { getAdminSession } from "@/lib/server/admin-supabase";

export const dynamic = "force-dynamic";

type Tier = "free" | "starter" | "essential";

interface DbUser {
  id: string;
  email: string;
  created_at: string;
  last_login_at: string | null;
  total_analyses: number | null;
  total_conversations: number | null;
}

interface DbSubscription {
  user_id: string;
  tier: Tier | string | null;
  status: string | null;
  expires_at: string | null;
  monthly_messages_used: number | null;
  daily_messages_used: number | null;
  monthly_reset_at: string | null;
  daily_reset_at: string | null;
}

function normalizeTier(tier: string | null | undefined): Tier {
  return tier === "starter" || tier === "essential" ? tier : "free";
}

function hasFutureExpiration(subscription: DbSubscription): boolean {
  if (!subscription.expires_at) {
    return false;
  }

  const expiresAt = new Date(subscription.expires_at).getTime();
  return Number.isFinite(expiresAt) && expiresAt > Date.now();
}

function hasPaidEntitlement(subscription: DbSubscription | undefined): boolean {
  if (!subscription) {
    return false;
  }

  const tier = normalizeTier(subscription.tier);
  if (tier === "free") {
    return false;
  }

  if (subscription.status === "active") {
    return true;
  }

  return subscription.status === "cancelled" && hasFutureExpiration(subscription);
}

function effectiveTier(subscription: DbSubscription | undefined): Tier {
  if (!hasPaidEntitlement(subscription)) {
    return "free";
  }

  return normalizeTier(subscription?.tier);
}

function statusLabel(subscription: DbSubscription | undefined): string {
  if (!subscription) {
    return "missing";
  }

  if (subscription.status === "cancelled" && hasPaidEntitlement(subscription)) {
    return "cancelled_until_expiry";
  }

  return subscription.status ?? "unknown";
}

function createdAfter(user: DbUser, date: Date): boolean {
  return new Date(user.created_at) >= date;
}

export async function GET() {
  const admin = await getAdminSession();

  if (!admin.ok) {
    return NextResponse.json(
      { error: admin.error },
      { status: admin.status }
    );
  }

  const { supabase } = admin.session;

  const { data: testUsers, error: testUsersError } = await supabase
    .from("test_users")
    .select("user_id");

  if (testUsersError) {
    return NextResponse.json(
      { error: testUsersError.message },
      { status: 500 }
    );
  }

  const testUserIds = new Set(
    (testUsers ?? [])
      .map((row) => row.user_id as string | null)
      .filter((id): id is string => Boolean(id))
  );

  const { data: users, error: usersError } = await supabase
    .from("users")
    .select(
      "id, email, created_at, last_login_at, total_analyses, total_conversations"
    )
    .order("created_at", { ascending: false })
    .limit(1000);

  if (usersError) {
    return NextResponse.json(
      { error: usersError.message },
      { status: 500 }
    );
  }

  const realUsers = ((users ?? []) as DbUser[]).filter(
    (user) => !testUserIds.has(user.id)
  );
  const userIds = realUsers.map((user) => user.id);

  let subscriptions: DbSubscription[] = [];

  if (userIds.length > 0) {
    const { data: subscriptionRows, error: subscriptionsError } = await supabase
      .from("subscriptions")
      .select(
        "user_id, tier, status, expires_at, monthly_messages_used, daily_messages_used, monthly_reset_at, daily_reset_at"
      )
      .in("user_id", userIds);

    if (subscriptionsError) {
      return NextResponse.json(
        { error: subscriptionsError.message },
        { status: 500 }
      );
    }

    subscriptions = (subscriptionRows ?? []) as DbSubscription[];
  }

  const subscriptionByUserId = new Map(
    subscriptions.map((subscription) => [subscription.user_id, subscription])
  );

  const enrichedUsers = realUsers.slice(0, 50).map((user) => {
    const subscription = subscriptionByUserId.get(user.id);
    const tier = effectiveTier(subscription);

    return {
      ...user,
      subscription_tier: tier,
      raw_subscription_tier: normalizeTier(subscription?.tier),
      subscription_status: statusLabel(subscription),
      expires_at: subscription?.expires_at ?? null,
      monthly_messages_used: subscription?.monthly_messages_used ?? 0,
      daily_messages_used: subscription?.daily_messages_used ?? 0,
      monthly_reset_at: subscription?.monthly_reset_at ?? null,
      daily_reset_at: subscription?.daily_reset_at ?? null,
    };
  });

  const now = new Date();
  const thisMonth = new Date(now.getFullYear(), now.getMonth(), 1);
  const thisWeek = new Date(now);
  thisWeek.setDate(thisWeek.getDate() - 7);

  const tierCounts = realUsers.reduce<Record<Tier, number>>(
    (counts, user) => {
      const tier = effectiveTier(subscriptionByUserId.get(user.id));
      counts[tier] += 1;
      return counts;
    },
    { free: 0, starter: 0, essential: 0 }
  );

  const paidUsers = tierCounts.starter + tierCounts.essential;

  return NextResponse.json({
    users: enrichedUsers,
    stats: {
      total: realUsers.length,
      thisMonth: realUsers.filter((user) => createdAfter(user, thisMonth))
        .length,
      thisWeek: realUsers.filter((user) => createdAfter(user, thisWeek))
        .length,
      paidUsers,
      conversionRate:
        realUsers.length > 0
          ? Math.round((paidUsers / realUsers.length) * 100)
          : 0,
      tiers: tierCounts,
    },
  });
}
