// supabase/functions/analyze-chat/ocr_rate_limit.ts
//
// recognizeOnly OCR 限流純 helper（docs/plans/2026-07-02-ocr-rate-limit-design.md）。
// recognizeOnly 是免費 Sonnet vision 入口，本模組給它一層與訂閱額度完全獨立的
// 節流（I3）：計數在 DB RPC `increment_ocr_usage`（FOR UPDATE＋超限 RAISE），
// 這裡只放 Edge 側的常數與訊息判別/回包，維持 OCR 隔離、不碰 _shared/quota.ts。

/** Eric 拍板（2026-07-02）：每用戶 6 次/分鐘。權威在 Edge，SQL 不寫死（I7）。 */
export const OCR_RATE_LIMIT_PER_MINUTE = 6;

/** Eric 拍板（2026-07-02）：每用戶 60 次/天（UTC 日＝台北早上 8 點恢復）。 */
export const OCR_RATE_LIMIT_PER_DAY = 60;

export type OcrRateLimitReason = "minute" | "daily";

/**
 * increment_ocr_usage RAISE 訊息的 Edge 側偵測。PostgREST 會把 RAISE 訊息包進
 * 較長字串，用 includes 抓（同 classifyQuotaRpcError / PRACTICE_DRAW_* 慣例）。
 * 非超限錯誤回 null → 呼叫端 fail-open 放行（I6）。
 */
export function classifyOcrRateLimitError(
  message: string | null | undefined,
): OcrRateLimitReason | null {
  if (!message) return null;
  if (message.includes("OCR_RATE_LIMITED_MINUTE")) return "minute";
  if (message.includes("OCR_RATE_LIMITED_DAILY")) return "daily";
  return null;
}

/**
 * 429 回包。絕不帶 monthlyLimit/dailyLimit（含 remaining/quotaNeeded）等訂閱
 * 額度鍵——client `_quotaExceptionFrom429` 靠那些鍵判 paywall 例外，帶了會把
 * 免費 OCR 限流誤導成升級 CTA（I4）。retryable=false 防自動重試風暴（I5）。
 */
export function buildOcrRateLimitedPayload(reason: OcrRateLimitReason): {
  error: string;
  code: "OCR_RATE_LIMITED";
  message: string;
  retryable: false;
} {
  return {
    error: "OCR rate limited",
    code: "OCR_RATE_LIMITED",
    message: reason === "minute"
      ? "截圖辨識太頻繁，請稍等一分鐘再試。"
      : "今日截圖辨識次數已達上限，明天早上 8 點恢復。",
    retryable: false,
  };
}
