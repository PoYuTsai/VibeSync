import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const TOKEN_COSTS: Record<string, { input: number; output: number }> = {
  "claude-sonnet-4-20250514": { input: 0.003, output: 0.015 },
  "claude-haiku-4-5-20251001": { input: 0.0008, output: 0.004 },
};

const MAX_STORED_TEXT_LENGTH = 500;
const MAX_STORED_OBJECT_KEYS = 32;
const SENSITIVE_KEYS = new Set([
  "messages",
  "message",
  "content",
  "conversation",
  "conversationText",
  "conversationSummary",
  "userDraft",
  "sessionContext",
  "images",
  "image",
  "data",
  "source",
  "system",
  "request",
  "response",
]);

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
  requestBody?: unknown;
  responseBody?: unknown;
}

function calculateCost(
  model: string,
  inputTokens: number,
  outputTokens: number,
): number {
  const costs = TOKEN_COSTS[model] || TOKEN_COSTS["claude-haiku-4-5-20251001"];
  return (inputTokens / 1000) * costs.input +
    (outputTokens / 1000) * costs.output;
}

function truncateText(
  value: string,
  maxLength = MAX_STORED_TEXT_LENGTH,
): string {
  if (value.length <= maxLength) {
    return value;
  }
  return `${value.slice(0, maxLength)}…`;
}

function sanitizeLogPayload(value: unknown): unknown {
  if (value == null) {
    return null;
  }

  if (typeof value === "string") {
    return truncateText(value);
  }

  if (typeof value === "number" || typeof value === "boolean") {
    return value;
  }

  if (Array.isArray(value)) {
    return { type: "array", length: value.length };
  }

  if (typeof value !== "object") {
    return String(value);
  }

  const record = value as Record<string, unknown>;
  const sanitized: Record<string, unknown> = {};
  let storedKeys = 0;

  for (const [key, rawValue] of Object.entries(record)) {
    if (storedKeys >= MAX_STORED_OBJECT_KEYS) {
      sanitized._truncated = true;
      break;
    }

    if (SENSITIVE_KEYS.has(key)) {
      sanitized[key] = "[redacted]";
      storedKeys++;
      continue;
    }

    if (
      rawValue == null || typeof rawValue === "number" ||
      typeof rawValue === "boolean"
    ) {
      sanitized[key] = rawValue;
    } else if (typeof rawValue === "string") {
      sanitized[key] = truncateText(rawValue);
    } else if (Array.isArray(rawValue)) {
      sanitized[key] = { type: "array", length: rawValue.length };
    } else if (typeof rawValue === "object") {
      sanitized[key] = {
        type: "object",
        keys: Object.keys(rawValue as Record<string, unknown>).slice(0, 8),
      };
    } else {
      sanitized[key] = String(rawValue);
    }

    storedKeys++;
  }

  return sanitized;
}

function sanitizeErrorMessage(errorMessage?: string): string | null {
  if (!errorMessage) {
    return null;
  }
  return truncateText(errorMessage, 300);
}

export async function logAiCall(
  supabaseUrl: string,
  serviceKey: string,
  entry: LogEntry,
): Promise<void> {
  try {
    const supabase = createClient(supabaseUrl, serviceKey);
    const costUsd = calculateCost(
      entry.model,
      entry.inputTokens,
      entry.outputTokens,
    );

    const { error } = await supabase.from("ai_logs").insert({
      user_id: entry.userId,
      model: entry.model,
      request_type: entry.requestType || "analyze",
      input_tokens: entry.inputTokens,
      output_tokens: entry.outputTokens,
      cost_usd: costUsd,
      latency_ms: entry.latencyMs,
      status: entry.status,
      error_code: entry.errorCode,
      error_message: sanitizeErrorMessage(entry.errorMessage),
      fallback_used: entry.fallbackUsed || false,
      retry_count: entry.retryCount || 0,
      request_body: entry.requestBody === undefined
        ? null
        : sanitizeLogPayload(entry.requestBody),
      response_body: entry.responseBody === undefined
        ? null
        : sanitizeLogPayload(entry.responseBody),
    });

    if (error) {
      console.error("Failed to log AI call:", error);
    }
  } catch (error) {
    console.error("Failed to log AI call:", error);
  }
}

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
  entry: TokenUsageEntry,
): Promise<void> {
  try {
    const supabase = createClient(supabaseUrl, serviceKey);
    const costUsd = calculateCost(
      entry.model,
      entry.inputTokens,
      entry.outputTokens,
    );

    const { error } = await supabase.from("token_usage").insert({
      user_id: entry.userId,
      model: entry.model,
      input_tokens: entry.inputTokens,
      output_tokens: entry.outputTokens,
      cost_usd: costUsd,
      conversation_id: entry.conversationId,
    });

    if (error) {
      console.error("Failed to track token usage:", error);
    }
  } catch (error) {
    console.error("Failed to track token usage:", error);
  }
}

export { calculateCost };
