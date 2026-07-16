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

type GenerationDeps = {
  callClaude: (args: ClaudeCallArgs) => Promise<unknown>;
  deductCredit: (userId: string) => Promise<void>;
};

export async function runKeyboardReply(
  input: KeyboardGenerationInput,
  deps: GenerationDeps,
): Promise<{ status: number; body: Record<string, unknown> }> {
  let reply: string | null = null;
  for (
    const message of [
      buildKeyboardReplyPrompt(input),
      buildRepairPrompt(input),
    ]
  ) {
    try {
      const result = await deps.callClaude({
        apiKey: input.apiKey,
        system: KEYBOARD_REPLY_SYSTEM_PROMPT,
        message,
        timeoutMs: 8000,
      });
      reply = parseAndValidateReply(result);
      break;
    } catch {
      // One bounded repair attempt. Never log copied text or raw model output.
    }
  }
  if (reply == null) {
    return { status: 500, body: { error: "generation_failed" } };
  }

  if (!input.accountIsTest) {
    try {
      await deps.deductCredit(input.userId);
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
        };
      }
      return { status: 500, body: { error: "credit_deduct_failed" } };
    }
  }

  return { status: 200, body: { reply, style: input.style } };
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
        model: "claude-haiku-4-5-20251001",
        max_tokens: 180,
        temperature: 0.7,
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
