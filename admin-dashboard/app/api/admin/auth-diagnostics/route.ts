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
      .from("auth_diagnostics")
      .select(
        "id, event, status, email_redacted, platform, app_version, build_number, error_code, message, metadata, created_at",
      )
      .order("created_at", { ascending: false })
      .limit(100);

    if (error) {
      throw error;
    }

    return jsonNoStore({ rows: data ?? [] });
  } catch (error) {
    console.error("Failed to fetch auth diagnostics:", error);
    return jsonNoStore({ error: "Failed to load auth diagnostics" }, 500);
  }
}
