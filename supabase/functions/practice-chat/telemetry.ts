// practice-chat generation telemetry privacy boundary.
//
// This module deliberately returns a fixed scalar-only shape. Do not add
// transcript, prompt, model response, partner/profile text, or raw errors here.
// promptChars is an aggregate count only; failureClass is a stable bucket.

export type PracticeGenerationMode = "hint" | "debrief";
export type TelemetryPracticeMode = "standard" | "beginner" | "game";

export const PRACTICE_GENERATION_FAILURE_CLASSES = [
  "timeout",
  "visible_text_guard",
  "invalid_json",
  "schema_invalid",
  "provider_error",
  "unknown",
] as const;

export type PracticeGenerationFailureClass =
  typeof PRACTICE_GENERATION_FAILURE_CLASSES[number];

export interface PracticeGenerationTelemetryInput {
  mode: PracticeGenerationMode;
  practiceMode: TelemetryPracticeMode;
  attempt?: number | null;
  attemptDurationMs?: number | null;
  failureClass?: PracticeGenerationFailureClass | null;
  fallbackUsed?: boolean;
  failoverUsed?: boolean;
  totalDurationMs?: number | null;
  promptChars: number;
}

export interface PracticeGenerationTelemetry {
  mode: PracticeGenerationMode | "unknown";
  practiceMode: TelemetryPracticeMode | "unknown";
  attempt: number | null;
  attemptDurationMs: number | null;
  failureClass: PracticeGenerationFailureClass | null;
  fallbackUsed: boolean;
  failoverUsed: boolean;
  totalDurationMs: number | null;
  promptChars: number;
}

export interface PracticeAiLogRow {
  user_id: string;
  model: string;
  request_type: string;
  input_tokens: 0;
  output_tokens: 0;
  latency_ms: number;
  status: "success" | "failed";
  error_code: PracticeGenerationFailureClass | null;
  fallback_used: boolean;
  retry_count: number;
  request_body: PracticeGenerationTelemetry & {
    attemptDurationsMs: number[];
    failureClasses: PracticeGenerationFailureClass[];
  };
  response_body: null;
  error_message: null;
}

const FAILURE_CLASS_SET = new Set<string>(
  PRACTICE_GENERATION_FAILURE_CLASSES,
);

function normalizeMode(value: unknown): PracticeGenerationMode | "unknown" {
  return value === "hint" || value === "debrief" ? value : "unknown";
}

function normalizePracticeMode(
  value: unknown,
): TelemetryPracticeMode | "unknown" {
  return value === "standard" || value === "beginner" || value === "game"
    ? value
    : "unknown";
}

function normalizeOptionalCount(value: unknown, minimum = 0): number | null {
  if (
    typeof value !== "number" || !Number.isFinite(value) || value < minimum
  ) {
    return null;
  }
  return Math.min(Math.floor(value), Number.MAX_SAFE_INTEGER);
}

function normalizeFailureClass(
  value: unknown,
): PracticeGenerationFailureClass | null {
  if (value == null) return null;
  return typeof value === "string" && FAILURE_CLASS_SET.has(value)
    ? value as PracticeGenerationFailureClass
    : "unknown";
}

/**
 * Build the only allowed generation telemetry payload.
 *
 * Every property is picked explicitly instead of spreading input. This is a
 * runtime privacy guard as well as a TypeScript contract: accidental extra
 * properties such as transcript/response/raw error are discarded.
 */
export function buildPracticeGenerationTelemetry(
  input: PracticeGenerationTelemetryInput,
): PracticeGenerationTelemetry {
  const raw = input as unknown as Record<string, unknown>;
  return {
    mode: normalizeMode(raw.mode),
    practiceMode: normalizePracticeMode(raw.practiceMode),
    attempt: normalizeOptionalCount(raw.attempt, 1),
    attemptDurationMs: normalizeOptionalCount(raw.attemptDurationMs),
    failureClass: normalizeFailureClass(raw.failureClass),
    fallbackUsed: raw.fallbackUsed === true,
    failoverUsed: raw.failoverUsed === true,
    totalDurationMs: normalizeOptionalCount(raw.totalDurationMs),
    promptChars: normalizeOptionalCount(raw.promptChars) ?? 0,
  };
}

/** Count prompt size without retaining or returning any prompt content. */
export function countPromptChars(
  messages: ReadonlyArray<{ readonly content: string }>,
): number {
  let total = 0;
  for (const message of messages) {
    total = Math.min(
      total + message.content.length,
      Number.MAX_SAFE_INTEGER,
    );
  }
  return total;
}

function normalizeCountList(values: readonly unknown[]): number[] {
  return values
    .map((value) => normalizeOptionalCount(value))
    .filter((value): value is number => value !== null)
    .slice(0, 3);
}

function normalizeFailureList(
  values: readonly unknown[],
): PracticeGenerationFailureClass[] {
  return values
    .map(normalizeFailureClass)
    .filter((value): value is PracticeGenerationFailureClass => value !== null)
    .slice(0, 3);
}

/**
 * Build one durable ai_logs outcome row. DeepSeek usage is not exposed by the
 * current caller, so token fields stay explicit zero rather than fake estimates.
 */
export function buildPracticeAiLogRow(input: {
  userId: string;
  model: string;
  telemetry: PracticeGenerationTelemetryInput;
  attemptDurationsMs: readonly unknown[];
  failureClasses: readonly unknown[];
}): PracticeAiLogRow {
  const telemetry = buildPracticeGenerationTelemetry(input.telemetry);
  const attempt = telemetry.attempt ?? 1;
  const failed = telemetry.fallbackUsed || telemetry.failureClass !== null;
  return {
    user_id: input.userId,
    model: input.model,
    request_type: `practice_${telemetry.mode}_${telemetry.practiceMode}`,
    input_tokens: 0,
    output_tokens: 0,
    latency_ms: telemetry.totalDurationMs ?? 0,
    status: failed ? "failed" : "success",
    error_code: failed ? telemetry.failureClass ?? "unknown" : null,
    fallback_used: telemetry.fallbackUsed,
    retry_count: Math.max(0, attempt - 1),
    request_body: {
      ...telemetry,
      attemptDurationsMs: normalizeCountList(input.attemptDurationsMs),
      failureClasses: normalizeFailureList(input.failureClasses),
    },
    response_body: null,
    error_message: null,
  };
}

/** Convert raw generation errors into queryable classes without echoing text. */
export function classifyPracticeGenerationFailure(
  error: unknown,
): PracticeGenerationFailureClass {
  const message = error instanceof Error
    ? error.message.toLowerCase()
    : typeof error === "string"
    ? error.toLowerCase()
    : "";

  if (
    message.includes("timeout") || message.includes("timed out") ||
    message.includes("aborterror")
  ) {
    return "timeout";
  }

  if (
    message.includes("_l4_unsafe") ||
    message.includes("_internal_label_leak") ||
    message.includes("_temperature_leak") ||
    message.includes("_canned_visible_text") ||
    message.includes("bossy_pasteable_reply")
  ) {
    return "visible_text_guard";
  }

  if (
    error instanceof SyntaxError || message.includes("unexpected token") ||
    message.includes("invalid json") || message.includes("json_parse") ||
    message.includes("unterminated string")
  ) {
    return "invalid_json";
  }

  if (
    /^(?:hint|debrief)_(?:missing|invalid|not_object|extra_keys|game_breakdown_missing)/
      .test(message) ||
    message.includes("_must_be_string") ||
    message.includes("quality_invalid") ||
    message.includes("debrief_hint_") ||
    message.includes("schema_invalid")
  ) {
    return "schema_invalid";
  }

  if (
    message.includes("deepseek_") || message.includes("claude_") ||
    message.includes("network") ||
    message.includes("fetch failed") || message.includes("connection") ||
    message.includes("socket") || message.includes("econn")
  ) {
    return "provider_error";
  }

  return "unknown";
}
