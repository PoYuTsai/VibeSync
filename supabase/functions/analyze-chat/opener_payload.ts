// Opener payload normalization / tier filtering, extracted from index.ts so
// the recommendedPick contract can be behavior-tested (index.ts starts the
// server on import and only supports source-scan tests).

import {
  normalizeOutgoingMessageText,
} from "./outgoing_message_text.ts";
import { sanitizeCustomerExplanationText } from "./customer_explanation.ts";

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

const OPENER_PROFILE_EXPLANATION_KEYS = [
  "style",
  "personality",
  "avoidTopics",
  "frameRead",
  "positiveHooks",
  "masterObservation",
  "curiosityHook",
  "masterMove",
  "twoBallPlan",
  "talkingPoints",
  "openingStrategy",
  // Legacy client-visible keys.
  "vibe",
  "interests",
] as const;

const OPENER_PROFILE_ARRAY_KEYS = new Set([
  "avoidTopics",
  "positiveHooks",
  "talkingPoints",
  "interests",
]);

const OPENER_PIONEER_KEYS = [
  "ifCold",
  "ifShortPositive",
  "ifEngaged",
  "handoff",
] as const;

function sanitizeOpenerProfileAnalysis(
  value: unknown,
): Record<string, unknown> | null {
  if (!isPlainObject(value)) return null;
  const result: Record<string, unknown> = {};
  for (const key of OPENER_PROFILE_EXPLANATION_KEYS) {
    const raw = value[key];
    if (Array.isArray(raw) && OPENER_PROFILE_ARRAY_KEYS.has(key)) {
      const items = raw
        .map((item) => sanitizeCustomerExplanationText(item, 240))
        .filter((item): item is string => item !== null);
      if (items.length > 0) result[key] = items;
      continue;
    }
    const text = sanitizeCustomerExplanationText(raw, 500);
    if (text !== null) result[key] = text;
  }
  // Telemetry only; the client whitelist intentionally does not render it.
  if (typeof value.insufficientInfo === "boolean") {
    result.insufficientInfo = value.insufficientInfo;
  }
  return Object.keys(result).length > 0 ? result : null;
}

function sanitizeOpenerPioneerPlan(
  value: unknown,
): Record<string, string> | null {
  if (!isPlainObject(value)) return null;
  const result: Record<string, string> = {};
  for (const key of OPENER_PIONEER_KEYS) {
    const text = sanitizeCustomerExplanationText(value[key], 500);
    if (text !== null) result[key] = text;
  }
  return Object.keys(result).length > 0 ? result : null;
}

function sanitizeOpenerCustomerExplanations(
  parsed: Record<string, unknown>,
): Record<string, unknown> {
  const {
    profileAnalysis: _profileAnalysis,
    pioneerPlan: _pioneerPlan,
    recommendation: _recommendation,
    recommendedReason: _recommendedReason,
    ...rest
  } = parsed;
  const result: Record<string, unknown> = { ...rest };

  const profileAnalysis = sanitizeOpenerProfileAnalysis(parsed.profileAnalysis);
  if (profileAnalysis !== null) result.profileAnalysis = profileAnalysis;

  const pioneerPlan = sanitizeOpenerPioneerPlan(parsed.pioneerPlan);
  if (pioneerPlan !== null) result.pioneerPlan = pioneerPlan;

  if (isPlainObject(parsed.recommendation)) {
    const recommendation: Record<string, unknown> = {};
    if (
      typeof parsed.recommendation.pick === "string" &&
      isOpenerType(parsed.recommendation.pick)
    ) {
      recommendation.pick = parsed.recommendation.pick;
    }
    const reason = sanitizeCustomerExplanationText(
      parsed.recommendation.reason,
      500,
    );
    if (reason !== null) recommendation.reason = reason;
    if (Object.keys(recommendation).length > 0) {
      result.recommendation = recommendation;
    }
  }

  const recommendedReason = sanitizeCustomerExplanationText(
    parsed.recommendedReason,
    500,
  );
  if (recommendedReason !== null) {
    result.recommendedReason = recommendedReason;
  }
  return result;
}

// 2026-08 關於我重新定位案 批3：stretchLevels 取代批1的本地規則，改由 AI
// 自判每個 opener 相對使用者舒適區的延伸程度。缺欄或值不合法一律 fallback
// 為 "within"——絕不因為這個新欄位整包拒絕重試（避免變成新的 503 來源）。
export const STRETCH_LEVELS = ["within", "stretch", "far"] as const;
export type StretchLevel = typeof STRETCH_LEVELS[number];

function isStretchLevel(value: unknown): value is StretchLevel {
  return typeof value === "string" &&
    (STRETCH_LEVELS as readonly string[]).includes(value);
}

export function normalizeStretchLevels(
  parsed: Record<string, unknown>,
): Record<OpenerType, StretchLevel> {
  const raw = isPlainObject(parsed.stretchLevels)
    ? parsed.stretchLevels
    : {};
  const result = {} as Record<OpenerType, StretchLevel>;
  for (const type of OPENER_TYPES) {
    const value = raw[type];
    result[type] = isStretchLevel(value) ? value : "within";
  }
  return result;
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

  // 分則支援（2026-08-19 Eric：對標練習室，高手不把一坨字擠一行）：模型
  // 常吐字面 "\n" 而不是真換行（練習室已登記坑），這裡統一正規化，並把
  // 三行以上的空行壓成單一換行——開場最多兩則。
  // 五張卡都是原封複製貼上傳給對方的訊息，人稱與標點正規化見 outgoing_message_text。
  const trimmed = normalizeOutgoingMessageText(text)
    ?.trim()
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .join("\n") ?? "";
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

  // 拒答說明不是開場白（2026-08-19 真機實錄：聊天截圖誤餵 opener，模型把
  // 「截圖資訊不足，無法生成開場白，請提供…」寫進五張卡照常渲染）。第一層
  // 是 wrongSurface 旗標；這裡是模型漏設旗標時的保底——整包被清空會走
  // completeness gate 的 502 不扣費路徑，不會端廢卡。
  // R1 主審 P1：寬鬆版會誤殺合法調情句（「妳的截圖資訊不足啊，多放幾張
  // 生活照」）。收窄成拒答句形：無法生成／資訊不足接無法／「對方的…截圖」
  // （開場白對她說話用「妳」，不會出現「對方的」）。
  if (
    /無法(?:生成|產生)開場白|截圖資訊不足[，,]?\s*無法|請提供對方的.{0,12}(?:截圖|個人頁)/u
      .test(trimmed)
  ) {
    return null;
  }

  return trimmed;
}

// ── 錯圖旗標（wrongSurface）純函式層：讓 422 不扣費路徑可行為測試 ──
// R1 主審 P1：source-scan 測不到邏輯被刪；判定與回應體抽純函式釘住。

export const WRONG_SURFACE_VALUES = ["chat_conversation", "unrelated"] as const;
export type WrongSurface = typeof WRONG_SURFACE_VALUES[number];

/** 只認 primary parse 的白名單值；無圖或未知值一律 fail-open 走正常計費路。 */
export function detectOpenerWrongSurface(
  parsed: Record<string, unknown> | null,
  imageCount: number,
): WrongSurface | null {
  if (imageCount <= 0 || !parsed) return null;
  const raw = parsed.wrongSurface;
  return raw === "chat_conversation" || raw === "unrelated" ? raw : null;
}

/** 固定鍵、靜態文案：模型輸出一個字都不得進 422 body（零內容外流）。 */
export function buildWrongSurfaceErrorBody(surface: WrongSurface): {
  error: string;
  surface: WrongSurface;
  message: string;
  shouldChargeQuota: false;
} {
  return {
    error: "OPENER_WRONG_SURFACE",
    surface,
    message: surface === "chat_conversation"
      ? "這看起來是聊天對話的截圖——分析對話、找下一句怎麼回，請改用「分析對話」功能。開場救星需要對方的交友軟體或社群個人頁截圖。本次不會扣額度。"
      : "這張截圖看不出對方的個人資料。開場救星需要對方的交友軟體或社群個人頁截圖。本次不會扣額度。",
    shouldChargeQuota: false,
  };
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

  // wrongSurface 剝除（R1 主審 P2）：它是 handler 在 parse 層就消費完的
  // 旗標，healthy 200 不得殘留新鍵。
  const sanitized = sanitizeOpenerCustomerExplanations(parsed);
  const { wrongSurface: _wrongSurface, ...rest } = sanitized;
  return {
    ...rest,
    openers,
    stretchLevels: normalizeStretchLevels(parsed),
  };
}

export function filterOpenerPayloadForAllowedFeatures(
  parsed: Record<string, unknown>,
  allowedFeatures: readonly string[],
  options?: { fallbackOrder?: readonly OpenerType[] },
): Record<string, unknown> | null {
  const sanitizedParsed = sanitizeOpenerCustomerExplanations(parsed);
  const allowedOpenerTypes = new Set(
    allowedFeatures.filter((feature): feature is OpenerType =>
      isOpenerType(feature)
    ),
  );
  const rawOpeners = isPlainObject(parsed.openers) ? parsed.openers : {};
  const openers: Record<string, string> = {};
  const allStretchLevels = normalizeStretchLevels(parsed);
  const stretchLevels: Record<string, StretchLevel> = {};

  for (const type of OPENER_TYPES) {
    if (!allowedOpenerTypes.has(type)) continue;
    const opener = sanitizeOpenerText(rawOpeners[type]);
    if (opener) {
      openers[type] = opener;
      stretchLevels[type] = allStretchLevels[type];
    }
  }

  // 模型 schema 只吐 recommendation.pick（live client 也只讀這欄）。contract
  // v2 起 nested recommendation 與可見 openers 一起 canonicalize：pick 一定
  // 指向 tier 可見且清洗後有句的風格；fallback 時依 tier 展示序取第一個完整
  // opener，並清掉只適用原鎖定內容的 reason（nested＋頂層一起清，不得只寫
  // 頂層 legacy recommendedPick 卻留下舊 nested pick）。
  const modelPick = isPlainObject(sanitizedParsed.recommendation) &&
      typeof sanitizedParsed.recommendation.pick === "string" &&
      isOpenerType(sanitizedParsed.recommendation.pick)
    ? sanitizedParsed.recommendation.pick
    : null;

  const modelPickVisible = modelPick !== null && !!openers[modelPick];

  const fallbackOrder = options?.fallbackOrder ?? OPENER_TYPES;
  const legacyTopLevelPick = typeof sanitizedParsed.recommendedPick === "string" &&
      isOpenerType(sanitizedParsed.recommendedPick) &&
      openers[sanitizedParsed.recommendedPick]
    ? sanitizedParsed.recommendedPick
    : null;

  const recommendedPick = modelPickVisible
    ? modelPick
    : legacyTopLevelPick ??
      fallbackOrder.find((type) => openers[type]) ??
      OPENER_TYPES.find((type) => openers[type]);

  if (!recommendedPick) {
    return null;
  }

  const modelReason = isPlainObject(sanitizedParsed.recommendation) &&
      typeof sanitizedParsed.recommendation.reason === "string" &&
      sanitizedParsed.recommendation.reason.trim().length > 0
    ? sanitizedParsed.recommendation.reason.trim()
    : null;
  // reason 只在模型原 pick 仍可見時保留——fallback pick 的 reason 是替被鎖
  // 內容寫的，硬套會誤導。
  const reason = modelPickVisible ? modelReason : null;

  // 同 normalizeOpenerPayload：wrongSurface 不隨 ...spread 外洩。
  const { wrongSurface: _wrongSurface, ...rest } = sanitizedParsed;
  const filtered: Record<string, unknown> = {
    ...rest,
    openers,
    stretchLevels,
    recommendedPick,
    recommendation: reason !== null
      ? { pick: recommendedPick, reason }
      : { pick: recommendedPick },
  };

  // 頂層 legacy recommendedReason 維持舊語意：pick 沒變才保留。
  if (filtered.recommendedPick !== sanitizedParsed.recommendedPick) {
    delete filtered.recommendedReason;
  }

  return filtered;
}
