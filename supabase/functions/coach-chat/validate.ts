import { containsBannedToken } from "../_shared/banned_tokens.ts";
import { containsPromptLeak } from "../_shared/prompt_leak_guard.ts";
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
    throw new Error(
      "invalid_input_for_mode: images not accepted in coach-chat v1",
    );
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
  answer: 360,
  userTruth: 120,
  userState: 100,
  nextStep: 100,
  suggestedLine: 160,
  rewriteReason: 100,
  boundaryReminder: 100,
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
  "userTruth",
  "userState",
  "nextStep",
  "suggestedLine",
  "rewriteReason",
  "boundaryReminder",
  "reflectionQuestion",
] as const;

function looksLikeRawModelPayload(value: string): boolean {
  const trimmed = value.trim();
  if (!trimmed) return false;

  const lower = trimmed.toLowerCase();
  if (trimmed.startsWith("```") || lower.includes("```json")) {
    return true;
  }

  if (!trimmed.startsWith("{") && !trimmed.startsWith("[")) {
    return false;
  }

  return [
    '"replies"',
    '"replyoptions"',
    '"finalrecommendation"',
    '"profileanalysis"',
    '"coachactionhint"',
    '"openers"',
    '"card"',
    '"responsetype"',
  ].some((marker) => lower.includes(marker));
}

// 反 prompt 外洩（2026-08-19）：coach system prompt 的內部行話長片段，
// 正常教練回覆絕不會逐字出現；命中＝系統指示外洩，整卡擋下。
const COACH_PROMPT_LEAK_SENTINELS: readonly string[] = [
  "先判斷這次使用者卡在哪個狀態",
  "suggestedLine 要守投入對等節奏",
  "內部先判斷，但輸出不要露出推理過程",
  "你是 VibeSync Coach 1:1：有記憶、有邊界",
];

export function assertCardSafe(
  card: Record<string, string | number | boolean | null | undefined>,
): void {
  for (const field of VISIBLE_FIELDS) {
    const value = card[field];
    if (typeof value !== "string") continue;
    if (looksLikeRawModelPayload(value)) {
      throw new Error(`raw_model_payload: ${field}`);
    }
    const token = containsBannedToken(value);
    if (token != null) {
      throw new Error(`banned_token: ${token} found in ${field}`);
    }
    if (containsPromptLeak(value, COACH_PROMPT_LEAK_SENTINELS)) {
      throw new Error(`prompt_leak: ${field}`);
    }
  }
}
