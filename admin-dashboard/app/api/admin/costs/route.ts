import { NextResponse } from "next/server";
import { getAdminSession } from "@/lib/server/admin-supabase";

export const dynamic = "force-dynamic";

interface TokenUsageRow {
  created_at: string;
  cost_usd: number | string | null;
  user_id: string | null;
}

interface RevenueEventRow {
  event_type: string;
  price_usd: number | string | null;
  event_timestamp: string;
}

function monthKey(value: string): string {
  return new Date(value).toISOString().slice(0, 7);
}

function monthLabel(key: string): string {
  return new Date(`${key}-01T00:00:00.000Z`).toLocaleDateString("zh-TW", {
    year: "2-digit",
    month: "short",
  });
}

export async function GET() {
  const admin = await getAdminSession();
  if (!admin.ok) {
    return NextResponse.json({ error: admin.error }, { status: admin.status });
  }

  const [tokenResult, revenueResult] = await Promise.all([
    admin.session.supabase
      .from("token_usage")
      .select("created_at, cost_usd, user_id")
      .order("created_at", { ascending: true })
      .limit(5000),
    admin.session.supabase
      .from("revenue_events")
      .select("event_type, price_usd, event_timestamp")
      .order("event_timestamp", { ascending: true })
      .limit(5000),
  ]);

  const firstError = tokenResult.error ?? revenueResult.error;
  if (firstError) {
    return NextResponse.json({ error: firstError.message }, { status: 500 });
  }

  const byMonth = new Map<
    string,
    {
      month: string;
      revenue: number;
      cost: number;
      payingUsers: Set<string>;
    }
  >();

  for (const item of (tokenResult.data ?? []) as TokenUsageRow[]) {
    const key = monthKey(item.created_at);
    const row = byMonth.get(key) ?? {
      month: key,
      revenue: 0,
      cost: 0,
      payingUsers: new Set<string>(),
    };
    row.cost += Number(item.cost_usd ?? 0);
    if (item.user_id) row.payingUsers.add(item.user_id);
    byMonth.set(key, row);
  }

  for (const item of (revenueResult.data ?? []) as RevenueEventRow[]) {
    if (item.event_type !== "INITIAL_PURCHASE" && item.event_type !== "RENEWAL") {
      continue;
    }
    const key = monthKey(item.event_timestamp);
    const row = byMonth.get(key) ?? {
      month: key,
      revenue: 0,
      cost: 0,
      payingUsers: new Set<string>(),
    };
    row.revenue += Number(item.price_usd ?? 0);
    byMonth.set(key, row);
  }

  const profitData = Array.from(byMonth.values())
    .sort((a, b) => a.month.localeCompare(b.month))
    .slice(-12)
    .map((row) => {
      const profit = row.revenue - row.cost;
      return {
        month: monthLabel(row.month),
        revenue: Math.round(row.revenue * 100) / 100,
        cost: Math.round(row.cost * 1000000) / 1000000,
        profit: Math.round(profit * 100) / 100,
        margin_percent:
          row.revenue > 0 ? Math.round((profit / row.revenue) * 10000) / 100 : 0,
        cost_per_user:
          row.payingUsers.size > 0
            ? Math.round((row.cost / row.payingUsers.size) * 10000) / 10000
            : 0,
      };
    });

  const totalCost = profitData.reduce((sum, row) => sum + row.cost, 0);

  return NextResponse.json({
    profitData,
    summary: {
      totalCost: Math.round(totalCost * 100) / 100,
      avgCostPerUser:
        profitData.length > 0
          ? Math.round(
              (profitData.reduce((sum, row) => sum + row.cost_per_user, 0) /
                profitData.length) *
                10000
            ) / 10000
          : 0,
      avgMargin:
        profitData.length > 0
          ? Math.round(
              (profitData.reduce((sum, row) => sum + row.margin_percent, 0) /
                profitData.length) *
                100
            ) / 100
          : 0,
    },
    source: "token_usage + revenue_events",
  });
}
