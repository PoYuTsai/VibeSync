import type { SupabaseClient } from "@supabase/supabase-js";

export async function checkAdminAccess(
  supabase: SupabaseClient,
  email: string
): Promise<{ allowed: boolean; error?: string }> {
  const { data: isAdmin, error: rpcError } = await supabase.rpc("is_admin_user");

  if (!rpcError) {
    return { allowed: isAdmin === true };
  }

  const { data: adminUser, error: rowError } = await supabase
    .from("admin_users")
    .select("id")
    .ilike("email", email)
    .maybeSingle();

  return {
    allowed: Boolean(adminUser?.id),
    error: rowError?.message ?? rpcError.message,
  };
}
