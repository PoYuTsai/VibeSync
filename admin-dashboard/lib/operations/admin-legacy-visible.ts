// ADMIN_V2 旗標分流的「可見輸出」單一真相。
// 旗標關閉：一比一重現 pre-B1 行為，包含轉發 Supabase／OAuth 原始錯誤訊息與
// session route 的 { error, email, detail } deny body。
// 旗標開啟：一律固定 generic 字串，不含 email、token、reason 或底層錯誤細節。
// 本檔只有純函式、零 runtime import：client component 拿到的是 server component
// 在 request 時算好的旗標布林值（不直接讀私有 ADMIN_V2 環境變數，也不進 client bundle）。
import type { ResolveAdminAccessResult } from "./admin-gate.ts";

type AdminDeny = Extract<ResolveAdminAccessResult, { allowed: false }>;

/** login route 401 訊息：pre-B1 是 `error?.message || "Login failed"`。 */
export function loginFailedMessage(
  v2Enabled: boolean,
  supabaseMessage: string | null | undefined,
): string {
  if (!v2Enabled) return supabaseMessage || "Login failed";
  return "Login failed";
}

/** session route deny：legacy 一比一重現 pre-B1 body shape；v2 只回 generic。 */
export function sessionDenyResponse(
  access: AdminDeny,
  userEmail: string | null | undefined,
): { status: number; body: Record<string, unknown> } {
  if (access.mode === "legacy") {
    return {
      status: 403,
      body: { error: "Forbidden", email: userEmail, detail: access.legacyError },
    };
  }
  return { status: access.status, body: { error: access.publicError } };
}

/** login page 的 signInWithOAuth 失敗：pre-B1 直接顯示 oauthError.message。 */
export function oauthStartErrorMessage(v2Enabled: boolean, rawMessage: string): string {
  return v2Enabled ? "無法前往 Google 登入，請稍後再試。" : rawMessage;
}

/** callback page 的 URL error 參數：pre-B1 直接回顯。 */
export function callbackUrlErrorMessage(v2Enabled: boolean, rawError: string): string {
  return v2Enabled ? "Google 登入失敗，請回登入頁重試。" : rawError;
}

/** callback page 的 exchangeCodeForSession 失敗：pre-B1 是 `message || fallback`。 */
export function callbackExchangeErrorMessage(
  v2Enabled: boolean,
  rawMessage: string | null | undefined,
): string {
  if (v2Enabled) return "無法完成 Google 登入，請重試。";
  return rawMessage || "Unable to complete Google login";
}
