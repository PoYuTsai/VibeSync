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
    const { data, error } = await supabase
      .from("monthly_revenue")
      .select("*")
      .order("month", { ascending: true })
      .limit(12);

    if (error) {
      throw error;
    }

    const rows = (data ?? []).map((row) => ({
      month: new Date(row.month).toLocaleDateString("zh-TW", {
        year: "2-digit",
        month: "short",
      }),
      revenue: Number(row.revenue),
      new_subscriptions: Number(row.new_subscriptions),
      renewals: Number(row.renewals),
      cancellations: Number(row.cancellations),
    }));

    const thisMonth = rows.at(-1) ?? null;
    const lastMonth = rows.length > 1 ? rows.at(-2) ?? null : null;
    const growth = thisMonth && lastMonth
      ? lastMonth.revenue > 0
        ? Math.round(((thisMonth.revenue - lastMonth.revenue) / lastMonth.revenue) * 100)
        : 100
      : 0;

    return jsonNoStore({
      rows,
      totals: {
        thisMonth: thisMonth?.revenue ?? 0,
        lastMonth: lastMonth?.revenue ?? 0,
        growth,
        totalSubscriptions: (thisMonth?.new_subscriptions ?? 0) +
          (thisMonth?.renewals ?? 0),
      },
    });
  } catch (error) {
    console.error("Failed to fetch revenue:", error);
    return jsonNoStore({ error: "Failed to load revenue" }, 500);
  }
}
