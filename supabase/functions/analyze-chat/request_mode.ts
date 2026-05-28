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
// shouldRejectFullMode — Phase 1 stub guard.
//
// Codex round-2 review fix: the full-mode rejection MUST fire BEFORE quota
// preflight / prompt building / Claude call. If it fires late, a user whose
// quota was exhausted by quick mode gets 429 quota_exceeded instead of
// MISSING_RUN_ID / FULL_MODE_NOT_READY — breaking the two-stage contract
// (full is not quota-gated in Phase 1).
//
// This helper is intentionally pure and has no awareness of quota, user,
// or upstream state. The handler in `index.ts` calls it immediately after
// `normalizeRequestMode` and returns the response if `reject === true`.
// Phase 2.1 will replace this helper's `FULL_MODE_NOT_READY` branch with
// the real anchor handler — at that point this function should be removed
// (or made always return `{ reject: false }`).
// ---------------------------------------------------------------------------

export type FullRejection =
  | { reject: false }
  | { reject: true; status: 400; code: "MISSING_RUN_ID" }
  | { reject: true; status: 503; code: "FULL_MODE_NOT_READY" };

export function shouldRejectFullMode(
  state: NormalizedRequestMode,
): FullRejection {
  if (state.responseMode !== "full") return { reject: false };
  if (!state.analysisRunId) {
    return { reject: true, status: 400, code: "MISSING_RUN_ID" };
  }
  return { reject: true, status: 503, code: "FULL_MODE_NOT_READY" };
}
