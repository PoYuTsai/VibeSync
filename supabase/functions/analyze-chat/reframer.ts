import {
  isStreamStyle,
  parseEventLine,
  type StreamEvent,
  type StreamStyle,
} from "./stream_events.ts";
import {
  type RecommendationValidation,
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
  let recommendationCharged = false;
  const preChargeEvents: StreamEvent[] = [];

  const emitError = (
    code: string,
    message: string,
    recoverable = true,
  ) => {
    options.emit({
      type: "analysis.error",
      code,
      message,
      recoverable,
    });
  };

  const emitDone = () => {
    if (doneEmitted || closed) return;
    options.emit({
      type: "analysis.done",
      finalResult: assembler.build(),
    });
    doneEmitted = true;
    closed = true;
  };

  const absorbAndEmit = (event: StreamOutputEvent) => {
    assembler.absorb(event);
    options.emit(event);
  };

  const flushPreChargeEvents = () => {
    for (const bufferedEvent of preChargeEvents) {
      absorbAndEmit(bufferedEvent);
    }
    preChargeEvents.length = 0;
  };

  const handleRecommendation = async (event: StreamEvent) => {
    if (recommendationCharged) {
      emitError(
        "STREAM_DUPLICATE_RECOMMENDATION",
        "Streaming analysis emitted more than one official recommendation.",
      );
      closed = true;
      return;
    }

    const validation = validateRecommendationEvent(event);
    if (!validation.ok) {
      emitError(validation.code, validation.reason);
      closed = true;
      return;
    }

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
      return;
    }

    recommendationCharged = true;
    flushPreChargeEvents();
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

    if (event.type === "analysis.error") {
      options.emit(event);
      closed = true;
      return;
    }

    if (!recommendationCharged) {
      if (event.type === "analysis.progress") {
        options.emit(event);
        return;
      }

      if (event.type === "analysis.done") {
        emitError(
          "STREAM_MISSING_RECOMMENDATION",
          "Streaming analysis ended before an official recommendation.",
        );
        closed = true;
        return;
      }

      preChargeEvents.push(event);
      return;
    }

    if (event.type === "analysis.done") {
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
        if (recommendationCharged) {
          emitDone();
        } else {
          emitError(
            "STREAM_MISSING_RECOMMENDATION",
            "Streaming analysis ended before an official recommendation.",
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
  ) => {
    const replies = ensureRecord(result, "replies");
    replies[style] = message;

    const replyOptions = ensureRecord(result, "replyOptions");
    replyOptions[style] = {
      approach: reason,
      messages: [
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
        const message = stringField(event.message);
        if (!style || !message) return;
        absorbReply(
          style,
          message,
          stringField(event.reason ?? event.approach),
          stringField(event.quotedContext ?? event.sourceMessage),
          event.isSelected === true,
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
        const finalResult = recordField(event.finalResult);
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

function stringField(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function numberField(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function recordField(value: unknown): Record<string, unknown> | null {
  return isRecord(value) ? value : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function omitType(event: Record<string, unknown>): Record<string, unknown> {
  const { type: _type, ...rest } = event;
  return rest;
}
