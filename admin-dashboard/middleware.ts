// admin-dashboard/middleware.ts
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { createClient } from "@supabase/supabase-js";
import { ADMIN_ACCESS_COOKIE } from "@/lib/auth";

export async function middleware(request: NextRequest) {
  // 跳過登入頁面和 403
  if (
    request.nextUrl.pathname === "/login" ||
    request.nextUrl.pathname === "/403"
  ) {
    return NextResponse.next();
  }

  // 從 cookie 取得 session token
  const accessToken = request.cookies.get(ADMIN_ACCESS_COOKIE)?.value;

  if (!accessToken) {
    return NextResponse.redirect(new URL("/login", request.url));
  }

  // 驗證 token 並檢查 admin 權限
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
  const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;
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

  if (authError || !user) {
    const response = NextResponse.redirect(new URL("/login", request.url));
    response.cookies.set({
      name: ADMIN_ACCESS_COOKIE,
      value: "",
      httpOnly: true,
      secure: process.env.NODE_ENV === "production",
      sameSite: "lax",
      path: "/",
      maxAge: 0,
    });
    return response;
  }

  // 檢查是否在 admin 白名單
  const { data: adminUser } = await supabase
    .from("admin_users")
    .select("id")
    .eq("email", user.email)
    .single();

  if (!adminUser) {
    const response = NextResponse.redirect(new URL("/403", request.url));
    response.cookies.set({
      name: ADMIN_ACCESS_COOKIE,
      value: "",
      httpOnly: true,
      secure: process.env.NODE_ENV === "production",
      sameSite: "lax",
      path: "/",
      maxAge: 0,
    });
    return response;
  }

  return NextResponse.next();
}

export const config = {
  matcher: ["/((?!api|_next/static|_next/image|favicon.ico|login|403).*)"],
};
