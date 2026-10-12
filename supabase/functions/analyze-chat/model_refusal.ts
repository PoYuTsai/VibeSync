// 模型拒答的判斷（開場救星、新話題共用）。Sonnet 5.5 多了安全過濾，被擋時
// stop_reason 是 refusal。照 ADR #28／#49，拒答當失敗、不換模型；同一份內容重送
// 一樣會被擋，所以客戶要看到「請調整內容」，不是「稍後再試」。拒答類別
// （stop_details.category）由共用呼叫層記進 ai_logs，這裡不讀。

import { AiServiceError } from "./fallback.ts";
import { AiStreamingServiceError } from "./streaming_fallback.ts";

export function isModelRefusalError(error: unknown): boolean {
  return (error instanceof AiServiceError && error.code === "MODEL_REFUSAL") ||
    (error instanceof AiStreamingServiceError &&
      error.code === "STREAM_MODEL_REFUSAL");
}
