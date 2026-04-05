import { createClient } from "@supabase/supabase-js";
import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";

import { ADMIN_ACCESS_COOKIE } from "@/lib/auth";

function jsonError(message: string, status: number) {
  return NextResponse.json(
    { error: message },
    {
      status,
      headers: {
        "Cache-Control": "no-store",
      },
    },
  );
}

export function jsonNoStore(data: unknown, status = 200) {
  return NextResponse.json(data, {
    status,
    headers: {
      "Cache-Control": "no-store",
    },
  });
}

function getSupabaseEnv() {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  const supabaseServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!supabaseUrl || !supabaseAnonKey) {
    throw new Error("Supabase public env vars are not configured");
  }

  return {
    supabaseUrl,
    supabaseAnonKey,
    supabaseServiceRoleKey,
  };
}

export async function requireAdminRequest(
  request: NextRequest,
): Promise<
  | { ok: true; accessToken: string; email: string | null }
  | { ok: false; response: NextResponse }
> {
  const accessToken = request.cookies.get(ADMIN_ACCESS_COOKIE)?.value;
  if (!accessToken) {
    return { ok: false, response: jsonError("Unauthorized", 401) };
  }

  let supabaseUrl: string;
  let supabaseAnonKey: string;
  try {
    ({ supabaseUrl, supabaseAnonKey } = getSupabaseEnv());
  } catch (error) {
    return {
      ok: false,
      response: jsonError(
        error instanceof Error ? error.message : "Supabase is not configured",
        500,
      ),
    };
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
    global: {
      headers: {
        Authorization: `Bearer ${accessToken}`,
      },
    },
  });

  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser();

  if (authError || !user?.email) {
    return { ok: false, response: jsonError("Unauthorized", 401) };
  }

  const { data: adminUser, error: adminError } = await supabase
    .from("admin_users")
    .select("id")
    .eq("email", user.email)
    .single();

  if (adminError || !adminUser) {
    return { ok: false, response: jsonError("Forbidden", 403) };
  }

  return { ok: true, accessToken, email: user.email };
}

export function createServiceRoleSupabase() {
  const { supabaseUrl, supabaseServiceRoleKey } = getSupabaseEnv();

  if (!supabaseServiceRoleKey) {
    throw new Error("SUPABASE_SERVICE_ROLE_KEY is not configured");
  }

  return createClient(supabaseUrl, supabaseServiceRoleKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  });
}
