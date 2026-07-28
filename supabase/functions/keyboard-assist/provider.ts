import type {
  KeyboardAssistMediaType,
  KeyboardAssistSpeakerOverride,
  KeyboardAssistV1Request,
} from "./contract.ts";
import { KEYBOARD_ASSIST_COMPILER_PROMPT } from "./compiler_prompt.ts";

export type KeyboardAssistImage = {
  bytes: Uint8Array;
  base64: string;
  mediaType: KeyboardAssistMediaType;
};

export type KeyboardAssistCompilerRequest = {
  image: KeyboardAssistImage;
  speakerOverride: KeyboardAssistSpeakerOverride;
  voice: KeyboardAssistV1Request["voice"];
  priorTurn: KeyboardAssistV1Request["priorTurn"];
  signal: AbortSignal;
  pipelineVersion: string;
};

export type KeyboardAssistCompiler = (
  request: KeyboardAssistCompilerRequest,
) => Promise<unknown>;

/// Why the model call failed, as a fixed token that is safe to log. The
/// message carries the same thing in prose, but nothing logs the message —
/// which is how "service_unavailable" ended up being everything we knew about
/// a request that had already spent fourteen seconds of model time.
export type KeyboardAssistProviderFailure =
  | "http_400"
  | "http_401"
  | "http_403"
  | "http_404"
  | "http_408"
  | "http_413"
  | "http_429"
  | "http_500"
  | "http_502"
  | "http_503"
  | "http_504"
  | "http_529"
  | "http_other"
  | "fetch_failed"
  | "response_not_json"
  | "stopped_max_tokens"
  | "stopped_refusal"
  | "stopped_other";

const OBSERVED_HTTP_STATUSES = new Set([
  400,
  401,
  403,
  404,
  408,
  413,
  429,
  500,
  502,
  503,
  504,
  529,
]);

function httpFailureToken(status: number): KeyboardAssistProviderFailure {
  return OBSERVED_HTTP_STATUSES.has(status)
    ? `http_${status}` as KeyboardAssistProviderFailure
    : "http_other";
}

export class KeyboardAssistProviderError extends Error {
  constructor(
    public readonly kind: "timeout" | "invalid_output" | "unavailable",
    message: string,
    public readonly failure?: KeyboardAssistProviderFailure,
  ) {
    super(message);
    this.name = "KeyboardAssistProviderError";
  }
}

type FetchLike = (
  input: string | URL | Request,
  init?: RequestInit,
) => Promise<Response>;

const COMPILER_OUTPUT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    conversationType: {
      type: "string",
      enum: ["chat", "group", "social_feed", "non_chat"],
    },
    suggestedMySide: { type: "string", enum: ["left", "right"] },
    sideConfidence: {
      type: "string",
      enum: ["high", "medium", "low"],
    },
    confidence: { type: "string", enum: ["high", "medium", "low"] },
    turnState: {
      type: "string",
      enum: ["reply_due", "optional_follow_up"],
    },
    cue: { type: "string" },
    uncertainty: {
      anyOf: [
        { type: "string" },
        { type: "null" },
      ],
    },
    messages: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          index: { type: "integer" },
          side: { type: "string", enum: ["left", "right"] },
          text: { type: "string" },
        },
        required: ["index", "side", "text"],
      },
    },
    candidates: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          strategy: {
            type: "string",
            enum: ["extend", "flirt", "humor"],
          },
          text: { type: "string" },
          why: { type: "string" },
          effect: { type: "string" },
          evidenceIndices: {
            type: "array",
            items: { type: "integer" },
          },
        },
        required: ["strategy", "text", "why", "effect", "evidenceIndices"],
      },
    },
  },
  required: [
    "conversationType",
    "suggestedMySide",
    "sideConfidence",
    "confidence",
    "turnState",
    "cue",
    "uncertainty",
    "messages",
    "candidates",
  ],
} as const;

function parseJsonObjectFromAnthropicEnvelope(value: unknown): unknown {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new KeyboardAssistProviderError(
      "invalid_output",
      "provider response is not an object",
    );
  }
  const envelope = value as {
    content?: Array<{ type?: string; text?: string }>;
    stop_reason?: string | null;
  };
  if (
    envelope.stop_reason === "max_tokens" ||
    envelope.stop_reason === "model_context_window_exceeded" ||
    envelope.stop_reason === "refusal"
  ) {
    throw new KeyboardAssistProviderError(
      "invalid_output",
      `provider stopped with ${envelope.stop_reason}`,
      envelope.stop_reason === "refusal"
        ? "stopped_refusal"
        : envelope.stop_reason === "max_tokens"
        ? "stopped_max_tokens"
        : "stopped_other",
    );
  }
  let raw = (envelope.content ?? [])
    .filter((block) => block.type === undefined || block.type === "text")
    .map((block) => block.text ?? "")
    .join("")
    .trim();
  raw = raw.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "").trim();
  try {
    const parsed: unknown = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error("not an object");
    }
    return parsed;
  } catch {
    throw new KeyboardAssistProviderError(
      "invalid_output",
      "provider did not return one JSON object",
    );
  }
}

function combinedSignal(parent: AbortSignal, timeoutMs: number): AbortSignal {
  return AbortSignal.any([parent, AbortSignal.timeout(timeoutMs)]);
}

/// Per-call wall clock. This is a cap on one HTTP call, not the request
/// budget: `phaseSignal` still clips it to whatever the phase deadline allows,
/// so raising it can never overrun `REQUEST_DEADLINE_MS`. The single call now
/// also writes each candidate's `why` and `effect`, which the removed judge
/// used to spend a second call on.
export const KEYBOARD_ASSIST_COMPILER_TIMEOUT_MS = 30_000;

export function createAnthropicKeyboardAssistProvider(input: {
  apiKey: string;
  compilerModel: string;
  fetchImpl?: FetchLike;
  compilerTimeoutMs?: number;
}): {
  compiler: KeyboardAssistCompiler;
} {
  if (!input.apiKey || !input.compilerModel) {
    throw new Error("keyboard assist provider config is incomplete");
  }
  const fetchImpl = input.fetchImpl ?? fetch;

  const call = async (
    body: Record<string, unknown>,
    parentSignal: AbortSignal,
    timeoutMs: number,
  ): Promise<unknown> => {
    let response: Response;
    try {
      response = await fetchImpl("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "x-api-key": input.apiKey,
          "anthropic-version": "2023-06-01",
          "content-type": "application/json",
        },
        body: JSON.stringify(body),
        signal: combinedSignal(parentSignal, timeoutMs),
      });
    } catch (error) {
      if (
        parentSignal.aborted ||
        error instanceof DOMException && error.name === "TimeoutError"
      ) {
        throw new KeyboardAssistProviderError(
          "timeout",
          "provider request timed out",
        );
      }
      // Deno's fetch resolves when the response headers arrive, so a
      // non-streaming call that fails here failed *after* the model had
      // already spent its time — a reset connection, not a rejected request.
      throw new KeyboardAssistProviderError(
        "unavailable",
        error instanceof Error ? error.message : String(error),
        "fetch_failed",
      );
    }
    if (!response.ok) {
      throw new KeyboardAssistProviderError(
        response.status === 408 || response.status === 504
          ? "timeout"
          : "unavailable",
        `provider returned HTTP ${response.status}`,
        httpFailureToken(response.status),
      );
    }
    const envelope = await response.json().catch(() => null);
    return parseJsonObjectFromAnthropicEnvelope(envelope);
  };

  return {
    compiler: (request) =>
      call(
        {
          model: input.compilerModel,
          max_tokens: 4000,
          // Sonnet 5 enables thinking by default and rejects every non-default
          // sampling parameter. Structured output, grounding and exactly-once
          // replay own consistency for this pipeline.
          ...(input.compilerModel === "claude-sonnet-5"
            ? { thinking: { type: "disabled" } }
            : { temperature: 0 }),
          output_config: {
            format: {
              type: "json_schema",
              schema: COMPILER_OUTPUT_SCHEMA,
            },
          },
          system: KEYBOARD_ASSIST_COMPILER_PROMPT,
          messages: [{
            role: "user",
            content: [
              {
                type: "image",
                source: {
                  type: "base64",
                  media_type: request.image.mediaType,
                  data: request.image.base64,
                },
              },
              {
                type: "text",
                text: JSON.stringify({
                  contractVersion: "keyboard-assist-compiler-v1",
                  speakerOverride: request.speakerOverride,
                  voice: request.voice,
                  // Never a source of facts: this only stops the next batch
                  // from repeating lines the user has already seen.
                  previouslyOffered: request.priorTurn?.offeredTexts ?? [],
                  previouslySent: request.priorTurn?.insertedText ?? null,
                }),
              },
            ],
          }],
        },
        request.signal,
        input.compilerTimeoutMs ?? KEYBOARD_ASSIST_COMPILER_TIMEOUT_MS,
      ),
  };
}
