import type { NextRequest } from "next/server";

import {
  createServiceRoleSupabase,
  jsonNoStore,
  requireAdminRequest,
} from "@/lib/admin-server";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  const auth = await requireAdminRequest(request);
  if (!auth.ok) {
    return auth.response;
  }

  try {
    const supabase = createServiceRoleSupabase();
    const [
      { data: subscriptions, error: subscriptionsError },
      { count: totalUsers, error: usersError },
    ] = await Promise.all([
      supabase.from("real_subscriptions").select("tier, status"),
      supabase.from("real_users").select("*", { count: "exact", head: true }),
    ]);

    if (subscriptionsError) {
      throw subscriptionsError;
    }
    if (usersError) {
      throw usersError;
    }

    const activeSubscriptions = (subscriptions ?? []).filter((subscription) =>
      subscription.status === "active"
    );
    const churnedSubscriptions = (subscriptions ?? []).filter((subscription) =>
      subscription.status === "cancelled"
    );

    const tierCounts: Record<string, number> = {
      free: Math.max((totalUsers ?? 0) - activeSubscriptions.length, 0),
      starter: 0,
      essential: 0,
    };

    for (const subscription of activeSubscriptions) {
      if (subscription.tier in tierCounts) {
        tierCounts[subscription.tier] += 1;
      }
    }

    const total = Object.values(tierCounts).reduce(
      (sum, value) => sum + value,
      0,
    );

    const tierStats = Object.entries(tierCounts).map(([tier, count]) => ({
      tier: tier.charAt(0).toUpperCase() + tier.slice(1),
      count,
      percentage: total > 0 ? Math.round((count / total) * 100) : 0,
    }));

    return jsonNoStore({
      tierStats,
      totals: {
        active: activeSubscriptions.length,
        churned: churnedSubscriptions.length,
        conversionRate: totalUsers && totalUsers > 0
          ? Math.round((activeSubscriptions.length / totalUsers) * 100)
          : 0,
      },
    });
  } catch (error) {
    console.error("Failed to fetch subscriptions:", error);
    return jsonNoStore({ error: "Failed to load subscriptions" }, 500);
  }
}
