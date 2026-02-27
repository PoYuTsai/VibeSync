// supabase/functions/analyze-chat/fallback.ts

interface CallOptions {
  timeout: number;
  maxRetries: number;
}

interface ClaudeRequest {
  model: string;
  max_tokens: number;
  system: string;
  messages: Array<{ role: string; content: string }>;
}

const DEFAULT_OPTIONS: CallOptions = {
  timeout: 30000, // 30 秒
  maxRetries: 2,
};

// 模型降級鏈
const MODEL_FALLBACK_CHAIN: Record<string, string | null> = {
  "claude-sonnet-4-20250514": "claude-3-5-haiku-20241022",
  "claude-3-5-haiku-20241022": null, // Haiku 是最後一層
};

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
    public readonly retryable: boolean = false
  ) {
    super(message);
    this.name = "AiServiceError";
  }
}

export async function callClaudeWithFallback(
  request: ClaudeRequest,
  apiKey: string,
  options: Partial<CallOptions> = {}
): Promise<FallbackResult> {
  const opts = { ...DEFAULT_OPTIONS, ...options };
  let currentModel = request.model;
  let totalRetries = 0;
  const originalModel = request.model;

  while (currentModel) {
    for (let attempt = 1; attempt <= opts.maxRetries; attempt++) {
      try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), opts.timeout);

        const response = await fetch("https://api.anthropic.com/v1/messages", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "x-api-key": apiKey,
            "anthropic-version": "2023-06-01",
          },
          body: JSON.stringify({ ...request, model: currentModel }),
          signal: controller.signal,
        });

        clearTimeout(timeoutId);

        if (!response.ok) {
          const error = await response.json();

          // 429 Too Many Requests - 可重試
          if (response.status === 429) {
            throw new AiServiceError(
              "AI 服務繁忙，請稍後再試",
              "RATE_LIMITED",
              true
            );
          }

          // 500+ Server Error - 可重試
          if (response.status >= 500) {
            throw new AiServiceError(
              "AI 服務暫時無法使用",
              "SERVER_ERROR",
              true
            );
          }

          // 其他錯誤
          throw new AiServiceError(
            `API Error: ${response.status} - ${error.message}`,
            "API_ERROR",
            false
          );
        }

        const data = await response.json();
        return {
          data,
          model: currentModel,
          retries: totalRetries,
          fallbackUsed: currentModel !== originalModel,
        };
      } catch (error) {
        totalRetries++;

        // Timeout 錯誤
        if (error instanceof Error && error.name === "AbortError") {
          console.log(
            `${currentModel} attempt ${attempt} timeout after ${opts.timeout}ms`
          );
        } else if (error instanceof AiServiceError) {
          console.log(`${currentModel} attempt ${attempt}: ${error.message}`);
          if (!error.retryable) {
            throw error;
          }
        } else {
          console.log(
            `${currentModel} attempt ${attempt} failed:`,
            (error as Error).message
          );
        }

        if (attempt === opts.maxRetries) {
          // 嘗試降級到下一個模型
          const nextModel = MODEL_FALLBACK_CHAIN[currentModel];
          if (nextModel) {
            console.log(`Falling back from ${currentModel} to ${nextModel}`);
            currentModel = nextModel;
            break;
          } else {
            // 沒有更多模型可以降級
            throw new AiServiceError(
              "AI 服務暫時無法使用，請稍後再試",
              "ALL_MODELS_FAILED",
              false
            );
          }
        }

        // 等待後重試 (exponential backoff)
        const delay = Math.min(1000 * Math.pow(2, attempt - 1), 5000);
        await new Promise((resolve) => setTimeout(resolve, delay));
      }
    }
  }

  // 不應該到這裡
  throw new AiServiceError(
    "AI 服務無法回應",
    "UNEXPECTED_ERROR",
    false
  );
}
