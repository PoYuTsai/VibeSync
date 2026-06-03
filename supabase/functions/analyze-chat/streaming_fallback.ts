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
}

export interface ClaudeStreamingOptions {
  timeout: number;
  fetchImpl: (input: string, init?: RequestInit) => Promise<Response>;
}

export interface StreamingClaudeResult {
  model: string;
  textStream: AsyncGenerator<string>;
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

function parseErrorMessage(errorText: string): string {
  try {
    const parsed = JSON.parse(errorText) as {
      message?: string;
      error?: { message?: string };
    };
    return parsed.error?.message || parsed.message || errorText;
  } catch {
    return errorText;
  }
}

function extractTextDelta(dataLines: string[]): { done: boolean; text?: string } {
  const data = dataLines.join("\n").trim();
  if (!data || data === "[DONE]") {
    return { done: data === "[DONE]" };
  }

  let parsed: {
    type?: string;
    delta?: { type?: string; text?: string };
  };
  try {
    parsed = JSON.parse(data);
  } catch (error) {
    throw new AiStreamingServiceError(
      error instanceof Error
        ? `Failed to parse Claude stream event: ${error.message}`
        : "Failed to parse Claude stream event.",
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

  return { done: false };
}

export async function* parseAnthropicSse(
  readable: ReadableStream<Uint8Array>,
): AsyncGenerator<string> {
  const reader = readable.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let dataLines: string[] = [];

  async function* dispatch(): AsyncGenerator<string> {
    if (dataLines.length === 0) {
      return;
    }
    const event = extractTextDelta(dataLines);
    dataLines = [];
    if (event.done) {
      return;
    }
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
    if (isAbortError(error)) {
      throw new AiStreamingServiceError(
        "Claude streaming request timed out.",
        "TIMEOUT",
        true,
        { timeoutMs },
      );
    }
    throw error;
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
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), opts.timeout);

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
        model: request.model,
        max_tokens: request.max_tokens,
        system: buildCachedSystemPrompt(request.system),
        messages: request.messages,
        stream: true,
      }),
      signal: controller.signal,
    });
  } catch (error) {
    clearTimeout(timeoutId);
    if (isAbortError(error)) {
      throw new AiStreamingServiceError(
        "Claude streaming request timed out.",
        "TIMEOUT",
        true,
        { timeoutMs: opts.timeout },
      );
    }
    throw new AiStreamingServiceError(
      error instanceof Error ? error.message : "Claude streaming request failed.",
      "NETWORK_ERROR",
      true,
    );
  }

  if (!response.ok) {
    clearTimeout(timeoutId);
    const errorText = await response.text();
    const errorMessage = parseErrorMessage(errorText);
    if (response.status === 429) {
      throw new AiStreamingServiceError(
        "AI rate limited the request. Please try again shortly.",
        "RATE_LIMITED",
        true,
        { status: response.status },
      );
    }
    if (response.status >= 500) {
      throw new AiStreamingServiceError(
        "AI service is temporarily unavailable.",
        "SERVER_ERROR",
        true,
        { status: response.status },
      );
    }
    throw new AiStreamingServiceError(
      `API Error: ${response.status} - ${errorMessage}`,
      "API_ERROR",
      false,
      { status: response.status },
    );
  }

  if (!response.body) {
    clearTimeout(timeoutId);
    throw new AiStreamingServiceError(
      "Claude streaming response did not include a body.",
      "EMPTY_STREAM",
      false,
    );
  }

  return {
    model: request.model,
    textStream: cleanupOnStreamEnd(
      parseAnthropicSse(response.body),
      () => clearTimeout(timeoutId),
      opts.timeout,
    ),
  };
}
