// Opener payload normalization / tier filtering, extracted from index.ts so
// the recommendedPick contract can be behavior-tested (index.ts starts the
// server on import and only supports source-scan tests).

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export const OPENER_TYPES = [
  "extend",
  "resonate",
  "tease",
  "humor",
  "coldRead",
] as const;

export type OpenerType = typeof OPENER_TYPES[number];

function isOpenerType(value: string): value is OpenerType {
  return (OPENER_TYPES as readonly string[]).includes(value);
}

export function sanitizeOpenerText(value: unknown): string | null {
  let text: string | null = null;

  if (typeof value === "string") {
    text = value;
  } else if (isPlainObject(value)) {
    for (const key of ["text", "message", "opener", "content", "line"]) {
      const nested = value[key];
      if (typeof nested === "string") {
        text = nested;
        break;
      }
    }
  }

  if (text == null) return null;

  const trimmed = text.trim();
  if (!trimmed) return null;

  const lower = trimmed.toLowerCase();
  if (
    trimmed.startsWith("```") ||
    trimmed.startsWith("{") ||
    trimmed.startsWith("[") ||
    lower.includes('"profileanalysis"') ||
    lower.includes('"openers"') ||
    lower.includes("```json")
  ) {
    return null;
  }

  // Opening lines are short by contract. A very long value is usually a model
  // explanation or malformed JSON that would be embarrassing to show.
  if (trimmed.length > 180) return null;

  return trimmed;
}

export function normalizeOpenerPayload(
  parsed: Record<string, unknown> | null,
): Record<string, unknown> | null {
  if (!parsed) return null;

  const rawOpeners = isPlainObject(parsed.openers) ? parsed.openers : {};
  const openers: Record<string, string> = {};

  for (const type of OPENER_TYPES) {
    const opener = sanitizeOpenerText(rawOpeners[type]);
    if (opener) {
      openers[type] = opener;
    }
  }

  if (Object.keys(openers).length === 0) {
    return null;
  }

  return {
    ...parsed,
    openers,
  };
}

export function filterOpenerPayloadForAllowedFeatures(
  parsed: Record<string, unknown>,
  allowedFeatures: readonly string[],
): Record<string, unknown> | null {
  const allowedOpenerTypes = new Set(
    allowedFeatures.filter((feature): feature is OpenerType =>
      isOpenerType(feature)
    ),
  );
  const rawOpeners = isPlainObject(parsed.openers) ? parsed.openers : {};
  const openers: Record<string, string> = {};

  for (const type of OPENER_TYPES) {
    if (!allowedOpenerTypes.has(type)) continue;
    const opener = sanitizeOpenerText(rawOpeners[type]);
    if (opener) {
      openers[type] = opener;
    }
  }

  // 模型 schema 只吐 recommendation.pick（client 也只讀這欄），頂層
  // recommendedPick 必須優先對齊它，否則 fallback 注入的頂層值恆為 extend、
  // 與 recommendation.pick 在同一 response 內矛盾。openers[pick] 同時保證
  // 該風格在 tier allowed 且清洗後仍有句可用。
  const recommendationPick = isPlainObject(parsed.recommendation) &&
      typeof parsed.recommendation.pick === "string" &&
      isOpenerType(parsed.recommendation.pick) &&
      openers[parsed.recommendation.pick]
    ? parsed.recommendation.pick
    : null;

  const recommendedPick = recommendationPick ??
    (typeof parsed.recommendedPick === "string" &&
        isOpenerType(parsed.recommendedPick) &&
        openers[parsed.recommendedPick]
      ? parsed.recommendedPick
      : OPENER_TYPES.find((type) => openers[type]));

  if (!recommendedPick) {
    return null;
  }

  const filtered: Record<string, unknown> = {
    ...parsed,
    openers,
    recommendedPick,
  };

  if (filtered.recommendedPick !== parsed.recommendedPick) {
    delete filtered.recommendedReason;
  }

  return filtered;
}
