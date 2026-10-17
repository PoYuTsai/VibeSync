// 串流分析扣費失敗 → 給 App 的錯誤碼與訊息（v2 與 v3 共用）。
import { getErrorMessage } from "./logger.ts";

export function mapStreamChargeFailure(error: unknown): {
  code: string;
  message: string;
} {
  const message = getErrorMessage(error);
  const normalized = message.toUpperCase();
  if (
    normalized.includes("QUOTA") ||
    normalized.includes("LIMIT") ||
    normalized.includes("INSUFFICIENT")
  ) {
    return {
      code: "QUOTA_EXHAUSTED",
      message: "額度已用完，請升級或下個週期再試。",
    };
  }

  return {
    code: "STREAM_CHARGE_FAILED",
    message: "額度扣除失敗，請稍後再試。本次不會扣額度。",
  };
}
