const FEEDBACK_SCHEMA_VERSION = 1;
const ENUM_MAX_LENGTH = 64;
const SHORT_TEXT_MAX_LENGTH = 300;
const MEDIUM_TEXT_MAX_LENGTH = 600;
const DISCORD_MESSAGE_MAX_LENGTH = 1900;

export const AI_RESPONSE_MAX_LENGTH = 12000;

export const VALID_FEEDBACK_CATEGORIES: ReadonlySet<string> = new Set([
  "too_direct",
  "too_long",
  "unnatural",
  "wrong_style",
  "other",
  // Batch E：Coach 1:1 專用可行動分類。舊分析頁分類完整保留。
  "too_beta",
  "should_not_send",
  "too_generic",
  "invented_detail",
  "wrong_judgment",
  "too_many_questions",
  "missed_context",
]);

/// 對話分析 v3 的負評分類（Eric 2026-10-18），存在 aiResponse.guideV3.feedbackCategory。
/// 分類欄（VALID_FEEDBACK_CATEGORIES，跟資料庫 CHECK 同一份）還沒有「像在考她」，
/// App 先送 other；確切分類靠這個欄位保留。
const GUIDE_V3_FEEDBACK_CATEGORY_LABELS: ReadonlyMap<string, string> = new Map([
  ["wrong_judgment", "Wrong judgment"],
  ["testing_her", "Testing / scoring her"],
  ["invented_detail", "Invented detail"],
  ["too_beta", "Too soft / customer-service tone"],
  ["other", "Other"],
]);
const GUIDE_V3_CARD_TASKS_MAX = 5;

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
    too_beta: "Too beta / approval-seeking",
    should_not_send: "Should not send",
    too_generic: "Too generic",
    invented_detail: "Invented detail",
    wrong_judgment: "Wrong judgment",
    too_many_questions: "Too many questions",
    missed_context: "Missed context",
    other: "Other",
  };

  const commentPreviewLength = options?.commentPreviewLength ?? 300;
  const snippetPreviewLength = options?.snippetPreviewLength ?? 500;
  const timestamp = options?.timestamp ?? new Date().toISOString();
  const maskedEmail = maskEmailForNotification(feedback.userEmail);

  // 2026-08-16 改版：正評也通知，開頭一眼看出 評分＋來源
  // （finalRecommendation.pick === 'coach_chat' 是教練卡拇指的來源標記）。
  const isPositive = feedback.rating === "positive";
  const header = isPositive ? "👍 有幫助回饋" : "👎 沒幫助回饋";
  const source = resolveFeedbackSourceLabel(feedback.aiResponse);

  const messageParts: string[] = [
    `${header} — ${source}\n\n`,
    `User: ${maskedEmail} (${feedback.userTier})\n`,
  ];

  const guideV3 = isPlainObject(feedback.aiResponse?.guideV3)
    ? feedback.aiResponse.guideV3
    : null;
  const guideV3Category = typeof guideV3?.feedbackCategory === "string"
    ? GUIDE_V3_FEEDBACK_CATEGORY_LABELS.get(guideV3.feedbackCategory)
    : undefined;

  // 分類是負評表單才有的概念；正評不放，避免每則都是無資訊的 Other。
  if (!isPositive) {
    messageParts.push(
      `Category: ${
        guideV3Category ??
          (categoryLabels[feedback.category || "other"] || feedback.category)
      }\n`,
    );
  }

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

  // v3：哪一次分析（runId 對得回卡片與扣費紀錄）、判讀與燈號。
  if (guideV3) {
    const verdict = [guideV3.decision, guideV3.light]
      .filter((value) => typeof value === "string")
      .join(" / ");
    const run = typeof guideV3.runId === "string"
      ? ` run ${guideV3.runId}`
      : "";
    messageParts.push(`\nv3: ${verdict || "unknown"}${run}\n`);
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

// 通知開頭的來源標籤。教練卡拇指固定送 pick='coach_chat'；分析頁送真實
// pick（extend/resonate…）；沒帶 aiResponse 的老 client 就標 App。
export function resolveFeedbackSourceLabel(
  aiResponse: Record<string, unknown> | undefined,
): string {
  if (!isPlainObject(aiResponse)) {
    return "App";
  }
  const recommendation = isPlainObject(aiResponse.finalRecommendation)
    ? aiResponse.finalRecommendation
    : null;
  if (recommendation?.pick === "coach_chat") {
    return "問教練";
  }
  return "分析頁";
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

  const guideV3 = sanitizeGuideV3Feedback(value.guideV3);
  if (guideV3 != null) {
    sanitized.guideV3 = guideV3;
  }

  return Object.keys(sanitized).length > 1 ? sanitized : undefined;
}

/// 對話分析 v3 的回饋欄位（Eric 2026-10-18）：只留固定的短欄位。runId 讓負評對得回
/// 是哪一次分析；沒有卡片文字、沒有對話。
function sanitizeGuideV3Feedback(
  value: unknown,
): Record<string, unknown> | undefined {
  if (!isPlainObject(value)) {
    return undefined;
  }

  const guideV3: Record<string, unknown> = {};
  for (const key of ["guideVersion", "decision", "light", "runId"]) {
    const field = clampOptionalString(value[key], ENUM_MAX_LENGTH);
    if (field != null) {
      guideV3[key] = field;
    }
  }

  if (Array.isArray(value.cardTasks)) {
    const cardTasks = value.cardTasks
      .slice(0, GUIDE_V3_CARD_TASKS_MAX)
      .map((task) => clampOptionalString(task, ENUM_MAX_LENGTH))
      .filter((task): task is string => task != null);
    if (cardTasks.length > 0) {
      guideV3.cardTasks = cardTasks;
    }
  }

  if (
    typeof value.feedbackCategory === "string" &&
    GUIDE_V3_FEEDBACK_CATEGORY_LABELS.has(value.feedbackCategory)
  ) {
    guideV3.feedbackCategory = value.feedbackCategory;
  }

  return Object.keys(guideV3).length > 0 ? guideV3 : undefined;
}
