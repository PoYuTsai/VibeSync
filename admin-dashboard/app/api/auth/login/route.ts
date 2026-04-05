import { NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import { ADMIN_ACCESS_COOKIE, ADMIN_ACCESS_COOKIE_MAX_AGE } from "@/lib/auth";

interface LoginBody {
  email?: string;
  password?: string;
}

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
    return jsonError(error?.message || "Login failed", 401);
  }

  const adminCheckClient = createClient(supabaseUrl, supabaseKey, {
    global: {
      headers: {
        Authorization: `Bearer ${data.session.access_token}`,
      },
    },
  });

  const { data: adminUser, error: adminError } = await adminCheckClient
    .from("admin_users")
    .select("id")
    .eq("email", data.user.email)
    .single();

  if (adminError || !adminUser) {
    await supabase.auth.signOut();
    return jsonError("You do not have access to this dashboard", 403);
  }

  const response = NextResponse.json(
    { success: true },
    {
      headers: {
        "Cache-Control": "no-store",
      },
    },
  );
  response.cookies.set({
    name: ADMIN_ACCESS_COOKIE,
    value: data.session.access_token,
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: ADMIN_ACCESS_COOKIE_MAX_AGE,
  });

  return response;
}
