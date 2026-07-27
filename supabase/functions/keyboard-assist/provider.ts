import type {
  KeyboardAssistMediaType,
  KeyboardAssistSpeakerOverride,
  KeyboardAssistV1Request,
} from "./contract.ts";
import { KEYBOARD_ASSIST_COMPILER_PROMPT } from "./compiler_prompt.ts";
import { KEYBOARD_ASSIST_JUDGE_PROMPT } from "./judge_prompt.ts";
import type { NormalizedKeyboardAssistCompilerOutput } from "./normalize.ts";

export type KeyboardAssistImage = {
  bytes: Uint8Array;
  base64: string;
  mediaType: KeyboardAssistMediaType;
};

export type KeyboardAssistCompilerRequest = {
  image: KeyboardAssistImage;
  speakerOverride: KeyboardAssistSpeakerOverride;
  voice: KeyboardAssistV1Request["voice"];
  signal: AbortSignal;
  pipelineVersion: string;
};

export type KeyboardAssistJudgeRequest = {
  conversation: NormalizedKeyboardAssistCompilerOutput;
  effectiveMySide: "left" | "right";
  voice: KeyboardAssistV1Request["voice"];
  signal: AbortSignal;
  pipelineVersion: string;
};

export type KeyboardAssistCompiler = (
  request: KeyboardAssistCompilerRequest,
) => Promise<unknown>;

export type KeyboardAssistJudge = (
  request: KeyboardAssistJudgeRequest,
) => Promise<unknown>;

export class KeyboardAssistProviderError extends Error {
  constructor(
    public readonly kind: "timeout" | "invalid_output" | "unavailable",
    message: string,
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
            enum: [
              "keep_pace",
              "build_connection",
              "move_forward",
              "clarify",
              "deescalate",
            ],
          },
          text: { type: "string" },
          evidenceIndices: {
            type: "array",
            items: { type: "integer" },
          },
        },
        required: ["strategy", "text", "evidenceIndices"],
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

const JUDGE_OUTPUT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    contractVersion: { type: "string", const: "keyboard-assist-v1" },
    status: { type: "string", const: "ready" },
    source: {
      type: "object",
      additionalProperties: false,
      properties: {
        scope: {
          type: "string",
          enum: ["screenshot_only", "screenshot_plus_global_voice"],
        },
        messageCount: { type: "integer" },
        confidence: { type: "string", enum: ["high", "medium", "low"] },
        sideConfidence: {
          type: "string",
          enum: ["high", "medium", "low"],
        },
      },
      required: [
        "scope",
        "messageCount",
        "confidence",
        "sideConfidence",
      ],
    },
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
    options: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          strategy: {
            type: "string",
            enum: [
              "keep_pace",
              "build_connection",
              "move_forward",
              "clarify",
              "deescalate",
            ],
          },
          text: { type: "string" },
          why: { type: "string" },
          effect: { type: "string" },
        },
        required: ["strategy", "text", "why", "effect"],
      },
    },
  },
  required: [
    "contractVersion",
    "status",
    "source",
    "turnState",
    "cue",
    "uncertainty",
    "options",
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

export function createAnthropicKeyboardAssistProvider(input: {
  apiKey: string;
  compilerModel: string;
  judgeModel: string;
  fetchImpl?: FetchLike;
  compilerTimeoutMs?: number;
  judgeTimeoutMs?: number;
}): {
  compiler: KeyboardAssistCompiler;
  judge: KeyboardAssistJudge;
} {
  if (!input.apiKey || !input.compilerModel || !input.judgeModel) {
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
      throw new KeyboardAssistProviderError(
        "unavailable",
        error instanceof Error ? error.message : String(error),
      );
    }
    if (!response.ok) {
      throw new KeyboardAssistProviderError(
        response.status === 408 || response.status === 504
          ? "timeout"
          : "unavailable",
        `provider returned HTTP ${response.status}`,
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
          // sampling parameter. Structured output, grounding, the text-only
          // judge, and exactly-once replay own consistency for this pipeline.
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
                }),
              },
            ],
          }],
        },
        request.signal,
        input.compilerTimeoutMs ?? 24_000,
      ),
    judge: (request) =>
      call(
        {
          model: input.judgeModel,
          max_tokens: 1200,
          // Keep this in lockstep with the compiler's Sonnet 5 wire contract.
          ...(input.judgeModel === "claude-sonnet-5"
            ? { thinking: { type: "disabled" } }
            : { temperature: 0 }),
          output_config: {
            format: {
              type: "json_schema",
              schema: JUDGE_OUTPUT_SCHEMA,
            },
          },
          system: KEYBOARD_ASSIST_JUDGE_PROMPT,
          messages: [{
            role: "user",
            content: JSON.stringify({
              contractVersion: "keyboard-assist-judge-v1",
              conversation: request.conversation,
              effectiveMySide: request.effectiveMySide,
              voice: request.voice,
            }),
          }],
        },
        request.signal,
        input.judgeTimeoutMs ?? 8_000,
      ),
  };
}
