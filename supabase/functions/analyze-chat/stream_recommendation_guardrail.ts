// supabase/functions/analyze-chat/stream_recommendation_guardrail.ts
//
// Charge-time validation for the first official streaming recommendation.
// Keep this narrow: it validates a single recommendation event before quota is
// charged. Full-result safety and product-quality checks still happen later.

import {
  isStreamStyle,
  type StreamEvent,
  type StreamStyle,
} from "./stream_events.ts";

export type StreamRecommendationGuardrailCode =
  | "STREAM_MALFORMED_RECOMMENDATION"
  | "STREAM_UNSAFE_RECOMMENDATION";

export type RecommendationValidation =
  | {
    ok: true;
    selectedStyle: StreamStyle;
    message: string;
    reason: string;
    quotedContext: string;
    warnings: string[];
    raw: StreamEvent | Record<string, unknown>;
  }
  | {
    ok: false;
    code: StreamRecommendationGuardrailCode;
    reason: string;
    warnings?: string[];
  };

export function validateDecisionChargeEvent(
  event: StreamEvent | Record<string, unknown>,
): RecommendationValidation {
  if (event.type !== "analysis.decision") {
    return {
      ok: false,
      code: "STREAM_MALFORMED_RECOMMENDATION",
      reason: "expected analysis.decision event",
    };
  }

  if (!isStreamStyle(event.selectedStyle)) {
    return {
      ok: false,
      code: "STREAM_MALFORMED_RECOMMENDATION",
      reason: "decision selectedStyle is required",
    };
  }

  const nextStepBody = textField(event.nextStepBody ?? event.nextStep);
  const doThis = textField(event.doThis);
  const avoidThis = textField(event.avoidThis);
  const message = nextStepBody || doThis;
  const reason = doThis || nextStepBody;

  if (!message || !reason) {
    return {
      ok: false,
      code: "STREAM_MALFORMED_RECOMMENDATION",
      reason: "decision nextStepBody or doThis is required",
    };
  }

  const modelAuthoredText = `${nextStepBody}\n${doThis}\n${avoidThis}`;
  if (
    hasPromptInjection(modelAuthoredText) ||
    hasUnsafeRecommendation(modelAuthoredText)
  ) {
    return {
      ok: false,
      code: "STREAM_UNSAFE_RECOMMENDATION",
      reason: "decision failed hard safety rules",
    };
  }

  return {
    ok: true,
    selectedStyle: event.selectedStyle,
    message,
    reason,
    quotedContext: textField(event.quotedContext) || "analysis.decision",
    warnings: [],
    raw: event,
  };
}

const PROMPT_INJECTION_PATTERNS = [
  /\bignore\s+(all\s+)?(previous|above|prior)\s+instructions?\b/i,
  /\bsystem\s+prompt\b/i,
  /\bdeveloper\s+message\b/i,
  /\bhidden\s+instructions?\b/i,
  /\breveal\b.*\b(prompt|instructions?|policy|rules?)\b/i,
  /\bprint\b.*\b(prompt|instructions?|policy|rules?)\b/i,
];

const UNSAFE_RECOMMENDATION_PATTERNS = [
  /\bfollow\s+(her|him|them)\b/i,
  /\bshow\s+up\b.*\b(home|work|office|school|class)\b/i,
  /\bpressure\b.*\b(reply|respond|answer|text)\b/i,
  /\buntil\s+(she|he|they)\s+(replies|responds|answers|texts)\b/i,
  /\bforce\s+(her|him|them)\b/i,
  /\bthreaten\b/i,
  /\bblackmail\b/i,
  /\bmake\s+(her|him|them)\s+jealous\b/i,
];

const BOUNDARY_CONTEXT_PATTERN =
  /\b(need|needs|want|wants|asked\s+for)\s+(space|time|distance)\b|\bdo\s+not\s+want\s+to\s+be\s+pushed\b|\bdon't\s+push\b/i;

const SOFT_PUSH_MESSAGE_PATTERN =
  /\bask\s+(one\s+more\s+time|again)\b|\btry\s+again\b|\bmessage\s+again\b|\btext\s+again\b/i;

function textField(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function hasPromptInjection(text: string): boolean {
  return PROMPT_INJECTION_PATTERNS.some((pattern) => pattern.test(text));
}

function hasUnsafeRecommendation(text: string): boolean {
  return UNSAFE_RECOMMENDATION_PATTERNS.some((pattern) => pattern.test(text));
}

function collectWarnings(message: string, quotedContext: string): string[] {
  if (
    BOUNDARY_CONTEXT_PATTERN.test(quotedContext) &&
    SOFT_PUSH_MESSAGE_PATTERN.test(message)
  ) {
    return ["semantic_contradiction_log_only"];
  }

  return [];
}

export function validateRecommendationEvent(
  event: StreamEvent | Record<string, unknown>,
): RecommendationValidation {
  if (event.type !== "analysis.recommendation") {
    return {
      ok: false,
      code: "STREAM_MALFORMED_RECOMMENDATION",
      reason: "expected analysis.recommendation event",
    };
  }

  if (!isStreamStyle(event.selectedStyle)) {
    return {
      ok: false,
      code: "STREAM_MALFORMED_RECOMMENDATION",
      reason: "invalid selectedStyle",
    };
  }

  const message = textField(event.message);
  const reason = textField(event.reason);
  const quotedContext = textField(event.quotedContext);

  if (!message || !reason || !quotedContext) {
    return {
      ok: false,
      code: "STREAM_MALFORMED_RECOMMENDATION",
      reason: "message, reason, and quotedContext are required",
    };
  }

  const modelAuthoredText = `${message}\n${reason}`;
  if (
    hasPromptInjection(modelAuthoredText) ||
    hasUnsafeRecommendation(modelAuthoredText)
  ) {
    return {
      ok: false,
      code: "STREAM_UNSAFE_RECOMMENDATION",
      reason: "recommendation failed hard safety rules",
    };
  }

  return {
    ok: true,
    selectedStyle: event.selectedStyle,
    message,
    reason,
    quotedContext,
    warnings: collectWarnings(message, quotedContext),
    raw: event,
  };
}
