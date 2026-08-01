import {
  buildKeyboardReplyPrompt,
  buildRepairPrompt,
  KEYBOARD_REPLY_SYSTEM_PROMPT,
} from "./prompts.ts";
import {
  type KeyboardReplyRequest,
  parseAndValidateReply,
} from "./validate.ts";

export interface ClaudeCallArgs {
  apiKey: string;
  system: string;
  message: string;
  timeoutMs: number;
}

export const KEYBOARD_REPLY_MODEL = "claude-sonnet-5";
export const KEYBOARD_REQUEST_BUDGET_MS = 24_000;
export const KEYBOARD_SETTLEMENT_RESERVE_MS = 4_000;
export const KEYBOARD_GENERATION_BUDGET_MS = 20_000;
export const KEYBOARD_CLAUDE_ATTEMPT_TIMEOUT_MS = 15_000;

export function keyboardGenerationBudgetRemaining(
  requestDeadlineAt: number,
  nowMs: number,
): number {
  if (!Number.isFinite(requestDeadlineAt) || !Number.isFinite(nowMs)) return 0;
  return Math.max(
    0,
    Math.min(
      KEYBOARD_GENERATION_BUDGET_MS,
      Math.floor(
        requestDeadlineAt - nowMs - KEYBOARD_SETTLEMENT_RESERVE_MS,
      ),
    ),
  );
}

export interface KeyboardGenerationInput extends KeyboardReplyRequest {
  userId: string;
  apiKey: string;
  accountIsTest: boolean;
}

export class KeyboardReplyQuotaExceededError extends Error {
  constructor(
    readonly reason: "monthly_limit_exceeded" | "daily_limit_exceeded",
    readonly used: number,
    readonly limit: number,
  ) {
    super(reason);
  }
}

export class KeyboardReplyFinalizeError extends Error {
  constructor(
    readonly status: 409 | 500 | 503,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

type GenerationDeps = {
  callClaude: (args: ClaudeCallArgs) => Promise<unknown>;
  generationBudgetMs?: number;
  now?: () => number;
  finalizeReply: (
    userId: string,
    reply: string,
  ) => Promise<{ reply: string; costDeducted: 0 | 1 }>;
};

export async function runKeyboardReply(
  input: KeyboardGenerationInput,
  deps: GenerationDeps,
): Promise<{
  status: number;
  body: Record<string, unknown>;
  costDeducted: 0 | 1;
}> {
  let reply: string | null = null;
  const now = deps.now ?? (() => performance.now());
  const requestedBudget = deps.generationBudgetMs ??
    KEYBOARD_GENERATION_BUDGET_MS;
  const generationBudgetMs = Number.isFinite(requestedBudget) &&
      requestedBudget > 0
    ? Math.min(KEYBOARD_GENERATION_BUDGET_MS, Math.floor(requestedBudget))
    : 0;
  const generationDeadline = now() + generationBudgetMs;
  for (
    const message of [
      buildKeyboardReplyPrompt(input),
      buildRepairPrompt(input),
    ]
  ) {
    const remainingMs = Math.floor(generationDeadline - now());
    if (remainingMs <= 0) break;
    try {
      const result = await deps.callClaude({
        apiKey: input.apiKey,
        system: KEYBOARD_REPLY_SYSTEM_PROMPT,
        message,
        timeoutMs: Math.min(
          KEYBOARD_CLAUDE_ATTEMPT_TIMEOUT_MS,
          remainingMs,
        ),
      });
      reply = parseAndValidateReply(result);
      break;
    } catch (error) {
      if (
        error instanceof Error &&
        (error.message === "model_refusal" ||
          error.message === "model_context_window_exceeded")
      ) {
        break;
      }
      // One bounded repair attempt. Never log copied text or raw model output.
    }
  }
  if (reply == null) {
    return {
      status: 500,
      body: { error: "generation_failed" },
      costDeducted: 0,
    };
  }

  try {
    const finalized = await deps.finalizeReply(input.userId, reply);
    return {
      status: 200,
      body: { reply: finalized.reply, style: input.style },
      costDeducted: finalized.costDeducted,
    };
  } catch (error) {
    if (error instanceof KeyboardReplyQuotaExceededError) {
      return {
        status: 429,
        body: {
          error: error.reason === "monthly_limit_exceeded"
            ? "Monthly limit exceeded"
            : "Daily limit exceeded",
          code: "QUOTA_EXCEEDED",
          used: error.used,
          limit: error.limit,
          quotaNeeded: 1,
        },
        costDeducted: 0,
      };
    }
    if (error instanceof KeyboardReplyFinalizeError) {
      return {
        status: error.status,
        body: {
          error: error.code,
          code: error.code,
          retryable: error.status === 503,
        },
        costDeducted: 0,
      };
    }
    return {
      status: 500,
      body: { error: "credit_deduct_failed" },
      costDeducted: 0,
    };
  }
}

export async function callClaudeAPI(args: ClaudeCallArgs): Promise<unknown> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), args.timeoutMs);
  try {
    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": args.apiKey,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: KEYBOARD_REPLY_MODEL,
        max_tokens: 180,
        // Sonnet 5 defaults to adaptive thinking. Keyboard replies are tiny,
        // latency-sensitive JSON, so disable thinking explicitly and omit
        // temperature (non-default sampling can conflict with thinking).
        thinking: { type: "disabled" },
        system: args.system,
        messages: [{ role: "user", content: args.message }],
      }),
      signal: controller.signal,
    });
    if (!response.ok) throw new Error(`claude_http_${response.status}`);
    return await response.json();
  } finally {
    clearTimeout(timeout);
  }
}
