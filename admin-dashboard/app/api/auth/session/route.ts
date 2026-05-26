import { NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import { ADMIN_ACCESS_COOKIE, ADMIN_ACCESS_COOKIE_MAX_AGE } from "@/lib/auth";

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

  if (authError || !user?.email) {
    return jsonError("Unauthorized", 401);
  }

  const { data: adminUser, error: adminError } = await supabase
    .from("admin_users")
    .select("id")
    .ilike("email", user.email)
    .maybeSingle();

  if (adminError || !adminUser) {
    return jsonError("Forbidden", 403);
  }

  const response = NextResponse.json({ success: true });
  response.cookies.set({
    name: ADMIN_ACCESS_COOKIE,
    value: body.accessToken,
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: ADMIN_ACCESS_COOKIE_MAX_AGE,
  });

  return response;
}
