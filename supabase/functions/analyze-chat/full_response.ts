// supabase/functions/analyze-chat/full_response.ts
//
// Phase 2.1 — pure helpers for the two-stage analyze FULL mode.
//
// Two responsibilities, kept in one module so the Codex review surface is
// one file:
//
//   1. `buildFullPromptAnchor(quickResult)` — produces the ANCHOR block we
//      prepend to the regular full-mode user prompt. Strict language enforces
//      plan I7: full is confirm/supplement/light-polish of quick, not a
//      redo. The user must never see "建議 A 變建議 B" in 10s.
//
//   2. `parseFullPayload(rawText)` — extracts the JSON object from Claude's
//      raw text. Mirrors the legacy parse + repair shape but is its own
//      module so Phase 2.1 stays additive and does NOT touch OCR-stable
//      legacy parsing code in index.ts (per CLAUDE.md OCR isolation rule).
//
// On parse failure the full handler treats the run reservation as ALREADY
// CONSUMED (matching plan I6 / test 7): one Claude attempt = one retry slot,
// regardless of whether Claude returned a wire error or unparseable text.
// Surfacing `retriesRemaining` lets the client decide whether to try again.

import type { QuickPayload } from "./quick_response.ts";

// ---------------------------------------------------------------------------
// Prompt anchor
// ---------------------------------------------------------------------------

export function buildFullPromptAnchor(
  quickResult: QuickPayload | Record<string, unknown>,
): string {
  const reply = stringOr((quickResult as QuickPayload).recommendedReply);
  const next = stringOr((quickResult as QuickPayload).nextStep);
  const reason = stringOr((quickResult as QuickPayload).shortReason);

  return [
    "## ANCHOR（來自快速分析）",
    "使用者已經在 3-5 秒前看到下列「本回合怎麼接」建議。完整分析必須將它視為錨點來確認、補充、與輕度潤飾，而不是當作可推翻的草稿。",
    "",
    `- nextStep: ${next}`,
    `- recommendedReply: ${reply}`,
    `- shortReason: ${reason}`,
    "",
    "規則：",
    "- finalRecommendation.content 必須使用 recommendedReply 的回覆文字（允許少量字詞替換、標點微調），不可換主題、不可改主要動詞、不可調轉語氣方向。",
    "- finalRecommendation.reason 必須與 shortReason 一致，可以延伸說明，但不可推翻判斷。",
    "- coachActionHint.microMove 必須順著 nextStep 方向，不可反向。",
    "- replyOptions 五個風格（extend/resonate/tease/humor/coldRead）可以提供替代版本，但 finalRecommendation.pick 必須指向實質沿用 recommendedReply 的風格。",
  ].join("\n");
}

// ---------------------------------------------------------------------------
// Full payload parser
// ---------------------------------------------------------------------------

export interface ParsedFullPayload {
  payload: Record<string, unknown>;
  source: "strict" | "repaired";
}

export type ParseFullError = "NO_JSON" | "INVALID_JSON";

export type ParseFullResult =
  | { ok: true; result: ParsedFullPayload }
  | { ok: false; error: ParseFullError };

export function parseFullPayload(rawText: string): ParseFullResult {
  const candidate = extractJsonObject(rawText);
  if (!candidate) return { ok: false, error: "NO_JSON" };

  try {
    const obj = JSON.parse(candidate);
    if (!isPlainObject(obj)) return { ok: false, error: "INVALID_JSON" };
    return { ok: true, result: { payload: obj, source: "strict" } };
  } catch (_strictErr) {
    try {
      const repaired = repairFullJson(candidate);
      const obj = JSON.parse(repaired);
      if (!isPlainObject(obj)) return { ok: false, error: "INVALID_JSON" };
      return { ok: true, result: { payload: obj, source: "repaired" } };
    } catch {
      return { ok: false, error: "INVALID_JSON" };
    }
  }
}

// ---------------------------------------------------------------------------
// Helpers (private)
// ---------------------------------------------------------------------------

function stringOr(v: unknown): string {
  return typeof v === "string" ? v : "";
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function extractJsonObject(rawText: string): string | null {
  // Strip optional ```json fence first; the regex below would otherwise grab
  // the closing fence as a stray brace.
  const trimmed = rawText.trim();
  const fenceMatch = trimmed.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
  const body = fenceMatch ? fenceMatch[1].trim() : trimmed;
  const start = body.indexOf("{");
  if (start < 0) return null;
  const end = body.lastIndexOf("}");
  if (end <= start) return null;
  return body.slice(start, end + 1);
}

// Local copy of the legacy repair routine. Kept here (instead of importing
// from index.ts) so this module is self-contained for Codex review and Phase
// 2.1 doesn't pull a transitive dependency on the legacy file. If this
// duplication ever grows past two callers, extract to a shared json_repair.ts.
function repairFullJson(jsonString: string): string {
  let repaired = jsonString.trim();
  // Remove trailing commas before } or ].
  repaired = repaired.replace(/,(\s*[}\]])/g, "$1");
  // Balance braces / brackets that Claude sometimes truncates near max_tokens.
  let braceCount = 0;
  let bracketCount = 0;
  let inString = false;
  let escape = false;
  for (const char of repaired) {
    if (escape) { escape = false; continue; }
    if (char === "\\") { escape = true; continue; }
    if (char === '"') { inString = !inString; continue; }
    if (inString) continue;
    if (char === "{") braceCount++;
    if (char === "}") braceCount--;
    if (char === "[") bracketCount++;
    if (char === "]") bracketCount--;
  }
  while (bracketCount > 0) { repaired += "]"; bracketCount--; }
  while (braceCount > 0) { repaired += "}"; braceCount--; }
  return repaired;
}
