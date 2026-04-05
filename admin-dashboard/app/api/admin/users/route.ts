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
    const { data, count, error } = await supabase
      .from("real_users")
      .select("id, email, created_at", { count: "exact" })
      .order("created_at", { ascending: false })
      .limit(50);

    if (error) {
      throw error;
    }

    const users = data ?? [];
    const userIds = users.map((user) => user.id);
    const { data: subscriptions, error: subscriptionsError } = userIds.length > 0
      ? await supabase
        .from("subscriptions")
        .select("user_id, tier")
        .in("user_id", userIds)
        .eq("status", "active")
      : { data: [], error: null };

    if (subscriptionsError) {
      throw subscriptionsError;
    }

    const subscriptionMap = new Map(
      (subscriptions ?? []).map((subscription) => [
        subscription.user_id,
        subscription.tier,
      ]),
    );

    const now = new Date();
    const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
    const weekStart = new Date(now);
    weekStart.setDate(now.getDate() - 7);

    const rows = users.map((user) => ({
      ...user,
      subscription_tier: subscriptionMap.get(user.id) ?? "free",
    }));

    const thisMonth = rows.filter((row) =>
      new Date(row.created_at) >= monthStart
    ).length;
    const thisWeek = rows.filter((row) =>
      new Date(row.created_at) >= weekStart
    ).length;

    return jsonNoStore({
      rows,
      stats: {
        total: count ?? rows.length,
        thisMonth,
        thisWeek,
      },
    });
  } catch (error) {
    console.error("Failed to fetch admin users:", error);
    return jsonNoStore({ error: "Failed to load users" }, 500);
  }
}
