import {
  isStreamStyle,
  parseEventLine,
  type StreamEvent,
  type StreamStyle,
} from "./stream_events.ts";
import {
  type RecommendationValidation,
  validateDecisionChargeEvent,
  validateRecommendationBackfill,
  validateRecommendationEvent,
  validateThinRecommendationEvent,
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
  // 件4 D2 瘦推薦卡：buffer 住的瘦 recommendation，等 selected
  // reply_option 到貨後回填全文再轉發（D3 契約凍結：App 看到的順序不變）。
  let pendingThinRecommendation:
    | Extract<RecommendationValidation, { ok: true }>
    | null = null;
  // 黑箱 r1 韌性網：記住已轉發的 reply_option 與 decision 的 selectedStyle，
  // 瘦卡晚到（option 已過）或整個沒來時可在終局 late-bind / 合成推薦卡。
  const seenReplyOptions = new Map<
    StreamStyle,
    { compat: StreamEvent; segments: Record<string, unknown>[] }
  >();
  let decisionSelectedStyle: StreamStyle | null = null;
  const preChargeEvents: StreamEvent[] = [];
  const requiredReplyStyles = normalizeRequiredReplyStyles(
    options.requiredReplyStyles,
  );
  const requiredReplyStyleSet = new Set(requiredReplyStyles);

  if (options.prechargedRecommendation) {
    const raw = options.prechargedRecommendation.raw;
    if (isThinRecommendationEvent(raw)) {
      // resume 自 v2 瘦卡扣費：重掛 pending，由 replay 的 selected
      // reply_option 重新綁卡回填；瘦卡本身不可直接外流。revalidation
      // 失敗（ledger 損壞）也不得讓 officialRecommendationEmitted 卡成
      // true 靜默完成——交給 replay 的瘦卡重新走 fresh 驗證。
      officialRecommendationEmitted = false;
      const revalidated = validateThinRecommendationEvent(raw);
      if (revalidated.ok) {
        pendingThinRecommendation = revalidated;
      }
    } else {
      if (raw?.type === "analysis.decision") {
        decisionSelectedStyle = options.prechargedRecommendation.selectedStyle;
      }
      assembler.absorb(toRecommendationEvent(options.prechargedRecommendation));
    }
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
    tryLateBind();
    if (closed) return; // late-bind 的 safety 檢查可能擋下並關閉 stream。
    if (pendingThinRecommendation) {
      // 件4 測試重點：buffer 中的瘦卡（已扣費）不得造成「已扣費但無輸出」
      // 的靜默 done——selected reply_option 沒到就走既有 INCOMPLETE 路徑，
      // 模型在 finalResult 塞滿五風格（雙軌殘骸）也一樣。
      emitError(
        "STREAM_INCOMPLETE_REPLY_OPTIONS",
        "Streaming analysis ended before the selected reply option arrived.",
        true,
        { missingStyles: [pendingThinRecommendation.selectedStyle] },
      );
      closed = true;
      return;
    }
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
      if (closed) break;
      // pre-charge buffer 裡的 reply_option 也要過 bind（模型亂序時
      // selected option 可能先於瘦卡到貨）。
      if (bufferedEvent.type === "analysis.reply_option") {
        forwardReplyOption(bufferedEvent);
      } else {
        absorbAndEmit(bufferedEvent);
      }
    }
    preChargeEvents.length = 0;
  };

  // 件4 D4：reply_option 轉發前由 server 合成 flat message / quotedContext
  // 相容欄位（segments join），App 收到的形狀與今天相同。
  const forwardReplyOption = (event: StreamEvent) => {
    const segments = replySegmentsFrom(
      event.segments ?? event.messages ?? event.messageGroup ??
        event.replySegments,
    );
    const compat = withReplyOptionCompatFields(event, segments);
    const style = replyStyleFrom(compat);
    if (style) seenReplyOptions.set(style, { compat, segments });
    if (
      pendingThinRecommendation &&
      replyStyleFrom(compat) === pendingThinRecommendation.selectedStyle &&
      !bindPendingRecommendation(compat, segments)
    ) {
      return; // 回填後 safety 擋下，stream 已關。
    }
    if (closed) return;
    absorbAndEmit(compat);
  };

  // 件4 扣卡回填：join 後全文 + 原始段落塞回瘦推薦卡，先轉發 enriched
  // recommendation 再轉發 selected reply_option（D3 舊順序）。safety 檢查
  // 對象是 join 後全文——驗的內容跟今天相同，只是時機後移。
  const bindPendingRecommendation = (
    option: StreamEvent,
    segments: readonly Record<string, unknown>[],
  ): boolean => {
    const thin = pendingThinRecommendation!;
    const joined = stringField(option.message) || joinedSegmentReply(segments);
    if (!joined) return true; // 無文字可回填：留 pending，終局走 INCOMPLETE。

    const quotedContext = stringField(option.quotedContext) ||
      joinedSegmentSources(segments);
    const backfill = validateRecommendationBackfill(joined, quotedContext);
    if (!backfill.ok) {
      emitError(backfill.code, backfill.reason);
      closed = true;
      return false;
    }

    pendingThinRecommendation = null;
    officialRecommendationEmitted = true;
    absorbAndEmit({
      ...thin.raw,
      type: "analysis.recommendation",
      selectedStyle: thin.selectedStyle,
      message: joined,
      reason: thin.reason,
      quotedContext,
      warnings: [...thin.warnings, ...backfill.warnings],
      ...(segments.length > 0 ? { replySegments: [...segments] } : {}),
    });
    return true;
  };

  // 黑箱 r1 韌性網：瘦卡晚到（selected option 已轉發）→ 立即補綁；瘦卡
  // 整條 stream 沒來 → 用 decision 的 selectedStyle + 該風格 option 合成
  // 推薦卡（扣費語意不變，decision 仍是第一扣費錨點）。
  const tryLateBind = () => {
    if (closed || officialRecommendationEmitted || !chargeCompleted) return;
    if (!pendingThinRecommendation) {
      if (!decisionSelectedStyle) return;
      const stored = seenReplyOptions.get(decisionSelectedStyle);
      if (!stored) return;
      pendingThinRecommendation = {
        ok: true,
        selectedStyle: decisionSelectedStyle,
        message: "",
        reason: stringField(stored.compat.reason ?? stored.compat.approach),
        quotedContext: "",
        warnings: [],
        raw: {
          type: "analysis.recommendation",
          selectedStyle: decisionSelectedStyle,
          synthesizedFromDecision: true,
        },
      };
    }
    const stored = seenReplyOptions.get(
      pendingThinRecommendation.selectedStyle,
    );
    if (!stored) return;
    bindPendingRecommendation(stored.compat, stored.segments);
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

    if (isStreamStyle(event.selectedStyle)) {
      decisionSelectedStyle = event.selectedStyle;
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

  // 件4：v2 瘦卡（無 message、帶 expectedReaction）→ buffer 等回填；
  // 帶 message 的 legacy 形狀照舊立即驗證+轉發（rollback 安全網）。
  const handleThinRecommendation = async (event: StreamEvent) => {
    const validation = validateThinRecommendationEvent(event);
    if (!validation.ok) {
      emitError(validation.code, validation.reason);
      closed = true;
      return;
    }

    if (!styleIsAllowed(validation.selectedStyle)) {
      rejectUnavailableAnchorStyle(validation.selectedStyle);
      return;
    }

    if (officialRecommendationEmitted || pendingThinRecommendation) {
      if (isResume) return;
      emitError(
        "STREAM_DUPLICATE_RECOMMENDATION",
        "Streaming analysis emitted more than one official recommendation.",
      );
      closed = true;
      return;
    }

    // 先掛 pending 再扣費：扣費成功的 flushPreChargeEvents 會把先到的
    // selected reply_option 路過 bind。
    pendingThinRecommendation = validation;
    if (!chargeCompleted && !(await chargeFromValidation(validation))) {
      pendingThinRecommendation = null;
      return;
    }
    // 瘦卡晚到：selected option 已轉發過 → 立即補綁。
    tryLateBind();
  };

  const handleRecommendation = async (event: StreamEvent) => {
    if (isThinRecommendationEvent(event)) {
      await handleThinRecommendation(event);
      return;
    }

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
      if (chargeCompleted) {
        forwardReplyOption(event);
        return;
      }
      // 未扣費：落到下方 pre-charge buffer，flush 時再過 bind。
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
      tryLateBind();
      if (closed) return;
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
        if (chargeCompleted) tryLateBind();
        if (closed) return;
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

// v2 瘦推薦卡判別：無 message + 帶 expectedReaction。message 缺但也沒
// expectedReaction 的事件仍走 legacy 驗證（維持 malformed 既有行為）。
export function isThinRecommendationEvent(
  event: StreamEvent | Record<string, unknown> | undefined,
): boolean {
  if (!event || event.type !== "analysis.recommendation") return false;
  return stringField(event.message) === "" &&
    stringField(event.expectedReaction) !== "";
}

function withReplyOptionCompatFields(
  event: StreamEvent,
  segments: readonly Record<string, unknown>[],
): StreamEvent {
  if (segments.length === 0) return event;
  const compat: StreamEvent = { ...event };
  if (stringField(compat.message) === "") {
    compat.message = joinedSegmentReply(segments);
  }
  if (stringField(compat.quotedContext) === "") {
    compat.quotedContext = joinedSegmentSources(segments);
  }
  return compat;
}

function joinedSegmentSources(
  segments: readonly Record<string, unknown>[],
): string {
  return segments
    .map((item) => stringField(item.sourceMessage))
    .filter((text) => text.length > 0)
    .join(" / ");
}

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

  // 件4 廢除雙軌：bind 過的 finalRecommendation（帶 segments）為權威，
  // 模型 done finalResult 不得 clobber。
  let finalRecommendationAuthoritative = false;

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
      const hasSegments = segments != null && segments.length > 0;
      result.finalRecommendation = {
        pick: style,
        content: message,
        reason,
        psychology: reason,
        ...(hasSegments ? { replySegments: [...segments] } : {}),
      };
      if (hasSegments) finalRecommendationAuthoritative = true;
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
          // bind 回填的 enriched recommendation 帶原始段落陣列。
          replySegmentsFrom(event.replySegments ?? event.segments),
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
          event.segments ?? event.messages ?? event.messageGroup ??
            event.replySegments,
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
    if (enthusiasm) result.enthusiasm = roundEnthusiasmScore(enthusiasm);

    const score = numberField(
      event.heat ?? event.enthusiasmScore ?? event.score,
    );
    if (score !== null) {
      const target = ensureRecord(result, "enthusiasm");
      target.score = Math.round(score);
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

    // 同一個 result 的另一條寫入路徑，必須走與 done merge 相同的形狀守門
    // （2026-06-13 queue 補強：section=gameStage/psychology 字串 payload 可
    // 繞過 mergeFinalResult 的 coerce）。
    const coerced = coerceClientShapeValue(
      result,
      section,
      payload ?? omitType(event),
    );
    if (coerced === undefined) return;
    result[section] = coerced;
  }

  function mergeFinalResult(finalResult: Record<string, unknown>) {
    for (const [key, value] of Object.entries(finalResult)) {
      // 廢除雙軌：finalRecommendation 一律以 selected reply_option 回填
      // 的版本為準，模型 done 殘骸不得覆蓋。
      if (key === "finalRecommendation" && finalRecommendationAuthoritative) {
        continue;
      }
      const coerced = coerceClientShapeValue(result, key, value);
      if (coerced === undefined) continue;
      result[key] = coerced;
    }
  }
}

// client AnalysisResult.fromJson 對這些 key 是硬 cast Map<String, dynamic>，
// 收到字串會 throw INVALID_STREAM_RESULT（dogfood P0 2026-06-13：Haiku 常把
// gameStage/psychology 攤平成字串，Sonnet 偶發）。merge 時必須守門：能語意
// 映射的塞回正確欄位，不能的丟棄保留 assembler 既有值，絕不原樣 clobber。
const RECORD_ONLY_FINAL_RESULT_KEYS = new Set([
  "gameStage",
  "psychology",
  "topicDepth",
  "enthusiasm",
  "replies",
  "replyOptions",
  "finalRecommendation",
  "usage",
  "targetProfile",
  "healthCheck",
  "optimizedMessage",
  "myMessageAnalysis",
  "recognizedConversation",
]);

// client 是 List<String>.from(json[key])，字串/物件 clobber 都會 throw。
const ARRAY_ONLY_FINAL_RESULT_KEYS = new Set([
  "warnings",
]);

function coerceClientShapeValue(
  result: Record<string, unknown>,
  key: string,
  value: unknown,
): unknown | undefined {
  if (ARRAY_ONLY_FINAL_RESULT_KEYS.has(key)) {
    return coerceStringArray(value);
  }
  if (!RECORD_ONLY_FINAL_RESULT_KEYS.has(key)) return value;
  if (isRecord(value)) return normalizeRecordForClient(key, value);

  const existing = isRecord(result[key])
    ? result[key] as Record<string, unknown>
    : {};
  const text = typeof value === "string" ? value.trim() : "";

  if (key === "gameStage" && text) return { ...existing, current: text };
  if (key === "psychology" && text) return { ...existing, subtext: text };
  if (key === "topicDepth" && text) return { ...existing, current: text };
  if (key === "enthusiasm") {
    const score = numberField(value);
    if (score !== null) return { ...existing, score: Math.round(score) };
  }
  return undefined;
}

// record 形狀正確不代表巢狀欄位安全——client 對 psychology.shitTest 是
// as Map? 硬 cast、healthCheck.issues/suggestions 是 List<String>.from，
// 巢狀字串/混型元素一樣炸。語意不可靠的（字串 shitTest 可能說「沒有測試」）
// 丟 key 讓 client 走預設值。
function normalizeRecordForClient(
  key: string,
  record: Record<string, unknown>,
): Record<string, unknown> {
  if (key === "enthusiasm") return roundEnthusiasmScore(record);
  if (key === "psychology") {
    if (!("shitTest" in record) || isRecord(record.shitTest)) return record;
    const { shitTest: _dropped, ...rest } = record;
    return rest;
  }
  if (key === "healthCheck") {
    const next = { ...record };
    for (const listKey of ["issues", "suggestions"]) {
      if (!(listKey in next)) continue;
      const coerced = coerceStringArray(next[listKey]);
      if (coerced === undefined) delete next[listKey];
      else next[listKey] = coerced;
    }
    return next;
  }
  return record;
}

// client 是 List<String>.from——非陣列 clobber 與混型元素都會 throw。
// 字串語意映射成單元素陣列，其餘丟棄。
function coerceStringArray(value: unknown): string[] | undefined {
  if (Array.isArray(value)) {
    return value.filter((item): item is string => typeof item === "string");
  }
  const text = typeof value === "string" ? value.trim() : "";
  return text ? [text] : undefined;
}

// client enthusiasm['score'] as int? 收到 72.5 會 throw——所有寫入路徑取整。
function roundEnthusiasmScore(
  record: Record<string, unknown>,
): Record<string, unknown> {
  const score = numberField(record.score);
  if (score === null || Number.isInteger(score)) return record;
  return { ...record, score: Math.round(score) };
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
