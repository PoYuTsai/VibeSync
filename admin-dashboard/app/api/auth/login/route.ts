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

interface LoginBody {
  email?: string;
  password?: string;
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

  let body: LoginBody;
  try {
    body = (await request.json()) as LoginBody;
  } catch {
    return jsonError("Invalid request body", 400);
  }

  const email = body.email?.trim().toLowerCase();
  const password = body.password;

  if (!email || !password) {
    return jsonError("Email and password are required", 400);
  }

  const supabase = createClient(supabaseUrl, supabaseKey);
  const { data, error } = await supabase.auth.signInWithPassword({
    email,
    password,
  });

  if (error || !data.session || !data.user) {
    // generic：不轉發 Supabase 錯誤細節給瀏覽器。
    return jsonError("Login failed", 401);
  }

  const adminCheckClient = createClient(supabaseUrl, supabaseKey, {
    global: {
      headers: {
        Authorization: `Bearer ${data.session.access_token}`,
      },
    },
  });

  const adminAccess = await resolveAdminAccess({
    accessToken: data.session.access_token,
    legacyCheck: () =>
      checkAdminAccess(adminCheckClient, data.user.email ?? email),
    touchSession: () => adminCheckClient.rpc("admin_v2_touch_session"),
    revokeSession: () => adminCheckClient.rpc("admin_v2_revoke_my_session"),
  });

  if (!adminAccess.allowed) {
    await supabase.auth.signOut();
    return jsonError("You do not have access to this dashboard", 403);
  }

  const response = NextResponse.json({ success: true });
  response.cookies.set({
    name: ADMIN_ACCESS_COOKIE,
    value: data.session.access_token,
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
