import { NextResponse } from "next/server";
import {
  mapAiErrorRow,
  resolveAiErrorsSource,
  type AiErrorRowInput,
} from "@/lib/operations/ai-logs-read";
import { getAdminSession } from "@/lib/server/admin-supabase";

export const dynamic = "force-dynamic";

export async function GET() {
  const admin = await getAdminSession();
  if (!admin.ok) {
    return NextResponse.json({ error: admin.error }, { status: admin.status });
  }

  const source = resolveAiErrorsSource();
  const { data, error } = source.mode === "v2"
    ? await admin.session.supabase.rpc(source.rpc)
    : await admin.session.supabase
      .from(source.table)
      .select(source.select)
      .eq("status", "failed")
      .order("created_at", { ascending: false })
      .limit(200);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  const rows = (data ?? []) as unknown as AiErrorRowInput[];
  const errors = rows.map((row) =>
    mapAiErrorRow(row, source.mode)
  );

  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const weekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
  const typeCounts = new Map<string, number>();

  for (const row of errors) {
    typeCounts.set(row.error_type, (typeCounts.get(row.error_type) ?? 0) + 1);
  }

  return NextResponse.json({
    errors: errors.slice(0, 50),
    errorStats: Array.from(typeCounts.entries())
      .map(([type, count]) => ({ type, count }))
      .sort((a, b) => b.count - a.count),
    totals: {
      today: errors.filter((row) => new Date(row.created_at) >= today).length,
      thisWeek: errors.filter((row) => new Date(row.created_at) >= weekAgo)
        .length,
      critical: errors.filter((row) =>
        row.error_type === "API_ERROR" || row.error_type === "TIMEOUT"
      ).length,
    },
  });
}
