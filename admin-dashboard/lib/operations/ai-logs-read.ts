// B2：admin errors route 的 ai_logs 讀取契約。
// 旗標關閉＝legacy 一比一：直接讀 ai_logs（含 error_message），輸出不變。
// 旗標開啟＝V2：只呼叫 metadata-only operation RPC，RPC 內部重跑完整 B1
// session gate；欄位清單裡根本沒有 error_message／request_body／response_body。
// route 在任何情況下都不 SELECT raw 欄位，也不把 authenticated JWT 直接授權到
// metadata view/table。
// route.ts 只負責接線；來源選擇與列映射都在這裡，供測試直接執行驗證。

import { isAdminV2Enabled } from "./admin-v2.ts";

export const AI_ERRORS_LEGACY_TABLE = "ai_logs";
export const AI_ERRORS_V2_RPC = "admin_v2_list_error_metadata";

/**
 * DB cutover 與 route flag 不能任意交錯：先部署可用的 V2 route/RPC，再開 DB
 * raw-log cutover；回退時先關 DB cutover，最後才關 ADMIN_V2 route。這是部署
 * 順序契約，避免 active admin 在兩個開關不同步時失去唯一可讀的 metadata 路徑。
 */
export const AI_ERRORS_CUTOVER_SEQUENCE = [
  "deploy-v2-metadata-route-and-rpc",
  "enable-db-ai-logs-cutover",
  "disable-db-ai-logs-cutover",
  "disable-admin-v2-route",
] as const;

export const AI_ERRORS_LEGACY_COLUMNS = [
  "id",
  "created_at",
  "error_code",
  "error_message",
  "request_type",
  "user_id",
] as const;

/** V2 RPC 回傳 allowlist 是 legacy 減去 error_message；不作為直接 SELECT 欄位。 */
export const AI_ERRORS_V2_COLUMNS = [
  "id",
  "created_at",
  "error_code",
  "request_type",
  "user_id",
] as const;

export type AiErrorsReadMode = "legacy" | "v2";

export interface LegacyAiErrorsSource {
  mode: "legacy";
  table: string;
  /** 直接餵給 supabase .select() 的欄位字串。 */
  select: string;
}

export interface V2AiErrorsSource {
  mode: "v2";
  /** 僅透過完整 session gate 的 metadata-only RPC。 */
  rpc: typeof AI_ERRORS_V2_RPC;
}

export type AiErrorsSource = LegacyAiErrorsSource | V2AiErrorsSource;

export function resolveAiErrorsSource(
  env: Record<string, string | undefined> = process.env,
): AiErrorsSource {
  if (isAdminV2Enabled(env)) {
    return {
      mode: "v2",
      rpc: AI_ERRORS_V2_RPC,
    };
  }
  return {
    mode: "legacy",
    table: AI_ERRORS_LEGACY_TABLE,
    select: AI_ERRORS_LEGACY_COLUMNS.join(", "),
  };
}

export interface AiErrorRowInput {
  id: string;
  created_at: string;
  error_code: string | null;
  error_message?: string | null;
  request_type: string | null;
  user_id: string | null;
}

export interface AiErrorRowOutput {
  id: string;
  created_at: string;
  error_type: string;
  error_message: string;
  user_id: string;
  request_id: string;
}

/**
 * 列映射：legacy 輸出與既有 route 一比一（含 error_message 原文）；
 * V2 的 error_message 恆為空字串——即使上游意外帶了值也不外流。
 */
export function mapAiErrorRow(
  row: AiErrorRowInput,
  mode: AiErrorsReadMode,
): AiErrorRowOutput {
  return {
    id: row.id,
    created_at: row.created_at,
    error_type: row.error_code?.trim() || row.request_type?.trim() || "UNKNOWN",
    error_message: mode === "v2" ? "" : row.error_message ?? "",
    user_id: row.user_id ?? "",
    request_id: row.id,
  };
}
