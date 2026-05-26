import { NextResponse } from "next/server";
import { getAdminSession } from "@/lib/server/admin-supabase";

export const dynamic = "force-dynamic";

export async function GET() {
  const admin = await getAdminSession();
  if (!admin.ok) {
    return NextResponse.json({ error: admin.error }, { status: admin.status });
  }

  const { data, error } = await admin.session.supabase
    .from("auth_diagnostics")
    .select(
      "id, event, status, email_redacted, platform, app_version, build_number, error_code, message, metadata, created_at"
    )
    .order("created_at", { ascending: false })
    .limit(100);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ rows: data ?? [] });
}
