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
