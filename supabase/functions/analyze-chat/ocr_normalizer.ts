// OcrNormalizer：模型回傳的 recognizedConversation 正規化管線。
// classification/importPolicy/confidence 正規化、通話事件與媒體佔位判讀、
// 引用預覽折疊、幾何/連續性/群組 speaker heuristics、聯絡人名穩定、
// Google Maps 分享折疊與序列去重，最終產出 client 可用的訊息序列。
// geometryDecisive／metaDecisive 是不可翻轉 invariant（詳見各 guard 註解）。

import { getErrorMessage, logWarn } from "./logger.ts";
import {
  MAX_CONTACT_NAME_LENGTH,
  MAX_QUOTED_REPLY_PREVIEW_LENGTH,
} from "./analysis_input_compiler.ts";
import {
  type BlockType,
  foldQuotedPreviewBlocks,
  normalizeBlockType,
} from "./blocktype_fold.ts";
import { applyLayoutFirstParser } from "./layout_parser.ts";
import { isReadReceiptSideDecisive } from "./screenshot_ocr_rules.ts";
import { normalizeGoogleMapsShares } from "./map_share_normalizer.ts";

type RecognizedBubbleSide = "left" | "right" | "unknown";

interface NormalizedRecognizedMessage {
  side: RecognizedBubbleSide;
  isFromMe: boolean;
  content: string;
  // bake-off arm-2：vision 忠實分類的視覺區塊型別。缺省＝message（向後相容）。
  // quoted_preview row 由 foldQuotedPreviewBlocks 確定性折進主訊息後移除。
  blockType?: BlockType;
  quotedReplyPreview?: string;
  quotedReplyPreviewIsFromMe?: boolean;
  // Carries the geometry-lock signal down to applyLayoutFirstParser so an
  // unambiguous spatial side is never flipped by neighbour/dominant heuristics.
  geometryDecisive?: boolean;
  // 已讀鎖：模型回報 readReceipt=true 的泡（LINE 介面規則＝已讀只出現在我方
  // 訊息旁）強制 isFromMe=true，任何 speaker heuristic 不得再翻——與
  // geometryDecisive 同款 invariant，訊號來源是 meta 錨點而非幾何。
  metaDecisive?: boolean;
}

type VisibleSpeakerPattern = "mixed" | "only_left" | "only_right" | "unknown";

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

function _isLikelyUserFacingChinese(value: string): boolean {
  return /[\u4e00-\u9fff]/.test(value);
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

  if (trimmed.includes("\n")) {
    return false;
  }

  const compact = trimmed.replace(/\s+/g, "");
  if (compact.length > 14) {
    return false;
  }

  if (/[.!?！？。]$/.test(trimmed) && compact.length > 4) {
    return false;
  }

  if (trimmed.split(/\s+/).length >= 2 && compact.length > 8) {
    return false;
  }

  return true;
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

  const targetSide: RecognizedBubbleSide = pattern === "only_left"
    ? "left"
    : "right";
  const targetIsFromMe = targetSide === "right";
  const adjusted = messages.map((message) => ({ ...message }));
  let adjustedCount = 0;

  for (let index = 0; index < adjusted.length; index += 1) {
    // 幾何已定側的泡（明確 outerColumn 或越界 horizontalPosition）不得被
    // 整體單側 pattern 壓掉——與四個 neighbour heuristic 同一 invariant。
    if (
      adjusted[index].geometryDecisive === true ||
      adjusted[index].metaDecisive === true
    ) {
      continue;
    }

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

  const previousComparable = normalizeComparableMessageText(previous.content);
  const currentComparable = normalizeComparableMessageText(current.content);
  const previousCanOverlap =
    isLikelyMediaPlaceholderContent(previous.content) ||
    !!previous.quotedReplyPreview ||
    previousComparable.replace(/\s+/g, "").length >= 8;
  const currentCanOverlap = isLikelyMediaPlaceholderContent(current.content) ||
    !!current.quotedReplyPreview ||
    currentComparable.replace(/\s+/g, "").length >= 8;

  if (!previousCanOverlap && !currentCanOverlap) {
    return false;
  }

  return previousComparable === currentComparable;
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

// Horizontal-position gates (0=far left, 100=far right). A bubble past either
// gate is geometrically unambiguous; the band between them is the mid-zone where
// spatial signal is too weak to lock a side. Shared by normalizeBubbleSide and
// isGeometrySideDecisive so the thresholds can never drift apart.
const RIGHT_HORIZONTAL_THRESHOLD = 58;
const LEFT_HORIZONTAL_THRESHOLD = 42;

function readHorizontalPosition(record: Record<string, unknown>): number {
  return typeof record.horizontalPosition === "number"
    ? record.horizontalPosition
    : typeof record.horizontalPosition === "string"
    ? Number(record.horizontalPosition)
    : Number.NaN;
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

  const rawHorizontalPosition = readHorizontalPosition(record);
  if (!Number.isNaN(rawHorizontalPosition)) {
    if (rawHorizontalPosition >= RIGHT_HORIZONTAL_THRESHOLD) {
      return "right";
    }
    if (rawHorizontalPosition <= LEFT_HORIZONTAL_THRESHOLD) {
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

// True when the resolved side came from an unambiguous spatial signal: an
// explicit outer column, or a horizontalPosition past either gate. The string
// `side` fallback and the mid-zone band are NOT decisive — those stay eligible
// for the layout parser's neighbour/dominant/quoted rescues. Mirrors the
// precedence in normalizeBubbleSide exactly; a decisive record always resolves
// to a concrete left/right side.
function isGeometrySideDecisive(record: Record<string, unknown>): boolean {
  const rawOuterColumn = typeof record.outerColumn === "string"
    ? record.outerColumn.trim().toLowerCase()
    : "";
  if (rawOuterColumn === "right" || rawOuterColumn === "left") {
    return true;
  }

  const rawHorizontalPosition = readHorizontalPosition(record);
  return !Number.isNaN(rawHorizontalPosition) &&
    (rawHorizontalPosition >= RIGHT_HORIZONTAL_THRESHOLD ||
      rawHorizontalPosition <= LEFT_HORIZONTAL_THRESHOLD);
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

    // 幾何已定側的泡（明確 outerColumn 或越界 horizontalPosition）不得被鄰居啟發式翻側。
    if (current.geometryDecisive === true || current.metaDecisive === true) {
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

    const shouldStripQuotedPreview = shouldStripExplicitQuotedPreview ||
      shouldStripBodyOnlyQuotedPreview;

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

    // 幾何已定側的泡（明確 outerColumn 或越界 horizontalPosition）不得被鄰居啟發式翻側。
    if (current.geometryDecisive === true || current.metaDecisive === true) {
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

    // 幾何已定側的泡（明確 outerColumn 或越界 horizontalPosition）不得被鄰居啟發式翻側。
    if (current.geometryDecisive === true || current.metaDecisive === true) {
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

  // 幾何已定側的泡（明確 outerColumn 或越界 horizontalPosition）不得被鄰居啟發式翻側。
  if (current.geometryDecisive === true || current.metaDecisive === true) {
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

// ── OCR 第③軌 Phase 1（量測閘）純觀測插樁 ──────────────────────────────
// 只在 OCR_PHASE1_INSTRUMENT=1（本機 bench）時掛上。教模型「額外」吐每泡填色、
// 發話者名字字串+位置、引用卡名字、整圖我方泡色+證據來源——全是 append-only 觀測欄，
// 明令「絕不」改變 side/isFromMe 判讀（仍只認外層泡泡位置）。
// 設計：docs/plans/2026-06-14-ocr-dark-fill-color-side-design.md「Phase 1 補強」段。
function extractPhase1VisionTelemetry(
  rawResult: Record<string, unknown>,
): Record<string, unknown> | null {
  const rc = rawResult?.recognizedConversation;
  if (!rc || typeof rc !== "object") return null;
  const rcObj = rc as Record<string, unknown>;
  const rawMessages = Array.isArray(rcObj.messages) ? rcObj.messages : [];
  const messages = rawMessages.map((m) => {
    const r = (m && typeof m === "object" ? m : {}) as Record<string, unknown>;
    return {
      content: typeof r.content === "string" ? r.content : "",
      side: typeof r.side === "string" ? r.side : null,
      outerColumn: typeof r.outerColumn === "string" ? r.outerColumn : null,
      horizontalPosition: typeof r.horizontalPosition === "number"
        ? r.horizontalPosition
        : (typeof r.horizontalPosition === "string" &&
            r.horizontalPosition.trim() !== "" &&
            !Number.isNaN(Number(r.horizontalPosition))
          ? Number(r.horizontalPosition)
          : null),
      blockType: typeof r.blockType === "string" ? r.blockType : null,
      isFromMe: r.isFromMe === true || r.isFromMe === "true",
      bubbleFillColor: typeof r.bubbleFillColor === "string"
        ? r.bubbleFillColor
        : null,
      senderNameRaw: typeof r.senderNameRaw === "string"
        ? r.senderNameRaw
        : null,
      senderNameX: typeof r.senderNameX === "number" ? r.senderNameX : null,
      quotedName: typeof r.quotedName === "string" ? r.quotedName : null,
      quotedNamePresent: typeof r.quotedNamePresent === "boolean"
        ? r.quotedNamePresent
        : null,
    };
  });
  return {
    myBubbleColor: typeof rcObj.myBubbleColor === "string"
      ? rcObj.myBubbleColor
      : null,
    myBubbleColorEvidence: typeof rcObj.myBubbleColorEvidence === "string"
      ? rcObj.myBubbleColorEvidence
      : null,
    screenSpeakerPattern: typeof rcObj.screenSpeakerPattern === "string"
      ? rcObj.screenSpeakerPattern
      : null,
    messages,
  };
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
      "這批截圖看起來可能混入了不同聯絡人或不同聊天段落，請先確認是不是同一段對話，再決定要不要匯入。";
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
    .map((message): NormalizedRecognizedMessage | null => {
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
      const geometryDecisive = side !== "unknown" &&
        isGeometrySideDecisive(record);
      // 已讀鎖：readReceipt=true 是介面規則級的我方訊號，蓋過模型自報的
      // side/isFromMe（黑箱驗證 29 個回報零捏造；metaSide 會被捏造、這個不會）。
      const metaDecisive = isReadReceiptSideDecisive(record);
      // 衝突 telemetry（P2-2）：readReceipt 若真的捏造一次，會無聲翻掉
      // geometry-decisive 的左側硬證據，事後無法從 log 觀察。只記錄不改
      // 優先序（metaDecisive 仍勝，bc02382 C 臂配方）；先收線上數據再議。
      if (metaDecisive && geometryDecisive && side === "left") {
        logWarn("ocr_meta_geometry_side_conflict", {
          outerColumn: typeof record.outerColumn === "string"
            ? record.outerColumn
            : undefined,
          horizontalPosition: typeof record.horizontalPosition === "number"
            ? record.horizontalPosition
            : undefined,
          contentLength: content.length,
        });
      }
      const blockType = normalizeBlockType(record);
      const quotedReplyPreview = sanitizeQuotedReplyPreviewValue(
        record.quotedReplyPreview,
      );
      const quotedReplyPreviewIsFromMe = quotedReplyPreview == null
        ? undefined
        : normalizeQuotedReplyPreviewIsFromMe(record);

      return {
        side: metaDecisive ? "right" : side,
        isFromMe: metaDecisive ? true : sideToIsFromMe(side, record.isFromMe),
        content,
        ...(blockType ? { blockType } : {}),
        ...(geometryDecisive ? { geometryDecisive } : {}),
        ...(metaDecisive ? { metaDecisive } : {}),
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
  // bake-off arm-2 / B-prime（Codex 裁決）：確定性 blockType 折疊先於舊 strip，
  // 但「永不」關掉舊 strip 安全網。fold 已先移除所有 quoted_preview row
  // （double-fold guard：殘留列零 quoted_preview，舊 strip 不可能重折同一張卡），
  // 之後對 residual rows 一律跑 stripQuotedReplyPreviewMessages，靠其既有 guards
  // 控 false positive，接住模型「有 blockType 意識卻漏標引用卡」洩漏的鬼訊息
  // （S__5513242 bake-off 打掉了純信任模型的 A 案）。
  const foldAdjustment = foldQuotedPreviewBlocks(groupedAdjustment.messages);
  const legacyStripAdjustment = stripQuotedReplyPreviewMessages(
    foldAdjustment.messages,
  );
  const quotedPreviewAdjustment = {
    messages: legacyStripAdjustment.messages,
    // 對外 telemetry/warning：折疊移除（折入＋丟孤兒）＋舊 strip 移除。
    removedCount: foldAdjustment.foldedCount +
      foldAdjustment.droppedOrphanCount + legacyStripAdjustment.removedCount,
    attachedCount: foldAdjustment.foldedCount +
      legacyStripAdjustment.attachedCount,
  };
  const sideRunAdjustment = applySideRunGroupingHeuristics(
    quotedPreviewAdjustment.messages,
  );
  let layoutFirstAdjustment;
  try {
    layoutFirstAdjustment = applyLayoutFirstParser(
      sideRunAdjustment.messages,
    );
  } catch (error) {
    // 兜底不變（沿用未調整訊息），但失敗必須可觀測。
    logWarn("layout_first_parser_failed", {
      error: getErrorMessage(error),
      messageCount: sideRunAdjustment.messages.length,
    });
    layoutFirstAdjustment = {
      messages: sideRunAdjustment.messages,
      adjustedCount: 0,
      systemRowsRemovedCount: 0,
    };
  }
  const trailingAdjustment = applyTrailingSpeakerHeuristics(
    layoutFirstAdjustment.messages,
  );
  const mapShareAdjustment = normalizeGoogleMapsShares(
    trailingAdjustment.messages,
  );
  const overlapAdjustment = deduplicateSequentialMessages(
    mapShareAdjustment.messages,
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
      mapShareCollapsedCount: mapShareAdjustment.collapsedCount,
      // bake-off arm-2 量測：blockType 折疊 telemetry。
      blockTypeMessageCount: foldAdjustment.blockTypeCounts.message,
      blockTypeQuotedPreviewCount:
        foldAdjustment.blockTypeCounts.quoted_preview,
      blockTypeFoldedCount: foldAdjustment.foldedCount,
      blockTypeDroppedOrphanCount: foldAdjustment.droppedOrphanCount,
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

export {
  applySingleVisibleSpeakerPattern,
  sanitizeContactNameValue,
  CALL_EVENT_KEYWORDS,
  deduplicateSequentialMessages,
  extractPhase1VisionTelemetry,
  inferScreenshotClassificationHint,
  isCallEventLikeMessage,
  isLikelyChatThreadCallEventScreenshot,
  normalizeRecognizedConversation,
  normalizeScreenshotClassification,
  VALID_IMPORT_POLICIES,
  VALID_SCREENSHOT_CLASSIFICATIONS,
};
export type {
  NormalizedRecognizedMessage,
  RecognizedBubbleSide,
  VisibleSpeakerPattern,
};
