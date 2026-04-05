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
      .from("ai_logs")
      .select(
        "id, created_at, error_code, error_message, user_id, model, request_type, latency_ms",
      )
      .eq("status", "failed")
      .order("created_at", { ascending: false })
      .limit(50);

    if (error) throw error;

    return jsonNoStore({
      rows: (data ?? []).map((row) => ({
        id: row.id,
        created_at: row.created_at,
        error_code: row.error_code,
        error_message: row.error_message,
        user_id: row.user_id,
        model: row.model,
        request_type: row.request_type,
        latency_ms: row.latency_ms,
      })),
    });
  } catch (error) {
    console.error("Failed to fetch AI errors:", error);
    return jsonNoStore({ error: "Failed to load AI errors" }, 500);
  }
}
