// supabase/functions/analyze-chat/logger.ts
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

// Token 成本 (USD per 1K tokens) - 根據 Anthropic 定價
const TOKEN_COSTS: Record<string, { input: number; output: number }> = {
  "claude-sonnet-4-20250514": { input: 0.003, output: 0.015 },
  "claude-haiku-4-5-20251001": { input: 0.0008, output: 0.004 },
};

export interface LogEntry {
  userId: string;
  model: string;
  requestType?: string;
  inputTokens: number;
  outputTokens: number;
  latencyMs: number;
  status: "success" | "failed" | "filtered";
  errorCode?: string;
  errorMessage?: string;
  fallbackUsed?: boolean;
  retryCount?: number;
  // 只在失敗時記錄
  requestBody?: unknown;
  responseBody?: unknown;
}

// 計算成本
function calculateCost(
  model: string,
  inputTokens: number,
  outputTokens: number
): number {
  const costs = TOKEN_COSTS[model] || TOKEN_COSTS["claude-haiku-4-5-20251001"];
  return (inputTokens / 1000) * costs.input + (outputTokens / 1000) * costs.output;
}

export async function logAiCall(
  supabaseUrl: string,
  serviceKey: string,
  entry: LogEntry
): Promise<void> {
  try {
    const supabase = createClient(supabaseUrl, serviceKey);

    const costUsd = calculateCost(entry.model, entry.inputTokens, entry.outputTokens);

    await supabase.from("ai_logs").insert({
      user_id: entry.userId,
      model: entry.model,
      request_type: entry.requestType || "analyze",
      input_tokens: entry.inputTokens,
      output_tokens: entry.outputTokens,
      cost_usd: costUsd,
      latency_ms: entry.latencyMs,
      status: entry.status,
      error_code: entry.errorCode,
      error_message: entry.errorMessage,
      fallback_used: entry.fallbackUsed || false,
      retry_count: entry.retryCount || 0,
      // 只在失敗時記錄完整內容
      request_body: entry.status === "failed" ? entry.requestBody : null,
      response_body: entry.status === "failed" ? entry.responseBody : null,
    });
  } catch (error) {
    // 日誌失敗不應影響主要請求
    console.error("Failed to log AI call:", error);
  }
}

// 從 Claude 回應中提取 token 使用量 (含 cache 資訊)
export function extractTokenUsage(claudeResponse: unknown): {
  inputTokens: number;
  outputTokens: number;
  cacheCreationTokens: number;
  cacheReadTokens: number;
} {
  const response = claudeResponse as {
    usage?: {
      input_tokens?: number;
      output_tokens?: number;
      cache_creation_input_tokens?: number;
      cache_read_input_tokens?: number;
    };
  };

  return {
    inputTokens: response?.usage?.input_tokens || 0,
    outputTokens: response?.usage?.output_tokens || 0,
    cacheCreationTokens: response?.usage?.cache_creation_input_tokens || 0,
    cacheReadTokens: response?.usage?.cache_read_input_tokens || 0,
  };
}

// Token 精確追蹤 (用於計費和用量分析)
export interface TokenUsageEntry {
  userId: string;
  model: string;
  inputTokens: number;
  outputTokens: number;
  conversationId?: string;
}

export async function trackTokenUsage(
  supabaseUrl: string,
  serviceKey: string,
  entry: TokenUsageEntry
): Promise<void> {
  try {
    const supabase = createClient(supabaseUrl, serviceKey);
    const costUsd = calculateCost(entry.model, entry.inputTokens, entry.outputTokens);

    await supabase.from("token_usage").insert({
      user_id: entry.userId,
      model: entry.model,
      input_tokens: entry.inputTokens,
      output_tokens: entry.outputTokens,
      cost_usd: costUsd,
      conversation_id: entry.conversationId,
    });
  } catch (error) {
    // Token 追蹤失敗不應影響主要請求
    console.error("Failed to track token usage:", error);
  }
}

// 導出 calculateCost 供外部使用
export { calculateCost };
