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
      { count: totalUsers, error: usersError },
      { count: activeSubscriptions, error: subscriptionsError },
      { data: latestProfit, error: profitError },
      { data: aiRows, error: aiError },
    ] = await Promise.all([
      supabase.from("real_users").select("*", { count: "exact", head: true }),
      supabase
        .from("real_subscriptions")
        .select("*", { count: "exact", head: true })
        .eq("status", "active"),
      supabase
        .from("monthly_profit")
        .select("revenue, profit, margin_percent")
        .order("month", { ascending: false })
        .limit(1)
        .single(),
      supabase
        .from("ai_success_rate")
        .select("success_rate")
        .order("date", { ascending: false })
        .limit(7),
    ]);

    if (usersError) throw usersError;
    if (subscriptionsError) throw subscriptionsError;
    if (profitError) throw profitError;
    if (aiError) throw aiError;

    const avgSuccessRate = (aiRows ?? []).length > 0
      ? Math.round(
        ((aiRows ?? []).reduce(
          (sum, row) => sum + Number(row.success_rate ?? 0),
          0,
        ) / (aiRows ?? []).length) * 100,
      ) / 100
      : 0;

    return jsonNoStore({
      totalUsers: totalUsers ?? 0,
      activeSubscriptions: activeSubscriptions ?? 0,
      monthlyRevenue: Number(latestProfit?.revenue ?? 0),
      monthlyProfit: Number(latestProfit?.profit ?? 0),
      marginPercent: Number(latestProfit?.margin_percent ?? 0),
      aiSuccessRate: avgSuccessRate,
    });
  } catch (error) {
    console.error("Failed to fetch dashboard stats:", error);
    return jsonNoStore({ error: "Failed to load dashboard stats" }, 500);
  }
}
