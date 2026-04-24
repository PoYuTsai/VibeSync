const FEEDBACK_SCHEMA_VERSION = 1;
const ENUM_MAX_LENGTH = 64;
const SHORT_TEXT_MAX_LENGTH = 300;
const MEDIUM_TEXT_MAX_LENGTH = 600;
const DISCORD_MESSAGE_MAX_LENGTH = 1900;

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

export function truncateOptionalStringToMax(
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

  if (normalized.length <= maxLength) {
    return normalized;
  }

  if (maxLength <= 3) {
    return normalized.slice(0, maxLength);
  }

  return `${normalized.slice(0, maxLength - 3)}...`;
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

export type FeedbackNotification = {
  userEmail: string;
  userTier: string;
  rating: string;
  category?: string;
  comment?: string;
  conversationSnippet?: string;
  aiResponse?: Record<string, unknown>;
  modelUsed?: string;
};

export type DiscordNotificationTarget = "webhook" | "bot";

function normalizeConfigString(
  value: string | null | undefined,
): string | undefined {
  const normalized = value?.trim();
  return normalized ? normalized : undefined;
}

export function resolveDiscordNotificationTarget(config: {
  webhookUrl?: string | null;
  botToken?: string | null;
  channelId?: string | null;
}): DiscordNotificationTarget | undefined {
  if (normalizeConfigString(config.webhookUrl)) {
    return "webhook";
  }

  if (
    normalizeConfigString(config.botToken) &&
    normalizeConfigString(config.channelId)
  ) {
    return "bot";
  }

  return undefined;
}

function truncateWholeMessage(message: string): string {
  if (message.length <= DISCORD_MESSAGE_MAX_LENGTH) {
    return message;
  }

  return `${message.slice(0, DISCORD_MESSAGE_MAX_LENGTH - 3)}...`;
}

export function buildDiscordNotificationContent(
  feedback: FeedbackNotification,
  options?: {
    commentPreviewLength?: number;
    snippetPreviewLength?: number;
    timestamp?: string;
  },
): string {
  const categoryLabels: Record<string, string> = {
    too_direct: "Too direct",
    too_long: "Too long",
    unnatural: "Unnatural",
    wrong_style: "Wrong style",
    other: "Other",
  };

  const commentPreviewLength = options?.commentPreviewLength ?? 300;
  const snippetPreviewLength = options?.snippetPreviewLength ?? 500;
  const timestamp = options?.timestamp ?? new Date().toISOString();
  const maskedEmail = maskEmailForNotification(feedback.userEmail);

  const messageParts: string[] = [
    "Negative feedback received\n\n",
    `User: ${maskedEmail} (${feedback.userTier})\n`,
    `Category: ${
      categoryLabels[feedback.category || "other"] || feedback.category
    }\n`,
  ];

  if (feedback.comment) {
    messageParts.push(
      `Comment: "${
        truncateForPreview(feedback.comment, commentPreviewLength)
      }"\n`,
    );
  }

  if (feedback.conversationSnippet) {
    messageParts.push(
      `\nConversation snippet:\n${
        truncateForPreview(feedback.conversationSnippet, snippetPreviewLength)
      }\n`,
    );
  }

  if (feedback.aiResponse?.finalRecommendation) {
    const rec = feedback.aiResponse.finalRecommendation as Record<
      string,
      string
    >;
    messageParts.push(`\nAI recommendation:\n${rec.pick}: "${rec.content}"\n`);
  }

  let message = messageParts.join("");
  message += `\nModel: ${feedback.modelUsed || "unknown"}`;
  message += `\nTime: ${timestamp}`;

  return truncateWholeMessage(message);
}

function clampOptionalString(
  value: unknown,
  maxLength: number,
): string | undefined {
  return truncateOptionalStringToMax(value, maxLength);
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
