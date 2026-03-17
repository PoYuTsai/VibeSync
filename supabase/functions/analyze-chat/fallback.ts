interface CallOptions {
  timeout: number;
  maxRetries: number;
}

type ClaudeMessageContent =
  | string
  | Array<{
    type: string;
    text?: string;
    source?: { type: string; media_type: string; data: string };
  }>;

interface ClaudeRequest {
  model: string;
  max_tokens: number;
  system: string;
  messages: Array<{ role: string; content: ClaudeMessageContent }>;
}

function buildCachedSystemPrompt(systemPrompt: string) {
  return [
    {
      type: "text",
      text: systemPrompt,
      cache_control: { type: "ephemeral" },
    },
  ];
}

const DEFAULT_OPTIONS: CallOptions = {
  timeout: 30000,
  maxRetries: 2,
};

const MODEL_FALLBACK_CHAIN: Record<string, string | null> = {
  "claude-sonnet-4-20250514": "claude-haiku-4-5-20251001",
  "claude-haiku-4-5-20251001": null,
};

const LOG_PREFIX = "[analyze-chat:fallback]";

function getErrorMessage(error: unknown): string {
  if (error instanceof Error) {
    return error.message;
  }
  return String(error);
}

function logInfo(event: string, metadata?: Record<string, unknown>) {
  console.log(`${LOG_PREFIX} ${event}`, metadata ?? {});
}

function logWarn(event: string, metadata?: Record<string, unknown>) {
  console.warn(`${LOG_PREFIX} ${event}`, metadata ?? {});
}

export interface FallbackResult {
  data: unknown;
  model: string;
  retries: number;
  fallbackUsed: boolean;
}

export class AiServiceError extends Error {
  constructor(
    message: string,
    public readonly code: string,
    public readonly retryable: boolean = false,
  ) {
    super(message);
    this.name = "AiServiceError";
  }
}

export async function callClaudeWithFallback(
  request: ClaudeRequest,
  apiKey: string,
  options: Partial<CallOptions> = {},
): Promise<FallbackResult> {
  const opts = { ...DEFAULT_OPTIONS, ...options };
  let currentModel = request.model;
  let totalRetries = 0;
  const originalModel = request.model;

  while (currentModel) {
    for (let attempt = 1; attempt <= opts.maxRetries; attempt++) {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), opts.timeout);

      try {
        const cachedRequest = {
          model: currentModel,
          max_tokens: request.max_tokens,
          system: buildCachedSystemPrompt(request.system),
          messages: request.messages,
        };

        const response = await fetch("https://api.anthropic.com/v1/messages", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "x-api-key": apiKey,
            "anthropic-version": "2023-06-01",
            "anthropic-beta": "prompt-caching-2024-07-31",
          },
          body: JSON.stringify(cachedRequest),
          signal: controller.signal,
        });

        if (!response.ok) {
          const errorText = await response.text();
          let errorMessage = errorText;
          try {
            const parsed = JSON.parse(errorText) as { message?: string };
            errorMessage = parsed.message || errorText;
          } catch {
            // Keep the original text when JSON parsing fails.
          }

          if (response.status === 429) {
            throw new AiServiceError(
              "AI rate limited the request. Please try again shortly.",
              "RATE_LIMITED",
              true,
            );
          }

          if (response.status >= 500) {
            throw new AiServiceError(
              "AI service is temporarily unavailable.",
              "SERVER_ERROR",
              true,
            );
          }

          throw new AiServiceError(
            `API Error: ${response.status} - ${errorMessage}`,
            "API_ERROR",
            false,
          );
        }

        const responseText = await response.text();
        let data;
        try {
          data = JSON.parse(responseText);
        } catch (parseError) {
          logWarn("claude_response_parse_failed", {
            model: currentModel,
            responseLength: responseText.length,
            error: getErrorMessage(parseError),
          });
          throw new AiServiceError(
            `Failed to parse Claude response: ${getErrorMessage(parseError)}`,
            "PARSE_ERROR",
            false,
          );
        }

        return {
          data,
          model: currentModel,
          retries: totalRetries,
          fallbackUsed: currentModel !== originalModel,
        };
      } catch (error) {
        totalRetries++;

        if (error instanceof Error && error.name === "AbortError") {
          logWarn("attempt_timeout", {
            model: currentModel,
            attempt,
            timeoutMs: opts.timeout,
          });
        } else if (error instanceof AiServiceError) {
          logWarn("attempt_failed", {
            model: currentModel,
            attempt,
            code: error.code,
            retryable: error.retryable,
            error: error.message,
          });
          if (!error.retryable) {
            throw error;
          }
        } else {
          logWarn("attempt_failed", {
            model: currentModel,
            attempt,
            error: getErrorMessage(error),
          });
        }

        if (attempt === opts.maxRetries) {
          const nextModel = MODEL_FALLBACK_CHAIN[currentModel];
          if (nextModel) {
            logInfo("falling_back_model", {
              from: currentModel,
              to: nextModel,
            });
            currentModel = nextModel;
            break;
          }

          throw new AiServiceError(
            "AI service is temporarily unavailable. Please try again later.",
            "ALL_MODELS_FAILED",
            false,
          );
        }

        const delay = Math.min(1000 * Math.pow(2, attempt - 1), 5000);
        await new Promise((resolve) => setTimeout(resolve, delay));
      } finally {
        clearTimeout(timeoutId);
      }
    }
  }

  throw new AiServiceError(
    "AI service returned an unexpected error.",
    "UNEXPECTED_ERROR",
    false,
  );
}
