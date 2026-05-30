// supabase/functions/analyze-chat/full_response.ts
//
// Pure helpers for the two-stage analyze FULL mode.
//
// `buildFullPromptAnchor(quickResult)` prepends the quick/Core result to the
// full prompt as a candidate, not as a binding answer. This is intentional for
// internal dogfood: Eric/Bruce need to see when the fast Core result and the
// full prompt disagree so we can judge whether the Core prompt is good enough.

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
  const pick = stringOr((quickResult as QuickPayload).pick);

  return [
    "## QUICK_CANDIDATE（Core 先行建議，供 Full 對照）",
    "以下是 3-8 秒 quick 模式先給使用者看的 Core 候選答案。Full 模式要把它當參考，不是硬性答案。",
    "",
    `- nextStep: ${next}`,
    `- pick: ${pick}`,
    `- recommendedReply: ${reply}`,
    `- shortReason: ${reason}`,
    "",
    "Full 判斷規則：",
    "- 先獨立重跑完整分析，再決定 finalRecommendation.pick 與 content。",
    "- 可以沿用 quick 的 recommendedReply；如果完整 prompt 判斷 quick 不夠準，必須覆蓋它。",
    "- 不要預設 extend。finalRecommendation.pick 必須在 extend/resonate/tease/humor/coldRead 之中重新選最適合的風格。",
    "- 如果覆蓋 quick，finalRecommendation.reason 簡短說明為什麼完整分析改判。",
    "- coachActionHint.microMove 跟隨 Full 的最終判斷，不要盲目沿用 quick 的 nextStep。",
    "- replyOptions 五個風格仍要完整產出，方便 dogfood 比對 quick 與 full 差異。",
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
    if (escape) {
      escape = false;
      continue;
    }
    if (char === "\\") {
      escape = true;
      continue;
    }
    if (char === '"') {
      inString = !inString;
      continue;
    }
    if (inString) continue;
    if (char === "{") braceCount++;
    if (char === "}") braceCount--;
    if (char === "[") bracketCount++;
    if (char === "]") bracketCount--;
  }
  while (bracketCount > 0) {
    repaired += "]";
    bracketCount--;
  }
  while (braceCount > 0) {
    repaired += "}";
    braceCount--;
  }
  return repaired;
}
