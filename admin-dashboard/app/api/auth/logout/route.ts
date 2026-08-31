import { NextResponse } from "next/server";
import { cookies } from "next/headers";
import { createClient } from "@supabase/supabase-js";
import { ADMIN_ACCESS_COOKIE } from "@/lib/auth";
import { isAdminV2Enabled } from "@/lib/operations/admin-v2";

export async function POST() {
  // ADMIN_V2：best-effort 撤銷伺服器端 session 列；失敗也必須完成清 cookie。
  if (isAdminV2Enabled()) {
    try {
      const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
      const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
      const accessToken = (await cookies()).get(ADMIN_ACCESS_COOKIE)?.value;
      if (supabaseUrl && supabaseKey && accessToken) {
        const supabase = createClient(supabaseUrl, supabaseKey, {
          global: {
            headers: {
              Authorization: `Bearer ${accessToken}`,
            },
          },
        });
        await supabase.rpc("admin_v2_revoke_my_session");
      }
    } catch {
      // 登出永遠成功清 legacy cookie 狀態。
    }
  }

  const response = NextResponse.json({ success: true });
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
