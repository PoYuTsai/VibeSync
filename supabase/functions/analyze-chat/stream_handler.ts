import { type NdjsonEmit, ndjsonStreamResponse } from "./ndjson_response.ts";
import {
  createStreamReframer,
  type StreamChargeResult,
  type StreamOutputEvent,
  type StreamRecommendationForCharge,
} from "./reframer.ts";

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
  callClaude: () => Promise<ClaudeTextStreamResult>;
  chargeRun: (
    recommendation: StreamRecommendationForCharge,
  ) => Promise<StreamChargeResult> | StreamChargeResult;
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

export function handleStreamAnalysisRequest(
  options: StreamAnalysisHandlerOptions,
): Response {
  return ndjsonStreamResponse(async (emit, close) => {
    let recommendationEmitted = false;
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
        recommendationEmitted = true;
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

    const reframer = createStreamReframer({
      emit: emitReframed,
      onRecommendation: options.chargeRun,
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
          pendingError = buildUpstreamError(error, recommendationEmitted);
        }
      }

      if (!pendingError) {
        await reframer.flush();
      }
    } catch (error) {
      if (!pendingError) {
        pendingError = buildUpstreamError(error, recommendationEmitted);
      }
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
      if (isRecord(processedFinalResult)) {
        doneEvent = Object.assign({}, originalDoneEvent, {
          finalResult: processedFinalResult,
        }) as StreamOutputEvent;
      }
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
  recommendationEmitted: boolean,
): StreamOutputEvent {
  if (recommendationEmitted) {
    return buildErrorEvent(
      "STREAM_INTERRUPTED_AFTER_RECOMMENDATION",
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
  if (!isRecord(finalResult)) return null;
  return finalResult;
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
