import { NextResponse } from "next/server";
import { getAdminSession } from "@/lib/server/admin-supabase";

export const dynamic = "force-dynamic";

interface AiLogRow {
  id: string;
  created_at: string;
  cost_usd: number | string | null;
  user_id: string | null;
}

interface RevenueEventRow {
  id: string;
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

  const pageSize = 1000;
  const now = new Date();
  const reportStartAt = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 11, 1),
  ).toISOString();
  const fetchAiLogs = async () => {
    const rows: AiLogRow[] = [];
    let lastCreatedAt: string | null = null;
    let lastId: string | null = null;
    for (;;) {
      let query = admin.session.supabase
        .from("ai_logs")
        .select("id, created_at, cost_usd, user_id")
        .gte("created_at", reportStartAt)
        .order("created_at", { ascending: true })
        .order("id", { ascending: true })
        .limit(pageSize);
      if (lastCreatedAt !== null && lastId !== null) {
        query = query.or(
          `created_at.gt.${lastCreatedAt},and(created_at.eq.${lastCreatedAt},id.gt.${lastId})`,
        );
      }
      const result = await query;
      if (result.error) return { data: null, error: result.error };
      const page = (result.data ?? []) as AiLogRow[];
      rows.push(...page);
      if (page.length < pageSize) return { data: rows, error: null };
      const last = page[page.length - 1];
      lastCreatedAt = last.created_at;
      lastId = last.id;
    }
  };
  const fetchRevenueEvents = async () => {
    const rows: RevenueEventRow[] = [];
    let lastEventAt: string | null = null;
    let lastId: string | null = null;
    for (;;) {
      let query = admin.session.supabase
        .from("revenue_events")
        .select("id, event_type, price_usd, event_timestamp")
        .gte("event_timestamp", reportStartAt)
        .order("event_timestamp", { ascending: true })
        .order("id", { ascending: true })
        .limit(pageSize);
      if (lastEventAt !== null && lastId !== null) {
        query = query.or(
          `event_timestamp.gt.${lastEventAt},and(event_timestamp.eq.${lastEventAt},id.gt.${lastId})`,
        );
      }
      const result = await query;
      if (result.error) return { data: null, error: result.error };
      const page = (result.data ?? []) as RevenueEventRow[];
      rows.push(...page);
      if (page.length < pageSize) return { data: rows, error: null };
      const last = page[page.length - 1];
      lastEventAt = last.event_timestamp;
      lastId = last.id;
    }
  };

  const [aiLogResult, revenueResult] = await Promise.all([
    fetchAiLogs(),
    fetchRevenueEvents(),
  ]);

  const firstError = aiLogResult.error ?? revenueResult.error;
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

  for (const item of (aiLogResult.data ?? []) as AiLogRow[]) {
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
    source: "ai_logs + revenue_events",
  });
}
