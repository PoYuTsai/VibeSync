// supabase/functions/coach-follow-up/generation.ts
//
// T7 — pure pipeline helper that runs AFTER auth + quota gate (in index.ts).
// Splits the Claude-call / validate / safety / deduct flow out of index.ts so
// it stays unit-testable without a Supabase double (T5/T6 precedent — Codex
// has ACK'd "pure helper > mock Supabase").
//
// HARD ORDER (do not reshuffle without updating tests + telemetry contract):
//   parseClaudeJSON → truncateCard → validateResponseCard → assertCardSafe →
//   deductCredit → respond
//
// If ANY step before deductCredit throws, deductCredit MUST NOT fire — the user
// is not charged for a failed generation. This invariant is asserted by
// generation_test.ts: every error-path test verifies deductCalls.length === 0.
//
// Telemetry events emitted (design §7):
//   coach_follow_up_invoked    { phase, tier, hasOptionalText: bool }
//   coach_follow_up_succeeded  { phase, tier, model, latencyMs, costDeducted: 0|1 }
//   coach_follow_up_failed     { phase, tier, errorClass: string }
//
// Privacy (assertion is in T8 tests): the data field carries field shape only.
// NEVER include free-text answers, prompt content, or Claude raw response.

import {
  assertCardSafe,
  truncateCard,
  validateResponseCard,
} from "./validate.ts";
import { buildCoachFollowUpPrompt } from "./prompts.ts";
import { quotaExceededMessage } from "../_shared/quota.ts";
import type {
  CoachFollowUpRequest,
  CoachFollowUpResponseCard,
} from "./schemas.ts";

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

export interface GenerationLogger {
  info: (event: string, data?: Record<string, unknown>) => void;
  warn: (event: string, data?: Record<string, unknown>) => void;
}

export interface ClaudeCallArgs {
  model: string;
  prompt: string;
  maxTokens: number;
  timeoutMs: number;
  apiKey: string;
}

export interface GenerationDeps {
  callClaude: (args: ClaudeCallArgs) => Promise<unknown>;
  deductCredit: (input: { userId: string }) => Promise<void>;
  logger: GenerationLogger;
  /** Override for deterministic latency in tests; defaults to Date.now. */
  now?: () => number;
}

// Batch C#2 — deductCredit 重查（或 increment_usage 鎖內 RAISE）發現額度已被
// 並發請求吃掉時丟這個，讓 429 語義與 coach-chat 對齊，而非 500
// credit_deduct_failed（結構同 CoachChatQuotaExceededError；跨函式不互 import，
// OCR isolation 慣例）。
export class CoachFollowUpQuotaExceededError extends Error {
  constructor(
    readonly reason: "monthly_limit_exceeded" | "daily_limit_exceeded",
    readonly used: number,
    readonly limit: number,
  ) {
    super(reason);
    this.name = "CoachFollowUpQuotaExceededError";
  }
}

export interface GenerationInput {
  userId: string;
  phase: CoachFollowUpRequest["phase"];
  answers: CoachFollowUpRequest["answers"];
  partnerHint?: CoachFollowUpRequest["partnerHint"];
  styleContext?: CoachFollowUpRequest["styleContext"];
  tier: "free" | "starter" | "essential";
  accountIsTest: boolean;
  apiKey: string;
}

export interface GenerationResult {
  status: number;
  body: Record<string, unknown>;
}

// ---------------------------------------------------------------------------
// Pipeline
// ---------------------------------------------------------------------------

export async function runCoachFollowUp(
  input: GenerationInput,
  deps: GenerationDeps,
): Promise<GenerationResult> {
  const now = deps.now ?? (() => Date.now());
  const startedAt = now();

  const model = input.tier === "free"
    ? "claude-haiku-4-5-20251001"
    : "claude-sonnet-4-6";

  const prompt = buildCoachFollowUpPrompt(
    input.phase,
    input.answers,
    input.partnerHint ?? { name: "" },
    input.styleContext,
  );

  // Telemetry: phase + tier + a boolean flag for q3 presence — never the value.
  deps.logger.info("coach_follow_up_invoked", {
    phase: input.phase,
    tier: input.tier,
    hasOptionalText: !!(input.answers.q3 && input.answers.q3.length > 0),
  });

  let claudeData: unknown;
  try {
    claudeData = await deps.callClaude({
      model,
      prompt,
      maxTokens: 1024,
      timeoutMs: 60000,
      apiKey: input.apiKey,
    });
  } catch (e) {
    deps.logger.warn("coach_follow_up_failed", {
      phase: input.phase,
      tier: input.tier,
      errorClass: classifyClaudeError(e),
    });
    return {
      status: 500,
      body: { error: `AI 生成失敗：${getErrorMessage(e)}` },
    };
  }

  let card: CoachFollowUpResponseCard;
  try {
    const parsed = parseClaudeJSON(claudeData);
    const truncated = truncateCard(parsed);
    card = validateResponseCard(truncated);
    assertCardSafe(card);
  } catch (e) {
    const errorClass = getErrorMessage(e).startsWith("banned_token")
      ? "banned_token"
      : "schema_invalid";
    deps.logger.warn("coach_follow_up_failed", {
      phase: input.phase,
      tier: input.tier,
      errorClass,
    });
    return { status: 500, body: { error: errorClass } };
  }

  // Deduct ONLY after BOTH schema and safety validation pass — and ONLY if not
  // a test account. Plan §A7 step 3: "If any step fails, NO deduct."
  //
  // Codex P1 (post-T7): Supabase update returning {error} doesn't throw, so
  // the wrapper in index.ts MUST check {error} and throw "credit_deduct_failed".
  // We catch here, emit the stable bucket, and 500 — never silently 200 a
  // generation the user wasn't actually charged for.
  if (!input.accountIsTest) {
    try {
      await deps.deductCredit({ userId: input.userId });
    } catch (e) {
      if (e instanceof CoachFollowUpQuotaExceededError) {
        deps.logger.warn("coach_follow_up_failed", {
          phase: input.phase,
          tier: input.tier,
          errorClass: e.reason,
        });
        return {
          status: 429,
          body: {
            error: e.reason === "monthly_limit_exceeded"
              ? "Monthly limit exceeded"
              : "Daily limit exceeded",
            message: quotaExceededMessage(e.reason),
            quotaNeeded: 1,
            used: e.used,
            limit: e.limit,
          },
        };
      }
      deps.logger.warn("coach_follow_up_failed", {
        phase: input.phase,
        tier: input.tier,
        errorClass: "credit_deduct_failed",
      });
      // Suppress raw error message; user gets the stable bucket name. The
      // detailed error is intentionally unused — log and response stay clean.
      void e;
      return { status: 500, body: { error: "credit_deduct_failed" } };
    }
  }

  deps.logger.info("coach_follow_up_succeeded", {
    phase: input.phase,
    tier: input.tier,
    model,
    latencyMs: now() - startedAt,
    costDeducted: input.accountIsTest ? 0 : 1,
  });

  return {
    status: 200,
    body: {
      phase: input.phase,
      card,
      model,
      generatedAt: new Date(now()).toISOString(),
    },
  };
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

function getErrorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (typeof error === "string") return error;
  return "unknown_error";
}

/**
 * Classify upstream Claude errors into stable telemetry buckets. Free-text
 * messages NEVER reach the log — only the bucket name.
 */
function classifyClaudeError(error: unknown): string {
  const msg = getErrorMessage(error).toLowerCase();
  if (msg.includes("timeout") || msg.includes("aborted")) {
    return "claude_timeout";
  }
  if (msg.includes("rate") && msg.includes("limit")) return "claude_rate_limit";
  if (msg.includes("network") || msg.includes("fetch failed")) {
    return "claude_network";
  }
  return "claude_unknown";
}

/**
 * Extract the JSON card from Claude's `{content:[{text:"..."}]}` envelope.
 * Throws "schema_invalid" so the caller tags telemetry consistently with the
 * downstream zod validation path.
 */
function parseClaudeJSON(
  claudeData: unknown,
): Record<string, string | null | undefined> {
  if (!claudeData || typeof claudeData !== "object") {
    throw new Error("schema_invalid: claude returned non-object");
  }
  const data = claudeData as { content?: Array<{ text?: string }> };
  const rawText = data.content?.[0]?.text ?? "";
  const jsonMatch = rawText.match(/\{[\s\S]*\}/);
  if (!jsonMatch) {
    throw new Error("schema_invalid: no JSON found in claude response");
  }
  try {
    const parsed = JSON.parse(jsonMatch[0]);
    if (!parsed || typeof parsed !== "object") {
      throw new Error("schema_invalid: claude JSON is not an object");
    }
    return parsed;
  } catch (e) {
    if (e instanceof Error && e.message.startsWith("schema_invalid")) throw e;
    throw new Error("schema_invalid: malformed JSON in claude response");
  }
}

// ---------------------------------------------------------------------------
// Real Claude HTTP client (used by index.ts orchestrator; not exercised by
// generation_test.ts because tests inject a fake callClaude).
// ---------------------------------------------------------------------------

export async function callClaudeAPI(args: ClaudeCallArgs): Promise<unknown> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), args.timeoutMs);
  try {
    const res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": args.apiKey,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: args.model,
        max_tokens: args.maxTokens,
        messages: [{ role: "user", content: args.prompt }],
      }),
      signal: controller.signal,
    });
    if (!res.ok) {
      const body = await res.text().catch(() => "");
      throw new Error(`claude_http_${res.status}: ${body.slice(0, 200)}`);
    }
    return await res.json();
  } finally {
    clearTimeout(timeout);
  }
}
