// AnalysisInputCompiler：analyze-chat 請求輸入的型別、長度上限與 sanitize。
// 全部發生在額度與模型工作之前；錯誤字串是 client 契約的一部分。
// 內容 byte-for-byte 沿用 fc8bbe84 基準（baseline_contract_test.ts 鎖定）。

import { logWarn } from "./logger.ts";

interface ImageData {
  data: string; // base64 encoded
  mediaType: string; // e.g., "image/jpeg"
  order: number; // 1, 2, 3...
}

interface AnalyzeMessage {
  isFromMe: boolean;
  content: string;
  quotedReplyPreview?: string;
  quotedReplyPreviewIsFromMe?: boolean;
}

interface SessionContextInput {
  meetingContext?: string;
  duration?: string;
  goal?: string;
  targetDescription?: string;
  analysisContextNote?: string;
}

const MAX_MESSAGES = 120;
const MAX_MESSAGE_LENGTH = 2000;
const MAX_TOTAL_MESSAGE_CHARS = 20000;
const MAX_QUOTED_REPLY_PREVIEW_LENGTH = 300;
const MAX_CONTACT_NAME_LENGTH = 40;
const MAX_USER_DRAFT_LENGTH = 1500;
const MAX_SESSION_FIELD_LENGTH = 300;
const MAX_CONVERSATION_SUMMARY_LENGTH = 5000;
// PartnerSummaryBuilder caps at 1500 grapheme clusters; allow a small
// headroom for trim variations and future expansion before rejecting.
const MAX_PARTNER_SUMMARY_LENGTH = 2000;
const MAX_EFFECTIVE_STYLE_CONTEXT_LENGTH = 1200;

function sanitizeMessages(
  input: unknown,
  options: { allowEmpty?: boolean } = {},
): { messages?: AnalyzeMessage[]; error?: string } {
  if (!Array.isArray(input)) {
    return { error: "Invalid messages" };
  }

  if (input.length === 0) {
    return options.allowEmpty
      ? { messages: [] }
      : { error: "Messages cannot be empty" };
  }

  if (input.length > MAX_MESSAGES) {
    return { error: `Too many messages (max ${MAX_MESSAGES})` };
  }

  let totalChars = 0;
  const sanitizedMessages: AnalyzeMessage[] = [];

  for (const message of input) {
    if (!message || typeof message !== "object") {
      return { error: "Invalid message item" };
    }

    const record = message as Record<string, unknown>;
    if (typeof record.isFromMe !== "boolean") {
      return { error: "Invalid message sender" };
    }

    if (typeof record.content !== "string") {
      return { error: "Invalid message content" };
    }

    const content = record.content.trim();
    if (!content) {
      return { error: "Message content cannot be empty" };
    }

    if (content.length > MAX_MESSAGE_LENGTH) {
      return { error: `Message too long (max ${MAX_MESSAGE_LENGTH} chars)` };
    }

    let quotedReplyPreview: string | undefined;
    let quotedReplyPreviewIsFromMe: boolean | undefined;
    if (record.quotedReplyPreview != null) {
      if (typeof record.quotedReplyPreview !== "string") {
        return { error: "Invalid message quotedReplyPreview" };
      }

      const trimmedQuotedReplyPreview = record.quotedReplyPreview.trim();
      if (trimmedQuotedReplyPreview) {
        if (
          trimmedQuotedReplyPreview.length > MAX_QUOTED_REPLY_PREVIEW_LENGTH
        ) {
          return {
            error:
              `quotedReplyPreview too long (max ${MAX_QUOTED_REPLY_PREVIEW_LENGTH} chars)`,
          };
        }
        quotedReplyPreview = trimmedQuotedReplyPreview;
        if (
          record.quotedReplyPreviewIsFromMe != null &&
          typeof record.quotedReplyPreviewIsFromMe !== "boolean"
        ) {
          return { error: "Invalid message quotedReplyPreviewIsFromMe" };
        }
        quotedReplyPreviewIsFromMe = record.quotedReplyPreviewIsFromMe as
          | boolean
          | undefined;
      }
    }

    totalChars += content.length;
    if (quotedReplyPreview) {
      totalChars += quotedReplyPreview.length;
    }
    if (totalChars > MAX_TOTAL_MESSAGE_CHARS) {
      return {
        error: `Messages too long (max ${MAX_TOTAL_MESSAGE_CHARS} chars)`,
      };
    }

    sanitizedMessages.push({
      isFromMe: record.isFromMe,
      content,
      ...(quotedReplyPreview ? { quotedReplyPreview } : {}),
      ...(quotedReplyPreview != null && quotedReplyPreviewIsFromMe != null
        ? { quotedReplyPreviewIsFromMe }
        : {}),
    });
  }

  return { messages: sanitizedMessages };
}

function sanitizeSessionContext(
  input: unknown,
): { sessionContext?: SessionContextInput; error?: string } {
  if (input == null) {
    return {};
  }

  if (typeof input !== "object" || Array.isArray(input)) {
    return { error: "Invalid sessionContext" };
  }

  const raw = input as Record<string, unknown>;
  const sanitized: SessionContextInput = {};

  for (
    const key of [
      "meetingContext",
      "duration",
      "goal",
      "targetDescription",
      "analysisContextNote",
    ] as const
  ) {
    const value = raw[key];
    if (value == null) continue;

    if (typeof value !== "string") {
      return { error: `Invalid sessionContext.${key}` };
    }

    const trimmed = value.trim();
    if (!trimmed) continue;

    if (trimmed.length > MAX_SESSION_FIELD_LENGTH) {
      return { error: `sessionContext.${key} too long` };
    }

    sanitized[key] = trimmed;
  }

  return { sessionContext: sanitized };
}

function sanitizeConversationSummary(
  input: unknown,
): { conversationSummary?: string; error?: string } {
  if (input == null) {
    return {};
  }

  if (typeof input !== "string") {
    return { error: "Invalid conversationSummary" };
  }

  const trimmed = input.trim();
  if (!trimmed) {
    return {};
  }

  if (trimmed.length > MAX_CONVERSATION_SUMMARY_LENGTH) {
    return {
      error:
        `conversationSummary too long (max ${MAX_CONVERSATION_SUMMARY_LENGTH} chars)`,
    };
  }

  return { conversationSummary: trimmed };
}

function sanitizePartnerSummary(
  input: unknown,
): { partnerSummary?: string; error?: string } {
  if (input == null) {
    return {};
  }

  if (typeof input !== "string") {
    return { error: "Invalid partnerSummary" };
  }

  const trimmed = input.trim();
  if (!trimmed) {
    return {};
  }

  if (trimmed.length > MAX_PARTNER_SUMMARY_LENGTH) {
    logWarn("partner_summary_too_long_dropped", {
      length: trimmed.length,
      max: MAX_PARTNER_SUMMARY_LENGTH,
    });
    return {};
  }

  return { partnerSummary: trimmed };
}

function sanitizeEffectiveStyleContext(
  input: unknown,
): { effectiveStyleContext?: string; error?: string } {
  if (input == null) {
    return {};
  }

  if (typeof input !== "string") {
    return { error: "Invalid effectiveStyleContext" };
  }

  const trimmed = input.trim();
  if (!trimmed) {
    return {};
  }

  if (trimmed.length > MAX_EFFECTIVE_STYLE_CONTEXT_LENGTH) {
    return {
      error:
        `effectiveStyleContext too long (max ${MAX_EFFECTIVE_STYLE_CONTEXT_LENGTH} chars)`,
    };
  }

  return { effectiveStyleContext: trimmed };
}

function sanitizeAnalysisFragmentStartIndex(
  input: unknown,
  messageCount: number,
): { analysisFragmentStartIndex?: number; error?: string } {
  if (input == null) return {};
  if (!Number.isInteger(input)) {
    return { error: "Invalid analysisFragmentStartIndex" };
  }
  const index = input as number;
  const valid = messageCount === 0
    ? index === 0
    : index >= 0 && index < messageCount;
  return valid
    ? { analysisFragmentStartIndex: index }
    : { error: "Invalid analysisFragmentStartIndex" };
}

function inferLatestIncomingRunStart(messages: AnalyzeMessage[]): number {
  if (messages.length === 0) return 0;
  let lastIncoming = messages.length - 1;
  while (lastIncoming >= 0 && messages[lastIncoming].isFromMe) {
    lastIncoming--;
  }
  if (lastIncoming < 0) return 0;
  let start = lastIncoming;
  while (start > 0 && !messages[start - 1].isFromMe) {
    start--;
  }
  return start;
}

export {
  inferLatestIncomingRunStart,
  MAX_CONTACT_NAME_LENGTH,
  MAX_CONVERSATION_SUMMARY_LENGTH,
  MAX_EFFECTIVE_STYLE_CONTEXT_LENGTH,
  MAX_MESSAGE_LENGTH,
  MAX_MESSAGES,
  MAX_PARTNER_SUMMARY_LENGTH,
  MAX_QUOTED_REPLY_PREVIEW_LENGTH,
  MAX_SESSION_FIELD_LENGTH,
  MAX_TOTAL_MESSAGE_CHARS,
  MAX_USER_DRAFT_LENGTH,
  sanitizeAnalysisFragmentStartIndex,
  sanitizeConversationSummary,
  sanitizeEffectiveStyleContext,
  sanitizeMessages,
  sanitizePartnerSummary,
  sanitizeSessionContext,
};
export type { AnalyzeMessage, ImageData, SessionContextInput };
