// supabase/functions/analyze-chat/request_mode.ts
//
// Phase 1.2 — parse + normalize 兩階段 analyze 的 routing 欄位。
//
// Invariants:
// - `responseMode` 永遠落在 "quick" | "full" | "legacy" 三值之一；任何非
//   `"quick"`/`"full"`/`"legacy"` string 一律 → `"legacy"` 維持 build 211 行為（I10）。
// - `analysisRunId` 空字串、whitespace、非 string 都 → `null`，讓 full handler 用
//   單一 falsy 判斷拒絕 → I2 (400 MISSING_RUN_ID)。

export type ResponseMode = "quick" | "full" | "legacy";

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
    : "legacy";

  let analysisRunId: string | null = null;
  if (typeof input.analysisRunId === "string") {
    const trimmed = input.analysisRunId.trim();
    if (trimmed.length > 0) analysisRunId = trimmed;
  }

  return { responseMode, analysisRunId };
}

// ---------------------------------------------------------------------------
// shouldRejectFullMode — early MISSING_RUN_ID bouncer.
//
// Codex round-2 review fix (Phase 1.3): the early reject MUST fire BEFORE
// quota preflight / prompt building / Claude call so a user whose quota was
// exhausted by quick mode still gets a deterministic 400 MISSING_RUN_ID
// instead of 429 quota_exceeded — full is not quota-gated.
//
// Phase 2.1 update: the `FULL_MODE_NOT_READY` (503) branch is gone — the real
// full handler now lives in `index.ts` next to the quick branch and validates
// the run via `AnalysisRunStore.validateRunForFull`. This helper now only
// short-circuits the no-runId case so we don't pay for hash/DB/Claude work on
// a request the handler would reject anyway.
//
// Intentionally pure (no quota/user/DB awareness). The handler calls it
// immediately after `normalizeRequestMode`.
// ---------------------------------------------------------------------------

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
  // Phase 2.1: full+runId is now handled by the real handler — let it through.
  return { reject: false };
}
