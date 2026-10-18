// 最低 App 版本閘門（Eric 2026-10-18）：之後發版時可以乾淨地停掉很舊的 build。
// 開關是 secret MIN_CLIENT_BUILD（每次請求讀，跟 ANALYZE_GUIDE_V3 一樣）；沒設、
// 空字串、不是正整數都當關閉，關閉時完全不看 clientBuild，誰都不受影響。
//
// 範圍刻意只到「對話分析」的新分析：開場救星（含兩段式）、新話題、草稿潤飾／
// 回覆微調、我說、截圖辨識雖然也走 analyze-chat，一律不擋——舊版在那些入口只會
// 顯示泛用錯誤，擋了反而誤導。續看（帶 analysisRunId）也不擋：那一次已經扣過
// 費，擋下等於拿不到付過的結果。要不要擴大範圍，是 Eric 打開閘門時的產品決定。
//
// 呼叫端放在合約版本解析之後、任何訂閱／額度／模型工作之前：擋下不花錢、不扣
// 額度，也不寫任何資料。

import { corsHeaders, jsonResponse } from "./http_response.ts";
import { ndjsonStreamResponse } from "./ndjson_response.ts";

export const APP_UPDATE_REQUIRED_CODE = "APP_UPDATE_REQUIRED";
export const APP_UPDATE_REQUIRED_MESSAGE =
  "這個版本已經停止支援，請到 App Store 更新到最新版（TestFlight 測試者請到 TestFlight 更新）。";

/// 沒設、打錯（不是正整數）都當關閉，回 null。
export function parseMinClientBuild(raw: string | undefined): number | null {
  const value = raw?.trim() ?? "";
  if (!/^\d+$/.test(value)) return null;
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null;
}

/// App 送來的 build 號（iOS 的 CFBundleVersion）；只認正整數，其他都當沒送。
export function parseClientBuild(raw: unknown): number | null {
  return typeof raw === "number" && Number.isSafeInteger(raw) && raw > 0
    ? raw
    : null;
}

export type ClientBuildGateResult =
  | { blocked: false }
  | {
    blocked: true;
    minClientBuild: number;
    clientBuild: number | null;
    response: Response;
  };

export function checkClientBuildGate(input: {
  /// `Deno.env.get("MIN_CLIENT_BUILD")` 的原始值。
  readonly minClientBuild: string | undefined;
  /// request body 的 clientBuild 原始值。
  readonly clientBuild: unknown;
  /// 對話分析的新分析（plain_analyze 且不是續看）；其他請求一律放行。
  readonly isNewChatAnalysis: boolean;
  readonly streaming: boolean;
}): ClientBuildGateResult {
  const minClientBuild = parseMinClientBuild(input.minClientBuild);
  if (minClientBuild === null || !input.isNewChatAnalysis) {
    return { blocked: false };
  }
  const clientBuild = parseClientBuild(input.clientBuild);
  if (clientBuild !== null && clientBuild >= minClientBuild) {
    return { blocked: false };
  }
  return {
    blocked: true,
    minClientBuild,
    clientBuild,
    response: clientBuild === null && input.streaming
      ? legacyStreamUpdateResponse()
      : updateRequiredJsonResponse(),
  };
}

/// 有帶 clientBuild 的 App 認得 426＋APP_UPDATE_REQUIRED，會跳更新視窗。
function updateRequiredJsonResponse(): Response {
  return jsonResponse({
    error: APP_UPDATE_REQUIRED_MESSAGE,
    code: APP_UPDATE_REQUIRED_CODE,
    message: APP_UPDATE_REQUIRED_MESSAGE,
    shouldChargeQuota: false,
  }, 426);
}

/// 沒帶 clientBuild 的舊版不認得 426（只會顯示「分析暫時失敗」），但會照原樣
/// 顯示串流 analysis.error 裡的中文，所以串流請求改回一則錯誤事件。
function legacyStreamUpdateResponse(): Response {
  return ndjsonStreamResponse((emit, close) => {
    emit({
      type: "analysis.error",
      code: APP_UPDATE_REQUIRED_CODE,
      message: APP_UPDATE_REQUIRED_MESSAGE,
      recoverable: false,
      retriesRemaining: 0,
    });
    close();
  }, corsHeaders);
}
