import { NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import {
  ADMIN_ACCESS_COOKIE,
  ADMIN_ACCESS_COOKIE_MAX_AGE,
  ADMIN_ACCESS_COOKIE_MAX_AGE_V2,
} from "@/lib/auth";
import { checkAdminAccess } from "@/lib/admin-check";
import { isAdminV2Enabled } from "@/lib/operations/admin-v2";
import { resolveAdminAccess } from "@/lib/operations/admin-gate";

interface SessionBody {
  accessToken?: string;
}

function jsonError(message: string, status: number) {
  return NextResponse.json({ error: message }, { status });
}

export async function POST(request: Request) {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!supabaseUrl || !supabaseKey) {
    return jsonError("Supabase is not configured", 500);
  }

  let body: SessionBody;
  try {
    body = (await request.json()) as SessionBody;
  } catch {
    return jsonError("Invalid request body", 400);
  }

  if (!body.accessToken) {
    return jsonError("Access token is required", 400);
  }

  const supabase = createClient(supabaseUrl, supabaseKey, {
    global: {
      headers: {
        Authorization: `Bearer ${body.accessToken}`,
      },
    },
  });

  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser();

  if (authError || !user || (!isAdminV2Enabled() && !user.email)) {
    return jsonError("Unauthorized", 401);
  }

  const adminAccess = await resolveAdminAccess({
    accessToken: body.accessToken,
    legacyCheck: () => checkAdminAccess(supabase, user.email ?? ""),
    touchSession: () => supabase.rpc("admin_v2_touch_session"),
    revokeSession: () => supabase.rpc("admin_v2_revoke_my_session"),
  });

  if (!adminAccess.allowed) {
    // 只回 generic 錯誤：不得帶 email、reason 細節或底層 RPC 錯誤。
    return jsonError(adminAccess.publicError, adminAccess.status);
  }

  const response = NextResponse.json({ success: true });
  response.cookies.set({
    name: ADMIN_ACCESS_COOKIE,
    value: body.accessToken,
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: isAdminV2Enabled()
      ? ADMIN_ACCESS_COOKIE_MAX_AGE_V2
      : ADMIN_ACCESS_COOKIE_MAX_AGE,
  });

  return response;
}
