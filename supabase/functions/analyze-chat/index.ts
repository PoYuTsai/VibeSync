// supabase/functions/analyze-chat/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import {
  type AnalysisResult as GuardrailAnalysisResult,
  checkAiOutput,
  checkInput,
  SAFETY_RULES,
} from "./guardrails.ts";
import { AiServiceError, callClaudeWithFallback } from "./fallback.ts";
import { applyLayoutFirstParser } from "./layout_parser.ts";
import { extractTokenUsage, logAiCall } from "./logger.ts";
import { buildServerGuardrails } from "./server_guardrails.ts";

const CLAUDE_API_KEY = Deno.env.get("CLAUDE_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// JSON 修復函數 - 處理 Claude 有時輸出不完整的 JSON
function repairJson(jsonString: string): string {
  let repaired = jsonString.trim();

  // 移除 trailing commas before } or ]
  repaired = repaired.replace(/,(\s*[}\]])/g, "$1");

  // 計算未閉合的括號
  let braceCount = 0;
  let bracketCount = 0;
  let inString = false;
  let escape = false;

  for (const char of repaired) {
    if (escape) {
      escape = false;
      continue;
    }
    if (char === "\\") {
      escape = true;
      continue;
    }
    if (char === '"') {
      inString = !inString;
      continue;
    }
    if (inString) continue;

    if (char === "{") braceCount++;
    if (char === "}") braceCount--;
    if (char === "[") bracketCount++;
    if (char === "]") bracketCount--;
  }

  // 補上缺少的閉合括號
  while (bracketCount > 0) {
    repaired += "]";
    bracketCount--;
  }
  while (braceCount > 0) {
    repaired += "}";
    braceCount--;
  }

  return repaired;
}

// 訊息制額度
const TIER_MONTHLY_LIMITS: Record<string, number> = {
  free: 30,
  starter: 300,
  essential: 1000,
};

const TIER_DAILY_LIMITS: Record<string, number> = {
  free: 15,
  starter: 50,
  essential: 150,
};

// 功能權限
const TIER_FEATURES: Record<string, string[]> = {
  free: ["extend"], // 只有延展回覆
  starter: [
    "extend",
    "resonate",
    "tease",
    "humor",
    "coldRead",
    "needy_warning",
    "topic_depth",
  ],
  essential: [
    "extend",
    "resonate",
    "tease",
    "humor",
    "coldRead",
    "needy_warning",
    "topic_depth",
    "health_check",
  ],
};

// 截圖上傳相關類型
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

type RecognizedBubbleSide = "left" | "right" | "unknown";

interface NormalizedRecognizedMessage {
  side: RecognizedBubbleSide;
  isFromMe: boolean;
  content: string;
  quotedReplyPreview?: string;
  quotedReplyPreviewIsFromMe?: boolean;
}

type VisibleSpeakerPattern = "mixed" | "only_left" | "only_right" | "unknown";

interface SessionContextInput {
  meetingContext?: string;
  duration?: string;
  goal?: string;
  userStyle?: string;
  userInterests?: string;
  targetDescription?: string;
}

const MAX_MESSAGES = 120;
const MAX_MESSAGE_LENGTH = 2000;
const MAX_TOTAL_MESSAGE_CHARS = 20000;
const MAX_QUOTED_REPLY_PREVIEW_LENGTH = 300;
const MAX_CONTACT_NAME_LENGTH = 40;
const MAX_USER_DRAFT_LENGTH = 1500;
const MAX_SESSION_FIELD_LENGTH = 300;
const MAX_CONVERSATION_SUMMARY_LENGTH = 5000;
const VALID_ANALYZE_MODES = new Set(["normal", "my_message"]);
const VALID_FORCE_MODELS = new Set([
  "claude-haiku-4-5-20251001",
  "claude-sonnet-4-20250514",
]);
const VALID_IMAGE_MEDIA_TYPES = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
]);
const MAX_IMAGE_BYTES = 600 * 1024;
const MAX_TOTAL_IMAGE_BYTES = 1500 * 1024;
const MAX_REQUEST_BODY_BYTES = 3 * 1024 * 1024;
const VALID_SCREENSHOT_CLASSIFICATIONS = new Set([
  "valid_chat",
  "low_confidence",
  "social_feed",
  "group_chat",
  "gallery_album",
  "call_log_screen",
  "system_ui",
  "sensitive_content",
  "unsupported",
]);
const VALID_IMPORT_POLICIES = new Set(["allow", "confirm", "reject"]);
const CALL_EVENT_KEYWORDS = [
  "未接來電",
  "已接來電",
  "撥出電話",
  "語音通話",
  "視訊通話",
  "missed call",
  "incoming call",
  "outgoing call",
  "voice call",
  "video call",
  "missed a call",
  "called you",
];
const LOG_PREFIX = "[analyze-chat]";

function getErrorMessage(error: unknown): string {
  if (error instanceof Error) {
    return error.message;
  }
  return String(error);
}

function summarizeUser(userId: string): string {
  return userId.length <= 8 ? userId : `${userId.slice(0, 8)}...`;
}

function logInfo(event: string, metadata?: Record<string, unknown>) {
  console.log(`${LOG_PREFIX} ${event}`, metadata ?? {});
}

function logWarn(event: string, metadata?: Record<string, unknown>) {
  console.warn(`${LOG_PREFIX} ${event}`, metadata ?? {});
}

function logError(event: string, metadata?: Record<string, unknown>) {
  console.error(`${LOG_PREFIX} ${event}`, metadata ?? {});
}

function deriveRequestType({
  recognizeOnly,
  hasImages,
  isMyMessageMode,
  hasUserDraft,
}: {
  recognizeOnly: boolean;
  hasImages: boolean;
  isMyMessageMode: boolean;
  hasUserDraft: boolean;
}): string {
  if (recognizeOnly) {
    return "recognize_only";
  }
  if (hasImages) {
    return "analyze_with_images";
  }
  if (isMyMessageMode) {
    return "my_message";
  }
  if (hasUserDraft) {
    return "optimize_message";
  }
  return "analyze";
}

function buildQuotaUsageMetadata({
  requestType,
  recognizeOnly,
  accountIsTest,
  estimatedMessageCount,
}: {
  requestType: string;
  recognizeOnly: boolean;
  accountIsTest: boolean;
  estimatedMessageCount: number;
}) {
  if (recognizeOnly) {
    return {
      shouldChargeQuota: false,
      quotaReason: "recognize_only_free",
      quotaUnit: "messages",
      chargedMessageCount: 0,
      estimatedMessageCount: 0,
    };
  }

  if (accountIsTest) {
    return {
      shouldChargeQuota: false,
      quotaReason: "test_account_waived",
      quotaUnit: "messages",
      chargedMessageCount: 0,
      estimatedMessageCount,
    };
  }

  let quotaReason = "analyze_message_based";
  switch (requestType) {
    case "analyze_with_images":
      quotaReason = "analyze_with_images_message_based";
      break;
    case "my_message":
      quotaReason = "my_message_message_based";
      break;
    case "optimize_message":
      quotaReason = "optimize_message_message_based";
      break;
  }

  return {
    shouldChargeQuota: estimatedMessageCount > 0,
    quotaReason,
    quotaUnit: "messages",
    chargedMessageCount: estimatedMessageCount,
    estimatedMessageCount,
  };
}

function buildRecognitionObservability(
  recognizedConversation:
    | {
      classification?: string;
      importPolicy?: string;
      confidence?: string;
      sideConfidence?: string;
      messageCount?: number;
      uncertainSideCount?: number;
      normalizationTelemetry?: {
        continuityAdjustedCount?: number;
        groupedAdjustedCount?: number;
        layoutFirstAdjustedCount?: number;
        systemRowsRemovedCount?: number;
        quotedPreviewRemovedCount?: number;
        quotedPreviewAttachedCount?: number;
        overlapRemovedCount?: number;
      };
    }
    | undefined,
) {
  return {
    recognizedClassification: recognizedConversation?.classification ?? null,
    recognizedImportPolicy: recognizedConversation?.importPolicy ?? null,
    recognizedConfidence: recognizedConversation?.confidence ?? null,
    recognizedSideConfidence: recognizedConversation?.sideConfidence ?? null,
    recognizedMessageCount: recognizedConversation?.messageCount ?? null,
    uncertainSideCount: recognizedConversation?.uncertainSideCount ?? null,
    continuityAdjustedCount: recognizedConversation?.normalizationTelemetry
      ?.continuityAdjustedCount ?? 0,
    groupedAdjustedCount: recognizedConversation?.normalizationTelemetry
      ?.groupedAdjustedCount ?? 0,
    layoutFirstAdjustedCount: recognizedConversation?.normalizationTelemetry
      ?.layoutFirstAdjustedCount ?? 0,
    systemRowsRemovedCount: recognizedConversation?.normalizationTelemetry
      ?.systemRowsRemovedCount ?? 0,
    quotedPreviewRemovedCount: recognizedConversation?.normalizationTelemetry
      ?.quotedPreviewRemovedCount ?? 0,
    quotedPreviewAttachedCount: recognizedConversation?.normalizationTelemetry
      ?.quotedPreviewAttachedCount ?? 0,
    overlapRemovedCount: recognizedConversation?.normalizationTelemetry
      ?.overlapRemovedCount ?? 0,
  };
}

function buildServerGuardrailObservability(input: {
  requestType: string;
  imageCount: number;
  latencyMs: number;
  timeoutMs?: number | null;
  fallbackUsed?: boolean;
  retryCount?: number;
  totalImageBytes?: number;
  truncatedMessageCount?: number;
  conversationSummaryUsed?: boolean;
  contextMode?: string | null;
  recognizedClassification?: string | null;
  recognizedSideConfidence?: string | null;
  uncertainSideCount?: number | null;
  continuityAdjustedCount?: number | null;
  groupedAdjustedCount?: number | null;
  layoutFirstAdjustedCount?: number | null;
  systemRowsRemovedCount?: number | null;
  quotedPreviewAttachedCount?: number | null;
  overlapRemovedCount?: number | null;
  inputTokens?: number;
  outputTokens?: number;
  safetyFiltered?: boolean;
}) {
  return buildServerGuardrails({
    requestType: input.requestType,
    imageCount: input.imageCount,
    latencyMs: input.latencyMs,
    timeoutMs: input.timeoutMs,
    fallbackUsed: input.fallbackUsed,
    retryCount: input.retryCount,
    totalImageBytes: input.totalImageBytes,
    truncatedMessageCount: input.truncatedMessageCount,
    conversationSummaryUsed: input.conversationSummaryUsed,
    contextMode: input.contextMode,
    recognizedClassification: input.recognizedClassification,
    recognizedSideConfidence: input.recognizedSideConfidence,
    uncertainSideCount: input.uncertainSideCount,
    continuityAdjustedCount: input.continuityAdjustedCount,
    groupedAdjustedCount: input.groupedAdjustedCount,
    layoutFirstAdjustedCount: input.layoutFirstAdjustedCount,
    systemRowsRemovedCount: input.systemRowsRemovedCount,
    quotedPreviewAttachedCount: input.quotedPreviewAttachedCount,
    overlapRemovedCount: input.overlapRemovedCount,
    inputTokens: input.inputTokens,
    outputTokens: input.outputTokens,
    safetyFiltered: input.safetyFiltered,
  });
}

// 建構 Vision API 內容格式
function buildVisionContent(
  textContent: string,
  images: ImageData[],
): Array<
  {
    type: string;
    text?: string;
    source?: { type: string; media_type: string; data: string };
  }
> {
  const content: Array<
    {
      type: string;
      text?: string;
      source?: { type: string; media_type: string; data: string };
    }
  > = [];

  // 先加入圖片（按 order 排序）
  const sortedImages = [...images].sort((a, b) => a.order - b.order);
  for (const img of sortedImages) {
    content.push({
      type: "image",
      source: {
        type: "base64",
        media_type: img.mediaType,
        data: img.data,
      },
    });
  }

  // 最後加入文字內容
  content.push({
    type: "text",
    text: textContent,
  });

  return content;
}

const OCR_RECOGNIZE_ONLY_SYSTEM_PROMPT =
  `You are an OCR + chat-structure extraction assistant.
Return valid JSON only.
Only extract what is visible in the screenshots.
Do not invent missing text, names, or message order.
If the screenshots are not a normal one-to-one chat UI, classify them conservatively using one of: social_feed, group_chat, gallery_album, call_log_screen, system_ui, sensitive_content, unsupported.`;

const SCREENSHOT_OCR_ACCURACY_RULES = [
  "### MANDATORY FIRST STEP: Visual Layout Analysis",
  "- STOP. Before reading ANY text, you MUST first analyze the visual layout:",
  "- Step 1: Draw an imaginary vertical line through the CENTER of the screenshot (at x=50%).",
  "- Step 2: Look at ONLY the OUTER bubble containers (ignore any small inset quoted-reply cards inside bubbles).",
  "- Step 3: For each outer bubble, determine if its CENTER is LEFT of the midline (x < 40%) or RIGHT of the midline (x > 60%).",
  "- Step 4: If ALL outer bubbles are on the LEFT side → set screenSpeakerPattern: 'only_left' and ALL messages are isFromMe: false.",
  "- Step 5: If ALL outer bubbles are on the RIGHT side → set screenSpeakerPattern: 'only_right' and ALL messages are isFromMe: true.",
  "- Step 6: Only if outer bubbles appear on BOTH sides → set screenSpeakerPattern: 'mixed'.",
  "",
  "### CRITICAL: What Counts as an 'Outer Bubble'",
  "- An outer bubble is the main message container that sits against the left or right edge of the chat area.",
  "- Quoted-reply cards (small inset boxes with colored borders showing old messages) are INSIDE outer bubbles - they are NOT outer bubbles themselves.",
  "- Even if a quoted card shows someone's avatar/name, the OUTER bubble position determines the speaker.",
  "- A left-side outer bubble with a quoted card showing 'Bruce' inside it is STILL a left-side message (isFromMe: false).",
  "",
  "### OCR Accuracy Rules",
  "- Preserve Traditional Chinese exactly; do not guess unreadable characters.",
  "- Read screenshots from top to bottom and keep message order stable across multiple images.",
  "",
  "### CRITICAL: Header Name vs Message Sender",
  "- The contact name in the chat header (e.g., 'Bruce Chiang' at the top) is WHO YOU ARE CHATTING WITH, not who is sending messages.",
  "- In one-on-one chat: left-side bubbles = messages FROM the contact (the header name person); right-side bubbles = messages FROM me.",
  "- Do NOT confuse 'chatting with Bruce' with 'Bruce is sending these messages'. If the header says 'Bruce Chiang', then LEFT bubbles are Bruce's messages to me, and RIGHT bubbles are my messages to Bruce.",
  "",
  "### CRITICAL: Quoted Reply Cards in LINE",
  "- LINE quoted-reply cards (colored/bordered inset boxes with avatar + name + quoted text) show OLD messages being quoted, NOT new messages.",
  "- If a quoted card shows the header contact's avatar/name (e.g., 'Bruce Chiang'), it means the OUTER bubble is quoting Bruce's OLD message. The OUTER bubble itself is still from whoever owns that bubble position (left or right).",
  "- NEVER let the avatar or name INSIDE a quoted card determine the speaker of the OUTER bubble. The outer bubble position (left/right) is the ONLY way to determine the current speaker.",
  "",
  "### SPECIFIC EXAMPLE: Single-Sided Screenshot with Quoted Replies",
  "- Scenario: Header shows 'Bruce Chiang'. All visible outer bubbles are on the LEFT side. Some bubbles contain red-bordered quoted cards showing 'Bruce Chiang' avatar.",
  "- CORRECT interpretation: This is screenSpeakerPattern: 'only_left'. ALL messages are from the contact (isFromMe: false). The quoted cards show Bruce's OLD messages being replied to.",
  "- WRONG interpretation: Thinking messages without Bruce's avatar are 'from me' (right side). This is WRONG because the outer bubble position is LEFT for all of them.",
  "- The presence or absence of an avatar in a quoted card does NOT change the outer bubble's side.",
  "",
  "### Screen Pattern Detection",
  "- Before deciding each row, first judge the whole screenshot's visible outer-bubble pattern as `mixed`, `only_left`, or `only_right`, ignoring quoted-reply inset cards.",
  "- If every visible outer bubble on the screen belongs to the left gutter and only the smaller quoted cards mention the other person, return `screenSpeakerPattern: only_left`.",
  "- If every visible outer bubble on the screen belongs to the right gutter and only the smaller quoted cards mention the other person, return `screenSpeakerPattern: only_right`.",
  "- When screenSpeakerPattern is `only_left`, ALL messages should be `isFromMe: false`. When it is `only_right`, ALL messages should be `isFromMe: true`.",
  "",
  "### Quoted Reply Handling",
  "- Treat LINE or Messenger quoted-reply previews as context, not as separate new messages.",
  "- In LINE reply UI, the smaller embedded card with avatar/name/light-gray text is usually quoted history. Do not output that embedded quoted card as its own message row.",
  "- If one outer bubble contains both an embedded quoted-reply card and a larger main reply text below it, keep only the larger main reply text as the current message.",
  "- If the quoted preview text is readable, attach it to the outer message as `quotedReplyPreview` instead of turning it into a standalone message row.",
  "- If the quoted preview text is too small or unreadable, omit `quotedReplyPreview` and still keep the outer main reply.",
  "- Do not split one outer bubble into two messages just because it contains a quoted preview plus the real reply.",
  "- This rule applies on both left-side and right-side bubbles. The quoted preview may refer to either speaker's old message, but the current speaker is still decided by the outer bubble side.",
  "- Never use the quoted preview avatar, name, or quoted-text author to override the speaker of the outer reply bubble.",
  '- Ignore LINE announcement banners, pinned-message jump banners, date separators, read receipts, timestamps, "回到最新訊息" style system hints, and other non-message UI. Do not turn them into chat messages.',
  "- If the screenshot was opened from a pinned announcement and starts in older history, only extract the visible real chat bubbles. Do not invent or summarize missing messages above the visible area.",
  "- Use a layout-first process: first identify each visible message bubble's horizontal side from the outer bubble/container position, then transcribe its content.",
  "- For every message, first decide the outer bubble column as `outerColumn: left | right | center` before deciding speaker.",
  "- Also estimate `horizontalPosition` as a rough 0-100 value for the outer bubble center, where 0 is far left, 50 is screen center, and 100 is far right.",
  "- If a bubble contains an embedded photo, screenshot, video preview, or sticker, determine `side` from the outer bubble frame on the main chat layout, never from the inner image content.",
  "- Determine `isFromMe` from bubble alignment first, not from wording, tone, or whose message would 'make sense' semantically.",
  "- In a normal one-to-one chat UI, left-side bubbles are usually the other person (`isFromMe: false`) and right-side bubbles are usually me (`isFromMe: true`).",
  "- If a bubble contains a quoted-reply preview card, keep the outer bubble on its own side, but also capture the quoted preview author as `quotedReplyPreviewIsFromMe` when that is visually clear.",
  "- Even for very short replies, stickers, image placeholders, or one-word bubbles like '超爽', follow the bubble side rather than guessing from meaning.",
  "- A photo, sticker, or image placeholder inside a clearly right-side bubble is still `isFromMe: true`; inside a clearly left-side bubble it is `isFromMe: false`.",
  "- If an image bubble and the next text bubble appear on the same side, keep them on the same speaker unless the layout clearly switches sides.",
  "- If a media/image bubble is visually sandwiched between two bubbles on the same side, keep the media bubble on that same side too.",
  "- Consecutive bubbles on the same side are common. Do not force alternating speakers if the layout still shows the same side.",
  "- Build a left/right side sequence for all visible outer bubbles in top-to-bottom order before deciding speakers. Preserve same-side runs exactly as they appear on screen.",
  "- Speaker changes should happen only when the visible outer bubble column actually switches sides. A pattern like left, left, left, right, right, left is normal and should stay that way.",
  "- Imagine a vertical midline through the screenshot first. Judge each outer bubble by whether the bubble body sits mostly left or mostly right of that midline before you read the text.",
  "- The outer bubble column is the source of truth across chat apps. Ignore quoted preview cards, inner screenshots, photo/video thumbnails, and avatar/no-avatar differences when deciding left vs right.",
  "- If the whole visible screen is one-sided, keep the whole run on that side even if quoted preview cards mention the other person's name or the app theme makes some bubbles look visually different.",
  "- In many chat apps, only the first bubble in a same-side run shows the avatar. Do not flip the last bubble in a left-side run to `isFromMe: true` just because the avatar disappears.",
  "- If multiple screenshots appear to come from different contacts or different chat threads, do not merge them as one clean thread. Lower confidence, set `importPolicy: confirm`, and explain that the screenshots may belong to different conversations.",
  "- Before returning JSON, double-check that no clearly right-aligned bubble is labeled `isFromMe: false` and no clearly left-aligned bubble is labeled `isFromMe: true`.",
  "- If a bubble side is genuinely ambiguous, keep the message but lower confidence and use `importPolicy: confirm` instead of making a confident guess.",
  "- Distinguish between a standalone phone call log screen and a one-to-one chat thread that contains missed-call or call-record entries.",
  "- If missed calls, outgoing calls, or answered-call records appear inside a normal chat thread with the contact header, treat them as valid conversation events instead of rejecting the screenshot outright.",
  "- Convert in-thread call records into messages while preserving direction: the other person's missed/incoming call is usually `isFromMe: false`, while my outgoing call is usually `isFromMe: true`.",
  "- If the screenshot looks like a social feed, comment thread, profile page, group chat, album, call-log page, sensitive media, or other non-chat UI, classify it with the most specific label: `social_feed`, `group_chat`, `gallery_album`, `call_log_screen`, `system_ui`, `sensitive_content`, or `unsupported`.",
  "- If text is blurry, cropped, or incomplete, lower confidence and use `importPolicy: confirm` instead of guessing.",
  "- If the contact name is unclear, return `contactName: null`.",
].join("\n");

const RECOGNIZED_CONVERSATION_SCHEMA = `{
  "recognizedConversation": {
    "contactName": "Alex",
    "screenSpeakerPattern": "mixed",
    "classification": "valid_chat",
    "importPolicy": "allow",
    "confidence": "high",
    "sideConfidence": "high",
    "uncertainSideCount": 0,
    "warning": null,
    "messageCount": 4,
    "summary": "A short summary of the visible exchange.",
    "messages": [
      { "outerColumn": "left", "horizontalPosition": 22, "side": "left", "isFromMe": false, "content": "Visible message from the other person", "quotedReplyPreview": "Optional quoted old message if readable", "quotedReplyPreviewIsFromMe": true },
      { "outerColumn": "right", "horizontalPosition": 78, "side": "right", "isFromMe": true, "content": "Visible message from me" }
    ]
  }
}

Example for single-sided screenshot (all left bubbles, header shows contact name like 'Bruce Chiang'):
{
  "recognizedConversation": {
    "contactName": null,
    "screenSpeakerPattern": "only_left",
    "classification": "valid_chat",
    "importPolicy": "allow",
    "confidence": "high",
    "sideConfidence": "high",
    "uncertainSideCount": 0,
    "warning": null,
    "messageCount": 5,
    "summary": "All visible messages are from the contact on the left side.",
    "messages": [
      { "outerColumn": "left", "horizontalPosition": 20, "side": "left", "isFromMe": false, "content": "到家一下了～～" },
      { "outerColumn": "left", "horizontalPosition": 20, "side": "left", "isFromMe": false, "content": "正要來吃晚餐！" },
      { "outerColumn": "left", "horizontalPosition": 20, "side": "left", "isFromMe": false, "content": "抱抱", "quotedReplyPreview": "辛苦北鼻了", "quotedReplyPreviewIsFromMe": true },
      { "outerColumn": "left", "horizontalPosition": 20, "side": "left", "isFromMe": false, "content": "好喜歡～～～", "quotedReplyPreview": "老師也有小獎品哦", "quotedReplyPreviewIsFromMe": true },
      { "outerColumn": "left", "horizontalPosition": 20, "side": "left", "isFromMe": false, "content": "等等吃飽打給北鼻" }
    ]
  }
}
Note: In the single-sided example, even though quoted cards show the header contact's name/avatar (e.g., 'Bruce Chiang'), ALL outer bubbles are on the LEFT, so ALL messages have isFromMe: false. The quotedReplyPreviewIsFromMe: true indicates the quoted OLD message was originally from me.`;

function joinPromptSections(
  ...sections: Array<string | undefined | null>
): string {
  return sections
    .map((section) => section?.trim())
    .filter((section): section is string => !!section)
    .join("\n\n");
}

function buildRecognizeOnlyImagePrompt(options: {
  imageCount: number;
  contextInfo: string;
  historicalContextInfo: string;
  compiledConversationText: string;
  knownContactName?: string;
}): string {
  const {
    imageCount,
    contextInfo,
    historicalContextInfo,
    compiledConversationText,
    knownContactName,
  } = options;

  return joinPromptSections(
    `You received ${imageCount} chat screenshot(s). Extract the visible conversation only and return the JSON schema below.`,
    SCREENSHOT_OCR_ACCURACY_RULES,
    "### Quote Preview Rules\n- In LINE-style quoted replies, the smaller inset quote card is context, not a new live message row.\n- This is true even when the inset card only shows the old message body and the quoted author's name is missing or too small to read.\n- Keep the quoted snippet in `quotedReplyPreview`, then keep the larger outer bubble as the actual message row.\n- If the quoted author is visually clear, also fill `quotedReplyPreviewIsFromMe`; if not, leave it empty.\n- Preserve visible names and nicknames exactly as shown in the screenshot header or quote card. Do not guess or normalize similar-looking Han characters.\n- IMPORTANT: If the quoted card shows the same name as the chat header (e.g., header='Bruce' and quoted card shows 'Bruce'), it means the contact is quoting old messages. The quoted card name does NOT change who is sending the OUTER bubble.\n- When all outer bubbles are visually on the LEFT side and only quoted cards reference the header contact, set `screenSpeakerPattern: only_left` and ALL messages must have `isFromMe: false`.",
    "### Output Rules\n- Return only `recognizedConversation`.\n- Do not include extra analysis fields.\n- Use `classification`, `importPolicy`, and `confidence` conservatively.\n- Valid `classification` values are: `valid_chat`, `low_confidence`, `social_feed`, `group_chat`, `gallery_album`, `call_log_screen`, `system_ui`, `sensitive_content`, `unsupported`.\n- If the thread only contains missed-call or call-record entries but is still a normal one-to-one chat view, return those call events as messages instead of rejecting the screenshot outright.\n- Determine each bubble's `side` from the outer chat layout first, before reading the text inside that bubble.\n- For speaker direction, layout beats semantics: a clearly right-side bubble should stay `isFromMe: true` even if the text itself is very short or could also sound like the other person.\n- This also applies to media placeholders and image-in-image content: a right-side photo bubble must not be flipped to `她說` just because the OCR text or the inner image content is generic.\n- If multiple visible bubbles continue on the same left side, keep them as the other person even when only the first bubble shows an avatar; do not treat missing-avatar rows as an automatic side switch.\n- If a quoted-reply preview is readable, keep it on the same outer message as `quotedReplyPreview`; do not emit it as a separate row.\n- If the quoted preview is readable and the quoted card author is visually clear, include `quotedReplyPreviewIsFromMe` for that quoted snippet. This metadata is for the quoted card only and must not override the outer bubble speaker.\n- If the quoted preview is unreadable, leave `quotedReplyPreview` empty instead of guessing.\n- For each returned message, include `outerColumn` as `left`, `right`, or `center`, and include `horizontalPosition` as an approximate 0-100 number for the outer bubble center.\n- For each returned message, include `side` as `left`, `right`, or `unknown`. If `outerColumn` or `horizontalPosition` is clear, keep `side` and `isFromMe` consistent with that geometry.",
    "### JSON Schema",
    RECOGNIZED_CONVERSATION_SCHEMA,
    contextInfo
      ? `${contextInfo}\n- Use this only as weak context for mismatch detection.`
      : "",
    knownContactName
      ? `## Known Contact Name\n- Existing thread contact name: ${knownContactName}\n- Use this only as a tie-breaker when the visible header or nickname is almost the same and OCR is uncertain by one similar-looking character.`
      : "",
    historicalContextInfo,
    compiledConversationText
      ? `## Existing Thread Context\n${compiledConversationText}\nUse this only to judge whether the screenshot likely belongs to the same thread.`
      : "",
  );
}

function buildImageAnalysisPrompt(options: {
  imageCount: number;
  contextInfo: string;
  historicalContextInfo: string;
  compiledConversationText: string;
  knownContactName?: string;
}): string {
  const {
    imageCount,
    contextInfo,
    historicalContextInfo,
    compiledConversationText,
    knownContactName,
  } = options;

  return joinPromptSections(
    `You received ${imageCount} chat screenshot(s). First extract the visible conversation, then analyze it and return the normal structured JSON response.`,
    SCREENSHOT_OCR_ACCURACY_RULES,
    "### Quote Preview Rules\n- In LINE-style quoted replies, the smaller inset quote card is context, not a new live message row.\n- This is true even when the inset card only shows the old message body and the quoted author's name is missing or too small to read.\n- Keep the quoted snippet in `quotedReplyPreview`, then keep the larger outer bubble as the actual message row.\n- If the quoted author is visually clear, also fill `quotedReplyPreviewIsFromMe`; if not, leave it empty.\n- Preserve visible names and nicknames exactly as shown in the screenshot header or quote card. Do not guess or normalize similar-looking Han characters.\n- IMPORTANT: If the quoted card shows the same name as the chat header (e.g., header='Bruce' and quoted card shows 'Bruce'), it means the contact is quoting old messages. The quoted card name does NOT change who is sending the OUTER bubble.\n- When all outer bubbles are visually on the LEFT side and only quoted cards reference the header contact, set `screenSpeakerPattern: only_left` and ALL messages must have `isFromMe: false`.",
    "### Additional Rules\n- Always include `recognizedConversation` in the response.\n- Base the final analysis on the screenshot content plus any existing thread context.\n- If the screenshot is likely unsupported, set `recognizedConversation.importPolicy` to `reject` and explain why in `warning`.\n- Prefer the most specific `classification` from: `valid_chat`, `low_confidence`, `social_feed`, `group_chat`, `gallery_album`, `call_log_screen`, `system_ui`, `sensitive_content`, `unsupported`.\n- Do not reject a screenshot only because the visible thread is dominated by call records, as long as it is still clearly a one-to-one chat conversation view.\n- Build `recognizedConversation.messages` with a layout-first pass: identify bubble side from the screen position first, then transcribe content.\n- When `recognizedConversation.messages` is built, verify speaker direction from bubble side before finalizing the JSON. Do not let semantic inference override a clearly left- or right-aligned bubble.\n- If a LINE-style bubble contains a quoted-reply preview card plus a larger main reply, only keep the larger main reply in `recognizedConversation.messages`; store the readable quoted text in `quotedReplyPreview` instead of emitting a separate message row.\n- If that quoted card clearly belongs to me or the other person, include `quotedReplyPreviewIsFromMe` for the quoted snippet. This quoted-card metadata must never flip the outer reply bubble's speaker.\n- If the quoted preview is too small or unclear, omit `quotedReplyPreview` rather than guessing.\n- Be extra careful with media rows: image bubbles and the text bubble immediately after them often belong to the same side and should not be split across two speakers unless the layout clearly changes.\n- If a bubble contains a screenshot/photo/video preview, use the outer bubble container to decide side; ignore the inner image contents for speaker assignment.\n- If the screenshots seem to mix two different contacts or unrelated thread segments, do not silently merge them into a clean conversation. Mark it low-confidence and explain the mismatch in `warning`.",
    "### recognizedConversation Schema",
    RECOGNIZED_CONVERSATION_SCHEMA,
    contextInfo,
    knownContactName
      ? `## Known Contact Name\n- Existing thread contact name: ${knownContactName}\n- Use this only as a tie-breaker when the visible header or nickname is almost the same and OCR is uncertain by one similar-looking character.`
      : "",
    historicalContextInfo,
    compiledConversationText
      ? `## Existing Thread Context\n${compiledConversationText}`
      : "",
  );
}

const SYSTEM_PROMPT =
  `你是一位專業的社交溝通教練，幫助用戶提升對話技巧，最終目標是幫助用戶成功邀約。

## AI 核心人設

你的建議必須體現以下心態：

### 1. 富裕心態 (Abundance Mindset)
- 表現得像是一個生活豐富、不缺社交對象的高價值男性
- 不害怕失去話題，不患得患失
- 不急於表現或討好對方

### 2. 情緒穩定 (Emotional Stability)
- 永遠保持從容，面對測試、抱怨或冷淡，絕不急躁
- 不展現防禦心、不生氣、不長篇大論解釋
- 允許對方有自己的情緒和想像空間

### 3. 邊界感清晰 (Clear Boundaries)
- 「對方的情緒是她自己的課題」
- 不主動干預、不說教、不急於解決對方的心理問題
- 不因對方不回訊息就覺得自己說錯話

### 4. 真實且謙遜 (Grounded & Humble)
- 展現高價值的同時，語氣保持低調與自我解嘲
- 不炫耀、不裝逼，也不刻意裝窮
- 高價值展示後要「接地氣」

### 5. 自嘲 vs 自貶（極重要）
- ✅ 自嘲：從高位往下輕鬆看自己，不當真
  - 「我就是這麼隨性」「沒事亂問的哈哈」
- ❌ 自貶：真的覺得自己不好、道歉、求認可
  - 「變成了怪人」「可能我太奇怪了」「不好意思讓你覺得奇怪」
- 自嘲保持框架，自貶丟失框架

### 6. 正常人說話原則
- 回覆要像正常朋友聊天，不要像 AI 或機器人
- 不要用太文縐縐或太刻意的措辭
- 簡單直接 > 複雜修飾
- ❌ 「沒什麼特別原因，就是想當個有趣的人結果變成了怪人」
- ✅ 「沒事亂問的，我就是這麼隨性哈哈」

## GAME 五階段框架

分析對話處於哪個階段：
1. Opening (打開) - 破冰階段
2. Premise (前提) - 進入男女框架，建立張力
3. Qualification (評估) - 她證明自己配得上用戶
4. Narrative (敘事) - 個性樣本、說故事
5. Close (收尾) - 模糊邀約 → 確立邀約

## 場景觸發矩陣

根據對話情境自動識別並給出對應策略：

### 情境1: 目的性測試
- 觸發: 詢問交友軟體使用目的（如：「你玩這個是為了交友還是...？」）
- 策略: 模糊化與幽默感，不正面回答，留白讓對方腦補
- 範例: 「這個不好說。」「找飯搭子啊。」「如果說是為了性，會不會顯得我很膚淺？」

### 情境2: 情緒試探與抱怨
- 觸發: 抱怨回覆太慢、指責沒有邊界感、說氣話
- 策略: 陳述事實，不解釋不道歉，保持中立
- 範例: 「剛到家。」「你觀察蠻仔細的，晚安。」

### 情境2.5: 被質疑/輕微測試
- 觸發: 「為什麼會這樣問」「你怎麼會問這個」等質疑
- 策略: 輕鬆帶過，不防禦、不道歉、不自貶
- ✅ 正確範例: 「沒事亂問的，我就是這麼隨性哈哈」「好奇嘛」「想到就問了」
- ❌ 錯誤範例: 「不好意思讓你覺得奇怪」「我變成怪人了」「可能問得太突然」

### 情境3: 展示冷淡/狀態差
- 觸發: 表達不想出門、覺得累、沒興趣約會
- 策略: 提供情緒價值，不把冷淡當作針對自己，用玩笑輕鬆帶過
- 範例: 「那太虧了，妳都是怎麼度過的呀？」「擺爛也是一種選擇。」

### 情境4: 模糊邀約
- 觸發: 給出不明確的見面暗示（如：「等天氣暖和一點我們見面吧」）
- 策略: 保持隨緣，不顯飢渴，同意但不急著敲定時間
- 範例: 「隨緣吧。」「要不今晚夢裡見也行，夢裡什麼都能幹還不用負責。」

### 情境5: 斷聯後的破冰
- 觸發: 超過一週以上沒有互動
- 策略: 低壓力環境分享，不提過去為何沒聊，直接分享當下的正面日常
- 範例: 「這兩天天氣好好。」「最近工作忙嗎？」

### 情境6: 正式確立邀約
- 觸發: 對方明確同意碰面
- 策略: 展現帶領力，不再反問對方意見，直接給出明確的人事時地物選項
- 範例: 「約這裡怎麼樣？幾點方便？」（搭配地點截圖）

## 最高指導原則

### 1. 1.8x 黃金法則
所有建議回覆的字數必須 ≤ 對方「單條」訊息字數 × 1.8
這條規則不可違反。

### 1.2 多條訊息處理規則
如果對方連續發了多條訊息，根據訊息類型決定是否回覆：

| 訊息類型 | 是否回覆 | 範例 |
|----------|----------|------|
| 肯定句/是非句 | ❌ 不需回覆 | 「對啊」「嗯嗯」「好」 |
| 陳述句 | 熱度 > 50 才回覆 | 「我今天去看電影」 |
| 疑問句 | ✅ 必須回覆 | 「你呢？」「為什麼？」 |
| 圖片/貼圖 | ✅ 必須回覆 | [圖片] |

**輸出格式**：當對方有多條訊息時，針對每條需要回覆的訊息分別給建議。

### 1.5 回覆結構指南
**優先考慮兩段式**（在 1.8x 限制內）：
- 第一部分：回應/共鳴/觀察
- 第二部分：延伸/提問/冷讀
- ✅ 「Laufey的聲音確實很有質感，你最近的主打歌是哪首？」

**但以下情況用簡短一句更好**：
- 幽默/調侃時：簡短更有力 → 「那太虧了吧」
- 對方訊息很短時：配合節奏 → 「隨緣吧」
- 維持框架時：不解釋不道歉 → 「剛到家。」
- 推拉/抽離時：故意簡短 → 「是喔」

**判斷標準**：對話是否能自然延續？太單薄就加第二句，夠豐富就保持簡潔。

### 2. 70/30 法則
好的對話是 70% 聆聽 + 30% 說話
- 用戶不該一直問問題 (索取)
- 要適時分享故事 (提供)

### 3. 具體化原則
- ❌ 「有特別喜歡哪個歌手嗎？」(太泛、面試感)
- ✅ 「你是 Taylor Swift 粉嗎？」(具體、有話題延伸性)
- 用具體名字/事物而非泛問

### 4. 小服從性訓練
- 讓對方做小事，建立投入感
- ✅ 「你最近的主打歌是哪首？我聽聽」(請她分享)
- ✅ 「推薦一家你覺得不錯的？」(請她推薦)

### 5. 假設代替問句
- ❌ 「你是做什麼工作的？」(面試感)
- ✅ 「感覺你是做創意相關的工作？」(冷讀)

### 6. 陳述優於問句
朋友間直接問句比較少，陳述句讓對話更自然

### 7. Topic Depth Ladder
- Level 1: Event-oriented (Events) - 剛認識
- Level 2: Personal-oriented (Personal) - 有基本認識
- Level 3: Intimate-oriented (Intimate) - 熱度 > 60
- 原則：不可越級，循序漸進

### 8. 細緻化優先
- 不要一直換話題
- 針對對方回答深入挖掘

### 9. 不查戶口
- 絕對禁止詢問對方的隱私（身高體重、過往情史等）
- 當沒有好話題時，可以回覆：「暫時沒想到要問什麼」

### 10. 熱度分析規則
熱度 (enthusiasm) 只根據「她」的訊息判斷，不考慮「我」的發言：
- 回覆長度：長回覆 > 短回覆
- 表情符號：多 emoji/顏文字 = 較熱
- 主動提問：她問你問題 = 好奇/有興趣
- 話題延伸：她主動延伸話題 = 投入
- 回應態度：敷衍單字 vs 認真回應
- 不要因為「我」說了很多就拉高熱度

## 核心技巧

### 隱性價值展示 (DHV)
- 一句話帶過，不解釋
- 例：「剛從北京出差回來」而非「我很常出國」
- 展示後要保持謙遜，適當自嘲

### 框架控制
- 不因對方攻擊/挑釁/廢測而改變
- 不用點對點回答問題
- 可以跳出問題框架思考

### 廢物測試 (Shit Test)
- 廢測是好事，代表她在評估用戶
- 橡膠球理論：讓它彈開
- 回應方式：幽默曲解 / 直球但維持框架 / 忽略

### 淺溝通解讀
- 女生文字背後的意思 > 字面意思
- 一致性測試藏在文字裡

## 進階對話技巧

### 橫向思維 (Lateral Thinking)
- 用「這讓我想到...」連結不相關的事物
- 創造意想不到的連結，展現創意與幽默
- ❌ 她：「我週末去爬山」→「哪座山？」
- ✅ 她：「我週末去爬山」→「這讓我想到，我小時候以為山頂住著神仙」

### 剝洋蔥效應 (Peeling the Onion)
- 問「為什麼」而非「什麼」，挖掘深層動機
- 人們喜歡談論自己的原因，而非事實
- ❌ 「你做什麼工作？」→「工程師」→「在哪家公司？」
- ✅ 「你做什麼工作？」→「工程師」→「什麼讓你選擇這行？」

### 守護空間 (Holding Space)
- 當她分享負面情緒時，不急著給建議或解決
- 先共情、傾聽，讓她感覺被理解
- ❌ 她：「工作壓力好大」→「你應該換工作」
- ✅ 她：「工作壓力好大」→「聽起來真的很累，最近發生什麼事了？」

### 書籤技術 (Bookmarking)
- 標記有趣話題，稍後回來深入
- 「這個等下一定要聽你說」「先記住這個，回頭聊」
- 創造期待感，展現你在認真聽

### IOI/IOD 判讀
**IOI (興趣指標)**：
- 主動延伸話題、問你問題
- 用 emoji/顏文字、回覆速度快
- 分享個人資訊、笑聲（哈哈、XD）

**IOD (無興趣指標)**：
- 回覆簡短單字、長時間已讀不回
- 不問你問題、敷衍語氣
- 頻繁結束話題

### 假設性提問
- 用有趣假設打破乾聊
- 「如果你有超能力，你會選什麼？」
- 「如果明天不用上班，你第一件事做什麼？」
- 注意：只在對話卡住時使用，不要連續用

## 幽默機制

### 良性冒犯 (Benign Violation)
- 輕微打破規範，但不傷人
- 自嘲、輕微調侃、預期翻轉
- 「我很會做飯，前提是你不介意吃黑暗料理」

### 三段式法則 (Rule of Three)
- 前兩個建立模式，第三個打破預期
- 「我週末三大愛好：睡覺、追劇、假裝有社交生活」

### 回調 (Callback)
- 引用之前對話的內容製造笑點
- 建立共同記憶，展現你有在聽
- 「哈，這又讓我想到你說的那個神仙山」

### 幽默禁區
- 不嘲笑她在意的事
- 不開她外表/身材的玩笑
- 不用貶低他人來逗笑

## 對話平衡

### 不要搶話
- 她分享經驗時，不要馬上說「我也是」然後講自己
- 先深入她的話題，再自然分享
- ❌ 她：「我最近學滑板」→「我也會滑板，我還⋯⋯」
- ✅ 她：「我最近學滑板」→「真的嗎？是什麼讓你想學的？」

### 給予空間
- 不要每句話都回得很長
- 有時候簡短回應讓她有空間說更多
- 「然後呢？」「說來聽聽」也是好回覆

## 個人化原則
如果有提供用戶風格，回覆建議要符合該風格的說話方式：
- 幽默型：多用輕鬆俏皮的語氣
- 穩重型：沉穩內斂，不輕浮
- 直球型：簡單直接，不繞圈子
- 溫柔型：細膩體貼，照顧對方感受
- 調皮型：帶點挑逗，製造小驚喜

如果有提供對方特質，策略要考慮對方的個性。

## 冰點特殊處理
當熱度 0-30 且判斷機會渺茫時：
- 不硬回
- 可建議「已讀不回」
- 鼓勵開新對話

## 輸出格式 (JSON)
{
  "gameStage": {
    "current": "premise",
    "status": "正常進行",
    "nextStep": "可以開始評估階段"
  },
  "scenarioDetected": "normal | purpose_test | emotion_test | cold_display | vague_invite | reconnect | confirm_invite",
  "enthusiasm": { "score": 75, "level": "hot" },
  "topicDepth": { "current": "Personal-oriented", "suggestion": "可以往曖昧導向推進" },
  "psychology": {
    "subtext": "她這句話背後的意思是：對你有興趣",
    "shitTest": {
      "detected": false,
      "type": null,
      "suggestion": null
    },
    "qualificationSignal": true
  },
  "herMessages": [
    {
      "content": "她的第一條訊息",
      "type": "question",
      "shouldReply": true,
      "replies": {
        "extend": "...",
        "resonate": "...",
        "tease": "...",
        "humor": "...",
        "coldRead": "..."
      }
    }
  ],
  "replies": {
    "extend": "針對最後一條訊息的回覆",
    "resonate": "...",
    "tease": "...",
    "humor": "...",
    "coldRead": "..."
  },
  "finalRecommendation": {
    "pick": "tease",
    "content": "推薦的完整回覆內容（可能包含多條訊息的回應）",
    "reason": "為什麼推薦這個回覆",
    "psychology": "心理學依據"
  },
  "warnings": [],
  "healthCheck": {
    "issues": ["面試式提問過多"],
    "suggestions": ["用假設代替問句"]
  },
  "strategy": "簡短策略說明",
  "reminder": "記得用你的方式說，見面才自然"
}

## 用戶訊息優化功能
如果用戶提供了「想說的內容」(userDraft)，根據以上原則優化：
1. 套用 1.8x 法則（依據她最後一則訊息長度）
2. 避免自貶，改用自嘲
3. 套用兩段式結構（如適用）
4. 符合用戶風格設定
5. 保持正常人說話的語氣

輸出 optimizedMessage 欄位：
{
  "optimizedMessage": {
    "original": "用戶原本想說的",
    "optimized": "優化後的版本",
    "reason": "簡短說明優化了什麼"
  }
}

**reason 欄位規則（重要）**：
- ❌ 禁止提及「1.8x法則」、「黃金法則」或任何字數計算公式
- ❌ 禁止顯示「她X字，建議≤Y字」這類計算
- ✅ 用自然的描述：「縮短讓訊息更簡潔」「精簡字數」
- ✅ 範例：「精簡字數、用『耶』讓語氣更自然」

${SAFETY_RULES}`;

// 「我說」模式的 System Prompt（話題延續建議）
const MY_MESSAGE_PROMPT =
  `你是一位專業的社交溝通教練。用戶剛剛發送了一則訊息給對方，現在需要你根據對話脈絡，提供話題延續的建議。

## 你的任務

根據：
1. 用戶剛發送的訊息
2. 之前對話中了解到的「她」的特質、興趣、話題
3. 目前的對話熱度和階段

提供：
1. 如果她冷淡回覆，可以怎麼延續
2. 如果她熱情回覆，可以怎麼深入
3. 備用話題方向（根據她之前提過的興趣）
4. 注意事項（避免踩雷）

## 輸出格式 (JSON)

{
  "myMessageAnalysis": {
    "sentMessage": "用戶剛發送的訊息",
    "ifColdResponse": {
      "prediction": "她可能的冷淡回覆",
      "suggestion": "你可以這樣接"
    },
    "ifWarmResponse": {
      "prediction": "她可能的熱情回覆",
      "suggestion": "你可以這樣深入"
    },
    "backupTopics": [
      "根據她之前提過喜歡咖啡 → 可以聊最近喝到的好店",
      "她說過週末喜歡追劇 → 可以問最近在看什麼"
    ],
    "warnings": [
      "她之前對工作話題反應冷淡，避免再提"
    ]
  },
  "enthusiasm": { "score": 50, "level": "warm" }
}

## 重要原則
- 建議要具體可執行，不要泛泛而談
- 備用話題要根據對話中「她」提過的內容
- 如果對話太短沒有足夠資訊，就說「對話還太短，多聊幾輪後會更了解她」

${SAFETY_RULES}`;

// 訊息計算函數
function countMessages(messages: Array<{ content: string }>): number {
  let total = 0;
  for (const msg of messages) {
    const charCount = msg.content.trim().length;
    total += Math.max(1, Math.ceil(charCount / 200));
  }
  return Math.max(1, total);
}

function normalizeScreenshotClassification(
  value: unknown,
  messageCount: number,
  ...hints: Array<unknown>
): string {
  if (
    typeof value === "string" &&
    VALID_SCREENSHOT_CLASSIFICATIONS.has(value)
  ) {
    return value;
  }

  const inferredClassification = inferScreenshotClassificationHint(
    value,
    ...hints,
  );
  if (inferredClassification) {
    return inferredClassification;
  }

  if (messageCount <= 0) {
    return "unsupported";
  }

  if (messageCount < 2) {
    return "low_confidence";
  }

  return "valid_chat";
}

function inferScreenshotClassificationHint(
  ...values: Array<unknown>
): string | undefined {
  for (const value of values) {
    if (typeof value !== "string" || !value.trim()) {
      continue;
    }

    const lower = value.trim().toLowerCase();

    if (
      lower.includes("group chat") ||
      lower.includes("group conversation") ||
      lower.includes("multiple participants") ||
      lower.includes("多人聊天") ||
      lower.includes("群組聊天") ||
      lower.includes("群聊")
    ) {
      return "group_chat";
    }

    if (
      lower.includes("gallery") ||
      lower.includes("album") ||
      lower.includes("camera roll") ||
      lower.includes("photo picker") ||
      lower.includes("相簿") ||
      lower.includes("照片庫") ||
      lower.includes("選圖畫面")
    ) {
      return "gallery_album";
    }

    if (
      lower.includes("call log") ||
      lower.includes("recent calls") ||
      lower.includes("phone app") ||
      lower.includes("通話紀錄") ||
      lower.includes("最近通話")
    ) {
      return "call_log_screen";
    }

    if (
      lower.includes("notification center") ||
      lower.includes("control center") ||
      lower.includes("system notification") ||
      lower.includes("settings page") ||
      lower.includes("通知中心") ||
      lower.includes("控制中心") ||
      lower.includes("設定頁面") ||
      lower.includes("系統畫面")
    ) {
      return "system_ui";
    }

    if (
      lower.includes("adult") ||
      lower.includes("nudity") ||
      lower.includes("sexual") ||
      lower.includes("explicit") ||
      lower.includes("violent") ||
      lower.includes("gore") ||
      lower.includes("色情") ||
      lower.includes("裸露") ||
      lower.includes("暴力") ||
      lower.includes("血腥")
    ) {
      return "sensitive_content";
    }

    if (
      lower.includes("social feed") ||
      lower.includes("comment thread") ||
      lower.includes("profile page") ||
      lower.includes("社群") ||
      lower.includes("貼文") ||
      lower.includes("留言串")
    ) {
      return "social_feed";
    }
  }

  return undefined;
}

function normalizeImportPolicy(
  value: unknown,
  classification: string,
): string {
  if (typeof value === "string" && VALID_IMPORT_POLICIES.has(value)) {
    return value;
  }

  switch (classification) {
    case "social_feed":
    case "group_chat":
    case "gallery_album":
    case "call_log_screen":
    case "system_ui":
    case "sensitive_content":
    case "unsupported":
      return "reject";
    case "low_confidence":
      return "confirm";
    default:
      return "allow";
  }
}

function normalizeConfidenceLabel(
  value: unknown,
  classification: string,
  messageCount: number,
): string {
  if (
    value === "high" || value === "medium" || value === "low"
  ) {
    return value;
  }

  if (classification === "valid_chat" && messageCount >= 4) {
    return "high";
  }

  if (classification === "low_confidence") {
    return "low";
  }

  return "medium";
}

function isCallEventLikeMessage(content: string): boolean {
  const normalized = content.trim().toLowerCase();
  if (!normalized) {
    return false;
  }

  return CALL_EVENT_KEYWORDS.some((keyword) =>
    normalized.includes(keyword.toLowerCase())
  );
}

function isLikelyChatThreadCallEventScreenshot(
  messages: Array<{ isFromMe: boolean; content: string }>,
): boolean {
  return messages.length > 0 &&
    messages.every((message) => isCallEventLikeMessage(message.content));
}

function isLikelyMediaPlaceholderContent(content: string): boolean {
  const normalized = content.trim().toLowerCase();
  if (!normalized) {
    return false;
  }

  return normalized.startsWith("[photo") ||
    normalized.startsWith("[image") ||
    normalized.startsWith("[sticker") ||
    normalized.startsWith("[video") ||
    normalized.includes("photo of ") ||
    normalized.includes("image of ") ||
    normalized.includes("shared a photo") ||
    normalized.includes("sent a photo") ||
    normalized.includes("uploaded a photo");
}

function isLikelyShortContinuationContent(content: string): boolean {
  const trimmed = content.trim();
  if (!trimmed) {
    return false;
  }

  if (
    isLikelyMediaPlaceholderContent(trimmed) ||
    isLikelyQuotedReplyPreviewContent(trimmed)
  ) {
    return false;
  }

  const compact = trimmed.replace(/\s+/g, "");
  return compact.length <= 24;
}

function sanitizeQuotedReplyPreviewValue(value: unknown): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }

  const trimmed = value.trim();
  if (!trimmed) {
    return undefined;
  }

  return trimmed.slice(0, MAX_QUOTED_REPLY_PREVIEW_LENGTH);
}

function sanitizeContactNameValue(value: unknown): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }

  const trimmed = value.trim().replace(/\s+/g, " ");
  if (!trimmed || trimmed.length > MAX_CONTACT_NAME_LENGTH) {
    return undefined;
  }

  if (/[\r\n\t]/.test(trimmed)) {
    return undefined;
  }

  return trimmed;
}

function normalizeVisibleSpeakerPattern(value: unknown): VisibleSpeakerPattern {
  if (typeof value !== "string") {
    return "unknown";
  }

  const normalized = value.trim().toLowerCase();
  if (normalized === "mixed") {
    return "mixed";
  }
  if (
    normalized === "only_left" ||
    normalized === "left_only" ||
    normalized === "single_left"
  ) {
    return "only_left";
  }
  if (
    normalized === "only_right" ||
    normalized === "right_only" ||
    normalized === "single_right"
  ) {
    return "only_right";
  }

  return "unknown";
}

function normalizeContactNameForComparison(value: string): string {
  return value.replace(/\s+/g, "").toLowerCase();
}

function countSingleCharacterDifferences(a: string, b: string): number | null {
  const left = Array.from(a);
  const right = Array.from(b);
  if (left.length !== right.length) {
    return null;
  }

  let differences = 0;
  for (let index = 0; index < left.length; index += 1) {
    if (left[index] !== right[index]) {
      differences += 1;
      if (differences > 1) {
        return differences;
      }
    }
  }

  return differences;
}

function shouldPreferKnownContactName(
  recognizedContactName: string,
  knownContactName: string | undefined,
): boolean {
  if (!knownContactName) {
    return false;
  }

  const normalizedRecognized = normalizeContactNameForComparison(
    recognizedContactName,
  );
  const normalizedKnown = normalizeContactNameForComparison(knownContactName);

  if (!normalizedRecognized || !normalizedKnown) {
    return false;
  }

  if (normalizedRecognized === normalizedKnown) {
    return true;
  }

  const singleCharacterDifference = countSingleCharacterDifferences(
    normalizedRecognized,
    normalizedKnown,
  );
  return singleCharacterDifference === 1;
}

function stabilizeRecognizedContactName({
  recognizedContactName,
  knownContactName,
}: {
  recognizedContactName: unknown;
  knownContactName?: string;
}): string | null {
  const sanitizedRecognized = sanitizeContactNameValue(recognizedContactName);
  const sanitizedKnown = sanitizeContactNameValue(knownContactName);

  if (!sanitizedRecognized) {
    return null;
  }

  if (shouldPreferKnownContactName(sanitizedRecognized, sanitizedKnown)) {
    return sanitizedKnown!;
  }

  return sanitizedRecognized;
}

function applySingleVisibleSpeakerPattern(
  messages: NormalizedRecognizedMessage[],
  pattern: VisibleSpeakerPattern,
): {
  messages: NormalizedRecognizedMessage[];
  adjustedCount: number;
} {
  if (pattern !== "only_left" && pattern !== "only_right") {
    return {
      messages,
      adjustedCount: 0,
    };
  }

  const targetSide: RecognizedBubbleSide =
    pattern === "only_left" ? "left" : "right";
  const targetIsFromMe = targetSide === "right";
  const adjusted = messages.map((message) => ({ ...message }));
  let adjustedCount = 0;

  for (let index = 0; index < adjusted.length; index += 1) {
    if (
      adjusted[index].side !== targetSide ||
      adjusted[index].isFromMe !== targetIsFromMe
    ) {
      adjusted[index] = {
        ...adjusted[index],
        side: targetSide,
        isFromMe: targetIsFromMe,
      };
      adjustedCount += 1;
    }
  }

  return {
    messages: adjusted,
    adjustedCount,
  };
}

function normalizeQuotedReplyPreviewIsFromMe(
  record: Record<string, unknown>,
): boolean | undefined {
  if (typeof record.quotedReplyPreviewIsFromMe === "boolean") {
    return record.quotedReplyPreviewIsFromMe;
  }

  const rawQuotedReplyPreviewSide =
    typeof record.quotedReplyPreviewSide === "string"
      ? record.quotedReplyPreviewSide.trim().toLowerCase()
      : "";

  if (rawQuotedReplyPreviewSide === "right") {
    return true;
  }

  if (rawQuotedReplyPreviewSide === "left") {
    return false;
  }

  return undefined;
}

function extractQuotedReplyPreviewContent(content: string): string | undefined {
  const originalLines = content
    .split(/\n+/)
    .map((line) => line.trim())
    .filter(Boolean);

  if (originalLines.length === 0) {
    return undefined;
  }

  const lines = originalLines.length > 0 &&
      isLikelyQuotedReplyPreviewLabelLine(originalLines[0])
    ? originalLines.slice(1)
    : originalLines;

  if (lines.length >= 2 && isLikelyQuotedReplyPreviewNameLine(lines[0])) {
    const previewBody = lines.slice(1).join(" ").trim();
    return previewBody || undefined;
  }

  return content.trim() || undefined;
}

function normalizeComparableMessageText(content: string): string {
  return content
    .trim()
    .toLowerCase()
    .replace(/\s+/g, " ")
    .replace(/[“”"]/g, "'")
    .replace(/[，、]/g, ",")
    .replace(/[。]/g, ".")
    .replace(/[！]/g, "!")
    .replace(/[？]/g, "?");
}

function shouldDeduplicateSequentialMessage(
  previous: NormalizedRecognizedMessage,
  current: NormalizedRecognizedMessage,
): boolean {
  const sideMatches = previous.side !== "unknown" && current.side !== "unknown"
    ? previous.side === current.side
    : previous.isFromMe === current.isFromMe;

  if (!sideMatches) {
    return false;
  }

  return normalizeComparableMessageText(previous.content) ===
    normalizeComparableMessageText(current.content);
}

function choosePreferredQuotedReplyPreview(
  previous: string | undefined,
  current: string | undefined,
): string | undefined {
  const previousValue = previous?.trim();
  const currentValue = current?.trim();

  if (!previousValue) {
    return currentValue || undefined;
  }

  if (!currentValue) {
    return previousValue;
  }

  return currentValue.length > previousValue.length
    ? currentValue
    : previousValue;
}

function choosePreferredQuotedReplyPreviewIsFromMe({
  previousPreview,
  previousIsFromMe,
  currentPreview,
  currentIsFromMe,
}: {
  previousPreview: string | undefined;
  previousIsFromMe: boolean | undefined;
  currentPreview: string | undefined;
  currentIsFromMe: boolean | undefined;
}): boolean | undefined {
  const previousValue = previousPreview?.trim();
  const currentValue = currentPreview?.trim();

  if (!previousValue) {
    return currentValue ? currentIsFromMe : undefined;
  }

  if (!currentValue) {
    return previousIsFromMe;
  }

  if (currentValue.length > previousValue.length) {
    return currentIsFromMe;
  }

  return previousIsFromMe;
}

function deduplicateSequentialMessages(
  messages: NormalizedRecognizedMessage[],
): {
  messages: NormalizedRecognizedMessage[];
  removedCount: number;
} {
  if (messages.length < 2) {
    return {
      messages,
      removedCount: 0,
    };
  }

  const deduplicated: NormalizedRecognizedMessage[] = [];
  let removedCount = 0;

  for (const message of messages) {
    const previous = deduplicated[deduplicated.length - 1];

    if (previous && shouldDeduplicateSequentialMessage(previous, message)) {
      const previousQuotedReplyPreview = previous.quotedReplyPreview;
      const preferredQuotedReplyPreview = choosePreferredQuotedReplyPreview(
        previous.quotedReplyPreview,
        message.quotedReplyPreview,
      );
      previous.quotedReplyPreview = preferredQuotedReplyPreview;
      previous.quotedReplyPreviewIsFromMe =
        choosePreferredQuotedReplyPreviewIsFromMe({
          previousPreview: previousQuotedReplyPreview,
          previousIsFromMe: previous.quotedReplyPreviewIsFromMe,
          currentPreview: message.quotedReplyPreview,
          currentIsFromMe: message.quotedReplyPreviewIsFromMe,
        });
      removedCount += 1;
      continue;
    }

    deduplicated.push({ ...message });
  }

  return {
    messages: deduplicated,
    removedCount,
  };
}

function normalizeBubbleSide(
  record: Record<string, unknown>,
): RecognizedBubbleSide {
  const rawOuterColumn = typeof record.outerColumn === "string"
    ? record.outerColumn.trim().toLowerCase()
    : "";
  if (rawOuterColumn === "right") {
    return "right";
  }

  if (rawOuterColumn === "left") {
    return "left";
  }

  const rawHorizontalPosition = typeof record.horizontalPosition === "number"
    ? record.horizontalPosition
    : typeof record.horizontalPosition === "string"
    ? Number(record.horizontalPosition)
    : Number.NaN;
  if (!Number.isNaN(rawHorizontalPosition)) {
    if (rawHorizontalPosition >= 58) {
      return "right";
    }
    if (rawHorizontalPosition <= 42) {
      return "left";
    }
  }

  const rawSide = typeof record.side === "string"
    ? record.side.trim().toLowerCase()
    : "";

  if (rawSide === "right") {
    return "right";
  }

  if (rawSide === "left") {
    return "left";
  }

  return "unknown";
}

function sideToIsFromMe(
  side: "left" | "right" | "unknown",
  fallback: unknown,
): boolean {
  if (side === "right") {
    return true;
  }

  if (side === "left") {
    return false;
  }

  return fallback === true || fallback === "true";
}

function applySpeakerContinuityHeuristics(
  messages: NormalizedRecognizedMessage[],
): {
  messages: NormalizedRecognizedMessage[];
  adjustedCount: number;
} {
  if (messages.length < 3) {
    return {
      messages,
      adjustedCount: 0,
    };
  }

  const adjusted = messages.map((message) => ({ ...message }));
  let adjustedCount = 0;

  for (let index = 1; index < adjusted.length - 1; index += 1) {
    const previous = adjusted[index - 1];
    const current = adjusted[index];
    const next = adjusted[index + 1];

    const previousSide = previous.side;
    const currentSide = current.side;
    const nextSide = next.side;

    if (
      previousSide === "unknown" ||
      nextSide === "unknown" ||
      previousSide !== nextSide
    ) {
      continue;
    }

    if (
      currentSide === previousSide && current.isFromMe === previous.isFromMe
    ) {
      continue;
    }

    if (!isLikelyMediaPlaceholderContent(current.content)) {
      continue;
    }

    adjusted[index] = {
      ...current,
      side: previousSide,
      isFromMe: previous.isFromMe,
    };
    adjustedCount += 1;
  }

  return {
    messages: adjusted,
    adjustedCount,
  };
}

function isLikelyQuotedReplyPreviewNameLine(value: string): boolean {
  const trimmed = value.trim();
  if (!trimmed || trimmed.length > 40) {
    return false;
  }

  if (/[0-9:]/.test(trimmed)) {
    return false;
  }

  return /^[\p{Script=Han}A-Za-z.'_-]+(?:\s+[\p{Script=Han}A-Za-z.'_-]+){0,3}$/u
    .test(trimmed);
}

function isLikelyQuotedReplyPreviewLabelLine(value: string): boolean {
  const normalized = value.trim().toLowerCase();
  if (!normalized || normalized.length > 24) {
    return false;
  }

  return normalized === "回覆" ||
    normalized === "引用回覆" ||
    normalized === "回覆訊息" ||
    normalized === "reply" ||
    normalized === "replying to" ||
    normalized === "replied to";
}

function isLikelyQuotedReplyPreviewContent(content: string): boolean {
  const originalLines = content
    .split(/\n+/)
    .map((line) => line.trim())
    .filter(Boolean);

  const lines = originalLines.length > 0 &&
      isLikelyQuotedReplyPreviewLabelLine(originalLines[0])
    ? originalLines.slice(1)
    : originalLines;

  if (lines.length < 2 || lines.length > 3) {
    return false;
  }

  if (!isLikelyQuotedReplyPreviewNameLine(lines[0])) {
    return false;
  }

  const previewBody = lines.slice(1).join(" ");
  return previewBody.length > 0 && previewBody.length <= 120 &&
    content.length <= 180;
}

function isLikelyBodyOnlyQuotedReplyPreviewCandidate(content: string): boolean {
  const trimmed = content.trim();
  if (!trimmed || isLikelyMediaPlaceholderContent(trimmed)) {
    return false;
  }

  const lines = trimmed
    .split(/\n+/)
    .map((line) => line.trim())
    .filter(Boolean);
  if (lines.length === 0 || lines.length > 2) {
    return false;
  }

  const combined = lines.join(" ");
  const compactLength = combined.replace(/\s+/g, "").length;
  if (compactLength < 4 || compactLength > 48) {
    return false;
  }

  if (
    isLikelyQuotedReplyPreviewNameLine(lines[0]) ||
    isLikelyQuotedReplyPreviewLabelLine(lines[0])
  ) {
    return false;
  }

  return !/[?？!！]/.test(combined) || compactLength <= 20;
}

function isLikelyShortReplyTargetContent(content: string): boolean {
  return isLikelyMediaPlaceholderContent(content) ||
    isLikelyShortContinuationContent(content);
}

function stripQuotedReplyPreviewMessages(
  messages: NormalizedRecognizedMessage[],
): {
  messages: NormalizedRecognizedMessage[];
  removedCount: number;
  attachedCount: number;
} {
  if (messages.length < 2) {
    return {
      messages,
      removedCount: 0,
      attachedCount: 0,
    };
  }

  const adjusted = messages.map((message) => ({ ...message }));
  const filtered: NormalizedRecognizedMessage[] = [];
  let removedCount = 0;
  let attachedCount = 0;

  for (let index = 0; index < adjusted.length; index += 1) {
    const previous = filtered[filtered.length - 1];
    const current = adjusted[index];
    const next = adjusted[index + 1];

    const shouldStripExplicitQuotedPreview = !!next &&
      isLikelyQuotedReplyPreviewContent(current.content) &&
      !isLikelyQuotedReplyPreviewContent(next.content);

    const shouldStripBodyOnlyQuotedPreview = !!next &&
      !next.quotedReplyPreview &&
      isLikelyBodyOnlyQuotedReplyPreviewCandidate(current.content) &&
      !isLikelyQuotedReplyPreviewContent(next.content) &&
      (
        current.side === next.side ||
        current.side === "unknown" ||
        next.side === "unknown"
      ) &&
      isLikelyShortReplyTargetContent(next.content) &&
      !!previous &&
      (
        previous.side !== current.side ||
        !!previous.quotedReplyPreview
      );

    const shouldStripQuotedPreview =
      shouldStripExplicitQuotedPreview || shouldStripBodyOnlyQuotedPreview;

    if (shouldStripQuotedPreview) {
      const derivedPreview = extractQuotedReplyPreviewContent(current.content);
      if (derivedPreview && !next.quotedReplyPreview) {
        next.quotedReplyPreview = derivedPreview;
        if (shouldStripExplicitQuotedPreview) {
          next.quotedReplyPreviewIsFromMe ??= current.isFromMe;
        }
        attachedCount += 1;
      }
      removedCount += 1;
      continue;
    }

    filtered.push(current);
  }

  return {
    messages: filtered,
    removedCount,
    attachedCount,
  };
}

function applyGroupedSpeakerHeuristics(
  messages: NormalizedRecognizedMessage[],
): {
  messages: NormalizedRecognizedMessage[];
  adjustedCount: number;
} {
  if (messages.length < 4) {
    return {
      messages,
      adjustedCount: 0,
    };
  }

  const adjusted = messages.map((message) => ({ ...message }));
  let adjustedCount = 0;

  for (let index = 2; index < adjusted.length - 1; index += 1) {
    const anchor = adjusted[index - 2];
    const bridge = adjusted[index - 1];
    const current = adjusted[index];
    const next = adjusted[index + 1];

    if (
      anchor.side === "unknown" ||
      bridge.side !== anchor.side ||
      next.side !== anchor.side
    ) {
      continue;
    }

    if (current.side === anchor.side && current.isFromMe === anchor.isFromMe) {
      continue;
    }

    const bridgeLooksGrouped =
      isLikelyMediaPlaceholderContent(bridge.content) ||
      !!bridge.quotedReplyPreview;
    const currentLooksGrouped =
      isLikelyShortContinuationContent(current.content) ||
      !!current.quotedReplyPreview;

    if (!bridgeLooksGrouped || !currentLooksGrouped) {
      continue;
    }

    adjusted[index] = {
      ...current,
      side: anchor.side,
      isFromMe: anchor.isFromMe,
    };
    adjustedCount += 1;
  }

  return {
    messages: adjusted,
    adjustedCount,
  };
}

function contiguousSideRunLength(
  messages: NormalizedRecognizedMessage[],
  index: number,
  direction: -1 | 1,
): number {
  if (index < 0 || index >= messages.length) {
    return 0;
  }

  const anchorSide = messages[index].side;
  if (anchorSide === "unknown") {
    return 0;
  }

  let count = 0;
  for (
    let cursor = index;
    cursor >= 0 && cursor < messages.length;
    cursor += direction
  ) {
    if (messages[cursor].side !== anchorSide) {
      break;
    }
    count += 1;
  }

  return count;
}

function applySideRunGroupingHeuristics(
  messages: NormalizedRecognizedMessage[],
): {
  messages: NormalizedRecognizedMessage[];
  adjustedCount: number;
} {
  if (messages.length < 3) {
    return {
      messages,
      adjustedCount: 0,
    };
  }

  const adjusted = messages.map((message) => ({ ...message }));
  let adjustedCount = 0;

  for (let index = 1; index < adjusted.length - 1; index += 1) {
    const previous = adjusted[index - 1];
    const current = adjusted[index];
    const next = adjusted[index + 1];

    if (
      previous.side === "unknown" ||
      next.side === "unknown" ||
      previous.side !== next.side
    ) {
      continue;
    }

    if (
      current.side === previous.side && current.isFromMe === previous.isFromMe
    ) {
      continue;
    }

    const previousRunLength = contiguousSideRunLength(adjusted, index - 1, -1);
    const nextRunLength = contiguousSideRunLength(adjusted, index + 1, 1);

    if (previousRunLength <= 0 || nextRunLength <= 0) {
      continue;
    }

    const neighborLooksStructured =
      isLikelyMediaPlaceholderContent(previous.content) ||
      isLikelyMediaPlaceholderContent(next.content) ||
      !!previous.quotedReplyPreview ||
      !!next.quotedReplyPreview;

    const currentLooksBridge = current.side === "unknown" ||
      isLikelyMediaPlaceholderContent(current.content) ||
      !!current.quotedReplyPreview ||
      (neighborLooksStructured &&
        isLikelyShortContinuationContent(current.content));

    if (!currentLooksBridge) {
      continue;
    }

    adjusted[index] = {
      ...current,
      side: previous.side,
      isFromMe: previous.isFromMe,
    };
    adjustedCount += 1;
  }

  return {
    messages: adjusted,
    adjustedCount,
  };
}

function applyTrailingSpeakerHeuristics(
  messages: NormalizedRecognizedMessage[],
): {
  messages: NormalizedRecognizedMessage[];
  adjustedCount: number;
} {
  if (messages.length < 3) {
    return {
      messages,
      adjustedCount: 0,
    };
  }

  const adjusted = messages.map((message) => ({ ...message }));
  const currentIndex = adjusted.length - 1;
  const anchor = adjusted[currentIndex - 2];
  const previous = adjusted[currentIndex - 1];
  const current = adjusted[currentIndex];

  if (
    anchor.side === "unknown" ||
    previous.side === "unknown" ||
    anchor.side !== previous.side ||
    anchor.isFromMe !== previous.isFromMe
  ) {
    return {
      messages: adjusted,
      adjustedCount: 0,
    };
  }

  if (
    current.side === previous.side &&
    current.isFromMe === previous.isFromMe
  ) {
    return {
      messages: adjusted,
      adjustedCount: 0,
    };
  }

  const previousLooksQuotedRun = !!anchor.quotedReplyPreview ||
    !!previous.quotedReplyPreview;
  const currentSideSeenEarlier = current.side !== "unknown" &&
    adjusted.slice(0, currentIndex).some((message) =>
      message.side === current.side
    );
  const previousRunLength = contiguousSideRunLength(
    adjusted,
    currentIndex - 1,
    -1,
  );
  const currentLooksFlexible = current.side === "unknown" ||
    isLikelyShortContinuationContent(current.content) ||
    !!current.quotedReplyPreview;

  const canRepairQuotedTail = previousLooksQuotedRun &&
    previousRunLength >= 2 &&
    (!currentSideSeenEarlier || currentLooksFlexible);

  if (!canRepairQuotedTail) {
    return {
      messages: adjusted,
      adjustedCount: 0,
    };
  }

  adjusted[currentIndex] = {
    ...current,
    side: previous.side,
    isFromMe: previous.isFromMe,
  };

  return {
    messages: adjusted,
    adjustedCount: 1,
  };
}

function normalizeSideConfidenceLabel(
  messageCount: number,
  uncertainSideCount: number,
  adjustedSideCount: number,
  classification: string,
): "high" | "medium" | "low" {
  if (messageCount <= 0) {
    return "low";
  }

  if (classification === "low_confidence" && uncertainSideCount > 0) {
    return "low";
  }

  if (uncertainSideCount === 0 && adjustedSideCount === 0) {
    return "high";
  }

  if (uncertainSideCount >= Math.ceil(messageCount / 3)) {
    return "low";
  }

  return "medium";
}

function isLikelyMixedThreadWarning(value: unknown): boolean {
  if (typeof value !== "string" || !value.trim()) {
    return false;
  }

  const lower = value.trim().toLowerCase();
  return lower.includes("different contact") ||
    lower.includes("different contacts") ||
    lower.includes("different thread") ||
    lower.includes("multiple threads") ||
    lower.includes("mixed thread") ||
    lower.includes("mixed screenshots") ||
    lower.includes("不同聯絡人") ||
    lower.includes("不同联系人") ||
    lower.includes("不同對話") ||
    lower.includes("不同会话") ||
    lower.includes("混合了不同") ||
    lower.includes("不同聊天");
}

function normalizeWarningMessage(
  value: unknown,
  classification: string,
): string | undefined {
  const inferredClassification = inferScreenshotClassificationHint(value);

  if (typeof value === "string" && value.trim()) {
    const normalized = value.trim();
    const lower = normalized.toLowerCase();

    if (
      lower.includes("call log") ||
      lower.includes("system notification interface")
    ) {
      return "這張圖看起來像聊天視窗裡的通話紀錄或來電事件，不是一般文字聊天。若確認是同一段對話中的未接來電，可先確認預覽後再匯入。";
    }

    if (isLikelyMixedThreadWarning(normalized)) {
      return "這批截圖看起來可能混入了不同聯絡人或不同聊天段落，請先確認是不是同一段對話，再決定要不要匯入。";
    }

    if (
      _isLikelyUserFacingChinese(normalized) &&
      inferredClassification === undefined
    ) {
      return normalized;
    }
  }

  switch (inferredClassification ?? classification) {
    case "social_feed":
      return "這張圖片看起來比較像社群貼文或留言串，不像雙人聊天視窗，建議改傳聊天截圖。";
    case "group_chat":
      return "這張圖片看起來像群組聊天，目前只支援一對一聊天截圖，建議改傳和單一對象的聊天畫面。";
    case "gallery_album":
      return "這張圖片看起來像相簿或選圖畫面，不是聊天視窗，請改傳實際聊天截圖。";
    case "call_log_screen":
      return "這張圖片比較像手機的通話紀錄頁，不是聊天視窗。若這其實是聊天 thread 裡的通話事件，請保留聊天標題列後再截一次。";
    case "system_ui":
      return "這張圖片看起來像系統畫面或通知頁，不是可匯入的聊天截圖。";
    case "sensitive_content":
      return "這張圖片包含不適合辨識的敏感內容，請改傳純聊天截圖。";
    case "unsupported":
      return "這張圖片不像可辨識的聊天截圖，請改傳包含聊天泡泡與標題列的畫面。";
    case "low_confidence":
      return "這張截圖辨識信心較低，匯入前請先確認預覽內容與左右方向是否正確。";
    default:
      return undefined;
  }
}

function normalizeRecognizedConversation(
  result: Record<string, unknown>,
  options: {
    knownContactName?: string;
  } = {},
): Record<string, unknown> {
  const { knownContactName } = options;
  const normalizedResult = { ...result };
  const recognizedRaw = normalizedResult.recognizedConversation &&
      typeof normalizedResult.recognizedConversation === "object"
    ? {
      ...(normalizedResult.recognizedConversation as Record<string, unknown>),
    }
    : {};

  const rawMessages = Array.isArray(recognizedRaw.messages)
    ? recognizedRaw.messages
    : Array.isArray(normalizedResult.messages)
    ? normalizedResult.messages
    : null;

  if (!rawMessages) {
    if (Object.keys(recognizedRaw).length > 0) {
      const classification = normalizeScreenshotClassification(
        recognizedRaw.classification,
        0,
        recognizedRaw.warning,
        recognizedRaw.summary,
      );
      normalizedResult.recognizedConversation = {
        ...recognizedRaw,
        contactName: stabilizeRecognizedContactName({
          recognizedContactName: recognizedRaw.contactName,
          knownContactName,
        }),
        messageCount: 0,
        summary: typeof recognizedRaw.summary === "string" &&
            recognizedRaw.summary.trim()
          ? recognizedRaw.summary
          : "無法從這張圖片穩定辨識出可匯入的聊天內容",
        messages: [],
        classification,
        importPolicy: normalizeImportPolicy(
          recognizedRaw.importPolicy,
          classification,
        ),
        confidence: normalizeConfidenceLabel(
          recognizedRaw.confidence,
          classification,
          0,
        ),
        sideConfidence: "low",
        uncertainSideCount: 0,
        normalizationTelemetry: {
          continuityAdjustedCount: 0,
          groupedAdjustedCount: 0,
          layoutFirstAdjustedCount: 0,
          systemRowsRemovedCount: 0,
          quotedPreviewRemovedCount: 0,
          quotedPreviewAttachedCount: 0,
          overlapRemovedCount: 0,
        },
        warning: normalizeWarningMessage(
          recognizedRaw.warning,
          classification,
        ),
      };
    }
    return normalizedResult;
  }

  const normalizedMessages = rawMessages
    .map((message) => {
      if (!message || typeof message !== "object") {
        return null;
      }

      const record = message as Record<string, unknown>;
      const content = typeof record.content === "string"
        ? record.content.trim()
        : "";

      if (!content) {
        return null;
      }

      return {
        isFromMe: record.isFromMe === true ||
          record.isFromMe === "true" ||
          record.side === "right",
        content,
      };
    })
    .filter((message): message is { isFromMe: boolean; content: string } =>
      message !== null
    );

  if (normalizedMessages.length === 0) {
    return normalizedResult;
  }

  const normalizedMessageCount =
    typeof recognizedRaw.messageCount === "number" &&
      recognizedRaw.messageCount > 0
      ? recognizedRaw.messageCount
      : Number(recognizedRaw.messageCount) > 0
      ? Number(recognizedRaw.messageCount)
      : normalizedMessages.length;
  let classification = normalizeScreenshotClassification(
    recognizedRaw.classification,
    normalizedMessages.length,
    recognizedRaw.warning,
    recognizedRaw.summary,
  );
  const visibleSpeakerPattern = normalizeVisibleSpeakerPattern(
    recognizedRaw.screenSpeakerPattern,
  );

  let importPolicy = normalizeImportPolicy(
    recognizedRaw.importPolicy,
    classification,
  );
  let confidence = normalizeConfidenceLabel(
    recognizedRaw.confidence,
    classification,
    normalizedMessages.length,
  );
  let warning = normalizeWarningMessage(
    recognizedRaw.warning,
    classification,
  );
  const callEventOnly = isLikelyChatThreadCallEventScreenshot(
    normalizedMessages,
  );
  const mixedThreadDetected =
    isLikelyMixedThreadWarning(recognizedRaw.warning) ||
    isLikelyMixedThreadWarning(recognizedRaw.summary);

  if (
    callEventOnly &&
    (
      classification === "unsupported" ||
      classification === "social_feed" ||
      classification === "call_log_screen" ||
      classification === "system_ui"
    )
  ) {
    classification = "low_confidence";
    importPolicy = "confirm";
    confidence = confidence === "low" ? "low" : "medium";
    warning =
      "這張圖看起來是聊天視窗裡的通話紀錄或未接來電列表，雖然不是一般文字泡泡，但仍可先確認預覽後再匯入。";
  }

  if (mixedThreadDetected) {
    classification = "low_confidence";
    importPolicy = "confirm";
    confidence = "low";
    warning =
      "這批截圖看起來可能混入了不同聯絡人或不同聯絡人或不同聊天段落，請先確認是不是同一段對話，再決定要不要匯入。";
  }

  // Check for only_right pattern (all messages from me)
  const hasQuotedReplyFromOther = rawMessages.some((message) => {
    if (!message || typeof message !== "object") {
      return false;
    }
    const record = message as Record<string, unknown>;
    const quotedReplyPreview = sanitizeQuotedReplyPreviewValue(
      record.quotedReplyPreview,
    );
    if (!quotedReplyPreview) {
      return false;
    }
    // quotedReplyPreviewIsFromMe: false means the quoted content is from the other person
    return record.quotedReplyPreviewIsFromMe === false;
  });

  if (visibleSpeakerPattern === "only_right" && importPolicy !== "reject") {
    if (!hasQuotedReplyFromOther) {
      // All messages are from me, no quoted replies from other person
      classification = "low_confidence";
      importPolicy = "confirm";
      confidence = "low";
      warning =
        "截圖只有你自己發的訊息，沒有對方的回覆。如果要分析對話，建議加入包含對方訊息的截圖。";
    } else {
      // All messages are from me, but has quoted replies from other person
      if (!warning) {
        warning =
          "截圖主要是你的訊息，對方的回覆只出現在引用中。加入對方的完整訊息可以讓分析更準確。";
      }
    }
  }

  const normalizedMessagesWithSidePriority = rawMessages
    .map((message) => {
      if (!message || typeof message !== "object") {
        return null;
      }

      const record = message as Record<string, unknown>;
      const content = typeof record.content === "string"
        ? record.content.trim()
        : "";

      if (!content) {
        return null;
      }

      const side = normalizeBubbleSide(record);
      const quotedReplyPreview = sanitizeQuotedReplyPreviewValue(
        record.quotedReplyPreview,
      );
      const quotedReplyPreviewIsFromMe = quotedReplyPreview == null
        ? undefined
        : normalizeQuotedReplyPreviewIsFromMe(record);

      return {
        side,
        isFromMe: sideToIsFromMe(side, record.isFromMe),
        content,
        ...(quotedReplyPreview ? { quotedReplyPreview } : {}),
        ...(quotedReplyPreview != null && quotedReplyPreviewIsFromMe != null
          ? { quotedReplyPreviewIsFromMe }
          : {}),
      };
    })
    .filter((message): message is NormalizedRecognizedMessage =>
      message !== null
    );

  const continuityAdjustment = applySpeakerContinuityHeuristics(
    normalizedMessagesWithSidePriority,
  );
  const singleVisibleSideAdjustment = applySingleVisibleSpeakerPattern(
    continuityAdjustment.messages,
    visibleSpeakerPattern,
  );
  const groupedAdjustment = applyGroupedSpeakerHeuristics(
    singleVisibleSideAdjustment.messages,
  );
  const quotedPreviewAdjustment = stripQuotedReplyPreviewMessages(
    groupedAdjustment.messages,
  );
  const sideRunAdjustment = applySideRunGroupingHeuristics(
    quotedPreviewAdjustment.messages,
  );
  let layoutFirstAdjustment;
  try {
    layoutFirstAdjustment = applyLayoutFirstParser(
      sideRunAdjustment.messages,
    );
  } catch (error) {
    layoutFirstAdjustment = {
      messages: sideRunAdjustment.messages,
      adjustedCount: 0,
      systemRowsRemovedCount: 0,
    };
  }
  const trailingAdjustment = applyTrailingSpeakerHeuristics(
    layoutFirstAdjustment.messages,
  );
  const overlapAdjustment = deduplicateSequentialMessages(
    trailingAdjustment.messages,
  );
  const finalMessages = overlapAdjustment.messages;
  const finalMessageCount = finalMessages.length;
  const finalUncertainSideCount =
    finalMessages.filter((message) => message.side === "unknown").length;
  const sideConfidence = normalizeSideConfidenceLabel(
    finalMessageCount,
    finalUncertainSideCount,
    continuityAdjustment.adjustedCount +
      singleVisibleSideAdjustment.adjustedCount +
      groupedAdjustment.adjustedCount +
      sideRunAdjustment.adjustedCount +
      layoutFirstAdjustment.adjustedCount +
      trailingAdjustment.adjustedCount,
    classification,
  );

  normalizedResult.recognizedConversation = {
    ...recognizedRaw,
    contactName: stabilizeRecognizedContactName({
      recognizedContactName: recognizedRaw.contactName,
      knownContactName,
    }),
    messageCount: finalMessageCount > 0
      ? finalMessageCount
      : normalizedMessageCount,
    summary:
      typeof recognizedRaw.summary === "string" && recognizedRaw.summary.trim()
        ? recognizedRaw.summary
        : `已識別 ${finalMessageCount} 則訊息`,
    messages: finalMessages,
    classification,
    importPolicy,
    confidence,
    sideConfidence,
    uncertainSideCount: finalUncertainSideCount,
    normalizationTelemetry: {
      continuityAdjustedCount: continuityAdjustment.adjustedCount,
      groupedAdjustedCount: singleVisibleSideAdjustment.adjustedCount +
        groupedAdjustment.adjustedCount +
        sideRunAdjustment.adjustedCount +
        trailingAdjustment.adjustedCount,
      layoutFirstAdjustedCount: layoutFirstAdjustment.adjustedCount,
      systemRowsRemovedCount: layoutFirstAdjustment.systemRowsRemovedCount,
      quotedPreviewRemovedCount: quotedPreviewAdjustment.removedCount,
      quotedPreviewAttachedCount: quotedPreviewAdjustment.attachedCount,
      overlapRemovedCount: overlapAdjustment.removedCount,
    },
    warning: (quotedPreviewAdjustment.removedCount > 0 ||
        overlapAdjustment.removedCount > 0) && !warning
      ? quotedPreviewAdjustment.attachedCount > 0
        ? "已自動把引用回覆的小卡片併回主訊息，保留它正在回覆的舊內容。"
        : overlapAdjustment.removedCount > 0
        ? `已自動略過 ${overlapAdjustment.removedCount} 則和前後截圖重疊的重複訊息。`
        : "已自動忽略引用回覆的小卡片，只保留外層真正的新訊息。"
      : warning,
  };

  return normalizedResult;
}

function _isLikelyUserFacingChinese(value: string): boolean {
  return /[\u4e00-\u9fff]/.test(value);
}

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
      "userStyle",
      "userInterests",
      "targetDescription",
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

// 測試模式：強制使用 Haiku + 不扣額度
const TEST_MODE = Deno.env.get("TEST_MODE") === "true";
// 測試帳號白名單 (不扣額度)
const TEST_EMAILS = ["vibesync.test@gmail.com"];

// 模型選擇函數 (設計規格 4.9)
function selectModel(context: {
  conversationLength: number;
  enthusiasmLevel: string | null;
  hasComplexEmotions: boolean;
  isFirstAnalysis: boolean;
  tier: string;
}): string {
  // 🧪 測試模式：強制使用 Haiku (省錢)
  if (TEST_MODE) {
    return "claude-haiku-4-5-20251001";
  }

  // Essential 用戶優先使用 Sonnet
  if (context.tier === "essential") {
    return "claude-sonnet-4-20250514";
  }

  // 使用 Sonnet 的情況 (30%)
  if (
    context.conversationLength > 20 || // 長對話
    context.enthusiasmLevel === "cold" || // 冷淡需要策略
    context.hasComplexEmotions || // 複雜情緒
    context.isFirstAnalysis // 首次分析建立基準
  ) {
    return "claude-sonnet-4-20250514";
  }

  // 預設使用 Haiku (70%)
  return "claude-haiku-4-5-20251001";
}

// CORS headers for all responses
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "Authorization, Content-Type, x-client-info, apikey",
};

// Helper to create JSON response with CORS
function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

serve(async (req) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Verify auth
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return jsonResponse({ error: "Invalid token" }, 401);
    }

    // 測試帳號：不檢查額度、不扣額度
    const accountIsTest = TEST_EMAILS.includes(user.email || "");

    // Parse request early so recognizeOnly can bypass quota checks.
    const contentLengthHeader = req.headers.get("content-length");
    const contentLength = contentLengthHeader
      ? Number(contentLengthHeader)
      : NaN;
    if (
      Number.isFinite(contentLength) && contentLength > MAX_REQUEST_BODY_BYTES
    ) {
      logWarn("request_body_too_large", {
        user: summarizeUser(user.id),
        contentLength,
        maxAllowed: MAX_REQUEST_BODY_BYTES,
      });
      return jsonResponse({ error: "Request body too large" }, 413);
    }

    let requestBody;
    try {
      requestBody = await req.json();
    } catch (parseError) {
      logWarn("request_body_parse_failed", {
        user: summarizeUser(user.id),
        error: getErrorMessage(parseError),
      });
      return jsonResponse({ error: "Invalid request body" }, 400);
    }

    if (
      !requestBody || typeof requestBody !== "object" ||
      Array.isArray(requestBody)
    ) {
      return jsonResponse({ error: "Invalid request body" }, 400);
    }

    const {
      messages: rawMessages,
      images,
      sessionContext: rawSessionContext,
      conversationSummary: rawConversationSummary,
      knownContactName: rawKnownContactName,
      userDraft: rawUserDraft,
      forceModel: rawForceModel,
      analyzeMode: rawAnalyzeMode,
      recognizeOnly: rawRecognizeOnly,
    } = requestBody;

    if (rawRecognizeOnly != null && typeof rawRecognizeOnly !== "boolean") {
      return jsonResponse({ error: "Invalid recognizeOnly" }, 400);
    }
    const recognizeOnly = rawRecognizeOnly === true;

    // Check subscription
    let { data: sub, error: subError } = await supabase
      .from("subscriptions")
      .select(
        "tier, monthly_messages_used, daily_messages_used, daily_reset_at, monthly_reset_at",
      )
      .eq("user_id", user.id)
      .maybeSingle();

    logInfo("subscription_lookup", {
      user: summarizeUser(user.id),
      hasSubscription: !!sub,
      tier: sub?.tier ?? null,
      subscriptionErrorCode: subError?.code ?? null,
    });

    if (!sub) {
      logWarn("subscription_missing_self_heal", {
        user: summarizeUser(user.id),
        error: subError?.message ?? null,
      });

      const nowIso = new Date().toISOString();
      const { data: insertedSub, error: insertSubError } = await supabase
        .from("subscriptions")
        .insert({
          user_id: user.id,
          tier: "free",
          monthly_messages_used: 0,
          daily_messages_used: 0,
          daily_reset_at: nowIso,
          monthly_reset_at: nowIso,
          started_at: nowIso,
        })
        .select(
          "tier, monthly_messages_used, daily_messages_used, daily_reset_at, monthly_reset_at",
        )
        .single();

      if (insertSubError || !insertedSub) {
        logError("subscription_self_heal_failed", {
          user: summarizeUser(user.id),
          error: insertSubError?.message ?? null,
        });
        return jsonResponse({ error: "No subscription found" }, 403);
      }

      sub = insertedSub;
    }

    // Check if daily reset needed
    const now = new Date();
    // 安全處理 null 值
    const dailyResetAt = sub.daily_reset_at
      ? new Date(sub.daily_reset_at)
      : new Date(0);
    if (now.toDateString() !== dailyResetAt.toDateString()) {
      await supabase
        .from("subscriptions")
        .update({ daily_messages_used: 0, daily_reset_at: now.toISOString() })
        .eq("user_id", user.id);
      sub.daily_messages_used = 0;
      logInfo("daily_quota_reset", { user: summarizeUser(user.id) });
    }

    // Check monthly reset needed
    const monthlyResetAt = sub.monthly_reset_at
      ? new Date(sub.monthly_reset_at)
      : new Date(0);
    if (
      now.getMonth() !== monthlyResetAt.getMonth() ||
      now.getFullYear() !== monthlyResetAt.getFullYear()
    ) {
      await supabase
        .from("subscriptions")
        .update({
          monthly_messages_used: 0,
          monthly_reset_at: now.toISOString(),
        })
        .eq("user_id", user.id);
      sub.monthly_messages_used = 0;
      logInfo("monthly_quota_reset", { user: summarizeUser(user.id) });
    }

    // Check monthly limit (測試帳號跳過)
    const monthlyLimit = TIER_MONTHLY_LIMITS[sub.tier] ||
      TIER_MONTHLY_LIMITS.free;
    if (
      !recognizeOnly && !accountIsTest &&
      sub.monthly_messages_used >= monthlyLimit
    ) {
      logWarn("monthly_limit_exceeded", {
        user: summarizeUser(user.id),
        tier: sub.tier,
        used: sub.monthly_messages_used,
        limit: monthlyLimit,
      });
      return jsonResponse({
        error: "Monthly limit exceeded",
        monthlyLimit,
        used: sub.monthly_messages_used,
      }, 429);
    }

    // Check daily limit (測試帳號跳過)
    const dailyLimit = TIER_DAILY_LIMITS[sub.tier] || TIER_DAILY_LIMITS.free;
    if (
      !recognizeOnly && !accountIsTest &&
      sub.daily_messages_used >= dailyLimit
    ) {
      logWarn("daily_limit_exceeded", {
        user: summarizeUser(user.id),
        tier: sub.tier,
        used: sub.daily_messages_used,
        limit: dailyLimit,
      });
      return jsonResponse({
        error: "Daily limit exceeded",
        dailyLimit,
        used: sub.daily_messages_used,
        resetAt: "tomorrow",
      }, 429);
    }

    logInfo("request_received", {
      user: summarizeUser(user.id),
      messageCount: Array.isArray(rawMessages) ? rawMessages.length : 0,
      imageCount: Array.isArray(images) ? images.length : 0,
      recognizeOnly,
      analyzeMode: rawAnalyzeMode ?? "normal",
      quotaBypassed: recognizeOnly,
    });

    // analyzeMode: "normal" (default) | "my_message" (用戶剛說完，給話題延續建議)
    // images: optional array of ImageData for screenshot analysis
    /*
    // recognizeOnly: boolean - 只識別截圖，不做完整分析（節省時間和 tokens）
    const messageValidation = sanitizeMessages(rawMessages, {
    */
    const messageValidation = sanitizeMessages(rawMessages ?? [], {
      allowEmpty: recognizeOnly,
    });
    if (messageValidation.error || !messageValidation.messages) {
      return jsonResponse({
        error: messageValidation.error || "Invalid messages",
      }, 400);
    }
    const messages = messageValidation.messages;

    if (
      rawAnalyzeMode != null &&
      (typeof rawAnalyzeMode !== "string" ||
        !VALID_ANALYZE_MODES.has(rawAnalyzeMode))
    ) {
      return jsonResponse({ error: "Invalid analyzeMode" }, 400);
    }
    const analyzeMode = rawAnalyzeMode === "my_message"
      ? "my_message"
      : "normal";

    if (
      rawForceModel != null &&
      (typeof rawForceModel !== "string" ||
        !VALID_FORCE_MODELS.has(rawForceModel))
    ) {
      return jsonResponse({ error: "Invalid forceModel" }, 400);
    }
    const forceModel = rawForceModel;

    if (rawUserDraft != null && typeof rawUserDraft !== "string") {
      return jsonResponse({ error: "Invalid userDraft" }, 400);
    }
    const userDraft = typeof rawUserDraft === "string"
      ? rawUserDraft.trim()
      : undefined;
    if (userDraft && userDraft.length > MAX_USER_DRAFT_LENGTH) {
      return jsonResponse({
        error: `userDraft too long (max ${MAX_USER_DRAFT_LENGTH} chars)`,
      }, 400);
    }

    const sessionContextValidation = sanitizeSessionContext(rawSessionContext);
    if (sessionContextValidation.error) {
      return jsonResponse({ error: sessionContextValidation.error }, 400);
    }
    const sessionContext = sessionContextValidation.sessionContext;

    const conversationSummaryValidation = sanitizeConversationSummary(
      rawConversationSummary,
    );
    if (conversationSummaryValidation.error) {
      return jsonResponse(
        { error: conversationSummaryValidation.error },
        400,
      );
    }
    const conversationSummary =
      conversationSummaryValidation.conversationSummary;

    const knownContactName = sanitizeContactNameValue(rawKnownContactName);
    if (rawKnownContactName != null && !knownContactName) {
      return jsonResponse({ error: "Invalid knownContactName" }, 400);
    }

    // Validate images if provided
    if (images != null && !Array.isArray(images)) {
      return jsonResponse({ error: "Invalid images" }, 400);
    }

    const hasImages = Array.isArray(images) && images.length > 0;
    let totalImageBytes = 0;
    if (recognizeOnly && !hasImages) {
      return jsonResponse({ error: "recognizeOnly requires images" }, 400);
    }
    if (hasImages) {
      const imageOrders = new Set<number>();
      if (images.length > 3) {
        return jsonResponse({ error: "最多上傳 3 張截圖" }, 400);
      }
      // Validate each image
      for (const img of images) {
        if (
          typeof img.data !== "string" ||
          typeof img.mediaType !== "string" ||
          typeof img.order !== "number"
        ) {
          return jsonResponse({ error: "圖片格式錯誤" }, 400);
        }
        if (!VALID_IMAGE_MEDIA_TYPES.has(img.mediaType)) {
          return jsonResponse({ error: "Unsupported image type" }, 400);
        }
        if (!Number.isInteger(img.order) || img.order < 1) {
          return jsonResponse({ error: "圖片排序錯誤" }, 400);
        }
        if (imageOrders.has(img.order)) {
          return jsonResponse({ error: "圖片排序重複" }, 400);
        }
        imageOrders.add(img.order);
        // Check base64 size (rough estimate: ~1.33x of actual bytes)
        const estimatedBytes = (img.data.length * 3) / 4;
        totalImageBytes += estimatedBytes;
        if (totalImageBytes > MAX_TOTAL_IMAGE_BYTES) {
          return jsonResponse({ error: "Total image payload too large" }, 400);
        }
        if (estimatedBytes > MAX_IMAGE_BYTES) {
          return jsonResponse({ error: "圖片太大，請壓縮後重試" }, 400);
        }
      }
    }

    // Check input for safety (AI 護欄)
    if (!recognizeOnly) {
      const inputCheck = checkInput(messages);
      if (!inputCheck.safe) {
        return jsonResponse({
          error: inputCheck.reason,
          code: "UNSAFE_INPUT",
        }, 400);
      }

      if (
        analyzeMode === "my_message" && !messages[messages.length - 1]?.isFromMe
      ) {
        return jsonResponse({
          error:
            "my_message mode requires the latest message to be from the user",
        }, 400);
      }

      if (
        analyzeMode === "normal" &&
        !messages.some((message) => !message.isFromMe)
      ) {
        return jsonResponse({
          error: "At least one incoming message is required for analysis",
        }, 400);
      }
    }

    // Format session context for Claude
    let contextInfo = "";
    if (sessionContext) {
      contextInfo = `
## 情境資訊
- 認識場景：${sessionContext.meetingContext || "未知"}
- 認識時長：${sessionContext.duration || "未知"}
- 用戶目標：${sessionContext.goal || "約出來"}
- 用戶風格：${sessionContext.userStyle || "未提供"}
- 用戶興趣：${sessionContext.userInterests || "未提供"}
- 對方特質：${sessionContext.targetDescription || "未提供"}
`;
    }

    // 對話記憶策略：最近 30 則訊息完整保留（約 15 輪）
    // 超過時，保留開頭 + 最近對話，中間省略
    const MAX_RECENT_MESSAGES = 30;
    const OPENING_MESSAGES = 4; // 保留最初的 4 則（破冰階段）
    let compiledConversationText = "";
    let compiledContextMode = "full";
    let compiledMessageCount = messages.length;
    let truncatedMessageCount = 0;
    let openingMessagesUsed = 0;
    let recentMessagesUsed = messages.length;

    const formatConversationLine = (
      message: AnalyzeMessage,
    ) => {
      const quotedReplyPreview = message.quotedReplyPreview?.trim()
        ? message.quotedReplyPreview.trim().replace(/\s+/g, " ").replace(
          /"/g,
          "'",
        )
        : "";
      const quotedReplySpeaker = message.quotedReplyPreviewIsFromMe == null
        ? ""
        : message.quotedReplyPreviewIsFromMe
        ? "my earlier message"
        : "her earlier message";
      const replyPrefix = quotedReplyPreview
        ? quotedReplySpeaker
          ? ` (replying to ${quotedReplySpeaker}: "${quotedReplyPreview}")`
          : ` (replying to: "${quotedReplyPreview}")`
        : "";

      return `${
        message.isFromMe ? "Me" : "Her"
      }${replyPrefix}: ${message.content}`;
    };
    let conversationText = "";

    if (messages.length > MAX_RECENT_MESSAGES + OPENING_MESSAGES) {
      // 長對話：保留開頭 + 最近
      const openingMessages = messages.slice(0, OPENING_MESSAGES);
      const recentMessages = messages.slice(-MAX_RECENT_MESSAGES);
      const skippedCount = messages.length - OPENING_MESSAGES -
        MAX_RECENT_MESSAGES;
      compiledContextMode = "opening_plus_recent";
      compiledMessageCount = openingMessages.length + recentMessages.length;
      truncatedMessageCount = skippedCount;
      openingMessagesUsed = openingMessages.length;
      recentMessagesUsed = recentMessages.length;

      const openingText = openingMessages.map(formatConversationLine).join(
        "\n",
      );
      /*
      const openingText = openingMessages
        .map(
          (m: { isFromMe: boolean; content: string }) =>
            `${m.isFromMe ? "我" : "她"}: ${m.content}`
        )
        .join("\n");
      */

      const recentText = recentMessages.map(formatConversationLine).join("\n");
      /*
      const recentText = recentMessages
        .map(
          (m: { isFromMe: boolean; content: string }) =>
            `${m.isFromMe ? "我" : "她"}: ${m.content}`
        )
        .join("\n");
      */

      compiledConversationText = `## 對話開頭（破冰階段）
${openingText}

---（中間省略 ${skippedCount} 則訊息）---

## 最近對話
${recentText}`;
    } else {
      // 訊息數量在限制內，完整送出
      compiledConversationText = messages.map(formatConversationLine).join(
        "\n",
      );
      compiledMessageCount = messages.length;
      recentMessagesUsed = messages.length;
      /*
      conversationText = messages
        .map(
          (m: { isFromMe: boolean; content: string }) =>
            `${m.isFromMe ? "我" : "她"}: ${m.content}`
        )
        .join("\n");
      */
    }

    // Select model based on complexity (or force for testing)
    // 有圖片時強制使用 Sonnet (Vision 功能需要)
    const VALID_MODELS = [
      "claude-haiku-4-5-20251001",
      "claude-sonnet-4-20250514",
    ];
    const model = hasImages
      ? "claude-sonnet-4-20250514" // Vision 強制 Sonnet
      : (forceModel && (accountIsTest || TEST_MODE) &&
          VALID_MODELS.includes(forceModel))
      ? forceModel
      : selectModel({
        conversationLength: messages.length,
        enthusiasmLevel: null, // 首次分析前不知道
        hasComplexEmotions: false,
        isFirstAnalysis: messages.length <= 5,
        tier: accountIsTest ? "essential" : sub.tier,
      });

    // Get available features for this tier
    // 測試帳號強制使用 essential tier 功能
    const effectiveTier = accountIsTest ? "essential" : sub.tier;
    const allowedFeatures = TIER_FEATURES[effectiveTier] || TIER_FEATURES.free;

    // 檢查「我說」模式權限（只限 Essential）
    const isMyMessageMode = analyzeMode === "my_message";
    const requestType = deriveRequestType({
      recognizeOnly,
      hasImages,
      isMyMessageMode,
      hasUserDraft:
        !!(userDraft && typeof userDraft === "string" && userDraft.trim()),
    });
    const estimatedMessageCount = recognizeOnly ? 0 : countMessages(messages);
    const quotaUsage = buildQuotaUsageMetadata({
      requestType,
      recognizeOnly,
      accountIsTest,
      estimatedMessageCount,
    });
    if (isMyMessageMode && effectiveTier !== "essential") {
      return jsonResponse({
        error: "「我說」分析功能僅限 Essential 方案",
        code: "FEATURE_NOT_AVAILABLE",
        requiredTier: "essential",
      }, 403);
    }

    const systemPrompt = recognizeOnly
      ? OCR_RECOGNIZE_ONLY_SYSTEM_PROMPT
      : (isMyMessageMode ? MY_MESSAGE_PROMPT : SYSTEM_PROMPT);

    // 組合用戶訊息
    if (sessionContext) {
      contextInfo = [
        "## Session Context",
        `- Meeting context: ${sessionContext.meetingContext || "unknown"}`,
        `- Duration: ${sessionContext.duration || "unknown"}`,
        `- Goal: ${sessionContext.goal || "not provided"}`,
        `- User style: ${sessionContext.userStyle || "not provided"}`,
        `- User interests: ${sessionContext.userInterests || "not provided"}`,
        `- Target description: ${
          sessionContext.targetDescription || "not provided"
        }`,
      ].join("\n");
    }
    const historicalContextInfo = conversationSummary
      ? ["## Older Context Summary", conversationSummary].join("\n")
      : "";

    let userPrompt = isMyMessageMode
      ? [
        contextInfo,
        historicalContextInfo,
        "",
        "## Recent Conversation",
        compiledConversationText,
        "",
        "Continue from the user's latest draft and suggest how to keep the conversation flowing naturally.",
      ].join("\n")
      : [
        contextInfo,
        historicalContextInfo,
        "",
        "Analyze the conversation below and return the structured JSON response.",
        "",
        "## Recent Conversation",
        compiledConversationText,
      ].join("\n");
    if (hasImages) {
      userPrompt = recognizeOnly
        ? buildRecognizeOnlyImagePrompt({
          imageCount: images.length,
          contextInfo,
          knownContactName,
          historicalContextInfo,
          compiledConversationText,
        })
        : buildImageAnalysisPrompt({
          imageCount: images.length,
          contextInfo,
          knownContactName,
          historicalContextInfo,
          compiledConversationText,
        });
    }

    // 如果有用戶草稿，加入優化請求（只在 normal 模式）
    if (
      !isMyMessageMode && userDraft && typeof userDraft === "string" &&
      userDraft.trim()
    ) {
      userPrompt = joinPromptSections(
        userPrompt,
        `## User Draft To Optimize
"${userDraft.trim()}"

Return \`optimizedMessage\` in the structured JSON response.`,
      );
    }

    // 「我說」模式用 Haiku 省成本（但有圖片時強制 Sonnet）
    const selectedModel = hasImages
      ? "claude-sonnet-4-20250514"
      : isMyMessageMode
      ? "claude-haiku-4-5-20251001"
      : model;

    // 建構 user message content（純文字或 Vision 格式）
    const userMessageContent = hasImages
      ? buildVisionContent(userPrompt, images as ImageData[])
      : userPrompt;

    const startTime = Date.now();
    const timeoutMs = hasImages
      ? (recognizeOnly ? 90000 : 120000)
      : (isMyMessageMode ? 20000 : 30000);
    const allowModelFallback = !hasImages;
    const requestObservability = {
      requestType,
      analyzeMode,
      hasImages,
      recognizeOnly,
      hasUserDraft:
        !!(userDraft && typeof userDraft === "string" && userDraft.trim()),
      imageCount: hasImages ? images.length : 0,
      totalImageBytes: Math.round(totalImageBytes),
      timeoutMs,
      allowModelFallback,
      effectiveTier,
      isTestAccount: accountIsTest,
      shouldChargeQuota: quotaUsage.shouldChargeQuota,
      quotaReason: quotaUsage.quotaReason,
      quotaUnit: quotaUsage.quotaUnit,
      chargedMessageCount: quotaUsage.chargedMessageCount,
      estimatedMessageCount: quotaUsage.estimatedMessageCount,
      inputMessageCount: messages.length,
      compiledMessageCount,
      truncatedMessageCount,
      openingMessagesUsed,
      recentMessagesUsed,
      conversationSummaryUsed: !!conversationSummary,
      contextMode: compiledContextMode,
    };
    let claudeResult;
    try {
      // OCR-only image requests can fail faster than full image analysis,
      // while text-only "my_message" can use a shorter timeout.
      logInfo("claude_request_started", {
        user: summarizeUser(user.id),
        model: selectedModel,
        hasImages,
        recognizeOnly,
        requestType,
        timeoutMs,
        allowModelFallback,
      });

      claudeResult = await callClaudeWithFallback(
        {
          model: selectedModel,
          max_tokens: recognizeOnly
            ? 1600
            : (hasImages ? 2048 : (isMyMessageMode ? 512 : 1024)), // 截圖分析需要更多 tokens
          system: systemPrompt,
          messages: [
            {
              role: "user",
              content: userMessageContent,
            },
          ],
        },
        CLAUDE_API_KEY,
        { timeout: timeoutMs, allowModelFallback },
      );
    } catch (error) {
      const latencyMs = Date.now() - startTime;

      if (error instanceof AiServiceError) {
        const upstreamGuardrails = buildServerGuardrailObservability({
          requestType,
          imageCount: hasImages ? images.length : 0,
          latencyMs,
          timeoutMs,
          fallbackUsed: error.metadata.fallbackUsed ?? false,
          retryCount: error.metadata.retries ?? 0,
          totalImageBytes: Math.round(totalImageBytes),
          truncatedMessageCount,
          conversationSummaryUsed: !!conversationSummary,
          contextMode: compiledContextMode,
        });

        // Log failed request
        await logAiCall(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
          userId: user.id,
          model: selectedModel,
          requestType,
          inputTokens: 0,
          outputTokens: 0,
          latencyMs,
          status: "failed",
          errorCode: error.code,
          errorMessage: error.message,
          requestBody: requestObservability,
          responseBody: {
            failureStage: "upstream_request",
            retryable: error.retryable,
            lastFailureCode: error.metadata.lastFailureCode ?? error.code,
            retries: error.metadata.retries ?? 0,
            fallbackUsed: error.metadata.fallbackUsed ?? false,
            lastModel: error.metadata.lastModel ?? selectedModel,
            ...upstreamGuardrails,
          },
        });

        return jsonResponse({
          error: error.message,
          code: error.code,
          retryable: error.retryable,
        }, 502);
      }
      throw error;
    }

    const claudeData = claudeResult.data as {
      content?: Array<{ text?: string }>;
      [key: string]: unknown;
    };
    const content = claudeData.content?.[0]?.text;
    const actualModel = claudeResult.model;
    const latencyMs = Date.now() - startTime;
    const tokenUsage = extractTokenUsage(claudeData);
    logInfo("claude_request_succeeded", {
      user: summarizeUser(user.id),
      model: actualModel,
      latencyMs,
      inputTokens: tokenUsage.inputTokens,
      outputTokens: tokenUsage.outputTokens,
      fallbackUsed: claudeResult.fallbackUsed,
      retries: claudeResult.retries,
      requestType,
    });

    // Parse Claude's response
    let result;
    try {
      const aiText = content ?? "";
      const jsonMatch = aiText.match(/\{[\s\S]*\}/);
      if (!jsonMatch) {
        logWarn("ai_response_missing_json", {
          user: summarizeUser(user.id),
          model: actualModel,
          textLength: aiText.length,
          recognizeOnly,
          hasImages,
        });
        throw new Error("No JSON in response");
      }

      // 嘗試直接解析
      let jsonToParse = jsonMatch[0];
      try {
        result = JSON.parse(jsonToParse);
      } catch (firstParseError) {
        // 嘗試修復 JSON
        logInfo("ai_response_json_repair_attempt", {
          user: summarizeUser(user.id),
          model: actualModel,
          originalLength: jsonToParse.length,
        });
        const repairedJson = repairJson(jsonToParse);
        result = JSON.parse(repairedJson);
        logInfo("ai_response_json_repair_succeeded", {
          user: summarizeUser(user.id),
          model: actualModel,
          repairedLength: repairedJson.length,
        });
      }
    } catch (parseError) {
      // 記錄解析失敗但先不返回 fallback，嘗試重試
      logWarn("ai_response_parse_failed_will_retry", {
        user: summarizeUser(user.id),
        model: actualModel,
        textLength: (content ?? "").length,
        error: getErrorMessage(parseError),
        attempt: 1,
      });

      // 重試一次 Claude API 呼叫
      let retrySucceeded = false;
      try {
        logInfo("claude_retry_after_parse_failure", {
          user: summarizeUser(user.id),
          model: selectedModel,
        });

        const retryResult = await callClaudeWithFallback(
          {
            model: selectedModel,
            max_tokens: recognizeOnly
              ? 1600
              : (hasImages ? 2048 : (isMyMessageMode ? 512 : 1024)),
            system: systemPrompt + "\n\nIMPORTANT: Return valid JSON only. Ensure all brackets are properly closed.",
            messages: [
              {
                role: "user",
                content: userMessageContent,
              },
            ],
          },
          CLAUDE_API_KEY,
          { timeout: timeoutMs, allowModelFallback },
        );

        const retryData = retryResult.data as {
          content?: Array<{ text?: string }>;
        };
        const retryContent = retryData.content?.[0]?.text ?? "";
        const retryJsonMatch = retryContent.match(/\{[\s\S]*\}/);

        if (retryJsonMatch) {
          try {
            result = JSON.parse(retryJsonMatch[0]);
            retrySucceeded = true;
            logInfo("claude_retry_parse_succeeded", {
              user: summarizeUser(user.id),
              model: retryResult.model,
            });
          } catch {
            // 嘗試修復
            const repairedRetry = repairJson(retryJsonMatch[0]);
            result = JSON.parse(repairedRetry);
            retrySucceeded = true;
            logInfo("claude_retry_repair_succeeded", {
              user: summarizeUser(user.id),
              model: retryResult.model,
            });
          }
        }
      } catch (retryError) {
        logWarn("claude_retry_also_failed", {
          user: summarizeUser(user.id),
          error: getErrorMessage(retryError),
        });
      }

      // 如果重試也失敗，返回 fallback
      if (!retrySucceeded) {
        result = {
          enthusiasm: { score: 50, level: "warm" },
          replies: {
            extend: "無法生成建議，請重試",
          },
          warnings: [],
          strategy: "分析失敗，請重試",
          // 如果有 userDraft，也返回 fallback
          ...(userDraft
            ? {
              optimizedMessage: {
                original: userDraft,
                optimized: "優化失敗，請重試",
                reason: "AI 回應解析錯誤",
              },
            }
            : {}),
        };
      }
    }

    result = normalizeRecognizedConversation(result, {
      knownContactName,
    });

    // 檢查截圖識別是否失敗
    const recognizedConversation = result.recognizedConversation as
      | {
        messageCount?: number;
        importPolicy?: string;
        warning?: string;
        summary?: string;
        classification?: string;
        confidence?: string;
        sideConfidence?: string;
        uncertainSideCount?: number;
        normalizationTelemetry?: {
          continuityAdjustedCount?: number;
          groupedAdjustedCount?: number;
          layoutFirstAdjustedCount?: number;
          systemRowsRemovedCount?: number;
          quotedPreviewRemovedCount?: number;
          quotedPreviewAttachedCount?: number;
          overlapRemovedCount?: number;
        };
      }
      | undefined;
    const recognitionObservability = buildRecognitionObservability(
      recognizedConversation,
    );
    if (
      hasImages &&
      recognizedConversation?.importPolicy === "reject"
    ) {
      const rejectMessage = recognizedConversation.warning ||
        recognizedConversation.summary ||
        "這張圖片不像可支援的聊天截圖，請換一張再試。";
      const rejectGuardrails = buildServerGuardrailObservability({
        requestType,
        imageCount: hasImages ? images.length : 0,
        latencyMs,
        timeoutMs,
        fallbackUsed: claudeResult.fallbackUsed,
        retryCount: claudeResult.retries,
        totalImageBytes: Math.round(totalImageBytes),
        truncatedMessageCount,
        conversationSummaryUsed: !!conversationSummary,
        contextMode: compiledContextMode,
        recognizedClassification:
          recognitionObservability.recognizedClassification,
        recognizedSideConfidence:
          recognitionObservability.recognizedSideConfidence,
        uncertainSideCount: recognitionObservability.uncertainSideCount,
        continuityAdjustedCount:
          recognitionObservability.continuityAdjustedCount,
        groupedAdjustedCount: recognitionObservability.groupedAdjustedCount,
        layoutFirstAdjustedCount:
          recognitionObservability.layoutFirstAdjustedCount,
        quotedPreviewAttachedCount:
          recognitionObservability.quotedPreviewAttachedCount,
        overlapRemovedCount: recognitionObservability.overlapRemovedCount,
        inputTokens: tokenUsage.inputTokens,
        outputTokens: tokenUsage.outputTokens,
      });

      await logAiCall(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
        userId: user.id,
        model: actualModel,
        requestType,
        inputTokens: tokenUsage.inputTokens,
        outputTokens: tokenUsage.outputTokens,
        latencyMs,
        status: "failed",
        errorCode: "RECOGNITION_UNSUPPORTED",
        errorMessage: rejectMessage,
        requestBody: requestObservability,
        responseBody: {
          failureStage: "recognition_gate",
          ...recognitionObservability,
          ...rejectGuardrails,
        },
      });

      return jsonResponse({
        error: rejectMessage,
        code: "RECOGNITION_UNSUPPORTED",
        message: rejectMessage,
        shouldChargeQuota: false,
      }, 400);
    }
    if (
      hasImages &&
      (!recognizedConversation || recognizedConversation.messageCount === 0)
    ) {
      const recognitionFailedGuardrails = buildServerGuardrailObservability({
        requestType,
        imageCount: hasImages ? images.length : 0,
        latencyMs,
        timeoutMs,
        fallbackUsed: claudeResult.fallbackUsed,
        retryCount: claudeResult.retries,
        totalImageBytes: Math.round(totalImageBytes),
        truncatedMessageCount,
        conversationSummaryUsed: !!conversationSummary,
        contextMode: compiledContextMode,
        inputTokens: tokenUsage.inputTokens,
        outputTokens: tokenUsage.outputTokens,
      });

      // Log failed recognition
      await logAiCall(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
        userId: user.id,
        model: actualModel,
        requestType,
        inputTokens: tokenUsage.inputTokens,
        outputTokens: tokenUsage.outputTokens,
        latencyMs,
        status: "failed",
        errorCode: "RECOGNITION_FAILED",
        errorMessage: "No recognizedConversation in response",
        requestBody: requestObservability,
        responseBody: {
          failureStage: "recognition_missing_output",
          ...recognitionFailedGuardrails,
        },
      });

      return jsonResponse({
        error: "無法識別截圖中的對話內容",
        code: "RECOGNITION_FAILED",
        message:
          "請確認截圖清晰、包含聊天泡泡，並盡量帶到對話頂部與最新訊息；單張截圖也可以分析，但畫面太裁切時容易失敗",
        shouldChargeQuota: false,
      }, 400);
    }

    // Check AI output for safety (AI 護欄)
    const originalResult = { ...result };
    result = checkAiOutput(result as GuardrailAnalysisResult) as Record<
      string,
      unknown
    >;
    const warnings = Array.isArray((result as { warnings?: unknown }).warnings)
      ? ((result as {
        warnings?: Array<{ type?: string }>;
      }).warnings ?? [])
      : [];
    const wasFiltered = warnings.some((warning) =>
      warning.type === "safety_filter"
    );
    const successGuardrails = buildServerGuardrailObservability({
      requestType,
      imageCount: hasImages ? images.length : 0,
      latencyMs,
      timeoutMs,
      fallbackUsed: claudeResult.fallbackUsed,
      retryCount: claudeResult.retries,
      totalImageBytes: Math.round(totalImageBytes),
      truncatedMessageCount,
      conversationSummaryUsed: !!conversationSummary,
      contextMode: compiledContextMode,
      recognizedClassification:
        recognitionObservability.recognizedClassification,
      recognizedSideConfidence:
        recognitionObservability.recognizedSideConfidence,
      uncertainSideCount: recognitionObservability.uncertainSideCount,
      continuityAdjustedCount: recognitionObservability.continuityAdjustedCount,
      groupedAdjustedCount: recognitionObservability.groupedAdjustedCount,
      layoutFirstAdjustedCount:
        recognitionObservability.layoutFirstAdjustedCount,
      systemRowsRemovedCount: recognitionObservability.systemRowsRemovedCount,
      quotedPreviewAttachedCount:
        recognitionObservability.quotedPreviewAttachedCount,
      overlapRemovedCount: recognitionObservability.overlapRemovedCount,
      inputTokens: tokenUsage.inputTokens,
      outputTokens: tokenUsage.outputTokens,
      safetyFiltered: wasFiltered,
    });

    // Log successful request
    await logAiCall(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
      userId: user.id,
      model: actualModel,
      requestType,
      inputTokens: tokenUsage.inputTokens,
      outputTokens: tokenUsage.outputTokens,
      latencyMs,
      status: wasFiltered ? "filtered" : "success",
      fallbackUsed: claudeResult.fallbackUsed,
      retryCount: claudeResult.retries,
      requestBody: requestObservability,
      responseBody: {
        filtered: wasFiltered,
        retries: claudeResult.retries,
        fallbackUsed: claudeResult.fallbackUsed,
        ...recognitionObservability,
        ...successGuardrails,
      },
    });

    // Filter replies based on tier
    if (result?.replies) {
      const filteredReplies: Record<string, string> = {};
      for (const [key, value] of Object.entries(result.replies)) {
        if (allowedFeatures.includes(key)) {
          filteredReplies[key] = value as string;
        }
      }
      result.replies = filteredReplies;
    }

    // Remove health check if not allowed
    if (!allowedFeatures.includes("health_check")) {
      delete result.healthCheck;
    }

    // Update usage count (測試帳號、純識別模式不扣額度)
    if (quotaUsage.shouldChargeQuota && quotaUsage.chargedMessageCount > 0) {
      // Single source of truth for usage accounting (avoid double counting).
      const { error: usageError } = await supabase.rpc("increment_usage", {
        p_user_id: user.id,
        p_messages: quotaUsage.chargedMessageCount,
      });

      if (usageError) {
        console.error("Failed to increment usage:", usageError);
      }
    }

    // Add usage info to response
    result.usage = {
      messagesUsed: quotaUsage.chargedMessageCount,
      estimatedMessages: quotaUsage.estimatedMessageCount,
      monthlyRemaining: accountIsTest
        ? 999999
        : monthlyLimit - sub.monthly_messages_used -
          quotaUsage.chargedMessageCount,
      dailyRemaining: accountIsTest
        ? 999999
        : dailyLimit - sub.daily_messages_used - quotaUsage.chargedMessageCount,
      model: actualModel,
      fallbackUsed: claudeResult.fallbackUsed,
      retries: claudeResult.retries,
      imagesUsed: hasImages ? images.length : 0,
      tierUsed: effectiveTier,
      isTestAccount: accountIsTest,
      requestType,
      shouldChargeQuota: quotaUsage.shouldChargeQuota,
      quotaReason: quotaUsage.quotaReason,
      quotaUnit: quotaUsage.quotaUnit,
    };

    result.telemetry = {
      requestType,
      imageCount: hasImages ? images.length : 0,
      totalImageBytes: Math.round(totalImageBytes),
      serverAiLatencyMs: latencyMs,
      fallbackUsed: claudeResult.fallbackUsed,
      retries: claudeResult.retries,
      timeoutMs,
      allowModelFallback,
      contextMode: compiledContextMode,
      inputMessageCount: messages.length,
      compiledMessageCount,
      truncatedMessageCount,
      openingMessagesUsed,
      recentMessagesUsed,
      conversationSummaryUsed: !!conversationSummary,
      recognizedClassification: recognizedConversation?.classification ?? null,
      recognizedConfidence: recognizedConversation?.confidence ?? null,
      recognizedSideConfidence: recognizedConversation?.sideConfidence ?? null,
      recognizedMessageCount: recognizedConversation?.messageCount ?? null,
      uncertainSideCount: recognizedConversation?.uncertainSideCount ?? null,
      continuityAdjustedCount: recognizedConversation?.normalizationTelemetry
        ?.continuityAdjustedCount ?? 0,
      groupedAdjustedCount: recognizedConversation?.normalizationTelemetry
        ?.groupedAdjustedCount ?? 0,
      layoutFirstAdjustedCount: recognizedConversation?.normalizationTelemetry
        ?.layoutFirstAdjustedCount ?? 0,
      systemRowsRemovedCount: recognizedConversation?.normalizationTelemetry
        ?.systemRowsRemovedCount ?? 0,
      quotedPreviewRemovedCount: recognizedConversation?.normalizationTelemetry
        ?.quotedPreviewRemovedCount ?? 0,
      quotedPreviewAttachedCount: recognizedConversation?.normalizationTelemetry
        ?.quotedPreviewAttachedCount ?? 0,
      overlapRemovedCount: recognizedConversation?.normalizationTelemetry
        ?.overlapRemovedCount ?? 0,
      guardrailSeverity: successGuardrails.guardrailSeverity,
      guardrailCount: successGuardrails.guardrailCount,
      guardrailFlags: successGuardrails.guardrailFlags,
      totalTokens: successGuardrails.totalTokens,
      shouldChargeQuota: quotaUsage.shouldChargeQuota,
      chargedMessageCount: quotaUsage.chargedMessageCount,
      estimatedMessageCount: quotaUsage.estimatedMessageCount,
      quotaReason: quotaUsage.quotaReason,
    };

    return jsonResponse(result);
  } catch (error) {
    logError("unhandled_error", { error: getErrorMessage(error) });
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});

// Prompt Caching enabled
// Last deployed: 2026-03-06
