import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { createClient } from "@supabase/supabase-js";
import { ADMIN_ACCESS_COOKIE } from "@/lib/auth";

const PUBLIC_PATHS = ["/login", "/403", "/auth/callback"];

function clearAdminCookie(response: NextResponse) {
  response.cookies.set({
    name: ADMIN_ACCESS_COOKIE,
    value: "",
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: 0,
  });
}

export async function middleware(request: NextRequest) {
  if (PUBLIC_PATHS.includes(request.nextUrl.pathname)) {
    return NextResponse.next();
  }

  const accessToken = request.cookies.get(ADMIN_ACCESS_COOKIE)?.value;

  if (!accessToken) {
    return NextResponse.redirect(new URL("/login", request.url));
  }

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!supabaseUrl || !supabaseKey) {
    const response = NextResponse.redirect(new URL("/login", request.url));
    clearAdminCookie(response);
    return response;
  }

  const supabase = createClient(supabaseUrl, supabaseKey, {
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
    const response = NextResponse.redirect(new URL("/login", request.url));
    clearAdminCookie(response);
    return response;
  }

  const { data: adminUser } = await supabase
    .from("admin_users")
    .select("id")
    .eq("email", user.email)
    .single();

  if (!adminUser) {
    const response = NextResponse.redirect(new URL("/403", request.url));
    clearAdminCookie(response);
    return response;
  }

  return NextResponse.next();
}

export const config = {
  matcher: [
    "/((?!api|_next/static|_next/image|favicon.ico|login|403|auth/callback).*)",
  ],
};
