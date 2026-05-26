import { NextResponse } from "next/server";
import { getAdminSession } from "@/lib/server/admin-supabase";

export const dynamic = "force-dynamic";

interface AiLogRow {
  created_at: string;
  status: string;
}

function dateKey(value: string): string {
  return new Date(value).toISOString().slice(0, 10);
}

export async function GET() {
  const admin = await getAdminSession();
  if (!admin.ok) {
    return NextResponse.json({ error: admin.error }, { status: admin.status });
  }

  const since = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
  const { data, error } = await admin.session.supabase
    .from("ai_logs")
    .select("created_at, status")
    .gte("created_at", since)
    .order("created_at", { ascending: true })
    .limit(5000);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  const byDate = new Map<
    string,
    {
      date: string;
      total_requests: number;
      success_count: number;
      failed_count: number;
      filtered_count: number;
      success_rate: number;
    }
  >();

  for (const log of (data ?? []) as AiLogRow[]) {
    const key = dateKey(log.created_at);
    const current = byDate.get(key) ?? {
      date: key,
      total_requests: 0,
      success_count: 0,
      failed_count: 0,
      filtered_count: 0,
      success_rate: 0,
    };
    current.total_requests += 1;
    if (log.status === "success") current.success_count += 1;
    if (log.status === "failed") current.failed_count += 1;
    if (log.status === "filtered") current.filtered_count += 1;
    byDate.set(key, current);
  }

  const rows = Array.from(byDate.values()).map((row) => ({
    ...row,
    success_rate:
      row.total_requests > 0
        ? Math.round((row.success_count / row.total_requests) * 10000) / 100
        : 0,
  }));

  const totals = rows.reduce(
    (acc, row) => ({
      totalRequests: acc.totalRequests + row.total_requests,
      totalFailed: acc.totalFailed + row.failed_count,
      totalFiltered: acc.totalFiltered + row.filtered_count,
      totalSuccess: acc.totalSuccess + row.success_count,
    }),
    { totalRequests: 0, totalFailed: 0, totalFiltered: 0, totalSuccess: 0 }
  );

  return NextResponse.json({
    healthData: rows,
    summary: {
      avgSuccessRate:
        totals.totalRequests > 0
          ? Math.round((totals.totalSuccess / totals.totalRequests) * 10000) /
            100
          : null,
      totalRequests: totals.totalRequests,
      totalFailed: totals.totalFailed,
      totalFiltered: totals.totalFiltered,
    },
  });
}
