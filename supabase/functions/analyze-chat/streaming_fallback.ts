// Anthropic streaming wrapper for analyze-chat.
//
// This mirrors fallback.ts request headers and prompt caching, but asks Claude
// for SSE streaming output and exposes only text deltas to the caller.

type ClaudeMessageContent =
  | string
  | Array<{
    type: string;
    text?: string;
    source?: { type: string; media_type: string; data: string };
  }>;

export interface ClaudeStreamingRequest {
  model: string;
  max_tokens: number;
  system: string;
  messages: Array<{ role: string; content: ClaudeMessageContent }>;
  thinking?: { type: "disabled" };
}

export interface ClaudeStreamingOptions {
  timeout: number;
  fetchImpl: (input: string, init?: RequestInit) => Promise<Response>;
}

export interface StreamingClaudeResult {
  model: string;
  textStream: AsyncGenerator<string>;
  usage: ClaudeStreamTokenUsage;
}

export interface ClaudeStreamTokenUsage {
  inputTokens: number;
  outputTokens: number;
  cacheCreationTokens: number;
  cacheReadTokens: number;
}

export interface AiStreamingServiceErrorMetadata {
  status?: number;
  timeoutMs?: number;
}

export class AiStreamingServiceError extends Error {
  constructor(
    message: string,
    public readonly code: string,
    public readonly retryable: boolean = false,
    public readonly metadata: AiStreamingServiceErrorMetadata = {},
  ) {
    super(message);
    this.name = "AiStreamingServiceError";
  }
}

const DEFAULT_OPTIONS: ClaudeStreamingOptions = {
  timeout: 30000,
  fetchImpl: fetch,
};

const SONNET_5_MODEL = "claude-sonnet-5";
const MODEL_FALLBACK_CHAIN: Readonly<Record<string, string | undefined>> = {
  [SONNET_5_MODEL]: "claude-sonnet-4-6",
  "claude-sonnet-4-6": "claude-haiku-4-5-20251001",
};
const PRE_STREAM_FALLBACK_CODES = new Set([
  "NETWORK_ERROR",
  "RATE_LIMITED",
  "SERVER_ERROR",
  "EMPTY_STREAM",
]);

function buildCachedSystemPrompt(systemPrompt: string) {
  return [
    {
      type: "text",
      text: systemPrompt,
      cache_control: { type: "ephemeral" },
    },
  ];
}

function isAbortError(error: unknown): boolean {
  return error instanceof Error && error.name === "AbortError";
}

function resolveThinkingContract(
  originalModel: string,
  currentModel: string,
  callerThinking?: { type: "disabled" },
): { type: "disabled" } | undefined {
  // A thinking choice made for the primary model is not portable across the
  // fallback chain. Sonnet 5 needs the endpoint's fixed visible-output budget,
  // while 4.6 and Haiku should receive their native request contract.
  if (currentModel !== originalModel) return undefined;
  if (callerThinking) return callerThinking;
  return currentModel === SONNET_5_MODEL ? { type: "disabled" } : undefined;
}

function preStreamFetchError(
  error: unknown,
  signal: AbortSignal,
  timeoutMs: number,
): AiStreamingServiceError {
  if (signal.aborted || isAbortError(error)) {
    return new AiStreamingServiceError(
      "Claude streaming request timed out.",
      "TIMEOUT",
      true,
      { timeoutMs },
    );
  }
  return new AiStreamingServiceError(
    "AI streaming service could not be reached.",
    "NETWORK_ERROR",
    true,
  );
}

function httpResponseError(response: Response): AiStreamingServiceError {
  if (response.status === 429) {
    return new AiStreamingServiceError(
      "AI rate limited the request. Please try again shortly.",
      "RATE_LIMITED",
      true,
      { status: response.status },
    );
  }
  if (response.status >= 500) {
    return new AiStreamingServiceError(
      "AI service is temporarily unavailable.",
      "SERVER_ERROR",
      true,
      { status: response.status },
    );
  }
  return new AiStreamingServiceError(
    "AI streaming request was rejected.",
    "API_ERROR",
    false,
    { status: response.status },
  );
}

function nextFallbackModel(
  currentModel: string,
  error: AiStreamingServiceError,
): string | undefined {
  if (!PRE_STREAM_FALLBACK_CODES.has(error.code)) return undefined;
  return MODEL_FALLBACK_CHAIN[currentModel];
}

function streamProviderFailure(errorType: unknown): AiStreamingServiceError {
  if (errorType === "overloaded_error") {
    return new AiStreamingServiceError(
      "AI streaming service is temporarily overloaded.",
      "STREAM_OVERLOADED",
      true,
    );
  }
  return new AiStreamingServiceError(
    "AI streaming service reported an error.",
    "STREAM_PROVIDER_ERROR",
    false,
  );
}

function terminalStopFailure(
  stopReason: unknown,
): AiStreamingServiceError | undefined {
  switch (stopReason) {
    case "max_tokens":
      return new AiStreamingServiceError(
        "AI streaming output reached its token limit.",
        "STREAM_MAX_TOKENS",
        true,
      );
    case "model_context_window_exceeded":
      return new AiStreamingServiceError(
        "AI streaming request exceeded the model context window.",
        "STREAM_CONTEXT_WINDOW_EXCEEDED",
        false,
      );
    case "refusal":
      return new AiStreamingServiceError(
        "AI declined to generate this response.",
        "STREAM_MODEL_REFUSAL",
        false,
      );
    default:
      return undefined;
  }
}

function extractStreamEvent(dataLines: string[]): {
  done: boolean;
  text?: string;
  usage?: Partial<ClaudeStreamTokenUsage>;
  failure?: AiStreamingServiceError;
} {
  const data = dataLines.join("\n").trim();
  if (!data || data === "[DONE]") {
    return { done: data === "[DONE]" };
  }

  let parsed: {
    type?: string;
    delta?: { type?: string; text?: string; stop_reason?: unknown };
    error?: { type?: unknown; message?: unknown };
    message?: {
      usage?: {
        input_tokens?: number;
        output_tokens?: number;
        cache_creation_input_tokens?: number;
        cache_read_input_tokens?: number;
      };
    };
    usage?: {
      input_tokens?: number;
      output_tokens?: number;
      cache_creation_input_tokens?: number;
      cache_read_input_tokens?: number;
    };
  };
  try {
    parsed = JSON.parse(data);
  } catch {
    throw new AiStreamingServiceError(
      "AI streaming response could not be parsed.",
      "STREAM_PARSE_ERROR",
      false,
    );
  }

  if (
    parsed.type === "content_block_delta" &&
    parsed.delta?.type === "text_delta" &&
    typeof parsed.delta.text === "string"
  ) {
    return { done: false, text: parsed.delta.text };
  }

  if (parsed.type === "error") {
    return {
      done: false,
      failure: streamProviderFailure(parsed.error?.type),
    };
  }

  const rawUsage = parsed.type === "message_start"
    ? parsed.message?.usage
    : parsed.type === "message_delta"
    ? parsed.usage
    : undefined;
  let usage: Partial<ClaudeStreamTokenUsage> | undefined;
  if (rawUsage) {
    usage = {};
    if (Number.isFinite(rawUsage.input_tokens)) {
      usage.inputTokens = Math.max(0, rawUsage.input_tokens ?? 0);
    }
    if (Number.isFinite(rawUsage.output_tokens)) {
      usage.outputTokens = Math.max(0, rawUsage.output_tokens ?? 0);
    }
    if (Number.isFinite(rawUsage.cache_creation_input_tokens)) {
      usage.cacheCreationTokens = Math.max(
        0,
        rawUsage.cache_creation_input_tokens ?? 0,
      );
    }
    if (Number.isFinite(rawUsage.cache_read_input_tokens)) {
      usage.cacheReadTokens = Math.max(
        0,
        rawUsage.cache_read_input_tokens ?? 0,
      );
    }
  }

  const failure = parsed.type === "message_delta"
    ? terminalStopFailure(parsed.delta?.stop_reason)
    : undefined;
  if (usage || failure) return { done: false, usage, failure };

  return { done: false };
}

export async function* parseAnthropicSse(
  readable: ReadableStream<Uint8Array>,
  usage: ClaudeStreamTokenUsage = {
    inputTokens: 0,
    outputTokens: 0,
    cacheCreationTokens: 0,
    cacheReadTokens: 0,
  },
): AsyncGenerator<string> {
  const reader = readable.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let dataLines: string[] = [];

  async function* dispatch(): AsyncGenerator<string> {
    if (dataLines.length === 0) {
      return;
    }
    const event = extractStreamEvent(dataLines);
    dataLines = [];
    if (event.done) {
      return;
    }
    if (event.usage) Object.assign(usage, event.usage);
    if (event.failure) throw event.failure;
    if (event.text !== undefined) {
      yield event.text;
    }
  }

  function normalizeLine(line: string): string {
    return line.endsWith("\r") ? line.slice(0, -1) : line;
  }

  try {
    while (true) {
      const { value, done } = await reader.read();
      buffer += decoder.decode(value, { stream: !done });

      let newlineIndex = buffer.indexOf("\n");
      while (newlineIndex >= 0) {
        const line = normalizeLine(buffer.slice(0, newlineIndex));
        buffer = buffer.slice(newlineIndex + 1);

        if (line === "") {
          for await (const text of dispatch()) {
            yield text;
          }
        } else if (line.startsWith("data:")) {
          dataLines.push(line.slice(5).trimStart());
        }

        newlineIndex = buffer.indexOf("\n");
      }

      if (done) {
        break;
      }
    }

    if (buffer.length > 0) {
      const line = normalizeLine(buffer);
      if (line.startsWith("data:")) {
        dataLines.push(line.slice(5).trimStart());
      }
    }

    for await (const text of dispatch()) {
      yield text;
    }
  } finally {
    reader.releaseLock();
  }
}

async function* cleanupOnStreamEnd(
  source: AsyncGenerator<string>,
  cleanup: () => void,
  timeoutMs: number,
): AsyncGenerator<string> {
  try {
    for await (const text of source) {
      yield text;
    }
  } catch (error) {
    if (error instanceof AiStreamingServiceError) throw error;
    if (isAbortError(error)) {
      throw new AiStreamingServiceError(
        "Claude streaming request timed out.",
        "TIMEOUT",
        true,
        { timeoutMs },
      );
    }
    throw new AiStreamingServiceError(
      "AI streaming connection was interrupted.",
      "STREAM_CONNECTION_ERROR",
      true,
    );
  } finally {
    cleanup();
  }
}

export async function callClaudeStreaming(
  request: ClaudeStreamingRequest,
  apiKey: string,
  options: Partial<ClaudeStreamingOptions> = {},
): Promise<StreamingClaudeResult> {
  const opts = { ...DEFAULT_OPTIONS, ...options };
  const originalModel = request.model;
  let currentModel: string | undefined = originalModel;
  const deadline = Date.now() + opts.timeout;

  while (currentModel) {
    const remainingMs = deadline - Date.now();
    if (remainingMs <= 0) {
      throw new AiStreamingServiceError(
        "Claude streaming request timed out.",
        "TIMEOUT",
        true,
        { timeoutMs: opts.timeout },
      );
    }
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), remainingMs);
    const thinking = resolveThinkingContract(
      originalModel,
      currentModel,
      request.thinking,
    );

    let response: Response;
    try {
      response = await opts.fetchImpl("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-api-key": apiKey,
          "anthropic-version": "2023-06-01",
          "anthropic-beta": "prompt-caching-2024-07-31",
        },
        body: JSON.stringify({
          model: currentModel,
          max_tokens: request.max_tokens,
          system: buildCachedSystemPrompt(request.system),
          messages: request.messages,
          stream: true,
          ...(thinking ? { thinking } : {}),
        }),
        signal: controller.signal,
      });
    } catch (error) {
      clearTimeout(timeoutId);
      const mapped = preStreamFetchError(
        error,
        controller.signal,
        opts.timeout,
      );
      const nextModel = nextFallbackModel(currentModel, mapped);
      if (nextModel) {
        currentModel = nextModel;
        continue;
      }
      throw mapped;
    }

    let preStreamError: AiStreamingServiceError | undefined;
    if (controller.signal.aborted || Date.now() >= deadline) {
      preStreamError = preStreamFetchError(
        new DOMException("aborted", "AbortError"),
        controller.signal,
        opts.timeout,
      );
    } else if (!response.ok) {
      preStreamError = httpResponseError(response);
    } else if (response.status !== 200) {
      preStreamError = httpResponseError(response);
    } else if (!response.body) {
      preStreamError = new AiStreamingServiceError(
        "Claude streaming response did not include a body.",
        "EMPTY_STREAM",
        true,
      );
    }

    if (preStreamError) {
      clearTimeout(timeoutId);
      if (response.body) {
        await response.body.cancel().catch(() => undefined);
      }
      const nextModel = nextFallbackModel(currentModel, preStreamError);
      if (nextModel) {
        currentModel = nextModel;
        continue;
      }
      throw preStreamError;
    }

    const usage: ClaudeStreamTokenUsage = {
      inputTokens: 0,
      outputTokens: 0,
      cacheCreationTokens: 0,
      cacheReadTokens: 0,
    };
    return {
      model: currentModel,
      textStream: cleanupOnStreamEnd(
        parseAnthropicSse(response.body!, usage),
        () => clearTimeout(timeoutId),
        opts.timeout,
      ),
      usage,
    };
  }

  throw new AiStreamingServiceError(
    "AI streaming service is temporarily unavailable.",
    "ALL_MODELS_FAILED",
    true,
  );
}
