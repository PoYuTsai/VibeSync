// supabase/functions/analyze-chat/request_mode.ts
//
// Normalizes analyze-chat routing fields before any quota, DB, or Claude work.
//
// Invariants:
// - Unknown `responseMode` values degrade to `legacy` for backwards
//   compatibility with older app builds.
// - `analysisRunId` is trimmed, and empty/non-string values become `null`.
// - `stream` is only a routing value here. Access gating and handler behavior
//   live in the streaming branch.

export type ResponseMode = "quick" | "full" | "legacy" | "stream";

export interface NormalizedRequestMode {
  responseMode: ResponseMode;
  analysisRunId: string | null;
}

export interface RequestModeInput {
  responseMode?: unknown;
  analysisRunId?: unknown;
}

export function normalizeRequestMode(
  input: RequestModeInput,
): NormalizedRequestMode {
  const responseMode: ResponseMode = input.responseMode === "quick"
    ? "quick"
    : input.responseMode === "full"
    ? "full"
    : input.responseMode === "stream"
    ? "stream"
    : "legacy";

  let analysisRunId: string | null = null;
  if (typeof input.analysisRunId === "string") {
    const trimmed = input.analysisRunId.trim();
    if (trimmed.length > 0) analysisRunId = trimmed;
  }

  return { responseMode, analysisRunId };
}

// Pure early bouncer for full mode. The handler calls this immediately after
// normalizeRequestMode so missing-runId requests fail before hash, quota, DB,
// prompt, or Claude work.
export type FullRejection =
  | { reject: false }
  | { reject: true; status: 400; code: "MISSING_RUN_ID" };

export function shouldRejectFullMode(
  state: NormalizedRequestMode,
): FullRejection {
  if (state.responseMode !== "full") return { reject: false };
  if (!state.analysisRunId) {
    return { reject: true, status: 400, code: "MISSING_RUN_ID" };
  }

  return { reject: false };
}
