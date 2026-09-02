// Phase 0 only: derive content-free observability from optional typed stream
// metadata. This module never changes a generated result or stream contract.

import { isPlainObject } from "../_shared/quota.ts";
import { isStreamStyle, type StreamStyle } from "./stream_events.ts";
import { COACH_ACTION_HINT_ACTION_TYPES } from "./post_process.ts";
import {
  DIVERGENCE_BRANCH_ID_PATTERN,
  MAX_STYLE_INTENSITY,
  parseDivergencePlanV1,
  RHETORICAL_MOVES,
  STYLE_BRANCH_SOURCES,
} from "./divergence_contract.ts";

const ACTIONS = new Set([
  "stop",
  "connect",
  "extend",
  "filter",
  "invite",
  "pause",
]);
const BRANCH_SOURCES = new Set<string>(STYLE_BRANCH_SOURCES);
const MOVES = new Set<string>(RHETORICAL_MOVES);

/// 只收 opaque 分枝 id（br_N）；空陣列代表 unresolved，也是合法值。
function branchIdArray(value: unknown): string[] | null {
  if (!Array.isArray(value)) return null;
  const ids: string[] = [];
  for (const id of value) {
    if (typeof id !== "string" || !DIVERGENCE_BRANCH_ID_PATTERN.test(id)) {
      return null;
    }
    if (!ids.includes(id)) ids.push(id);
  }
  return ids;
}
const MESSAGE_DECISIONS = new Set([
  "send",
  "do_not_send",
  "acknowledge_and_stop",
  "need_context",
]);
const REPLY_MODES = new Set(["variants", "single", "none"]);
// Telemetry may carry only a canonical opaque decision identifier, never a
// readable model field. `ad_` + an uppercase Crockford ULID is the Phase 0
// log allowlist; the persisted decision keeps its original optional value.
const SAFE_DECISION_ID = /^ad_[0-7][0-9A-HJKMNPQRSTVWXYZ]{25}$/;
const BETA_FLAGS = new Set([
  "over_explaining",
  "reassurance_seeking",
  "approval_seeking",
  "self_deprecation",
  "all_flexibility",
  "conversation_rescue",
  "over_investment",
  "question_only",
  "unsupported_compliment",
  "reinvite_without_window",
  "apologizing_for_interest",
  "customer_service_tone",
  "tone_mismatch",
  "topic_spray",
  "question_barrage",
  "solution_mode",
  "remote_association",
  "frame_pleasing",
]);

type Variant = {
  sourceIndices?: number[];
  sourceBallIds?: string[];
  action?: string;
  selectedBallIds?: string[];
  questionCount?: number;
  newTopicCount?: number;
  semanticDistance?: number;
  solutionMode?: boolean;
  selectedBranchIds?: string[];
  branchSource?: string;
  rhetoricalMove?: string;
  styleIntensity?: number;
  branchAttributionInvalid?: boolean;
};

type SourceMessageSegment = {
  sourceIndex: number;
  sourceMessage: string;
};

type TelemetryEmitter = (
  event: string,
  metadata?: Record<string, unknown>,
) => void;

function record(value: unknown): Record<string, unknown> | null {
  return isPlainObject(value) && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function enumValue(
  value: unknown,
  allowed: ReadonlySet<string>,
): string | null {
  return typeof value === "string" && allowed.has(value) ? value : null;
}

function safeDecisionId(value: unknown): string | null {
  return typeof value === "string" && SAFE_DECISION_ID.test(value)
    ? value
    : null;
}

function stringArray(value: unknown): string[] | null {
  if (!Array.isArray(value) || value.some((item) => typeof item !== "string")) {
    return null;
  }
  const values = value.map((item) => item.trim());
  return values.every(Boolean) ? values : null;
}

function positiveIndices(value: unknown): number[] | null {
  if (!Array.isArray(value)) return null;
  const values = value.map((item) =>
    typeof item === "number" && Number.isInteger(item) && item > 0 ? item : null
  );
  return values.every((item) => item !== null) ? values as number[] : null;
}

function nonNegativeNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) && value >= 0
    ? value
    : null;
}

function variantsFrom(
  linkage: Record<string, unknown> | null,
): Record<string, Variant> | null {
  const raw = record(linkage?.variants);
  if (!raw) return null;

  const variants: Record<string, Variant> = {};
  for (const [style, value] of Object.entries(raw)) {
    if (!isStreamStyle(style)) return null;
    const candidate = record(value);
    if (!candidate) return null;
    const sourceIndices = positiveIndices(candidate.sourceIndices);

    const action = enumValue(candidate.action, ACTIONS);
    const sourceBallIds = stringArray(candidate.sourceBallIds);
    const selectedBallIds = stringArray(candidate.selectedBallIds);
    const questionCount = nonNegativeNumber(candidate.questionCount);
    const newTopicCount = nonNegativeNumber(candidate.newTopicCount);
    const semanticDistance = nonNegativeNumber(candidate.semanticDistance);
    const solutionMode = typeof candidate.solutionMode === "boolean"
      ? candidate.solutionMode
      : undefined;
    const selectedBranchIds = branchIdArray(candidate.selectedBranchIds);
    const branchSource = enumValue(candidate.branchSource, BRANCH_SOURCES);
    const rhetoricalMove = enumValue(candidate.rhetoricalMove, MOVES);
    const styleIntensity = nonNegativeNumber(candidate.styleIntensity);
    const branchAttributionInvalid =
      typeof candidate.branchAttributionInvalid === "boolean"
        ? candidate.branchAttributionInvalid
        : undefined;
    variants[style] = {
      ...(selectedBranchIds ? { selectedBranchIds } : {}),
      ...(branchSource ? { branchSource } : {}),
      ...(rhetoricalMove ? { rhetoricalMove } : {}),
      ...(styleIntensity !== null && styleIntensity <= MAX_STYLE_INTENSITY
        ? { styleIntensity }
        : {}),
      ...(branchAttributionInvalid !== undefined
        ? { branchAttributionInvalid }
        : {}),
      ...(sourceIndices ? { sourceIndices } : {}),
      ...(sourceBallIds ? { sourceBallIds } : {}),
      ...(action ? { action } : {}),
      ...(selectedBallIds ? { selectedBallIds } : {}),
      ...(questionCount !== null ? { questionCount } : {}),
      ...(newTopicCount !== null ? { newTopicCount } : {}),
      ...(semanticDistance !== null ? { semanticDistance } : {}),
      ...(solutionMode !== undefined ? { solutionMode } : {}),
    };
  }
  return Object.keys(variants).length > 0 ? variants : null;
}

function meaningfulInventoryIndices(
  inventory: Record<string, unknown> | null,
): number[] | null {
  if (!inventory || !Array.isArray(inventory.balls)) return null;
  const indices: number[] = [];
  for (const ball of inventory.balls) {
    const item = record(ball);
    if (!item || !["接", "併", "略"].includes(item.disposition as string)) {
      return null;
    }
    const sourceIndex = positiveIndices([item.sourceIndex]);
    if (!sourceIndex) return null;
    if (item.disposition === "接") indices.push(sourceIndex[0]);
  }
  const unique = [...new Set(indices)].sort((left, right) => left - right);
  return unique.length > 0 ? unique : null;
}

function sameStringSet(left: string[], right: string[]): boolean {
  return left.length === right.length &&
    left.every((value) => right.includes(value)) &&
    right.every((value) => left.includes(value));
}

function sameStringOrder(
  left: readonly string[],
  right: readonly string[],
): boolean {
  return left.length === right.length &&
    left.every((value, index) => value === right[index]);
}

function sameNumberOrder(
  left: readonly number[],
  right: readonly number[],
): boolean {
  return left.length === right.length &&
    left.every((value, index) => value === right[index]);
}

function nonEmptyString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value : null;
}

function replyTextFromSegments(
  segments: readonly Record<string, unknown>[],
): string {
  return segments
    .map((segment) =>
      nonEmptyString(
        segment.reply ?? segment.content ?? segment.text,
      )
    )
    .filter((text): text is string => text !== null)
    .join("\n");
}

function replySegmentsForStyle(
  finalResult: Record<string, unknown>,
  style: string,
  selectedStyle: string | null,
): Record<string, unknown>[] | null {
  const finalRecommendation = record(finalResult.finalRecommendation);
  if (
    style === selectedStyle &&
    isStreamStyle(finalRecommendation?.pick) &&
    finalRecommendation.pick === style &&
    Array.isArray(finalRecommendation.replySegments)
  ) {
    return finalRecommendation.replySegments.flatMap((segment) => {
      const candidate = record(segment);
      return candidate ? [candidate] : [];
    });
  }

  const replyOptions = record(finalResult.replyOptions);
  const option = record(replyOptions?.[style]);
  const rawSegments = option?.messages ?? option?.messageGroup ??
    option?.replySegments;
  if (!Array.isArray(rawSegments)) return null;
  return rawSegments.flatMap((segment) => {
    const candidate = record(segment);
    return candidate ? [candidate] : [];
  });
}

function sourceIndexSequenceFromDeliveredSegments(
  segments: readonly Record<string, unknown>[] | null,
): number[] | null {
  if (!segments || segments.length === 0) return null;
  const indices: number[] = [];
  for (const segment of segments) {
    const sourceIndex = positiveIndices([segment.sourceIndex])?.[0];
    // An incomplete source sequence must not be reported as partial coverage.
    if (!sourceIndex) return null;
    indices.push(sourceIndex);
  }
  return indices.length > 0 ? indices : null;
}

function sourceIndicesFromDeliveredSegments(
  segments: readonly Record<string, unknown>[] | null,
): number[] | null {
  const sequence = sourceIndexSequenceFromDeliveredSegments(segments);
  return sequence ? [...new Set(sequence)] : null;
}

function sourceBallIdsFromDeliveredIndices(
  finalResult: Record<string, unknown>,
  sourceIndices: readonly number[],
): string[] | null {
  const inventory = record(finalResult.analysisInventory);
  if (!inventory || !Array.isArray(inventory.balls)) return null;

  const idsByIndex = new Map<number, string | null>();
  for (const ball of inventory.balls) {
    const item = record(ball);
    const sourceIndex = item && positiveIndices([item.sourceIndex])?.[0];
    const id = item && nonEmptyString(item.id)?.trim();
    if (!sourceIndex || !id) continue;
    idsByIndex.set(
      sourceIndex,
      idsByIndex.has(sourceIndex) ? null : id,
    );
  }

  const sourceBallIds = sourceIndices.map((sourceIndex) =>
    idsByIndex.get(sourceIndex)
  );
  return sourceBallIds.every((id): id is string => typeof id === "string")
    ? sourceBallIds
    : null;
}

function deliveredReplyText(
  finalResult: Record<string, unknown>,
  style: string,
  selectedStyle: string | null,
  segments: readonly Record<string, unknown>[] | null,
): string | null {
  const finalRecommendation = record(finalResult.finalRecommendation);
  if (
    style === selectedStyle && finalRecommendation?.pick === style &&
    nonEmptyString(finalRecommendation.content)
  ) {
    return finalRecommendation.content as string;
  }

  const segmentText = segments ? replyTextFromSegments(segments) : "";
  if (segmentText.length > 0) return segmentText;

  const replies = record(finalResult.replies);
  return nonEmptyString(replies?.[style]);
}

function selectedDeliveredStyle(
  finalResult: Record<string, unknown>,
  linkage: Record<string, unknown>,
): string | null {
  const finalRecommendation = record(finalResult.finalRecommendation);
  if (isStreamStyle(finalRecommendation?.pick)) return finalRecommendation.pick;
  return isStreamStyle(linkage.selectedStyle) ? linkage.selectedStyle : null;
}

function hasSafetyReplacement(finalResult: Record<string, unknown>): boolean {
  return Array.isArray(finalResult.warnings) &&
    finalResult.warnings.some((warning) =>
      record(warning)?.type === "safety_filter"
    );
}

function rawVariantMatchesDeliveredSequence(
  rawVariant: Record<string, unknown> | null,
  deliveredSourceIndexSequence: readonly number[] | null,
  deliveredSourceBallIds: readonly string[] | null,
): boolean {
  if (!rawVariant || !deliveredSourceIndexSequence) return false;
  const rawSourceIndices = positiveIndices(rawVariant.sourceIndexSequence) ??
    positiveIndices(rawVariant.sourceIndices);
  if (
    !rawSourceIndices || !sameNumberOrder(
      rawSourceIndices,
      deliveredSourceIndexSequence,
    )
  ) {
    return false;
  }

  const rawSourceBallIds = stringArray(rawVariant.sourceBallIds);
  return rawSourceBallIds === null ||
    (deliveredSourceBallIds !== null && sameStringOrder(
      rawSourceBallIds,
      deliveredSourceBallIds,
    ));
}

function invariantVariantFields(
  rawVariant: Record<string, unknown> | null,
  safetyReplacement: boolean,
  deliveredSourceSequenceMatchesRaw: boolean,
  deliveredSourceBallIds: readonly string[] | null,
): Record<string, unknown> {
  // A safety replacement, crop, merge, or reorder severs raw option metadata
  // from the output that is actually delivered. Preserve it only when every
  // delivered source position still proves the same raw variant.
  if (!rawVariant || safetyReplacement || !deliveredSourceSequenceMatchesRaw) {
    return {};
  }

  const action = enumValue(rawVariant.action, ACTIONS);
  const rawSelectedBallIds = stringArray(rawVariant.selectedBallIds);
  const selectedBallIds = rawSelectedBallIds && deliveredSourceBallIds &&
      sameStringSet(rawSelectedBallIds, [...deliveredSourceBallIds])
    ? [...deliveredSourceBallIds]
    : null;
  const newTopicCount = nonNegativeNumber(rawVariant.newTopicCount);
  const semanticDistance = nonNegativeNumber(rawVariant.semanticDistance);
  const solutionMode = typeof rawVariant.solutionMode === "boolean"
    ? rawVariant.solutionMode
    : undefined;
  // Phase 2b 歸因跟 action 一樣是 raw option 的 metadata：送出的內容還證明
  // 是同一個 raw variant 才保留。
  const selectedBranchIds = branchIdArray(rawVariant.selectedBranchIds);
  const branchSource = enumValue(rawVariant.branchSource, BRANCH_SOURCES);
  const rhetoricalMove = enumValue(rawVariant.rhetoricalMove, MOVES);
  const styleIntensity = nonNegativeNumber(rawVariant.styleIntensity);
  const branchAttributionInvalid =
    typeof rawVariant.branchAttributionInvalid === "boolean"
      ? rawVariant.branchAttributionInvalid
      : undefined;
  return {
    ...(action ? { action } : {}),
    ...(selectedBallIds ? { selectedBallIds } : {}),
    ...(newTopicCount !== null ? { newTopicCount } : {}),
    ...(semanticDistance !== null ? { semanticDistance } : {}),
    ...(solutionMode !== undefined ? { solutionMode } : {}),
    ...(branchSource ? { branchSource } : {}),
    ...(selectedBranchIds && branchSource ? { selectedBranchIds } : {}),
    ...(rhetoricalMove ? { rhetoricalMove } : {}),
    ...(styleIntensity !== null && styleIntensity <= MAX_STYLE_INTENSITY
      ? { styleIntensity }
      : {}),
    ...(branchAttributionInvalid !== undefined
      ? { branchAttributionInvalid }
      : {}),
  };
}

/**
 * Rebuilds Phase 0 per-style evidence from the post-guardrail result that the
 * client actually receives. It intentionally changes only the optional
 * linkage snapshot; user-visible replies and existing safety behavior stay
 * untouched.
 */
export function calibratePhase0EvidenceLinkage(
  finalResult: Record<string, unknown>,
): Record<string, unknown> {
  try {
    return calibratePhase0EvidenceLinkageUnsafe(finalResult);
  } catch {
    // Phase 0 is shadow-only. A malformed optional snapshot must never block
    // post-charge completion, persistence, or the stream response.
    return finalResult;
  }
}

function calibratePhase0EvidenceLinkageUnsafe(
  finalResult: Record<string, unknown>,
): Record<string, unknown> {
  const linkage = record(finalResult.analysisEvidenceLinkage);
  if (linkage?.schemaVersion !== 1) return finalResult;

  const selectedStyle = selectedDeliveredStyle(finalResult, linkage);
  const rawVariants = record(linkage.variants) ?? {};
  const styles = new Set<string>();
  const replies = record(finalResult.replies);
  const replyOptions = record(finalResult.replyOptions);
  for (
    const style of [
      ...Object.keys(replies ?? {}),
      ...Object.keys(replyOptions ?? {}),
    ]
  ) {
    if (isStreamStyle(style)) styles.add(style);
  }
  if (selectedStyle) styles.add(selectedStyle);

  const safetyReplacement = hasSafetyReplacement(finalResult);
  const variants: Record<string, Record<string, unknown>> = {};
  for (const style of styles) {
    const segments = replySegmentsForStyle(finalResult, style, selectedStyle);
    const text = deliveredReplyText(
      finalResult,
      style,
      selectedStyle,
      segments,
    );
    if (!text) continue;

    const sourceIndexSequence = sourceIndexSequenceFromDeliveredSegments(
      segments,
    );
    const sourceIndices = sourceIndicesFromDeliveredSegments(segments);
    const sourceBallIds = sourceIndices
      ? sourceBallIdsFromDeliveredIndices(finalResult, sourceIndices)
      : null;
    const rawVariant = record(rawVariants[style]);
    variants[style] = {
      ...invariantVariantFields(
        rawVariant,
        safetyReplacement,
        rawVariantMatchesDeliveredSequence(
          rawVariant,
          sourceIndexSequence,
          sourceBallIds,
        ),
        sourceBallIds,
      ),
      ...(sourceIndices ? { sourceIndices } : {}),
      ...(sourceBallIds ? { sourceBallIds } : {}),
      questionCount: text.match(/[?？]/g)?.length ?? 0,
    };
  }

  const calibratedLinkage: Record<string, unknown> = {
    ...linkage,
    ...(selectedStyle ? { selectedStyle } : {}),
  };
  if (Object.keys(variants).length > 0) {
    calibratedLinkage.variants = variants;
  } else {
    delete calibratedLinkage.variants;
  }

  return {
    ...finalResult,
    analysisEvidenceLinkage: calibratedLinkage,
  };
}

function sourceMessageSequence(
  finalResult: Record<string, unknown>,
  style: string,
  selectedStyle: string,
): SourceMessageSegment[] | null {
  const finalRecommendation = record(finalResult.finalRecommendation);
  const replyOptions = record(finalResult.replyOptions);
  const option = record(replyOptions?.[style]);
  // The recommended card renders finalRecommendation.replySegments, whose
  // sources may have been repaired after stream assembly. Other style cards
  // render their replyOptions messages. Read the same final paths here.
  const messages = style === selectedStyle &&
      finalRecommendation?.pick === style &&
      Array.isArray(finalRecommendation.replySegments)
    ? finalRecommendation.replySegments
    : option?.messages ?? option?.messageGroup ?? option?.replySegments;
  if (!Array.isArray(messages) || messages.length === 0) return null;

  const sequence: SourceMessageSegment[] = [];
  for (const message of messages) {
    const segment = record(message);
    const sourceIndex = segment && positiveIndices([segment.sourceIndex])?.[0];
    const sourceMessage = segment?.sourceMessage;
    if (
      !sourceIndex || typeof sourceMessage !== "string" ||
      sourceMessage.trim() === ""
    ) {
      return null;
    }
    sequence.push({ sourceIndex, sourceMessage });
  }
  return sequence;
}

function sameSourceMessageOrder(
  left: SourceMessageSegment[],
  right: SourceMessageSegment[],
): boolean {
  return left.length === right.length &&
    left.every((value, index) =>
      value.sourceIndex === right[index].sourceIndex &&
      value.sourceMessage === right[index].sourceMessage
    );
}

// Mirror of the Flutter give-up banner rule in analysis_models.dart
// (`shouldGiveUp`): enthusiasm.level is "cold" and a warning mentions
// 建議放棄 or 開新對話. The v1 model never emits a typed decision, so this is
// the only observable "stop" signal today; only the boolean leaves this
// function, never the warning text.
function legacyGiveUpBanner(
  finalResult: Record<string, unknown>,
): boolean | null {
  const level = record(finalResult.enthusiasm)?.level;
  if (typeof level !== "string") return null;
  const warnings = Array.isArray(finalResult.warnings)
    ? finalResult.warnings
    : [];
  return level === "cold" && warnings.some((warning) => {
    const text = typeof warning === "string"
      ? warning
      : JSON.stringify(warning) ?? "";
    return text.includes("建議放棄") || text.includes("開新對話");
  });
}

function candidateCount(
  finalResult: Record<string, unknown>,
  variants: Record<string, Variant> | null,
): number | null {
  const replies = record(finalResult.replies);
  const replyCount = replies
    ? Object.entries(replies)
      .filter(([style, reply]) =>
        isStreamStyle(style) && typeof reply === "string"
      )
      .length
    : 0;
  if (replyCount > 0) return replyCount;

  const variantCount = variants ? Object.keys(variants).length : 0;
  if (variantCount > 0) return variantCount;

  const replyOptions = record(finalResult.replyOptions);
  const optionCount = replyOptions
    ? Object.entries(replyOptions)
      .filter(([style, option]) => isStreamStyle(style) && record(option))
      .length
    : 0;
  if (optionCount > 0) return optionCount;

  return replies ? 0 : null;
}

function questionCounts(
  finalResult: Record<string, unknown>,
  variants: Record<string, Variant> | null,
): Record<string, unknown> {
  if (variants) {
    const entries = Object.entries(variants);
    if (entries.every(([, variant]) => variant.questionCount !== undefined)) {
      const byStyle = Object.fromEntries(entries.map(([style, variant]) => [
        style,
        variant.questionCount,
      ]));
      return {
        status: "observed",
        byStyle,
        maxQuestionCount: Math.max(
          ...entries.map(([, variant]) => variant.questionCount ?? 0),
        ),
      };
    }
  }

  const replies = record(finalResult.replies);
  if (!replies) return { status: "unknown" };
  const entries = Object.entries(replies)
    .filter(([style, reply]) =>
      isStreamStyle(style) && typeof reply === "string"
    );
  if (entries.length === 0) return { status: "unknown" };
  const byStyle = Object.fromEntries(entries.map(([style, reply]) => [
    style,
    (reply as string).match(/[?？]/g)?.length ?? 0,
  ]));
  return {
    status: "observed",
    byStyle,
    maxQuestionCount: Math.max(...Object.values(byStyle) as number[]),
  };
}

function sourceDivergence(
  selectedStyle: string,
  variants: Record<string, Variant> | null,
  finalResult: Record<string, unknown>,
): Record<string, unknown> {
  const entries = variants ? Object.entries(variants) : [];
  const baselineStyle = selectedStyle !== "unknown" && variants?.[selectedStyle]
    ? selectedStyle
    : entries[0]?.[0];
  if (!baselineStyle || !variants || entries.length < 2) {
    return { status: "unknown" };
  }

  const sourceBallIdEvidence =
    entries.every(([, variant]) => (variant.sourceBallIds?.length ?? 0) > 0)
      ? "complete"
      : entries.some(([, variant]) => (variant.sourceBallIds?.length ?? 0) > 0)
      ? "partial"
      : "absent";
  const sourceIndexEvidence =
    entries.every(([, variant]) => (variant.sourceIndices?.length ?? 0) > 0)
      ? "complete"
      : entries.some(([, variant]) => (variant.sourceIndices?.length ?? 0) > 0)
      ? "partial"
      : "absent";
  const sourceMessagesByStyle = Object.fromEntries(
    entries.flatMap(([style]) => {
      const sequence = sourceMessageSequence(finalResult, style, selectedStyle);
      return sequence ? [[style, sequence]] : [];
    }),
  ) as Record<string, SourceMessageSegment[]>;
  const sourceMessageEvidence =
    Object.keys(sourceMessagesByStyle).length === entries.length
      ? "complete"
      : Object.keys(sourceMessagesByStyle).length > 0
      ? "partial"
      : "absent";
  if (
    sourceIndexEvidence === "absent" &&
    sourceBallIdEvidence === "absent" &&
    sourceMessageEvidence === "absent"
  ) {
    return { status: "unknown" };
  }
  const baseline = variants[baselineStyle];
  const baselineMessages = sourceMessagesByStyle[baselineStyle];
  const differs = (variant: Variant) =>
    (baseline.sourceIndices !== undefined &&
      variant.sourceIndices !== undefined &&
      !sameNumberOrder(variant.sourceIndices, baseline.sourceIndices)) ||
    (baseline.sourceBallIds !== undefined &&
      variant.sourceBallIds !== undefined &&
      !sameStringOrder(variant.sourceBallIds, baseline.sourceBallIds));
  const stylesWithDivergence = entries
    .filter(([style, variant]) => {
      if (style === baselineStyle) return false;
      if (differs(variant)) return true;
      const sourceMessages = sourceMessagesByStyle[style];
      return baselineMessages !== undefined && sourceMessages !== undefined &&
        !sameSourceMessageOrder(sourceMessages, baselineMessages);
    })
    .map(([style]) => style);

  return {
    status: "observed",
    baselineStyle,
    sourceBallIdEvidence,
    sourceMessageEvidence,
    divergentStyles: stylesWithDivergence,
    // sourceMessage is part of the required same-source baseline. With no
    // complete message sequence we can report a detected mismatch, but must
    // never claim every card matches.
    allMatch: sourceMessageEvidence === "complete"
      ? stylesWithDivergence.length === 0
      : stylesWithDivergence.length > 0
      ? false
      : "unknown",
  };
}

export function buildPhase0ObservabilityTelemetry({
  finalResult,
  user,
  analysisRunId,
  contractVersion2 = false,
}: {
  finalResult: Record<string, unknown>;
  user: string;
  analysisRunId: string;
  /// Phase 2a：request 走 analysisContractVersion 2（noSendDecisions）。
  /// divergencePlan 母數只算 v2 且非 no-send 的 run。
  contractVersion2?: boolean;
}): Record<string, unknown> {
  const decisionRecord = record(finalResult.analysisDecisionV2);
  const decision = decisionRecord?.schemaVersion === 2 ? decisionRecord : null;
  const inventory = record(finalResult.analysisInventory);
  const linkage = record(finalResult.analysisEvidenceLinkage);
  const variants = variantsFrom(linkage);
  const action = enumValue(decision?.action, ACTIONS);
  const decisionId = safeDecisionId(decision?.decisionId);
  const messageDecision = enumValue(
    decision?.messageDecision,
    MESSAGE_DECISIONS,
  );
  const replyMode = enumValue(decision?.replyMode, REPLY_MODES);
  const selectedBallIds = stringArray(decision?.selectedBallIds);
  const betaRiskFlags = Array.isArray(decision?.betaRiskFlags) &&
      decision.betaRiskFlags.every((flag) =>
        typeof flag === "string" && BETA_FLAGS.has(flag)
      )
    ? decision.betaRiskFlags as string[]
    : null;
  const selectedStyle = isStreamStyle(linkage?.selectedStyle)
    ? linkage.selectedStyle
    : isStreamStyle(decision?.selectedStyle)
    ? decision.selectedStyle
    : "unknown";

  const meaningfulSourceIndices = meaningfulInventoryIndices(inventory);
  const hasCompleteSourceIndices = variants &&
    Object.values(variants).every((variant) =>
      variant.sourceIndices !== undefined
    );
  const coverage =
    meaningfulSourceIndices && variants && hasCompleteSourceIndices
      ? {
        status: "observed",
        meaningfulSourceIndices,
        coveredSourceIndicesByStyle: Object.fromEntries(
          Object.entries(variants).map(([style, variant]) => [
            style,
            variant.sourceIndices!,
          ]),
        ),
        allVariantsCoverMeaningful: Object.values(variants).every((variant) =>
          meaningfulSourceIndices.every((index) =>
            variant.sourceIndices!.includes(index)
          )
        ),
      }
      : { status: "unknown" };

  // Phase 2a：v1 run 沒有這個欄位，母數只算 v2 send。

  const variantValues = variants ? Object.values(variants) : null;
  const actionMismatch = action && variantValues &&
      variantValues.every((variant) => variant.action !== undefined)
    ? variantValues.some((variant) => variant.action !== action)
    : "unknown";
  const ballMismatch = selectedBallIds && variantValues &&
      variantValues.every((variant) => variant.selectedBallIds !== undefined)
    ? variantValues.some((variant) =>
      !sameStringSet(variant.selectedBallIds ?? [], selectedBallIds)
    )
    : "unknown";

  const noSendExpected = messageDecision === "do_not_send" ||
    messageDecision === "need_context" || replyMode === "none";

  // v2 send decision 未必宣告 schemaVersion 2（模型不一定帶），所以用 request
  // 的 contract version 加「不是 no-send」判斷，而不是只看 decision 快照。
  const divergence = divergencePlanTelemetry(finalResult, variants, {
    expected: contractVersion2 && !noSendExpected &&
      messageDecision !== "acknowledge_and_stop",
  });
  const observedCandidateCount = candidateCount(finalResult, variants);
  const giveUpBanner = legacyGiveUpBanner(finalResult);
  const legacyGiveUpConflict =
    giveUpBanner === null || observedCandidateCount === null
      ? "unknown"
      : giveUpBanner && observedCandidateCount > 0;
  const coachActionType = enumValue(
    record(finalResult.coachActionHint)?.actionType,
    COACH_ACTION_HINT_ACTION_TYPES,
  );
  const noSendConflict = noSendExpected
    ? observedCandidateCount === null ? "unknown" : observedCandidateCount > 0
    : "unknown";

  const newTopicBudget = nonNegativeNumber(decision?.newTopicBudget);
  const hasNewTopicCounts = variants &&
    Object.values(variants).every((variant) =>
      variant.newTopicCount !== undefined
    );
  const topicJump = newTopicBudget !== null && hasNewTopicCounts
    ? {
      status: "observed",
      newTopicBudget,
      maxNewTopicCount: Math.max(
        ...Object.values(variants!).map((variant) =>
          variant.newTopicCount ?? 0
        ),
      ),
      exceedsBudget: Object.values(variants!).some((variant) =>
        (variant.newTopicCount ?? 0) > newTopicBudget
      ),
    }
    : { status: "unknown" };

  const hasSemanticDistances = variants &&
    Object.values(variants).every((variant) =>
      variant.semanticDistance !== undefined
    );
  const semanticDistance = hasSemanticDistances
    ? {
      status: "observed",
      byStyle: Object.fromEntries(
        Object.entries(variants!).map(([style, variant]) => [
          style,
          variant.semanticDistance,
        ]),
      ),
    }
    : { status: "unknown" };

  const solutionModeAllowed = typeof decision?.solutionModeAllowed === "boolean"
    ? decision.solutionModeAllowed
    : null;
  const hasSolutionModes = variants &&
    Object.values(variants).every((variant) =>
      variant.solutionMode !== undefined
    );
  const solutionMode = solutionModeAllowed !== null && hasSolutionModes
    ? {
      status: "observed",
      allowed: solutionModeAllowed,
      usedByStyle: Object.fromEntries(
        Object.entries(variants!).map(([style, variant]) => [
          style,
          variant.solutionMode,
        ]),
      ),
      conflict: !solutionModeAllowed &&
        Object.values(variants!).some((variant) =>
          variant.solutionMode === true
        ),
    }
    : { status: "unknown" };

  return {
    schemaVersion: 1,
    user,
    analysisRunId,
    decisionSchema: decision ? "v2" : "unknown",
    decisionId: decisionId ?? "unknown",
    action: action ?? "unknown",
    messageDecision: messageDecision ?? "unknown",
    replyMode: replyMode ?? "unknown",
    selectedStyle,
    selectedBallCount: selectedBallIds?.length ?? "unknown",
    betaRiskFlags: betaRiskFlags ?? "unknown",
    solutionModeAllowed: solutionModeAllowed ?? "unknown",
    actionMismatch,
    ballMismatch,
    noSendConflict,
    candidateCount: observedCandidateCount ?? "unknown",
    legacyGiveUpBanner: giveUpBanner ?? "unknown",
    legacyGiveUpConflict,
    coachActionType: coachActionType ?? "unknown",
    meaningfulBallCoverage: coverage,
    questionCounts: questionCounts(finalResult, variants),
    topicJump,
    semanticDistance,
    solutionMode,
    fiveCardSourceDivergence: sourceDivergence(
      selectedStyle,
      variants,
      finalResult,
    ),
    ...(divergence ? { divergencePlan: divergence } : {}),
  };
}

/// Phase 2a shadow：只出數字與 enum，threadFrame／idea／associationPath 這些
/// 從她的訊息推出的文字一律不進 telemetry。
function divergencePlanTelemetry(
  finalResult: Record<string, unknown>,
  variants: Record<string, Variant> | null,
  options: { expected: boolean },
): Record<string, unknown> | null {
  // 母數只算 v2 send：不是 v2 send 的 run 連 key 都不出，就算 finalResult
  // 裡有一份看起來合法的計畫也一樣（那不該存在，更不該進統計）。
  if (!options.expected) return null;
  const plan = parseDivergencePlanV1(finalResult.analysisDivergencePlan);
  if (!plan) return { status: "unknown" };
  const methods: Record<string, number> = {};
  for (const branch of plan.branchPool) {
    methods[branch.method] = (methods[branch.method] ?? 0) + 1;
  }
  const maxBranchDistance = Math.max(
    ...plan.branchPool.map((branch) => branch.semanticDistance),
  );
  const variantValues = variants ? Object.values(variants) : null;
  const anchorCoveredByAllStyles = variantValues && variantValues.length > 0 &&
      variantValues.every((variant) => variant.sourceIndices !== undefined)
    ? variantValues.every((variant) =>
      variant.sourceIndices!.includes(plan.anchorSourceIndex)
    )
    : "unknown";
  const questionBudgetExceeded = variantValues && variantValues.length > 0 &&
      variantValues.every((variant) => variant.questionCount !== undefined)
    ? variantValues.some((variant) =>
      (variant.questionCount ?? 0) > plan.questionBudget
    )
    : "unknown";
  const newTopicBudgetExceeded = variantValues && variantValues.length > 0 &&
      variantValues.every((variant) => variant.newTopicCount !== undefined)
    ? variantValues.some((variant) =>
      (variant.newTopicCount ?? 0) > plan.newTopicBudget
    )
    : "unknown";
  return {
    status: "observed",
    anchorSourceIndex: plan.anchorSourceIndex,
    supportCount: plan.supportSourceIndices.length,
    mergeContextCount: plan.mergeContextSourceIndices.length,
    branchCount: plan.branchPool.length,
    methods,
    semanticDistanceCap: plan.semanticDistanceCap,
    maxBranchDistance,
    branchExceedsCap: maxBranchDistance > plan.semanticDistanceCap,
    questionBudget: plan.questionBudget,
    questionBudgetExceeded,
    newTopicBudget: plan.newTopicBudget,
    newTopicBudgetExceeded,
    anchorCoveredByAllStyles,
    styleBranchAssigned: Object.keys(plan.styleBranchIds ?? {}).length,
    // Eric 2026-09-02：缺幾種要看得到——送出的風格裡計畫沒指定枝的數量。
    styleBranchMissing: variants
      ? Object.keys(variants).filter((style) =>
        plan.styleBranchIds?.[style as StreamStyle] === undefined
      ).length
      : "unknown",
    // §6.3 不得同開頭：正規化前四字相同的卡數（本刀只量不擋，Phase 3 gate）。
    sameOpeningCount: sameOpeningCount(finalResult),
    repairs: repairTelemetry(record(finalResult.analysisEvidenceLinkage)),
    attribution: attributionTelemetry(variantValues),
  };
}

function sameOpeningCount(
  finalResult: Record<string, unknown>,
): number | "unknown" {
  const replies = record(finalResult.replies);
  if (!replies) return "unknown";
  const openings: string[] = [];
  for (const [style, text] of Object.entries(replies)) {
    if (!isStreamStyle(style) || typeof text !== "string") continue;
    const normalized = text.replace(/[\s\p{P}\p{S}]/gu, "").slice(0, 4);
    if (normalized.length === 4) openings.push(normalized);
  }
  if (openings.length < 2) return "unknown";
  return openings.filter((opening, index) =>
    openings.some((other, otherIndex) =>
      otherIndex !== index && other === opening
    )
  ).length;
}

/// Phase 2b repair-first：計畫解析時修了幾處（method 手法→六法、
/// sourceIndex<N> 多餘 key）。只數形狀合法的紀錄。
const PLAN_REPAIR_ENTRY =
  /^(br_[0-9]{1,2}:(method:[a-z_]+->[a-z_]+|sourceIndex\d+)|line:sourceIndex=)$/;
function repairTelemetry(
  linkage: Record<string, unknown> | null,
): { method: number; sourceIndexKey: number; line: number } {
  const counts = { method: 0, sourceIndexKey: 0, line: 0 };
  const raw = linkage?.divergencePlanRepairs;
  if (!Array.isArray(raw)) return counts;
  for (const entry of raw) {
    if (typeof entry !== "string" || !PLAN_REPAIR_ENTRY.test(entry)) continue;
    if (entry.startsWith("line:")) counts.line += 1;
    else if (entry.includes(":method:")) counts.method += 1;
    else counts.sourceIndexKey += 1;
  }
  return counts;
}

/// Phase 2b：五張卡實際跟了哪一枝、怎麼來的。純數字，不帶文字。
/// variants 缺席（舊快照／無 reply_option）→ unknown。
function attributionTelemetry(
  variants: Variant[] | null,
): Record<string, unknown> {
  if (!variants || variants.length === 0) return { status: "unknown" };
  const attributed = variants.filter((variant) =>
    variant.branchSource !== undefined
  );
  if (attributed.length === 0) return { status: "unknown" };
  const bySource: Record<string, number> = {};
  for (const source of STYLE_BRANCH_SOURCES) bySource[source] = 0;
  const rhetoricalMoves: Record<string, number> = {};
  const styleIntensity: Record<string, number> = {};
  const branches = new Set<string>();
  let invalidCount = 0;
  for (const variant of attributed) {
    bySource[variant.branchSource!] += 1;
    for (const id of variant.selectedBranchIds ?? []) branches.add(id);
    if (variant.rhetoricalMove) {
      rhetoricalMoves[variant.rhetoricalMove] =
        (rhetoricalMoves[variant.rhetoricalMove] ?? 0) + 1;
    }
    if (variant.styleIntensity !== undefined) {
      const key = String(variant.styleIntensity);
      styleIntensity[key] = (styleIntensity[key] ?? 0) + 1;
    }
    if (variant.branchAttributionInvalid) invalidCount += 1;
  }
  return {
    status: "observed",
    styleCount: variants.length,
    attributedCount: attributed.length,
    bySource,
    distinctBranchCount: branches.size,
    rhetoricalMoves,
    styleIntensity,
    invalidCount,
  };
}

export function emitPhase0Observability({
  finalResult,
  user,
  analysisRunId,
  emit,
  contractVersion2 = false,
}: {
  finalResult: Record<string, unknown>;
  user: string;
  analysisRunId: string;
  emit: TelemetryEmitter;
  contractVersion2?: boolean;
}): void {
  try {
    emit(
      "stream_phase0_observability",
      buildPhase0ObservabilityTelemetry({
        finalResult,
        user,
        analysisRunId,
        contractVersion2,
      }),
    );
  } catch {
    // Observability must never block markDone, a stream response, or resume.
  }
}
