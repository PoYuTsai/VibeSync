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
      .from("ai_success_rate")
      .select("*")
      .order("date", { ascending: true })
      .limit(30);

    if (error) throw error;

    return jsonNoStore({
      rows: (data ?? []).map((row) => ({
        date: row.date,
        total_requests: Number(row.total_requests ?? 0),
        success_count: Number(row.success_count ?? 0),
        failed_count: Number(row.failed_count ?? 0),
        filtered_count: Number(row.filtered_count ?? 0),
        success_rate: Number(row.success_rate ?? 0),
      })),
    });
  } catch (error) {
    console.error("Failed to fetch AI health:", error);
    return jsonNoStore({ error: "Failed to load AI health" }, 500);
  }
}
