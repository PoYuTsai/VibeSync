import {
  ndjsonStreamResponse,
  type NdjsonEmit,
} from "./ndjson_response.ts";
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
  headers?: HeadersInit;
  progressEvents?: StreamOutputEvent[];
  callClaude: () => Promise<ClaudeTextStreamResult>;
  chargeRun: (
    recommendation: StreamRecommendationForCharge,
  ) => Promise<StreamChargeResult> | StreamChargeResult;
  markDone: (finalResult: Record<string, unknown>) => Promise<void> | void;
  markFailed: (
    code: string,
    details?: Record<string, unknown>,
  ) => Promise<void> | void;
}

const DEFAULT_PROGRESS_EVENTS: StreamOutputEvent[] = [
  {
    type: "analysis.progress",
    phase: "reading",
    label: "正在整理這段對話",
    detail: "先抓本回合重點，完整建議會逐步補上。",
  },
  {
    type: "analysis.progress",
    phase: "decision",
    label: "正在判斷這回合怎麼接",
    detail: "會先整理方向，再接著產生正式推薦回覆。",
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
          "分析暫時中斷，這次不會扣額度。請重新分析。",
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
          "完整分析整理失敗，請稍後重新分析。",
          true,
        ),
      );
      close();
      return;
    }

    try {
      await options.markDone(finalResult);
    } catch (error) {
      await markFailedAndEmit(
        options,
        emit,
        buildErrorEvent(
          "STREAM_FINAL_PERSIST_FAILED",
          "完整分析儲存失敗，請稍後重試。",
          true,
          { cause: errorMessage(error) },
        ),
      );
      close();
      return;
    }

    emit(pendingDone);
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
      label: "分析狀態紀錄失敗",
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
      "完整分析中斷，但已保留目前建議。你可以稍後重試補完。",
      true,
      { cause: errorMessage(error) },
    );
  }

  return buildErrorEvent(
    "STREAM_UPSTREAM_FAILED",
    "分析暫時中斷，這次不會扣額度。請重新分析。",
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

function getFinalResult(event: StreamOutputEvent): Record<string, unknown> | null {
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
