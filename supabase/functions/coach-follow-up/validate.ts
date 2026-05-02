// supabase/functions/coach-follow-up/validate.ts
//
// Request validator + response card hard-truncate + banned-token enforcement.
//
// T2 surface: validateRequest (rejects images explicitly with stable error code
// "invalid_input_for_mode" so client can branch), validateResponseCard,
// validateFullResponse.
//
// T3 will add truncateCard + assertCardSafe (banned-token validator) — committed
// here as separate task per plan §4.

import {
  RequestSchema,
  ResponseCardSchema,
  ResponseSchema,
  type CoachFollowUpRequest,
  type CoachFollowUpResponse,
  type CoachFollowUpResponseCard,
} from "./schemas.ts";

/**
 * Parse + validate an incoming POST body.
 * Throws Error("invalid_input_for_mode: ...") if the caller sent the v1-prohibited
 * `images` field. All other shape errors surface through zod's ZodError.message.
 */
export function validateRequest(payload: unknown): CoachFollowUpRequest {
  if (
    typeof payload === "object" &&
    payload !== null &&
    "images" in (payload as Record<string, unknown>)
  ) {
    throw new Error(
      "invalid_input_for_mode: images not accepted in coach-follow-up v1",
    );
  }
  return RequestSchema.parse(payload);
}

export function validateResponseCard(card: unknown): CoachFollowUpResponseCard {
  return ResponseCardSchema.parse(card);
}

export function validateFullResponse(payload: unknown): CoachFollowUpResponse {
  return ResponseSchema.parse(payload);
}

// =============================================================================
// T3 — truncateCard + assertCardSafe
// =============================================================================
//
// truncateCard hard-caps each visible field to its max byte length. Run BEFORE
// validateResponseCard so model verbosity doesn't 5xx the user (design §1.4 row
// "Response schema 違規"). boundaryReminder still needs to satisfy min(1) — but
// truncateCard never empties a non-empty string, so a Claude reply with a
// non-empty boundaryReminder always passes both gates.
//
// assertCardSafe enforces the product red-line vocabulary at the response level
// (Codex Plan-Review P1 #5 — defense-in-depth alongside the prompt guardrail in
// prompts.ts). Throws Error("banned_token: <token> found in <field>") so the
// caller can tag telemetry errorClass without leaking the offending text.

const FIELD_CAPS: Record<string, number> = {
  headline: 30,
  observation: 80,
  task: 30,
  suggestedLine: 80,
  boundaryReminder: 60,
};

export function truncateCard<T extends Record<string, string | null | undefined>>(
  card: T,
): T {
  const out = { ...card };
  for (const [field, cap] of Object.entries(FIELD_CAPS)) {
    const v = out[field as keyof T];
    if (typeof v === "string" && v.length > cap) {
      (out as Record<string, string | null | undefined>)[field] = v.slice(0, cap);
    }
  }
  return out;
}

const BANNED_TOKENS = [
  "PUA",
  "收割",
  "控住",
  "攻略",
  "壞女人",
  "高分妹",
  "玩咖",
] as const;

const VISIBLE_FIELDS = [
  "headline",
  "observation",
  "task",
  "suggestedLine",
  "boundaryReminder",
] as const;

export function assertCardSafe(
  card: Record<string, string | null | undefined>,
): void {
  for (const field of VISIBLE_FIELDS) {
    const value = card[field];
    if (typeof value !== "string") continue;
    for (const token of BANNED_TOKENS) {
      if (value.includes(token)) {
        throw new Error(`banned_token: ${token} found in ${field}`);
      }
    }
  }
}
