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
