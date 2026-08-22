// Recognize（免費 OCR）與帶圖請求的辨識流程守門：
// OCR 成本限流（6/分、60/天，與訂閱額度零交集）、structured-output 解析
// 失敗的單次呼叫 fail-closed、辨識結果的 reject／空結果 gate（不扣費）。
// 正規化本體在 ocr_normalizer.ts；這裡是 gate 與 telemetry。

import {
  buildOcrRateLimitedPayload,
  classifyOcrRateLimitError,
  OCR_RATE_LIMIT_PER_DAY,
  OCR_RATE_LIMIT_PER_MINUTE,
} from "./ocr_rate_limit.ts";
import { buildServerGuardrails } from "./server_guardrails.ts";
import { jsonResponse } from "./http_response.ts";
import { logAiCall, logError, logWarn, summarizeUser } from "./logger.ts";

export interface RecognizedConversationSummary {
  classification?: string;
  importPolicy?: string;
  confidence?: string;
  sideConfidence?: string;
  messageCount?: number;
  uncertainSideCount?: number;
  warning?: string;
  summary?: string;
  normalizationTelemetry?: {
    continuityAdjustedCount?: number;
    groupedAdjustedCount?: number;
    layoutFirstAdjustedCount?: number;
    systemRowsRemovedCount?: number;
    quotedPreviewRemovedCount?: number;
    quotedPreviewAttachedCount?: number;
    overlapRemovedCount?: number;
    mapShareCollapsedCount?: number;
  };
}

export function buildRecognitionObservability(
  recognizedConversation: RecognizedConversationSummary | undefined,
) {
  return {
    recognizedClassification: recognizedConversation?.classification ?? null,
    recognizedImportPolicy: recognizedConversation?.importPolicy ?? null,
    recognizedConfidence: recognizedConversation?.confidence ?? null,
    recognizedSideConfidence: recognizedConversation?.sideConfidence ?? null,
    recognizedMessageCount: recognizedConversation?.messageCount ?? null,
    uncertainSideCount: recognizedConversation?.uncertainSideCount ?? null,
    continuityAdjustedCount: recognizedConversation?.normalizationTelemetry
      ?.continuityAdjustedCount ?? 0,
    groupedAdjustedCount: recognizedConversation?.normalizationTelemetry
      ?.groupedAdjustedCount ?? 0,
    layoutFirstAdjustedCount: recognizedConversation?.normalizationTelemetry
      ?.layoutFirstAdjustedCount ?? 0,
    systemRowsRemovedCount: recognizedConversation?.normalizationTelemetry
      ?.systemRowsRemovedCount ?? 0,
    quotedPreviewRemovedCount: recognizedConversation?.normalizationTelemetry
      ?.quotedPreviewRemovedCount ?? 0,
    quotedPreviewAttachedCount: recognizedConversation?.normalizationTelemetry
      ?.quotedPreviewAttachedCount ?? 0,
    overlapRemovedCount: recognizedConversation?.normalizationTelemetry
      ?.overlapRemovedCount ?? 0,
    mapShareCollapsedCount: recognizedConversation?.normalizationTelemetry
      ?.mapShareCollapsedCount ?? 0,
  };
}

/// recognizeOnly OCR 限流（docs/plans/2026-07-02-ocr-rate-limit-design.md）。
/// 免費 Sonnet vision 入口的成本上界：6/分、60/天。計 attempt 不計
/// success——限的是成本不是產出。超限回 429；infra 錯誤 fail-open 留 telemetry。
export async function enforceOcrRateLimit(args: {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  userId: string;
}): Promise<Response | null> {
  const { error: ocrRateError } = await args.supabase.rpc(
    "increment_ocr_usage",
    {
      p_user_id: args.userId,
      p_minute_limit: OCR_RATE_LIMIT_PER_MINUTE,
      p_daily_limit: OCR_RATE_LIMIT_PER_DAY,
    },
  );
  if (ocrRateError) {
    const ocrRateReason = classifyOcrRateLimitError(ocrRateError.message);
    if (ocrRateReason) {
      logWarn("ocr_rate_limited", {
        user: summarizeUser(args.userId),
        reason: ocrRateReason,
      });
      return jsonResponse(buildOcrRateLimitedPayload(ocrRateReason), 429);
    }
    // fail-open：infra 錯誤（非超限 RAISE）不擋免費核心匯入流程——RPC
    // 失敗非用戶可誘發，漏計一次成本上界仍近似成立；但必留 telemetry。
    logError("ocr_rate_limit_check_failed", {
      user: summarizeUser(args.userId),
      error: ocrRateError.message,
    });
  }
  return null;
}

/// OCR 是刻意的「一次用戶動作＝一次 provider 呼叫」：structured output
/// 解析失敗直接 502 不重打（不重傳截圖），不扣費。
export async function respondRecognizeParseFailure(args: {
  supabaseUrl: string;
  supabaseServiceKey: string;
  userId: string;
  actualModel: string;
  requestType: string;
  tokenUsage: {
    inputTokens: number;
    outputTokens: number;
    cacheCreationTokens?: number;
    cacheReadTokens?: number;
  };
  latencyMs: number;
  fallbackUsed: boolean;
  retries: number;
  stopReason: string | null;
  contentBlockTypes: string[];
  textLength: number;
  requestObservability: Record<string, unknown>;
}): Promise<Response> {
  await logAiCall(args.supabaseUrl, args.supabaseServiceKey, {
    userId: args.userId,
    model: args.actualModel,
    requestType: args.requestType,
    inputTokens: args.tokenUsage.inputTokens,
    outputTokens: args.tokenUsage.outputTokens,
    cacheCreationTokens: args.tokenUsage.cacheCreationTokens,
    cacheReadTokens: args.tokenUsage.cacheReadTokens,
    latencyMs: args.latencyMs,
    status: "failed",
    errorCode: "AI_RESPONSE_INVALID",
    errorMessage: "OCR response did not match the JSON contract",
    fallbackUsed: args.fallbackUsed,
    retryCount: args.retries,
    requestBody: args.requestObservability,
    responseBody: {
      failureStage: "response_parse",
      stopReason: args.stopReason,
      contentBlockTypeSummary: args.contentBlockTypes.join(","),
      textLength: args.textLength,
      retries: args.retries,
      fallbackUsed: args.fallbackUsed,
    },
  });
  return jsonResponse(
    {
      error: "AI_RESPONSE_INVALID",
      code: "AI_RESPONSE_INVALID",
      message: "這次辨識結果格式異常，請再試一次。本次不會扣額度。",
      retryable: false,
      shouldChargeQuota: false,
    },
    502,
  );
}

export interface RecognitionGateContext {
  supabaseUrl: string;
  supabaseServiceKey: string;
  userId: string;
  actualModel: string;
  requestType: string;
  imageCount: number;
  latencyMs: number;
  timeoutMs: number;
  fallbackUsed: boolean;
  retries: number;
  totalImageBytes: number;
  truncatedMessageCount: number;
  conversationSummaryUsed: boolean;
  contextMode: string;
  tokenUsage: {
    inputTokens: number;
    outputTokens: number;
    cacheCreationTokens?: number;
    cacheReadTokens?: number;
  };
  requestObservability: Record<string, unknown>;
}

/// 帶圖請求的辨識 gate：模型宣告 importPolicy=reject → 400 不扣費；
/// 完全沒有 recognizedConversation 或 0 則 → 400 不扣費。兩者都留完整
/// telemetry（recognition + guardrail observability）。
export async function enforceRecognitionGates(
  recognizedConversation: RecognizedConversationSummary | undefined,
  context: RecognitionGateContext,
): Promise<Response | null> {
  const recognitionObservability = buildRecognitionObservability(
    recognizedConversation,
  );
  if (recognizedConversation?.importPolicy === "reject") {
    const rejectMessage = recognizedConversation.warning ||
      recognizedConversation.summary ||
      "這張圖片不像可支援的聊天截圖，請換一張再試。";
    const rejectGuardrails = buildServerGuardrails({
      requestType: context.requestType,
      imageCount: context.imageCount,
      latencyMs: context.latencyMs,
      timeoutMs: context.timeoutMs,
      fallbackUsed: context.fallbackUsed,
      retryCount: context.retries,
      totalImageBytes: context.totalImageBytes,
      truncatedMessageCount: context.truncatedMessageCount,
      conversationSummaryUsed: context.conversationSummaryUsed,
      contextMode: context.contextMode,
      recognizedClassification:
        recognitionObservability.recognizedClassification,
      recognizedSideConfidence:
        recognitionObservability.recognizedSideConfidence,
      uncertainSideCount: recognitionObservability.uncertainSideCount,
      continuityAdjustedCount: recognitionObservability.continuityAdjustedCount,
      groupedAdjustedCount: recognitionObservability.groupedAdjustedCount,
      layoutFirstAdjustedCount:
        recognitionObservability.layoutFirstAdjustedCount,
      quotedPreviewAttachedCount:
        recognitionObservability.quotedPreviewAttachedCount,
      overlapRemovedCount: recognitionObservability.overlapRemovedCount,
      inputTokens: context.tokenUsage.inputTokens,
      outputTokens: context.tokenUsage.outputTokens,
    });

    await logAiCall(context.supabaseUrl, context.supabaseServiceKey, {
      userId: context.userId,
      model: context.actualModel,
      requestType: context.requestType,
      inputTokens: context.tokenUsage.inputTokens,
      outputTokens: context.tokenUsage.outputTokens,
      cacheCreationTokens: context.tokenUsage.cacheCreationTokens,
      cacheReadTokens: context.tokenUsage.cacheReadTokens,
      latencyMs: context.latencyMs,
      status: "failed",
      errorCode: "RECOGNITION_UNSUPPORTED",
      errorMessage: rejectMessage,
      requestBody: context.requestObservability,
      responseBody: {
        failureStage: "recognition_gate",
        ...recognitionObservability,
        ...rejectGuardrails,
      },
    });

    return jsonResponse({
      error: rejectMessage,
      code: "RECOGNITION_UNSUPPORTED",
      message: rejectMessage,
      shouldChargeQuota: false,
    }, 400);
  }
  if (!recognizedConversation || recognizedConversation.messageCount === 0) {
    const recognitionFailedGuardrails = buildServerGuardrails({
      requestType: context.requestType,
      imageCount: context.imageCount,
      latencyMs: context.latencyMs,
      timeoutMs: context.timeoutMs,
      fallbackUsed: context.fallbackUsed,
      retryCount: context.retries,
      totalImageBytes: context.totalImageBytes,
      truncatedMessageCount: context.truncatedMessageCount,
      conversationSummaryUsed: context.conversationSummaryUsed,
      contextMode: context.contextMode,
      inputTokens: context.tokenUsage.inputTokens,
      outputTokens: context.tokenUsage.outputTokens,
    });

    // Log failed recognition
    await logAiCall(context.supabaseUrl, context.supabaseServiceKey, {
      userId: context.userId,
      model: context.actualModel,
      requestType: context.requestType,
      inputTokens: context.tokenUsage.inputTokens,
      outputTokens: context.tokenUsage.outputTokens,
      cacheCreationTokens: context.tokenUsage.cacheCreationTokens,
      cacheReadTokens: context.tokenUsage.cacheReadTokens,
      latencyMs: context.latencyMs,
      status: "failed",
      errorCode: "RECOGNITION_FAILED",
      errorMessage: "No recognizedConversation in response",
      requestBody: context.requestObservability,
      responseBody: {
        failureStage: "recognition_missing_output",
        ...recognitionFailedGuardrails,
      },
    });

    return jsonResponse({
      error: "無法識別截圖中的對話內容",
      code: "RECOGNITION_FAILED",
      message:
        "請確認截圖清晰、包含聊天泡泡，並盡量帶到對話頂部與最新訊息；單張截圖也可以分析，但畫面太裁切時容易失敗",
      shouldChargeQuota: false,
    }, 400);
  }
  return null;
}
