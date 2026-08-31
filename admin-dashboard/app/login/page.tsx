import { isAdminV2Enabled } from "@/lib/operations/admin-v2";
import { LoginPageClient } from "./login-client";

// 旗標決策必須在 server 端於 request 時做：強制 dynamic render，
// 不在 build 時定死、也不把私有 ADMIN_V2 環境變數暴露進 client bundle。
export const dynamic = "force-dynamic";

export default function LoginPage() {
  return <LoginPageClient adminV2={isAdminV2Enabled()} />;
}
