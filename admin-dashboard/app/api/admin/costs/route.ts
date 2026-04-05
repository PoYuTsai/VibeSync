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
      .from("monthly_profit")
      .select("*")
      .order("month", { ascending: false })
      .limit(12);

    if (error) {
      throw error;
    }

    const rows = (data ?? []).reverse().map((row) => ({
      month: new Date(row.month).toLocaleDateString("zh-TW", {
        year: "2-digit",
        month: "short",
      }),
      revenue: Number(row.revenue),
      cost: Number(row.cost),
      profit: Number(row.profit),
      margin_percent: Number(row.margin_percent),
      cost_per_user: Number(row.cost_per_user),
    }));

    const totalCost = rows.reduce((sum, row) => sum + row.cost, 0);
    const avgCostPerUser = rows.length > 0
      ? rows.reduce((sum, row) => sum + row.cost_per_user, 0) / rows.length
      : 0;
    const avgMargin = rows.length > 0
      ? rows.reduce((sum, row) => sum + row.margin_percent, 0) / rows.length
      : 0;

    return jsonNoStore({
      rows,
      summary: {
        totalCost: Math.round(totalCost * 100) / 100,
        avgCostPerUser: Math.round(avgCostPerUser * 10000) / 10000,
        avgMargin: Math.round(avgMargin * 100) / 100,
      },
    });
  } catch (error) {
    console.error("Failed to fetch costs:", error);
    return jsonNoStore({ error: "Failed to load costs" }, 500);
  }
}
