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
    const [
      { data: signals, error: signalsError },
      { data: jobs, error: jobsError },
      { data: alerts, error: alertsError },
    ] = await Promise.all([
      supabase.from("security_signals").select("*"),
      supabase.from("security_automation_status").select("*"),
      supabase
        .from("security_alert_events")
        .select(
          "dedupe_key, signal_key, severity, channel, title, last_detected_at, last_notified_at, notification_count, last_status, last_response_code, last_error_message",
        )
        .order("last_detected_at", { ascending: false })
        .limit(20),
    ]);

    if (signalsError) throw signalsError;
    if (jobsError) throw jobsError;
    if (alertsError) throw alertsError;

    return jsonNoStore({
      signals: signals ?? [],
      jobs: jobs ?? [],
      alerts: alerts ?? [],
    });
  } catch (error) {
    console.error("Failed to fetch security dashboard data:", error);
    return jsonNoStore({ error: "Failed to load security dashboard data" }, 500);
  }
}
