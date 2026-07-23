// practice-chat generation telemetry privacy boundary.
//
// This module deliberately returns a fixed scalar-only shape. Do not add
// transcript, prompt, model response, partner/profile text, or raw errors here.
// promptChars is an aggregate count only; failureClass is a stable bucket.
// failureCodes are machine codes only: each entry is the first token of an
// error message, hard-limited to [a-z0-9_:.-] after lowercasing, so user or
// model text can never leak through this field.

export type PracticeGenerationMode = "hint" | "debrief";
export type TelemetryPracticeMode = "standard" | "beginner" | "game";

export const PRACTICE_GENERATION_FAILURE_CLASSES = [
  "timeout",
  "visible_text_guard",
  "invalid_json",
  "schema_invalid",
  "semantic_rejected",
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
  semanticProviderCalls?: number | null;
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
  semanticProviderCalls: number | null;
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
    failureCodes: string[];
    /** 管線世代標記；single_shot_v2 起帶，舊 row 沒有此鍵。 */
    pipeline?: string;
  };
  // 失敗列且帶被打回候選時才有值（診斷 gate TP/FP 用，2026-07-23 起）；
  // 其餘一律 null。
  response_body:
    | { rejectedCandidates: PracticeRejectedCandidate[] }
    | null;
  // 失敗列才有值，且只由 sanitizePracticeFailureCode 白名單機器碼與
  // failureClass 分類詞組成——絕不含使用者逐字稿或模型輸出。
  error_message: string | null;
}

export interface PracticeRejectedCandidate {
  model: string;
  code: string;
  raw: string;
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
    semanticProviderCalls: normalizeOptionalCount(raw.semanticProviderCalls),
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

const FAILURE_CODE_MAX_LENGTH = 120;

// 已知的機器碼前綴：claude.ts / deepseek.ts / hint.ts / debrief_card.ts /
// practice_persona.ts / validate.ts 的實際 throw 前綴，加上
// classifyPracticeGenerationFailure 的分類詞彙（schema_/timeout/provider_/
// visible_）與 hint_fact_ledger.ts 的 unsupported_detail 家族，供未來
// 直接以子碼（不掛 hint_/debrief_ 字首）拋出時仍收得到。charset 白名單只防
// 夾帶用戶/模型文字，前綴白名單才是「這是設計過的機器碼」的正面判準——
// 呼叫點以外新冒出的自訂碼一律落 null 丟棄，不落盤。
const KNOWN_PRACTICE_FAILURE_CODE_PREFIXES = [
  "claude_",
  "deepseek_",
  "hint_",
  "debrief_",
  "invalid_",
  "practice_",
  "unsupported_",
  "schema_",
  "timeout_",
  "provider_",
  "visible_",
  "semantic_",
] as const;

function hasKnownPracticeFailureCodePrefix(token: string): boolean {
  if (token === "timeout") return true;
  return KNOWN_PRACTICE_FAILURE_CODE_PREFIXES.some((prefix) =>
    token.startsWith(prefix)
  );
}

/**
 * Reduce a raw generation error to a queryable machine code without ever
 * echoing user or model text: keep only the first whitespace-delimited token
 * of the message, truncated, and drop it entirely unless the token passes the
 * [a-z0-9_:.-] whitelist after lowercasing AND starts with a known machine-code
 * prefix. The charset whitelist alone only blocked stray user/model text that
 * happened to look like one token; the prefix whitelist is the actual
 * allowlist of designed codes.
 */
export function sanitizePracticeFailureCode(error: unknown): string | null {
  const message = error instanceof Error
    ? error.message
    : typeof error === "string"
    ? error
    : "";
  const token = (message.trim().split(/\s+/u)[0] ?? "")
    .slice(0, FAILURE_CODE_MAX_LENGTH)
    .toLowerCase();
  if (!token || !/^[a-z0-9_:.-]+$/.test(token)) return null;
  if (!hasKnownPracticeFailureCodePrefix(token)) return null;
  return token;
}

function normalizeFailureCodeList(values: readonly unknown[]): string[] {
  return values
    .map(sanitizePracticeFailureCode)
    .filter((value): value is string => value !== null)
    .slice(0, 3);
}

const ERROR_MESSAGE_MAX_LENGTH = 300;

/**
 * Failed rows only: build ai_logs.error_message from the already-sanitized
 * machine codes (charset + known-prefix whitelist), falling back to the
 * coarse failure class so the column is never empty on a failed row. No raw
 * error text ever flows through here, so transcripts/model output cannot leak.
 */
function buildPracticeErrorMessage(
  failureCodes: readonly string[],
  fallbackClass: PracticeGenerationFailureClass,
): string {
  const joined = failureCodes.join("; ");
  return (joined || fallbackClass).slice(0, ERROR_MESSAGE_MAX_LENGTH);
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
  failureCodes?: readonly unknown[];
  /** 管線世代標記（如 "single_shot_v2"），供 ai_logs 新舊對比查詢。 */
  pipeline?: string;
  /**
   * 被 gate 打回的候選（真機 gh6 觀測缺口，2026-07-23）：failed row 落進
   * response_body 供 TP/FP 判定；transport 失敗沒有 raw 不落。error_message
   * 消毒鏈不經過這裡，不受影響。
   */
  rejectedCandidates?: readonly {
    model?: unknown;
    code?: unknown;
    raw?: unknown;
  }[];
}): PracticeAiLogRow {
  const telemetry = buildPracticeGenerationTelemetry(input.telemetry);
  const attempt = telemetry.attempt ?? 1;
  const failed = telemetry.fallbackUsed || telemetry.failureClass !== null;
  const failureCodes = normalizeFailureCodeList(input.failureCodes ?? []);
  const errorCode = failed ? telemetry.failureClass ?? "unknown" : null;
  return {
    user_id: input.userId,
    model: input.model,
    request_type: `practice_${telemetry.mode}_${telemetry.practiceMode}`,
    input_tokens: 0,
    output_tokens: 0,
    latency_ms: telemetry.totalDurationMs ?? 0,
    status: failed ? "failed" : "success",
    error_code: errorCode,
    fallback_used: telemetry.fallbackUsed,
    retry_count: Math.max(0, attempt - 1),
    request_body: {
      ...telemetry,
      attemptDurationsMs: normalizeCountList(input.attemptDurationsMs),
      failureClasses: normalizeFailureList(input.failureClasses),
      failureCodes,
      ...(typeof input.pipeline === "string" && input.pipeline.length > 0
        ? { pipeline: input.pipeline.slice(0, 40) }
        : {}),
    },
    response_body: failed
      ? normalizeRejectedCandidates(input.rejectedCandidates ?? [])
      : null,
    error_message: errorCode === null
      ? null
      : buildPracticeErrorMessage(failureCodes, errorCode),
  };
}

const REJECTED_CANDIDATE_MAX_COUNT = 4;
const REJECTED_CANDIDATE_RAW_MAX_LENGTH = 2000;

/** 只留帶 raw 的 gate 打回（transport 失敗沒有候選原文），截斷防巨列。 */
function normalizeRejectedCandidates(
  values: readonly { model?: unknown; code?: unknown; raw?: unknown }[],
): { rejectedCandidates: PracticeRejectedCandidate[] } | null {
  const candidates: PracticeRejectedCandidate[] = [];
  for (const value of values) {
    if (typeof value?.raw !== "string" || value.raw.length === 0) continue;
    candidates.push({
      model: typeof value.model === "string" ? value.model.slice(0, 60) : "",
      code: typeof value.code === "string" ? value.code.slice(0, 160) : "",
      raw: value.raw.slice(0, REJECTED_CANDIDATE_RAW_MAX_LENGTH),
    });
    if (candidates.length >= REJECTED_CANDIDATE_MAX_COUNT) break;
  }
  return candidates.length > 0 ? { rejectedCandidates: candidates } : null;
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
    message.includes("aborterror") || message.includes("deadline_exceeded")
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
    message.includes("unterminated string") ||
    message.includes("semantic_adjudication_invalid_json")
  ) {
    return "invalid_json";
  }

  if (
    message.includes("semantic_fact_verification_rejected") ||
    message.includes("semantic_hint_active_reply_question") ||
    message.includes("semantic_adjudication_rejected") ||
    message.includes("semantic_adjudication_fact_rejection")
  ) {
    return "semantic_rejected";
  }

  if (
    /^(?:hint|debrief)_(?:missing|invalid|not_object|extra_keys|game_breakdown_missing)/
      .test(message) ||
    message.includes("_must_be_string") ||
    message.includes("quality_invalid") ||
    message.includes("debrief_hint_") ||
    message.includes("schema_invalid") ||
    message.includes("semantic_adjudication_")
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
