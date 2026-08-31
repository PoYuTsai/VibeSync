import { cookies } from "next/headers";
import { createClient, type SupabaseClient, type User } from "@supabase/supabase-js";
import { ADMIN_ACCESS_COOKIE } from "@/lib/auth";
import { checkAdminAccess } from "@/lib/admin-check";
import { isAdminV2Enabled } from "@/lib/operations/admin-v2";
import {
  resolveAdminAccess,
  type AdminCapability,
  type AdminRole,
} from "@/lib/operations/admin-gate";

export interface AdminSession {
  supabase: SupabaseClient;
  user: User;
  adminId: string;
  /** 只有 ADMIN_V2 開啟時才有值；legacy 路徑維持原輸出。 */
  role?: AdminRole;
  capabilities?: readonly AdminCapability[];
  lastReauthAt?: string | null;
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

  if (authError || !user || (!isAdminV2Enabled() && !user.email)) {
    return { ok: false, status: 401, error: "Unauthorized" };
  }

  const adminAccess = await resolveAdminAccess({
    accessToken,
    legacyCheck: () => checkAdminAccess(supabase, user.email ?? ""),
    touchSession: () => supabase.rpc("admin_v2_touch_session"),
    revokeSession: () => supabase.rpc("admin_v2_revoke_my_session"),
  });

  if (!adminAccess.allowed) {
    return { ok: false, status: adminAccess.status, error: adminAccess.publicError };
  }

  return {
    ok: true,
    session: {
      supabase,
      user,
      adminId: user.id,
      ...(adminAccess.mode === "v2"
        ? {
            role: adminAccess.role,
            capabilities: adminAccess.capabilities,
            lastReauthAt: adminAccess.lastReauthAt,
          }
        : {}),
    },
  };
}
