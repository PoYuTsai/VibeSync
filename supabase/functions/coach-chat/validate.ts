import { containsBannedToken } from "../_shared/banned_tokens.ts";
import {
  type CoachChatRequest,
  type CoachChatResponse,
  type CoachChatResponseCard,
  RequestSchema,
  ResponseCardSchema,
  ResponseSchema,
} from "./schemas.ts";

export function validateRequest(payload: unknown): CoachChatRequest {
  if (
    typeof payload === "object" &&
    payload !== null &&
    "images" in (payload as Record<string, unknown>)
  ) {
    throw new Error("invalid_input_for_mode: images not accepted in coach-chat v1");
  }
  return RequestSchema.parse(payload);
}

export function validateResponseCard(card: unknown): CoachChatResponseCard {
  return ResponseCardSchema.parse(card);
}

export function validateFullResponse(payload: unknown): CoachChatResponse {
  return ResponseSchema.parse(payload);
}

const FIELD_CAPS: Record<string, number> = {
  headline: 32,
  answer: 220,
  userState: 90,
  nextStep: 90,
  suggestedLine: 100,
  boundaryReminder: 80,
  reflectionQuestion: 90,
};

export function truncateCard<
  T extends Record<string, string | number | boolean | null | undefined>,
>(
  card: T,
): T {
  const out = { ...card };
  for (const [field, cap] of Object.entries(FIELD_CAPS)) {
    const value = out[field as keyof T];
    if (typeof value === "string" && value.length > cap) {
      (out as Record<string, string | number | boolean | null | undefined>)[
        field
      ] = truncateVisibleText(value, cap);
    }
  }
  return out;
}

function truncateVisibleText(value: string, cap: number): string {
  if (value.length <= cap) return value;
  const head = value.slice(0, cap);
  const punctuation = /[。！？!?]/g;
  let lastBoundary = -1;
  for (const match of head.matchAll(punctuation)) {
    lastBoundary = match.index ?? -1;
  }
  if (lastBoundary >= Math.floor(cap * 0.45)) {
    return head.slice(0, lastBoundary + 1);
  }
  return `${head.slice(0, Math.max(0, cap - 1)).trimEnd()}…`;
}

const VISIBLE_FIELDS = [
  "headline",
  "answer",
  "userState",
  "nextStep",
  "suggestedLine",
  "boundaryReminder",
  "reflectionQuestion",
] as const;

export function assertCardSafe(
  card: Record<string, string | number | boolean | null | undefined>,
): void {
  for (const field of VISIBLE_FIELDS) {
    const value = card[field];
    if (typeof value !== "string") continue;
    const token = containsBannedToken(value);
    if (token != null) {
      throw new Error(`banned_token: ${token} found in ${field}`);
    }
  }
}
