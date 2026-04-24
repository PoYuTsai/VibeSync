const FEEDBACK_SCHEMA_VERSION = 1;
const ENUM_MAX_LENGTH = 64;
const SHORT_TEXT_MAX_LENGTH = 300;
const MEDIUM_TEXT_MAX_LENGTH = 600;

export const AI_RESPONSE_MAX_LENGTH = 12000;

export function normalizeOptionalString(
  value: unknown,
  maxLength: number,
): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }

  const normalized = value.trim();
  if (!normalized) {
    return undefined;
  }

  if (normalized.length > maxLength) {
    throw new Error(`STRING_TOO_LONG:${maxLength}`);
  }

  return normalized;
}

export function truncateForPreview(value: string, maxLength: number): string {
  return value.length > maxLength ? `${value.slice(0, maxLength)}...` : value;
}

export function stripBearer(value: string): string {
  return value.trim().replace(/^Bearer\s+/i, "");
}

export function isPlainObject(
  value: unknown,
): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function maskEmailForNotification(email: string): string {
  const normalized = email.trim();
  const atIndex = normalized.indexOf("@");
  if (atIndex <= 0 || atIndex >= normalized.length - 1) {
    return "hidden";
  }

  const localPart = normalized.slice(0, atIndex);
  const domain = normalized.slice(atIndex + 1);
  const visiblePrefix = localPart.slice(0, Math.min(2, localPart.length));
  return `${visiblePrefix}***@${domain}`;
}

function clampOptionalString(
  value: unknown,
  maxLength: number,
): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }

  const normalized = value.trim();
  if (!normalized) {
    return undefined;
  }

  return normalized.length > maxLength
    ? `${normalized.slice(0, maxLength)}...`
    : normalized;
}

export function sanitizeFeedbackAiResponse(
  value: unknown,
): Record<string, unknown> | undefined {
  if (!isPlainObject(value)) {
    return undefined;
  }

  const sanitized: Record<string, unknown> = {
    schemaVersion: FEEDBACK_SCHEMA_VERSION,
  };

  const rawRecommendation = isPlainObject(value.finalRecommendation)
    ? value.finalRecommendation
    : null;
  if (rawRecommendation != null) {
    const recommendation: Record<string, string> = {};
    const pick = clampOptionalString(rawRecommendation.pick, ENUM_MAX_LENGTH);
    const content = clampOptionalString(
      rawRecommendation.content,
      SHORT_TEXT_MAX_LENGTH,
    );
    const reason = clampOptionalString(
      rawRecommendation.reason,
      SHORT_TEXT_MAX_LENGTH,
    );

    if (pick != null) {
      recommendation.pick = pick;
    }
    if (content != null) {
      recommendation.content = content;
    }
    if (reason != null) {
      recommendation.reason = reason;
    }

    if (Object.keys(recommendation).length > 0) {
      sanitized.finalRecommendation = recommendation;
    }
  }

  const strategy = clampOptionalString(value.strategy, MEDIUM_TEXT_MAX_LENGTH);
  if (strategy != null) {
    sanitized.strategy = strategy;
  }

  const gameStage = clampOptionalString(value.gameStage, ENUM_MAX_LENGTH);
  if (gameStage != null) {
    sanitized.gameStage = gameStage;
  }

  const gameStageStatus = clampOptionalString(
    value.gameStageStatus,
    ENUM_MAX_LENGTH,
  );
  if (gameStageStatus != null) {
    sanitized.gameStageStatus = gameStageStatus;
  }

  const topicDepth = clampOptionalString(value.topicDepth, ENUM_MAX_LENGTH);
  if (topicDepth != null) {
    sanitized.topicDepth = topicDepth;
  }

  const tierUsed = clampOptionalString(value.tierUsed, ENUM_MAX_LENGTH);
  if (tierUsed != null) {
    sanitized.tierUsed = tierUsed;
  }

  if (
    typeof value.enthusiasmScore === "number" &&
    Number.isFinite(value.enthusiasmScore)
  ) {
    sanitized.enthusiasmScore = Math.max(
      0,
      Math.min(100, Math.round(value.enthusiasmScore)),
    );
  }

  return Object.keys(sanitized).length > 1 ? sanitized : undefined;
}
