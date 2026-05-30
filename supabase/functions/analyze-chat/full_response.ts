// supabase/functions/analyze-chat/full_response.ts
//
// Pure helpers for the two-stage analyze FULL mode.
//
// Full mode must stay independent from the quick/Core answer. The quick result
// is compared after the model returns, never injected into this prompt path.

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
