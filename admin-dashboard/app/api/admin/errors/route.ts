import { NextResponse } from "next/server";
import { getAdminSession } from "@/lib/server/admin-supabase";

export const dynamic = "force-dynamic";

interface AiErrorRow {
  id: string;
  created_at: string;
  error_code: string | null;
  error_message: string | null;
  request_type: string | null;
  user_id: string | null;
}

function errorType(row: AiErrorRow): string {
  return row.error_code?.trim() || row.request_type?.trim() || "UNKNOWN";
}

export async function GET() {
  const admin = await getAdminSession();
  if (!admin.ok) {
    return NextResponse.json({ error: admin.error }, { status: admin.status });
  }

  const { data, error } = await admin.session.supabase
    .from("ai_logs")
    .select("id, created_at, error_code, error_message, request_type, user_id")
    .eq("status", "failed")
    .order("created_at", { ascending: false })
    .limit(200);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  const errors = ((data ?? []) as AiErrorRow[]).map((row) => ({
    id: row.id,
    created_at: row.created_at,
    error_type: errorType(row),
    error_message: row.error_message ?? "",
    user_id: row.user_id ?? "",
    request_id: row.id,
  }));

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
