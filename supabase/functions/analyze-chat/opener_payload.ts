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

// Opener contract v2（2026-07-24 Eric 拍板）：Free 恰好三種。順序是 Free UI
// 展示序（三張實卡在前），也是推薦 fallback 的優先序。
export const OPENER_FREE_V2_TYPES = ["extend", "humor", "tease"] as const;
export const OPENER_FREE_V2_LOCKED_TYPES = ["resonate", "coldRead"] as const;
// 舊 App（缺 openerContractVersion / v1）維持 legacy 單卡，避免 Edge 先上線
// 時舊 client 把多出來的卡誤判成付費結果。
export const OPENER_FREE_V1_TYPES = ["extend"] as const;

function isOpenerType(value: string): value is OpenerType {
  return (OPENER_TYPES as readonly string[]).includes(value);
}

/**
 * `openerContractVersion` 解析：缺席／null／1 → v1；整數 >= 2 → 以目前支援
 * 的 v2 處理；字串、浮點、0、負數→ invalid（呼叫端須在 rate limit、模型與
 * 扣費前 400）。只在 opener mode 解析，不影響其他 mode。
 */
export function parseOpenerContractVersion(
  raw: unknown,
): { ok: true; version: 1 | 2 } | { ok: false } {
  if (raw == null) return { ok: true, version: 1 };
  if (typeof raw !== "number" || !Number.isInteger(raw)) {
    return { ok: false };
  }
  if (raw === 1) return { ok: true, version: 1 };
  if (raw >= 2) return { ok: true, version: 2 };
  return { ok: false };
}

/**
 * 五種 opener 完整性檢查（tier filter 前的 completeness gate）。回傳清洗後
 * 仍缺句的風格清單；空陣列＝五種俱全。
 */
export function missingOpenerTypes(
  parsed: Record<string, unknown>,
): OpenerType[] {
  const rawOpeners = isPlainObject(parsed.openers) ? parsed.openers : {};
  return OPENER_TYPES.filter(
    (type) => sanitizeOpenerText(rawOpeners[type]) === null,
  );
}

/**
 * Server 權威 access metadata：client 不可只靠「有幾張卡」猜 tier。
 * visibleTypes 依 tier 展示序排列；lockedTypes 是本 tier 看不到的風格。
 */
export function buildOpenerAccess(opts: {
  contractVersion: 1 | 2;
  servedTier: string;
  visibleTypes: readonly OpenerType[];
}): {
  contractVersion: 1 | 2;
  servedTier: string;
  visibleTypes: OpenerType[];
  lockedTypes: OpenerType[];
} {
  const visible = new Set(opts.visibleTypes);
  return {
    contractVersion: opts.contractVersion,
    servedTier: opts.servedTier,
    visibleTypes: [...opts.visibleTypes],
    lockedTypes: OPENER_TYPES.filter((type) => !visible.has(type)),
  };
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

  // Raw formulaOpeners 絕不穿透（2026-07-24 公式回覆計畫 §6.2 第一層）：
  // canonical 公式由 handler 用 normalizeFormulaReplies 另行計算，
  // response 再明確覆蓋（第二層）。
  const { formulaOpeners: _rawFormulaOpeners, ...rest } = parsed;
  return {
    ...rest,
    openers,
  };
}

export function filterOpenerPayloadForAllowedFeatures(
  parsed: Record<string, unknown>,
  allowedFeatures: readonly string[],
  options?: { fallbackOrder?: readonly OpenerType[] },
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

  // 模型 schema 只吐 recommendation.pick（live client 也只讀這欄）。contract
  // v2 起 nested recommendation 與可見 openers 一起 canonicalize：pick 一定
  // 指向 tier 可見且清洗後有句的風格；fallback 時依 tier 展示序取第一個完整
  // opener，並清掉只適用原鎖定內容的 reason（nested＋頂層一起清，不得只寫
  // 頂層 legacy recommendedPick 卻留下舊 nested pick）。
  const modelPick = isPlainObject(parsed.recommendation) &&
      typeof parsed.recommendation.pick === "string" &&
      isOpenerType(parsed.recommendation.pick)
    ? parsed.recommendation.pick
    : null;

  const modelPickVisible = modelPick !== null && !!openers[modelPick];

  const fallbackOrder = options?.fallbackOrder ?? OPENER_TYPES;
  const legacyTopLevelPick = typeof parsed.recommendedPick === "string" &&
      isOpenerType(parsed.recommendedPick) &&
      openers[parsed.recommendedPick]
    ? parsed.recommendedPick
    : null;

  const recommendedPick = modelPickVisible
    ? modelPick
    : legacyTopLevelPick ??
      fallbackOrder.find((type) => openers[type]) ??
      OPENER_TYPES.find((type) => openers[type]);

  if (!recommendedPick) {
    return null;
  }

  const modelReason = isPlainObject(parsed.recommendation) &&
      typeof parsed.recommendation.reason === "string" &&
      parsed.recommendation.reason.trim().length > 0
    ? parsed.recommendation.reason.trim()
    : null;
  // reason 只在模型原 pick 仍可見時保留——fallback pick 的 reason 是替被鎖
  // 內容寫的，硬套會誤導。
  const reason = modelPickVisible ? modelReason : null;

  // 同 normalizeOpenerPayload：raw formulaOpeners 不隨 ...spread 外洩。
  const { formulaOpeners: _rawFormulaOpeners, ...rest } = parsed;
  const filtered: Record<string, unknown> = {
    ...rest,
    openers,
    recommendedPick,
    recommendation: reason !== null
      ? { pick: recommendedPick, reason }
      : { pick: recommendedPick },
  };

  // 頂層 legacy recommendedReason 維持舊語意：pick 沒變才保留。
  if (filtered.recommendedPick !== parsed.recommendedPick) {
    delete filtered.recommendedReason;
  }

  return filtered;
}
