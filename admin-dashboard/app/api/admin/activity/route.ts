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
      .from("user_activity")
      .select("*")
      .order("date", { ascending: true })
      .limit(30);

    if (error) throw error;

    return jsonNoStore({
      rows: (data ?? []).map((row) => ({
        date: row.date,
        dau: Number(row.dau ?? 0),
      })),
    });
  } catch (error) {
    console.error("Failed to fetch activity:", error);
    return jsonNoStore({ error: "Failed to load activity" }, 500);
  }
}
