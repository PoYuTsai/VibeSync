import { NextResponse } from "next/server";
import { getAdminSession } from "@/lib/server/admin-supabase";

export const dynamic = "force-dynamic";

type Tier = "free" | "starter" | "essential";

interface DbUser {
  id: string;
}

interface DbSubscription {
  user_id: string;
  tier: Tier | string | null;
  status: string | null;
  expires_at: string | null;
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
    .select("id")
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
      .select("user_id, tier, status, expires_at")
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

  const tierCounts = realUsers.reduce<Record<Tier, number>>(
    (counts, user) => {
      const tier = effectiveTier(subscriptionByUserId.get(user.id));
      counts[tier] += 1;
      return counts;
    },
    { free: 0, starter: 0, essential: 0 }
  );

  const activePaid = tierCounts.starter + tierCounts.essential;
  const cancelled = subscriptions.filter(
    (subscription) => subscription.status === "cancelled"
  ).length;
  const cancelledButUsable = subscriptions.filter(
    (subscription) =>
      subscription.status === "cancelled" && hasPaidEntitlement(subscription)
  ).length;
  const expired = subscriptions.filter(
    (subscription) => subscription.status === "expired"
  ).length;

  const totalUsers = realUsers.length;

  return NextResponse.json({
    totals: {
      totalUsers,
      activePaid,
      cancelled,
      cancelledButUsable,
      expired,
      conversionRate:
        totalUsers > 0 ? Math.round((activePaid / totalUsers) * 100) : 0,
    },
    tierStats: Object.entries(tierCounts).map(([tier, count]) => ({
      tier,
      count,
      percentage: totalUsers > 0 ? Math.round((count / totalUsers) * 100) : 0,
    })),
  });
}
