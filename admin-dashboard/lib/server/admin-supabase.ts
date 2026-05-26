import { cookies } from "next/headers";
import { createClient, type SupabaseClient, type User } from "@supabase/supabase-js";
import { ADMIN_ACCESS_COOKIE } from "@/lib/auth";
import { checkAdminAccess } from "@/lib/admin-check";

export interface AdminSession {
  supabase: SupabaseClient;
  user: User;
  adminId: string;
}

export async function getAdminSession(): Promise<
  | { ok: true; session: AdminSession }
  | { ok: false; status: number; error: string }
> {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!supabaseUrl || !supabaseKey) {
    return { ok: false, status: 500, error: "Supabase is not configured" };
  }

  const cookieStore = await cookies();
  const accessToken = cookieStore.get(ADMIN_ACCESS_COOKIE)?.value;

  if (!accessToken) {
    return { ok: false, status: 401, error: "Unauthorized" };
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
    return { ok: false, status: 401, error: "Unauthorized" };
  }

  const adminAccess = await checkAdminAccess(supabase, user.email);

  if (!adminAccess.allowed) {
    return { ok: false, status: 403, error: "Forbidden" };
  }

  return {
    ok: true,
    session: {
      supabase,
      user,
      adminId: user.id,
    },
  };
}
