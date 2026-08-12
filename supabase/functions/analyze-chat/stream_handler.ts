import { type NdjsonEmit, ndjsonStreamResponse } from "./ndjson_response.ts";
import {
  createStreamReframer,
  isThinRecommendationEvent,
  type StreamChargeResult,
  type StreamOutputEvent,
  type StreamRecommendationForCharge,
  toRecommendationEvent,
} from "./reframer.ts";
import type { StreamStyle } from "./stream_events.ts";
import { AiStreamingServiceError } from "./streaming_fallback.ts";

export interface ClaudeTextStreamResult {
  model?: string;
  textStream: AsyncIterable<string>;
}

export interface StreamAnalysisHandlerOptions {
  runId: string;
  conversationHash: string;
  etaSeconds?: number;
  headers?: HeadersInit;
  progressEvents?: StreamOutputEvent[];
  heartbeatIntervalMs?: number;
  callClaude: () => Promise<ClaudeTextStreamResult>;
  chargeRun: (
    recommendation: StreamRecommendationForCharge,
  ) => Promise<StreamChargeResult> | StreamChargeResult;
  prechargedRecommendation?: StreamRecommendationForCharge;
  requiredReplyStyles?: readonly StreamStyle[];
  markDone: (
    finalResult: Record<string, unknown>,
  ) => Promise<Record<string, unknown> | void> | Record<string, unknown> | void;
  markFailed: (
    code: string,
    details?: Record<string, unknown>,
  ) => Promise<void> | void;
}

const DEFAULT_PROGRESS_EVENTS: StreamOutputEvent[] = [
  {
    type: "analysis.progress",
    phase: "reading",
    label: "讀取對話脈絡",
    detail: "正在整理你們這一輪的訊息、情緒與回覆目標。",
  },
  {
    type: "analysis.progress",
    phase: "decision",
    label: "判斷本回合方向",
    detail: "正在選擇最適合的回覆策略，完整分析會在下方繼續整理。",
  },
];

const DEFAULT_HEARTBEAT_INTERVAL_MS = 15000;
const DEFAULT_RESUME_POLL_INTERVAL_MS = 2000;
const DEFAULT_RESUME_MAX_WAIT_MS = 125000;

export type StreamAnalysisResumeStatus =
  | "pending"
  | "charged"
  | "done"
  | "failed";

export interface StreamAnalysisResumeSnapshot {
  status: StreamAnalysisResumeStatus;
  finalResult: Record<string, unknown> | null;
  lastErrorCode: string | null;
  retriesRemaining: number;
  wasCharged: boolean;
}

export interface StreamAnalysisResumeOptions {
  runId: string;
  conversationHash: string;
  headers?: HeadersInit;
  initialRun: StreamAnalysisResumeSnapshot;
  loadRun: () =>
    | Promise<StreamAnalysisResumeSnapshot>
    | StreamAnalysisResumeSnapshot;
  pollIntervalMs?: number;
  maxWaitMs?: number;
  heartbeatIntervalMs?: number;
}

/**
 * Reattaches a client to a run that is still owned by the original Edge
 * request. The original request remains the only writer/model caller; this
 * response only observes the ledger and replays the durable final payload.
 */
export function handleStreamAnalysisResume(
  options: StreamAnalysisResumeOptions,
): Response {
  return ndjsonStreamResponse(async (emit, close) => {
    const pollIntervalMs = Math.max(
      0,
      options.pollIntervalMs ?? DEFAULT_RESUME_POLL_INTERVAL_MS,
    );
    const maxWaitMs = Math.max(
      pollIntervalMs,
      options.maxWaitMs ?? DEFAULT_RESUME_MAX_WAIT_MS,
    );
    const heartbeatIntervalMs = Math.max(
      0,
      options.heartbeatIntervalMs ?? DEFAULT_HEARTBEAT_INTERVAL_MS,
    );
    const startedAt = Date.now();
    let lastProgressAt = startedAt;
    let run = options.initialRun;

    emit({
      type: "analysis.started",
      runId: options.runId,
      conversationHash: options.conversationHash,
      resumed: true,
      label: "正在取回分析結果",
    });
    emit({
      type: "analysis.progress",
      phase: "recovery",
      runId: options.runId,
      conversationHash: options.conversationHash,
      label: "連線已恢復",
      detail: "正在取回原本的分析，不會重新扣除額度。",
    });

    while (true) {
      if (run.status === "done") {
        if (!run.finalResult) {
          emit({
            type: "analysis.error",
            code: "STREAM_DONE_RESULT_MISSING",
            message: "已完成的分析結果暫時無法讀取，請重新分析。",
            recoverable: false,
            retriesRemaining: 0,
          });
          close();
          return;
        }

        emit({
          type: "analysis.done",
          runId: options.runId,
          finalResult: run.finalResult,
          result: run.finalResult,
          recovered: true,
        });
        close();
        return;
      }

      if (run.status === "failed") {
        const canRetry = run.wasCharged && run.retriesRemaining > 0;
        emit({
          type: "analysis.error",
          code: canRetry
            ? "STREAM_RUN_RECOVERY_RETRY_READY"
            : "STREAM_RUN_RETRY_UNAVAILABLE",
          message: canRetry
            ? "連線已恢復，正在重新接續完整分析。"
            : "原本的分析沒有完成，請重新分析一次。",
          recoverable: canRetry,
          retriesRemaining: canRetry ? run.retriesRemaining : 0,
          upstreamCode: run.lastErrorCode,
        });
        close();
        return;
      }

      if (Date.now() - startedAt >= maxWaitMs) {
        emit({
          type: "analysis.error",
          code: "STREAM_RUN_STILL_PROCESSING",
          message: "原本的分析仍在整理中，請稍後再試。",
          recoverable: true,
          retriesRemaining: Math.max(1, run.retriesRemaining),
        });
        close();
        return;
      }

      if (pollIntervalMs > 0) {
        await new Promise((resolve) => setTimeout(resolve, pollIntervalMs));
      }

      try {
        run = await options.loadRun();
      } catch (_error) {
        emit({
          type: "analysis.error",
          code: "STREAM_RECOVERY_LOOKUP_FAILED",
          message: "暫時無法取回原本的分析，請稍後再試。",
          recoverable: true,
          retriesRemaining: Math.max(1, run.retriesRemaining),
        });
        close();
        return;
      }

      if (
        heartbeatIntervalMs > 0 &&
        Date.now() - lastProgressAt >= heartbeatIntervalMs
      ) {
        emit({
          type: "analysis.progress",
          phase: "recovery",
          runId: options.runId,
          conversationHash: options.conversationHash,
          label: "正在取回分析結果",
          detail: "原本的分析仍在整理中，不會重新扣除額度。",
        });
        lastProgressAt = Date.now();
      }
    }
  }, options.headers);
}

export function handleStreamAnalysisRequest(
  options: StreamAnalysisHandlerOptions,
): Response {
  return ndjsonStreamResponse(async (emit, close) => {
    let chargedContentEmitted = false;
    let pendingDone: StreamOutputEvent | null = null;
    let pendingError: StreamOutputEvent | null = null;

    const emitReframed = (event: StreamOutputEvent) => {
      if (event.type === "analysis.done") {
        pendingDone = event;
        return;
      }

      if (event.type === "analysis.error") {
        pendingError = event;
        return;
      }

      if (event.type === "analysis.recommendation") {
        chargedContentEmitted = true;
      }

      if (event.type === "analysis.decision") {
        chargedContentEmitted = true;
      }

      emit(event);
    };

    emit({
      type: "analysis.started",
      runId: options.runId,
      conversationHash: options.conversationHash,
      etaSeconds: options.etaSeconds ?? 18,
    });

    for (const event of options.progressEvents ?? DEFAULT_PROGRESS_EVENTS) {
      emit(event);
    }

    if (options.prechargedRecommendation) {
      chargedContentEmitted = true;
      // 件4 D2：v2 瘦卡（無 message）不可直接回放給 client；reframer 會用
      // replay 的 selected reply_option 綁卡回填後再 emit 完整推薦卡。
      if (!isThinRecommendationEvent(options.prechargedRecommendation.raw)) {
        emit(toRecommendationEvent(options.prechargedRecommendation));
      }
    }

    const stopHeartbeat = startHeartbeat(options, emit);
    const reframer = createStreamReframer({
      emit: emitReframed,
      onRecommendation: options.chargeRun,
      prechargedRecommendation: options.prechargedRecommendation,
      requiredReplyStyles: options.requiredReplyStyles,
    });

    try {
      const claude = await options.callClaude();
      try {
        for await (const chunk of claude.textStream) {
          reframer.pushText(chunk);
        }
      } catch (error) {
        await reframer.drain();
        if (!pendingError) {
          pendingError = buildUpstreamError(error, chargedContentEmitted);
        }
      }

      if (!pendingError) {
        await reframer.flush();
      }
    } catch (error) {
      if (!pendingError) {
        pendingError = buildUpstreamError(error, chargedContentEmitted);
      }
    } finally {
      stopHeartbeat();
    }

    if (pendingError) {
      await markFailedAndEmit(options, emit, pendingError);
      close();
      return;
    }

    if (!pendingDone) {
      await markFailedAndEmit(
        options,
        emit,
        buildErrorEvent(
          "STREAM_EMPTY_RESPONSE",
          "分析沒有產生結果，請稍後重新分析。",
          true,
        ),
      );
      close();
      return;
    }

    const finalResult = getFinalResult(pendingDone);
    if (!finalResult) {
      await markFailedAndEmit(
        options,
        emit,
        buildErrorEvent(
          "STREAM_MISSING_FINAL_RESULT",
          "完整分析格式不完整，請重新分析。",
          true,
        ),
      );
      close();
      return;
    }

    const originalDoneEvent: StreamOutputEvent & { type: string } = pendingDone;
    let doneEvent: StreamOutputEvent = originalDoneEvent;
    try {
      const processedFinalResult = await options.markDone(finalResult);
      const emittedFinalResult = isRecord(processedFinalResult)
        ? processedFinalResult
        : finalResult;
      doneEvent = Object.assign({}, originalDoneEvent, {
        finalResult: emittedFinalResult,
        result: emittedFinalResult,
      }) as StreamOutputEvent;
    } catch (error) {
      await markFailedAndEmit(
        options,
        emit,
        buildErrorEvent(
          "STREAM_FINAL_PERSIST_FAILED",
          "完整分析儲存失敗，請重新分析。",
          true,
          { cause: errorMessage(error) },
        ),
      );
      close();
      return;
    }

    emit(doneEvent);
    close();
  }, options.headers);
}

function startHeartbeat(
  options: StreamAnalysisHandlerOptions,
  emit: NdjsonEmit,
): () => void {
  const intervalMs = options.heartbeatIntervalMs ??
    DEFAULT_HEARTBEAT_INTERVAL_MS;
  if (!Number.isFinite(intervalMs) || intervalMs <= 0) {
    return () => {};
  }

  let count = 0;
  const timer = setInterval(() => {
    count += 1;
    emit({
      type: "analysis.progress",
      phase: "heartbeat",
      runId: options.runId,
      conversationHash: options.conversationHash,
      etaSeconds: options.etaSeconds ?? 18,
      label: "完整分析仍在進行",
      detail: count === 1
        ? "正在等待模型完成深度推理，請保持連線。"
        : "正在整理完整分析結果，請保持連線。",
    });
  }, intervalMs);

  return () => clearInterval(timer);
}

async function markFailedAndEmit(
  options: StreamAnalysisHandlerOptions,
  emit: NdjsonEmit,
  event: StreamOutputEvent,
) {
  const code = stringField(event.code) || "STREAM_FAILED";
  try {
    await options.markFailed(code, { event });
  } catch (error) {
    emit({
      type: "analysis.progress",
      phase: "failure-log",
      label: "紀錄失敗狀態時發生問題",
      detail: errorMessage(error),
    });
  }
  emit(event);
}

function buildUpstreamError(
  error: unknown,
  chargedContentEmitted: boolean,
): StreamOutputEvent {
  if (error instanceof AiStreamingServiceError) {
    return buildErrorEvent(
      error.code,
      chargedContentEmitted
        ? "分析串流中斷；已完成的內容會保留，請依提示決定是否重試。"
        : "AI 分析暫時無法完成，請依提示決定是否重試。",
      error.retryable,
      {
        upstreamCode: error.code,
        afterContent: chargedContentEmitted,
      },
    );
  }

  if (chargedContentEmitted) {
    return buildErrorEvent(
      "STREAM_INTERRUPTED_AFTER_CONTENT",
      "分析中途斷線，已保留先前產生的建議；請重新整理完整分析。",
      true,
      { cause: errorMessage(error) },
    );
  }

  return buildErrorEvent(
    "STREAM_UPSTREAM_FAILED",
    "分析暫時無法完成，請稍後重新分析。",
    true,
    { cause: errorMessage(error) },
  );
}

function buildErrorEvent(
  code: string,
  message: string,
  recoverable: boolean,
  extra: Record<string, unknown> = {},
): StreamOutputEvent {
  return {
    type: "analysis.error",
    code,
    message,
    recoverable,
    ...extra,
  };
}

function getFinalResult(
  event: StreamOutputEvent,
): Record<string, unknown> | null {
  const finalResult = event.finalResult;
  if (isRecord(finalResult)) return finalResult;

  const result = event.result;
  if (isRecord(result)) return result;

  return null;
}

function stringField(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
