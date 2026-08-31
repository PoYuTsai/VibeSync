// B2：admin errors route 的 ai_logs 讀取契約。
// 旗標關閉＝legacy 一比一：直接讀 ai_logs（含 error_message），輸出不變。
// 旗標開啟＝V2：只讀 metadata-only view（admin_ai_logs_meta_v2，欄位清單裡
// 根本沒有 error_message／request_body／response_body），route 在任何情況下
// 都不 SELECT raw 欄位；view 的授權走 anon key＋使用者 JWT（authenticated
// 角色）＋view 自帶的 admin_v2_is_active_admin() 守門。
// route.ts 只負責接線；來源選擇與列映射都在這裡，供測試直接執行驗證。

import { isAdminV2Enabled } from "./admin-v2.ts";

export const AI_ERRORS_LEGACY_TABLE = "ai_logs";
export const AI_ERRORS_V2_TABLE = "admin_ai_logs_meta_v2";

export const AI_ERRORS_LEGACY_COLUMNS = [
  "id",
  "created_at",
  "error_code",
  "error_message",
  "request_type",
  "user_id",
] as const;

/** V2 欄位是 legacy 減去 error_message：raw 錯誤內文永不出現在 V2 查詢。 */
export const AI_ERRORS_V2_COLUMNS = [
  "id",
  "created_at",
  "error_code",
  "request_type",
  "user_id",
] as const;

export type AiErrorsReadMode = "legacy" | "v2";

export interface AiErrorsSource {
  mode: AiErrorsReadMode;
  table: string;
  /** 直接餵給 supabase .select() 的欄位字串。 */
  select: string;
}

export function resolveAiErrorsSource(
  env: Record<string, string | undefined> = process.env,
): AiErrorsSource {
  if (isAdminV2Enabled(env)) {
    return {
      mode: "v2",
      table: AI_ERRORS_V2_TABLE,
      select: AI_ERRORS_V2_COLUMNS.join(", "),
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
