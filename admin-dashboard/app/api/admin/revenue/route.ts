import { NextResponse } from "next/server";
import { getAdminSession } from "@/lib/server/admin-supabase";

export const dynamic = "force-dynamic";

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

  const { data, error } = await admin.session.supabase
    .from("revenue_events")
    .select("event_type, price_usd, event_timestamp")
    .order("event_timestamp", { ascending: true })
    .limit(5000);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  const byMonth = new Map<
    string,
    {
      month: string;
      revenue: number;
      new_subscriptions: number;
      renewals: number;
      cancellations: number;
    }
  >();

  for (const event of (data ?? []) as RevenueEventRow[]) {
    const key = monthKey(event.event_timestamp);
    const row = byMonth.get(key) ?? {
      month: key,
      revenue: 0,
      new_subscriptions: 0,
      renewals: 0,
      cancellations: 0,
    };

    if (event.event_type === "INITIAL_PURCHASE") {
      row.new_subscriptions += 1;
      row.revenue += Number(event.price_usd ?? 0);
    } else if (event.event_type === "RENEWAL") {
      row.renewals += 1;
      row.revenue += Number(event.price_usd ?? 0);
    } else if (event.event_type === "CANCELLATION") {
      row.cancellations += 1;
    }

    byMonth.set(key, row);
  }

  const revenueData = Array.from(byMonth.values())
    .slice(-12)
    .map((row) => ({
      ...row,
      month: monthLabel(row.month),
      revenue: Math.round(row.revenue * 100) / 100,
    }));

  const thisMonth = revenueData.at(-1) ?? null;
  const lastMonth = revenueData.length > 1 ? revenueData.at(-2) : null;
  const growth =
    thisMonth && lastMonth
      ? lastMonth.revenue > 0
        ? Math.round(((thisMonth.revenue - lastMonth.revenue) / lastMonth.revenue) * 100)
        : thisMonth.revenue > 0
          ? 100
          : 0
      : 0;

  return NextResponse.json({
    revenueData,
    totals: {
      thisMonth: thisMonth?.revenue ?? 0,
      lastMonth: lastMonth?.revenue ?? 0,
      growth,
      totalSubscriptions:
        (thisMonth?.new_subscriptions ?? 0) + (thisMonth?.renewals ?? 0),
    },
    source: "revenue_events",
  });
}
