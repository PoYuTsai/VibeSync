import {
  isStreamStyle,
  parseEventLine,
  type StreamEvent,
  type StreamStyle,
} from "./stream_events.ts";
import {
  type RecommendationValidation,
  validateDecisionChargeEvent,
  validateRecommendationEvent,
} from "./stream_recommendation_guardrail.ts";

export type StreamOutputEvent =
  | StreamEvent
  | (Record<string, unknown> & { type: string });

export interface StreamRecommendationForCharge {
  selectedStyle: StreamStyle;
  message: string;
  reason: string;
  quotedContext: string;
  warnings: string[];
  raw: StreamEvent | Record<string, unknown>;
}

export interface StreamChargeResult {
  charged: boolean;
  code?: string;
  message?: string;
  recoverable?: boolean;
}

export interface ReframerOptions {
  emit: (event: StreamOutputEvent) => void;
  onRecommendation: (
    recommendation: StreamRecommendationForCharge,
  ) => Promise<StreamChargeResult> | StreamChargeResult;
  prechargedRecommendation?: StreamRecommendationForCharge;
  requiredReplyStyles?: readonly StreamStyle[];
}

export interface StreamReframer {
  pushText: (chunk: string) => void;
  drain: () => Promise<void>;
  flush: () => Promise<void>;
}

const DEFAULT_CHARGE_FAILURE_MESSAGE =
  "Streaming analysis could not continue. Please retry.";

export function createStreamReframer(options: ReframerOptions): StreamReframer {
  const assembler = createLegacyAnalysisAssembler();
  let buffer = "";
  let pending = Promise.resolve();
  let closed = false;
  let sawValidEvent = false;
  let doneEmitted = false;
  const isResume = options.prechargedRecommendation != null;
  let chargeCompleted = isResume;
  let resumeDecisionReplayPending = options.prechargedRecommendation?.raw
    ?.type === "analysis.decision";
  let officialRecommendationEmitted = options.prechargedRecommendation?.raw
    ?.type === "analysis.recommendation";
  let modelDoneHadFinalResult = false;
  const preChargeEvents: StreamEvent[] = [];
  const requiredReplyStyles = normalizeRequiredReplyStyles(
    options.requiredReplyStyles,
  );
  const requiredReplyStyleSet = new Set(requiredReplyStyles);

  if (options.prechargedRecommendation) {
    assembler.absorb(toRecommendationEvent(options.prechargedRecommendation));
  }

  const emitError = (
    code: string,
    message: string,
    recoverable = true,
    extra: Record<string, unknown> = {},
  ) => {
    options.emit({
      type: "analysis.error",
      code,
      message,
      recoverable,
      ...extra,
    });
  };

  const emitDone = () => {
    if (doneEmitted || closed) return;
    const finalResult = assembler.build();
    const missingStyles = findMissingRequiredReplyStyles(
      finalResult,
      requiredReplyStyles,
    );
    if (missingStyles.length > 0) {
      emitError(
        "STREAM_INCOMPLETE_REPLY_OPTIONS",
        "Streaming analysis ended before every allowed reply style was generated.",
        true,
        { missingStyles },
      );
      closed = true;
      return;
    }
    options.emit({
      type: "analysis.done",
      finalResult,
    });
    doneEmitted = true;
    closed = true;
  };

  const hasCompletionAnchor = () =>
    officialRecommendationEmitted || modelDoneHadFinalResult;

  const emitMissingCompletionAnchor = () => {
    emitError(
      "STREAM_MISSING_COMPLETION_ANCHOR",
      "Streaming analysis ended before an official recommendation or final result.",
    );
    closed = true;
  };

  const absorbAndEmit = (event: StreamOutputEvent) => {
    assembler.absorb(event);
    options.emit(event);
  };

  const styleIsAllowed = (style: StreamStyle) =>
    requiredReplyStyleSet.size === 0 || requiredReplyStyleSet.has(style);

  const rejectUnavailableAnchorStyle = (style: StreamStyle) => {
    emitError(
      "STREAM_UNAVAILABLE_REPLY_STYLE",
      "Streaming analysis selected a reply style outside this user's plan.",
      true,
      { selectedStyle: style },
    );
    closed = true;
  };

  const flushPreChargeEvents = () => {
    for (const bufferedEvent of preChargeEvents) {
      absorbAndEmit(bufferedEvent);
    }
    preChargeEvents.length = 0;
  };

  const chargeFromValidation = async (
    validation: Extract<RecommendationValidation, { ok: true }>,
  ): Promise<boolean> => {
    const chargeResult = await options.onRecommendation(
      toChargePayload(validation),
    );
    if (!chargeResult.charged) {
      emitError(
        chargeResult.code ?? "STREAM_CHARGE_FAILED",
        chargeResult.message ?? DEFAULT_CHARGE_FAILURE_MESSAGE,
        chargeResult.recoverable ?? true,
      );
      closed = true;
      return false;
    }

    chargeCompleted = true;
    flushPreChargeEvents();
    return true;
  };

  const handleDecision = async (event: StreamEvent) => {
    if (resumeDecisionReplayPending) {
      resumeDecisionReplayPending = false;
      return;
    }

    if (chargeCompleted) {
      absorbAndEmit(event);
      return;
    }

    const validation = validateDecisionChargeEvent(event);
    if (!validation.ok) {
      emitError(validation.code, validation.reason);
      closed = true;
      return;
    }

    if (!styleIsAllowed(validation.selectedStyle)) {
      rejectUnavailableAnchorStyle(validation.selectedStyle);
      return;
    }

    if (!(await chargeFromValidation(validation))) return;
    absorbAndEmit(event);
  };

  const handleRecommendation = async (event: StreamEvent) => {
    const validation = validateRecommendationEvent(event);
    if (!validation.ok) {
      emitError(validation.code, validation.reason);
      closed = true;
      return;
    }

    if (!styleIsAllowed(validation.selectedStyle)) {
      rejectUnavailableAnchorStyle(validation.selectedStyle);
      return;
    }

    if (officialRecommendationEmitted) {
      if (isResume) return;
      emitError(
        "STREAM_DUPLICATE_RECOMMENDATION",
        "Streaming analysis emitted more than one official recommendation.",
      );
      closed = true;
      return;
    }

    if (!chargeCompleted && !(await chargeFromValidation(validation))) return;

    officialRecommendationEmitted = true;
    const enriched = {
      ...event,
      selectedStyle: validation.selectedStyle,
      message: validation.message,
      reason: validation.reason,
      quotedContext: validation.quotedContext,
      warnings: validation.warnings,
    };
    absorbAndEmit(enriched);
  };

  const handleEvent = async (event: StreamEvent) => {
    if (closed) return;
    sawValidEvent = true;

    if (event.type === "analysis.recommendation") {
      await handleRecommendation(event);
      return;
    }

    if (event.type === "analysis.decision") {
      await handleDecision(event);
      return;
    }

    if (event.type === "analysis.error") {
      options.emit(event);
      closed = true;
      return;
    }

    if (event.type === "analysis.reply_option") {
      const style = replyStyleFrom(event);
      if (style && !styleIsAllowed(style)) return;
    }

    if (!chargeCompleted) {
      if (event.type === "analysis.done") {
        emitError(
          "STREAM_MISSING_CHARGE_ANCHOR",
          "Streaming analysis ended before a chargeable decision or recommendation.",
        );
        closed = true;
        return;
      }

      preChargeEvents.push(event);
      return;
    }

    if (event.type === "analysis.done") {
      if (doneResultField(event)) {
        modelDoneHadFinalResult = true;
      }
      if (!hasCompletionAnchor()) {
        emitMissingCompletionAnchor();
        return;
      }
      assembler.absorb(event);
      emitDone();
      return;
    }

    absorbAndEmit(event);
  };

  const queueLine = (line: string) => {
    const trimmed = stripCarriageReturn(line).trim();
    if (!trimmed) return;
    pending = pending.then(async () => {
      if (closed) return;
      const event = parseEventLine(trimmed);
      if (!event) return;
      await handleEvent(event);
    }).catch((error) => {
      if (closed) return;
      emitError(
        "STREAM_REFRAMER_ERROR",
        error instanceof Error ? error.message : "Failed to process stream.",
      );
      closed = true;
    });
  };

  const drain = async () => {
    await pending;
  };

  return {
    pushText(chunk: string) {
      if (closed || chunk.length === 0) return;
      buffer += chunk;
      const lines = buffer.split("\n");
      buffer = lines.pop() ?? "";
      for (const line of lines) queueLine(line);
    },

    drain,

    async flush() {
      if (buffer.trim()) queueLine(buffer);
      buffer = "";
      await drain();
      if (!closed && sawValidEvent) {
        if (chargeCompleted && hasCompletionAnchor()) {
          emitDone();
        } else if (chargeCompleted) {
          emitMissingCompletionAnchor();
        } else {
          emitError(
            "STREAM_MISSING_CHARGE_ANCHOR",
            "Streaming analysis ended before a chargeable decision or recommendation.",
          );
          closed = true;
        }
      }
    },
  };
}

export const createReframer = createStreamReframer;

function stripCarriageReturn(line: string): string {
  return line.endsWith("\r") ? line.slice(0, -1) : line;
}

function toChargePayload(
  validation: Extract<RecommendationValidation, { ok: true }>,
): StreamRecommendationForCharge {
  return {
    selectedStyle: validation.selectedStyle,
    message: validation.message,
    reason: validation.reason,
    quotedContext: validation.quotedContext,
    warnings: validation.warnings,
    raw: validation.raw,
  };
}

export function toRecommendationEvent(
  recommendation: StreamRecommendationForCharge,
): StreamOutputEvent {
  if (recommendation.raw.type === "analysis.decision") {
    return {
      ...recommendation.raw,
      type: "analysis.decision",
      selectedStyle: recommendation.selectedStyle,
    };
  }

  return {
    ...recommendation.raw,
    type: "analysis.recommendation",
    selectedStyle: recommendation.selectedStyle,
    message: recommendation.message,
    reason: recommendation.reason,
    quotedContext: recommendation.quotedContext,
    warnings: recommendation.warnings,
  };
}

function createLegacyAnalysisAssembler() {
  const result: Record<string, unknown> = {
    gameStage: {
      current: "opening",
      status: "normal",
      nextStep: "",
    },
    enthusiasm: {
      score: 50,
    },
    topicDepth: {
      current: "facts",
      suggestion: "",
    },
    psychology: {
      subtext: "",
    },
    replies: {},
    replyOptions: {},
    finalRecommendation: {
      pick: "",
      content: "",
      reason: "",
      psychology: "",
    },
    warnings: [],
    strategy: "",
    reminder: "",
  };

  const absorbReply = (
    style: StreamStyle,
    message: string,
    reason: string,
    quotedContext: string,
    markFinal: boolean,
    segments?: readonly Record<string, unknown>[],
  ) => {
    const replies = ensureRecord(result, "replies");
    replies[style] = message;

    const replyOptions = ensureRecord(result, "replyOptions");
    replyOptions[style] = {
      approach: reason,
      messages: segments && segments.length > 0 ? [...segments] : [
        {
          label: "recommended",
          sourceMessage: quotedContext,
          reply: message,
          reason,
        },
      ],
    };

    if (markFinal) {
      result.finalRecommendation = {
        pick: style,
        content: message,
        reason,
        psychology: reason,
      };
    }
  };

  return {
    absorb(event: StreamOutputEvent) {
      if (event.type === "analysis.recommendation") {
        const style = streamStyleFrom(event.selectedStyle ?? event.style);
        const message = stringField(event.message);
        if (!style || !message) return;
        absorbReply(
          style,
          message,
          stringField(event.reason),
          stringField(event.quotedContext),
          true,
        );
        return;
      }

      if (event.type === "analysis.reply_option") {
        const style = streamStyleFrom(event.style ?? event.selectedStyle);
        // 2026-06-12 P0：#12 一球一回 prompt 下，多球對話的 reply_option
        // 常只帶 messages 段落陣列、無頂層 message 字串——必須回退到
        // segments join，否則該風格被靜默丟棄，emitDone 會誤判
        // STREAM_INCOMPLETE_REPLY_OPTIONS（與 findMissingRequiredReplyStyles
        // 的 segments 寬容度對齊）。
        const segments = replySegmentsFrom(
          event.messages ?? event.messageGroup ?? event.replySegments,
        );
        const message = stringField(event.message) ||
          joinedSegmentReply(segments);
        if (!style || !message) return;
        absorbReply(
          style,
          message,
          stringField(event.reason ?? event.approach),
          stringField(event.quotedContext ?? event.sourceMessage),
          event.isSelected === true,
          segments,
        );
        return;
      }

      if (event.type === "analysis.decision") {
        result.streamingDecision = omitType(event);
        const nextStep = stringField(
          event.nextStepBody ?? event.nextStep ?? event.doThis,
        );
        if (nextStep) {
          const gameStage = ensureRecord(result, "gameStage");
          gameStage.nextStep = nextStep;
        }
        return;
      }

      if (event.type === "analysis.metrics") {
        absorbMetrics(event);
        return;
      }

      if (event.type === "analysis.coach_hint") {
        result.coachActionHint = event.coachActionHint ?? omitType(event);
        return;
      }

      if (event.type === "analysis.report_section") {
        absorbReportSection(event);
        return;
      }

      if (event.type === "analysis.done") {
        const finalResult = doneResultField(event);
        if (finalResult) mergeFinalResult(finalResult);
      }
    },

    build(): Record<string, unknown> {
      return JSON.parse(JSON.stringify(result)) as Record<string, unknown>;
    },
  };

  function absorbMetrics(event: Record<string, unknown>) {
    const enthusiasm = recordField(event.enthusiasm);
    if (enthusiasm) result.enthusiasm = enthusiasm;

    const score = numberField(
      event.heat ?? event.enthusiasmScore ?? event.score,
    );
    if (score !== null) {
      const target = ensureRecord(result, "enthusiasm");
      target.score = score;
    }

    const dimensions = recordField(event.dimensions);
    if (dimensions) result.dimensions = dimensions;

    const topicDepth = recordField(event.topicDepth);
    if (topicDepth) result.topicDepth = topicDepth;
  }

  function absorbReportSection(event: Record<string, unknown>) {
    const section = stringField(event.section);
    if (!section) return;

    const payload = event.payload ?? event.content;
    if (section === "strategy") {
      result.strategy = stringField(payload) || JSON.stringify(payload ?? "");
      return;
    }

    if (section === "warnings" && Array.isArray(payload)) {
      result.warnings = payload;
      return;
    }

    result[section] = payload ?? omitType(event);
  }

  function mergeFinalResult(finalResult: Record<string, unknown>) {
    for (const [key, value] of Object.entries(finalResult)) {
      result[key] = value;
    }
  }
}

function ensureRecord(
  target: Record<string, unknown>,
  key: string,
): Record<string, unknown> {
  const value = target[key];
  if (isRecord(value)) return value;
  const next: Record<string, unknown> = {};
  target[key] = next;
  return next;
}

function streamStyleFrom(value: unknown): StreamStyle | null {
  return isStreamStyle(value) ? value : null;
}

function replyStyleFrom(event: Record<string, unknown>): StreamStyle | null {
  return streamStyleFrom(event.style ?? event.selectedStyle);
}

function stringField(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function numberField(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function recordField(value: unknown): Record<string, unknown> | null {
  return isRecord(value) ? value : null;
}

function normalizeRequiredReplyStyles(
  values: readonly StreamStyle[] | undefined,
): StreamStyle[] {
  if (!values) return [];

  const normalized: StreamStyle[] = [];
  for (const value of values) {
    if (isStreamStyle(value) && !normalized.includes(value)) {
      normalized.push(value);
    }
  }
  return normalized;
}

function findMissingRequiredReplyStyles(
  result: Record<string, unknown>,
  requiredStyles: readonly StreamStyle[],
): StreamStyle[] {
  if (requiredStyles.length === 0) return [];

  const replies = recordField(result.replies) ?? {};
  const replyOptions = recordField(result.replyOptions) ?? {};

  return requiredStyles.filter((style) =>
    !hasUsableReplyValue(replies[style]) &&
    !hasUsableReplyOption(replyOptions[style])
  );
}

function hasUsableReplyValue(value: unknown): boolean {
  if (stringField(value).length > 0) return true;
  if (!isRecord(value)) return false;

  return [
    value.reply,
    value.content,
    value.text,
    value.message,
  ].some((candidate) => stringField(candidate).length > 0) ||
    hasUsableReplySegments(
      value.messages ?? value.messageGroup ?? value.replySegments,
    );
}

function hasUsableReplyOption(value: unknown): boolean {
  if (!isRecord(value)) return false;

  return [
    value.reply,
    value.content,
    value.text,
    value.message,
  ].some((candidate) => stringField(candidate).length > 0) ||
    hasUsableReplySegments(
      value.messages ?? value.messageGroup ?? value.replySegments,
    );
}

function replySegmentsFrom(value: unknown): Record<string, unknown>[] {
  if (!Array.isArray(value)) return [];
  const segments: Record<string, unknown>[] = [];
  for (const item of value) {
    if (!isRecord(item)) continue;
    if (stringField(item.reply ?? item.content ?? item.text).length === 0) {
      continue;
    }
    segments.push(item);
  }
  return segments;
}

function joinedSegmentReply(
  segments: readonly Record<string, unknown>[],
): string {
  return segments
    .map((item) => stringField(item.reply ?? item.content ?? item.text))
    .filter((text) => text.length > 0)
    .join("\n");
}

function hasUsableReplySegments(value: unknown): boolean {
  if (!Array.isArray(value)) return false;
  return value.some((item) =>
    isRecord(item) &&
    stringField(item.reply ?? item.content ?? item.text).length > 0
  );
}

function doneResultField(event: Record<string, unknown>) {
  return recordField(event.finalResult) ?? recordField(event.result);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function omitType(event: Record<string, unknown>): Record<string, unknown> {
  const { type: _type, ...rest } = event;
  return rest;
}
