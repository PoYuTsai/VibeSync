// Resolves analyze-chat routing before quota, DB, prompt, or model work.
//
// Plain AnalyzeChat is streaming-only. Compatibility quick/full modes are
// retired instead of silently falling back to the legacy single-response
// handler. The legacy value remains only for other request shapes sharing this
// Edge Function (OCR, optimize/refine, opener, new_topic, and my_message).

export type ResponseMode = "legacy" | "stream";

export type RequestModeErrorCode =
  | "ANALYZE_RESPONSE_MODE_RETIRED"
  | "ANALYZE_STREAMING_REQUIRED"
  | "INVALID_RESPONSE_MODE";

export type RequestModeResolution =
  | {
    ok: true;
    responseMode: ResponseMode;
    analysisRunId: string | null;
  }
  | {
    ok: false;
    status: 400 | 410;
    code: RequestModeErrorCode;
  };

export interface RequestModeInput {
  responseMode?: unknown;
  analysisRunId?: unknown;

  /// True only for the main AnalyzeChat request shape. Other modes sharing
  /// analyze-chat may keep their existing legacy response contract.
  plainAnalyzeRequest: boolean;
}

export function resolveRequestMode(
  input: RequestModeInput,
): RequestModeResolution {
  if (input.responseMode === "quick" || input.responseMode === "full") {
    return {
      ok: false,
      status: 410,
      code: "ANALYZE_RESPONSE_MODE_RETIRED",
    };
  }

  const responseMode = input.responseMode === undefined ||
      input.responseMode === "legacy"
    ? "legacy"
    : input.responseMode === "stream"
    ? "stream"
    : null;
  if (responseMode === null) {
    return {
      ok: false,
      status: 400,
      code: "INVALID_RESPONSE_MODE",
    };
  }

  if (input.plainAnalyzeRequest && responseMode !== "stream") {
    return {
      ok: false,
      status: 410,
      code: "ANALYZE_STREAMING_REQUIRED",
    };
  }

  let analysisRunId: string | null = null;
  if (responseMode === "stream" && typeof input.analysisRunId === "string") {
    const trimmed = input.analysisRunId.trim();
    if (trimmed.length > 0) analysisRunId = trimmed;
  }

  return { ok: true, responseMode, analysisRunId };
}
