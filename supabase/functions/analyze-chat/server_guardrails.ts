const OCR_SINGLE_WARNING_MS = 7000;
const OCR_MULTI_WARNING_MS = 15000;
const ANALYZE_WARNING_MS = 12000;
const MY_MESSAGE_WARNING_MS = 6000;
const OPTIMIZE_WARNING_MS = 6000;
const HEAVY_IMAGE_PAYLOAD_BYTES = 700 * 1024;
const HIGH_TOKEN_USAGE_TOTAL = 6000;
const NEAR_TIMEOUT_RATIO = 0.8;

export type ServerGuardrailSeverity = "none" | "info" | "warning" | "critical";

export interface ServerGuardrailInput {
  requestType: string;
  imageCount?: number;
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
  quotedPreviewAttachedCount?: number | null;
  overlapRemovedCount?: number | null;
  inputTokens?: number;
  outputTokens?: number;
  safetyFiltered?: boolean;
}

export interface ServerGuardrailSnapshot {
  guardrailSeverity: ServerGuardrailSeverity;
  guardrailCount: number;
  guardrailFlags: string;
  hasSlowRequest: boolean;
  hasNearTimeout: boolean;
  hasUnstableUpstream: boolean;
  hasHeavyImagePayload: boolean;
  hasCompressedContext: boolean;
  hasNonstandardScreenshot: boolean;
  hasUncertainSide: boolean;
  hasStructureRepairs: boolean;
  hasHighTokenUsage: boolean;
  hasSafetyFilter: boolean;
  totalTokens: number;
}

export function buildServerGuardrails(
  input: ServerGuardrailInput,
): ServerGuardrailSnapshot {
  const flags: string[] = [];
  const totalTokens = (input.inputTokens ?? 0) + (input.outputTokens ?? 0);

  const hasSlowRequest = input.latencyMs >
    warningThresholdMs(input.requestType, input.imageCount ?? 0);
  if (hasSlowRequest) flags.push("slow_request");

  const timeoutMs = input.timeoutMs ?? 0;
  const hasNearTimeout = timeoutMs > 0 &&
    input.latencyMs >= timeoutMs * NEAR_TIMEOUT_RATIO;
  if (hasNearTimeout) flags.push("near_timeout");

  const hasUnstableUpstream = (input.retryCount ?? 0) > 0 ||
    input.fallbackUsed === true;
  if (hasUnstableUpstream) flags.push("unstable_upstream");

  const hasHeavyImagePayload = (input.totalImageBytes ?? 0) >
    HEAVY_IMAGE_PAYLOAD_BYTES;
  if (hasHeavyImagePayload) flags.push("heavy_image_payload");

  const hasCompressedContext = (input.truncatedMessageCount ?? 0) > 0 ||
    input.conversationSummaryUsed === true ||
    input.contextMode === "opening_plus_recent";
  if (hasCompressedContext) flags.push("compressed_context");

  const hasNonstandardScreenshot = !!input.recognizedClassification &&
    input.recognizedClassification !== "valid_chat";
  if (hasNonstandardScreenshot) flags.push("nonstandard_screenshot");

  const hasUncertainSide = input.recognizedSideConfidence === "low" ||
    (input.uncertainSideCount ?? 0) > 0;
  if (hasUncertainSide) flags.push("uncertain_speaker_side");

  const hasStructureRepairs = (input.continuityAdjustedCount ?? 0) > 0 ||
    (input.groupedAdjustedCount ?? 0) > 0 ||
    (input.layoutFirstAdjustedCount ?? 0) > 0 ||
    (input.quotedPreviewAttachedCount ?? 0) > 0 ||
    (input.overlapRemovedCount ?? 0) > 0;
  if (hasStructureRepairs) flags.push("structure_repaired");

  const hasHighTokenUsage = totalTokens >= HIGH_TOKEN_USAGE_TOTAL;
  if (hasHighTokenUsage) flags.push("high_token_usage");

  const hasSafetyFilter = input.safetyFiltered === true;
  if (hasSafetyFilter) flags.push("safety_filtered");

  return {
    guardrailSeverity: deriveSeverity({
      hasSlowRequest,
      hasNearTimeout,
      hasUnstableUpstream,
      hasHeavyImagePayload,
      hasCompressedContext,
      hasNonstandardScreenshot,
      hasUncertainSide,
      hasStructureRepairs,
      hasHighTokenUsage,
      hasSafetyFilter,
    }),
    guardrailCount: flags.length,
    guardrailFlags: flags.join(","),
    hasSlowRequest,
    hasNearTimeout,
    hasUnstableUpstream,
    hasHeavyImagePayload,
    hasCompressedContext,
    hasNonstandardScreenshot,
    hasUncertainSide,
    hasStructureRepairs,
    hasHighTokenUsage,
    hasSafetyFilter,
    totalTokens,
  };
}

function warningThresholdMs(requestType: string, imageCount: number): number {
  switch (requestType) {
    case "recognize_only":
      return imageCount > 1 ? OCR_MULTI_WARNING_MS : OCR_SINGLE_WARNING_MS;
    case "analyze_with_images":
      return OCR_MULTI_WARNING_MS;
    case "my_message":
      return MY_MESSAGE_WARNING_MS;
    case "optimize_message":
      return OPTIMIZE_WARNING_MS;
    default:
      return ANALYZE_WARNING_MS;
  }
}

function deriveSeverity(
  input: Omit<
    ServerGuardrailSnapshot,
    "guardrailSeverity" | "guardrailCount" | "guardrailFlags" | "totalTokens"
  >,
): ServerGuardrailSeverity {
  if (
    input.hasNearTimeout ||
    input.hasSafetyFilter ||
    input.hasHighTokenUsage ||
    input.hasNonstandardScreenshot
  ) {
    return "critical";
  }

  if (
    input.hasSlowRequest ||
    input.hasUnstableUpstream ||
    input.hasHeavyImagePayload ||
    input.hasUncertainSide
  ) {
    return "warning";
  }

  if (input.hasCompressedContext || input.hasStructureRepairs) {
    return "info";
  }

  return "none";
}
