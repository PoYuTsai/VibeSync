// 新話題（破冰腦力）payload helpers（2026-07-24 計畫 §5/§10.2）。
//
// 純 helper：不 import Edge server、不碰 DB。職責＝strict request sanitize、
// situation enum normalize、模型輸出 normalize＋完整性驗證、server topicId
// 配置、Free/Paid 投影與 ledger result 驗證。
//
// 鐵則：任何缺欄、空白、超長、重複、項數不是五、推薦不存在、raw JSON／
// code fence 修不回，都必須整份失敗；不可丟掉壞題後照樣扣 3。

export const NEW_TOPIC_SITUATIONS = [
  "went_cold",
  "after_date",
  "stuck",
  "warm_up",
] as const;

export type NewTopicSituation = typeof NEW_TOPIC_SITUATIONS[number];

export const NEW_TOPIC_PARTNER_SUMMARY_MAX = 2000;
export const NEW_TOPIC_STYLE_CONTEXT_MAX = 1200;

export const NEW_TOPIC_FIELD_CAPS = {
  direction: 80,
  openingLine: 180,
  whyItWorks: 400,
  nextMove: 300,
  recommendationReason: 300,
} as const;

export const NEW_TOPIC_TOPIC_COUNT = 5;

// 公式新話題（2026-07-24 公式回覆計畫 §3/§7.2）：ledger 選填第四鍵，
// canonical 0–2 則；cap 以 Unicode code points 計（TS [...text].length＝
// PostgreSQL char_length()＝Dart runes.length）。
export const NEW_TOPIC_FORMULA_MAX_COUNT = 2;
export const NEW_TOPIC_FORMULA_CAPS = {
  openingLine: 180,
  whyItWorks: 300,
} as const;

export type NewTopicFormulaReply = {
  openingLine: string;
  whyItWorks: string;
};

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const TOPIC_ID_PATTERN = /^nt_[1-5]$/;

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function blankToNull(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length === 0 ? null : trimmed;
}

// ---------------------------------------------------------------------------
// Request sanitize
// ---------------------------------------------------------------------------

/** new_topic request 唯一允許的業務欄位（§5.3 allowlist）。 */
const NEW_TOPIC_ALLOWED_KEYS = new Set([
  "mode",
  "requestId",
  "partnerSummary",
  "effectiveStyleContext",
  "situation",
  "expectedTier",
  "revenueCatAppUserId",
]);

export type NewTopicSanitizedRequest = {
  requestId: string;
  partnerSummary: string | null;
  effectiveStyleContext: string | null;
  situation: NewTopicSituation | null;
  expectedTier: string | null;
  revenueCatAppUserId: string | null;
};

export type NewTopicRequestSanitizeResult =
  | { ok: true; request: NewTopicSanitizedRequest }
  | { ok: false; reason: string };

/**
 * Strict allowlist sanitize（§5.3）：禁用欄位一律拒絕、不靜默忽略；
 * 未列入 allowlist 的任何業務欄位也拒絕。全部發生在 rate limit、claim、
 * 模型與扣費之前（400 路徑扣 0）。
 */
export function sanitizeNewTopicRequest(
  body: Record<string, unknown>,
): NewTopicRequestSanitizeResult {
  // 禁用欄位顯式點名（比 unknown-key 拒絕先報，錯誤訊息更可診斷）。
  if (body.images !== undefined && body.images !== null) {
    return { ok: false, reason: "images_forbidden" };
  }
  if (Array.isArray(body.messages) && body.messages.length > 0) {
    return { ok: false, reason: "messages_forbidden" };
  }
  if (body.profileInfo !== undefined && body.profileInfo !== null) {
    return { ok: false, reason: "profile_info_forbidden" };
  }
  if (body.userDraft !== undefined && body.userDraft !== null) {
    return { ok: false, reason: "user_draft_forbidden" };
  }
  if (body.recognizeOnly === true) {
    return { ok: false, reason: "recognize_only_forbidden" };
  }
  if (body.sessionContext !== undefined && body.sessionContext !== null) {
    return { ok: false, reason: "session_context_forbidden" };
  }
  if (
    body.conversationSummary !== undefined && body.conversationSummary !== null
  ) {
    return { ok: false, reason: "conversation_summary_forbidden" };
  }

  for (const key of Object.keys(body)) {
    if (NEW_TOPIC_ALLOWED_KEYS.has(key)) continue;
    // 已在上面顯式擋掉的禁用欄位若值為 null/[]/false 會落到這裡：一樣拒絕
    //（allowlist 之外的鍵不靜默忽略）。
    return { ok: false, reason: `unknown_field:${key}` };
  }

  const rawRequestId = body.requestId;
  if (typeof rawRequestId !== "string" || !UUID_PATTERN.test(rawRequestId)) {
    return { ok: false, reason: "request_id_invalid" };
  }

  if (
    body.partnerSummary !== undefined && body.partnerSummary !== null &&
    typeof body.partnerSummary !== "string"
  ) {
    return { ok: false, reason: "partner_summary_invalid" };
  }
  const partnerSummary = blankToNull(body.partnerSummary);
  if (
    partnerSummary !== null &&
    partnerSummary.length > NEW_TOPIC_PARTNER_SUMMARY_MAX
  ) {
    return { ok: false, reason: "partner_summary_too_long" };
  }

  if (
    body.effectiveStyleContext !== undefined &&
    body.effectiveStyleContext !== null &&
    typeof body.effectiveStyleContext !== "string"
  ) {
    return { ok: false, reason: "style_context_invalid" };
  }
  const effectiveStyleContext = blankToNull(body.effectiveStyleContext);
  if (
    effectiveStyleContext !== null &&
    effectiveStyleContext.length > NEW_TOPIC_STYLE_CONTEXT_MAX
  ) {
    return { ok: false, reason: "style_context_too_long" };
  }

  let situation: NewTopicSituation | null = null;
  if (body.situation !== undefined && body.situation !== null) {
    const rawSituation = blankToNull(body.situation);
    if (
      rawSituation === null ||
      !(NEW_TOPIC_SITUATIONS as readonly string[]).includes(rawSituation)
    ) {
      return { ok: false, reason: "situation_invalid" };
    }
    situation = rawSituation as NewTopicSituation;
  }

  if (
    body.expectedTier !== undefined && body.expectedTier !== null &&
    typeof body.expectedTier !== "string"
  ) {
    return { ok: false, reason: "expected_tier_invalid" };
  }
  if (
    body.revenueCatAppUserId !== undefined &&
    body.revenueCatAppUserId !== null &&
    typeof body.revenueCatAppUserId !== "string"
  ) {
    return { ok: false, reason: "revenuecat_id_invalid" };
  }

  return {
    ok: true,
    request: {
      requestId: rawRequestId.toLowerCase(),
      partnerSummary,
      effectiveStyleContext,
      situation,
      expectedTier: blankToNull(body.expectedTier),
      revenueCatAppUserId: blankToNull(body.revenueCatAppUserId),
    },
  };
}

/**
 * 三類素材（作戰板摘要／關於我風格／情境）至少一類有實質內容才可生成；
 * 全空必須在 rate limit、model、claim、charge 前回 422（§1.4）。
 */
export function hasNewTopicMaterial(request: NewTopicSanitizedRequest): boolean {
  return request.partnerSummary !== null ||
    request.effectiveStyleContext !== null ||
    request.situation !== null;
}

// ---------------------------------------------------------------------------
// 模型輸出 normalize
// ---------------------------------------------------------------------------

export type NewTopicModelTopic = {
  direction: string;
  openingLine: string;
  whyItWorks: string;
  nextMove: string;
};

export type NewTopicModelNormalizeResult =
  | {
    ok: true;
    topics: NewTopicModelTopic[];
    recommendationIndex: number;
    recommendationReason: string | null;
  }
  | { ok: false; reason: string };

/**
 * 可見文字守門：raw JSON、code fence、schema 說明洩漏一律判缺。
 * 超長不截斷——整份失敗（設計鐵則：不可修剪後照扣）。
 */
function sanitizeVisibleText(value: unknown, maxLen: number): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > maxLen) return null;
  if (trimmed.includes("```")) return null;
  if (/^[{[]/.test(trimmed)) return null;
  const lower = trimmed.toLowerCase();
  if (
    lower.includes('"topics"') ||
    lower.includes('"recommendation"') ||
    lower.includes('"openingline"') ||
    lower.includes('"whyitworks"') ||
    lower.includes('"nextmove"')
  ) {
    return null;
  }
  return trimmed;
}

/** 重複判定用 normalize：小寫＋去空白（全形空白一併吃掉）。 */
function dedupeKey(value: string): string {
  return value.toLowerCase().replace(/[\s　]+/g, "");
}

/**
 * 模型輸出完整性驗證（§5.4）：恰好五題、四欄俱全且在 cap 內、
 * direction/openingLine 不重複、recommendation.index 是 0–4 整數。
 * 任一不合格整份失敗，交由呼叫端決定 repair 或 502。
 */
export function normalizeNewTopicModelPayload(
  parsed: unknown,
): NewTopicModelNormalizeResult {
  if (!isPlainObject(parsed)) {
    return { ok: false, reason: "payload_not_object" };
  }

  const rawTopics = parsed.topics;
  if (!Array.isArray(rawTopics)) {
    return { ok: false, reason: "topics_not_array" };
  }
  if (rawTopics.length !== NEW_TOPIC_TOPIC_COUNT) {
    return { ok: false, reason: `topics_count:${rawTopics.length}` };
  }

  const topics: NewTopicModelTopic[] = [];
  const directionKeys = new Set<string>();
  const openingKeys = new Set<string>();
  for (const rawTopic of rawTopics) {
    if (!isPlainObject(rawTopic)) {
      return { ok: false, reason: "topic_not_object" };
    }
    const direction = sanitizeVisibleText(
      rawTopic.direction,
      NEW_TOPIC_FIELD_CAPS.direction,
    );
    const openingLine = sanitizeVisibleText(
      rawTopic.openingLine,
      NEW_TOPIC_FIELD_CAPS.openingLine,
    );
    const whyItWorks = sanitizeVisibleText(
      rawTopic.whyItWorks,
      NEW_TOPIC_FIELD_CAPS.whyItWorks,
    );
    const nextMove = sanitizeVisibleText(
      rawTopic.nextMove,
      NEW_TOPIC_FIELD_CAPS.nextMove,
    );
    if (!direction || !openingLine || !whyItWorks || !nextMove) {
      return { ok: false, reason: "topic_field_invalid" };
    }

    const directionKey = dedupeKey(direction);
    const openingKey = dedupeKey(openingLine);
    if (directionKeys.has(directionKey) || openingKeys.has(openingKey)) {
      return { ok: false, reason: "topic_duplicate" };
    }
    directionKeys.add(directionKey);
    openingKeys.add(openingKey);

    topics.push({ direction, openingLine, whyItWorks, nextMove });
  }

  const rawRecommendation = parsed.recommendation;
  if (!isPlainObject(rawRecommendation)) {
    return { ok: false, reason: "recommendation_missing" };
  }
  const rawIndex = rawRecommendation.index;
  if (
    typeof rawIndex !== "number" || !Number.isInteger(rawIndex) ||
    rawIndex < 0 || rawIndex >= NEW_TOPIC_TOPIC_COUNT
  ) {
    return { ok: false, reason: "recommendation_index_invalid" };
  }

  let recommendationReason: string | null = null;
  if (
    rawRecommendation.reason !== undefined && rawRecommendation.reason !== null
  ) {
    recommendationReason = sanitizeVisibleText(
      rawRecommendation.reason,
      NEW_TOPIC_FIELD_CAPS.recommendationReason,
    );
    if (recommendationReason === null) {
      return { ok: false, reason: "recommendation_reason_invalid" };
    }
  }

  return {
    ok: true,
    topics,
    recommendationIndex: rawIndex,
    recommendationReason,
  };
}

// ---------------------------------------------------------------------------
// Tier 投影＋ledger result
// ---------------------------------------------------------------------------

export type NewTopicServedTier = "free" | "starter" | "essential";

export type NewTopicLedgerTopic = NewTopicModelTopic & { id: string };

export type NewTopicAccess = {
  servedTier: NewTopicServedTier;
  limited: boolean;
  totalCount: number;
  unlockedCount: number;
  lockedCount: number;
};

export type NewTopicLedgerResult = {
  topics: NewTopicLedgerTopic[];
  recommendation: { topicId: string; reason?: string };
  access: NewTopicAccess;
  // 選填第四鍵：舊 stored row 缺席＝合法（client 解析成空清單）；新 Edge
  // 寫入的 row 一律有，值為 canonical 0–2 則。tier 投影永遠不讀它。
  formulaTopics?: NewTopicFormulaReply[];
};

/**
 * Server topicId 配置＋tier 投影（§5.5/§5.6）：
 * - `nt_1`～`nt_5` 依模型原始陣列順序配置，不因排序重算。
 * - 推薦 topic 永遠排 client response 第一位。
 * - Free 只存推薦那一題；另外四題文字不進 ledger、不進 response。
 * - Paid 五題全存（推薦在前）。
 * - formulaTopics（0–2 則 canonical，呼叫端先過 normalizeFormulaReplies）
 *   原封存入兩種 tier 的 ledger，不參與 topics counts／推薦（公式回覆
 *   計畫 §7.2）；必填讓「只回 fresh response 不進 ledger」在編譯期就露餡。
 */
export function buildNewTopicLedgerResult(opts: {
  topics: NewTopicModelTopic[];
  recommendationIndex: number;
  recommendationReason: string | null;
  servedTier: NewTopicServedTier;
  formulaTopics: NewTopicFormulaReply[];
}): NewTopicLedgerResult {
  if (opts.topics.length !== NEW_TOPIC_TOPIC_COUNT) {
    throw new Error("buildNewTopicLedgerResult: topics must be exactly 5");
  }
  if (
    !Number.isInteger(opts.recommendationIndex) ||
    opts.recommendationIndex < 0 ||
    opts.recommendationIndex >= NEW_TOPIC_TOPIC_COUNT
  ) {
    throw new Error("buildNewTopicLedgerResult: invalid recommendation index");
  }
  if (opts.formulaTopics.length > NEW_TOPIC_FORMULA_MAX_COUNT) {
    throw new Error("buildNewTopicLedgerResult: formulaTopics must be 0-2");
  }

  const withIds: NewTopicLedgerTopic[] = opts.topics.map((topic, index) => ({
    id: `nt_${index + 1}`,
    ...topic,
  }));
  const recommended = withIds[opts.recommendationIndex];

  const isFree = opts.servedTier === "free";
  const topics = isFree ? [recommended] : [
    recommended,
    ...withIds.filter((topic) => topic.id !== recommended.id),
  ];

  const recommendation: { topicId: string; reason?: string } = {
    topicId: recommended.id,
  };
  if (opts.recommendationReason !== null) {
    recommendation.reason = opts.recommendationReason;
  }

  return {
    topics,
    recommendation,
    access: {
      servedTier: opts.servedTier,
      limited: isFree,
      totalCount: NEW_TOPIC_TOPIC_COUNT,
      unlockedCount: isFree ? 1 : NEW_TOPIC_TOPIC_COUNT,
      lockedCount: isFree ? NEW_TOPIC_TOPIC_COUNT - 1 : 0,
    },
    // 新 Edge row 一律帶（即使空）；Free/Paid 存同一份、不投影。
    formulaTopics: opts.formulaTopics.map((reply) => ({
      openingLine: reply.openingLine,
      whyItWorks: reply.whyItWorks,
    })),
  };
}

const LEDGER_TOPIC_KEYS = [
  "id",
  "direction",
  "openingLine",
  "whyItWorks",
  "nextMove",
] as const;

const LEDGER_ACCESS_KEYS = [
  "servedTier",
  "limited",
  "totalCount",
  "unlockedCount",
  "lockedCount",
] as const;

// 公式欄可見文字守門（與 migration helper 同組；marker 檢查比 SQL 嚴格，
// 但 canonical 寫入端一律先過 normalizer，正常 row 不會分歧）。
function isStoredFormulaText(value: unknown, maxCodePoints: number): boolean {
  if (typeof value !== "string") return false;
  const trimmed = value.trim();
  if (trimmed.length === 0) return false;
  // cap 對 raw 字串以 code points 計，對齊 PostgreSQL char_length()。
  if ([...value].length > maxCodePoints) return false;
  if (trimmed.includes("```")) return false;
  if (/^[{[]/.test(trimmed)) return false;
  const lower = trimmed.toLowerCase();
  if (
    lower.includes('"formulaopeners"') ||
    lower.includes('"formulatopics"') ||
    lower.includes('"openingline"') ||
    lower.includes('"whyitworks"') ||
    lower.includes('"openers"') ||
    lower.includes('"topics"')
  ) {
    return false;
  }
  return true;
}

function isValidStoredFormulaReply(
  value: unknown,
): value is NewTopicFormulaReply {
  if (!isPlainObject(value)) return false;
  const keys = Object.keys(value);
  if (
    keys.length !== 2 || !("openingLine" in value) || !("whyItWorks" in value)
  ) {
    return false;
  }
  return isStoredFormulaText(
    value.openingLine,
    NEW_TOPIC_FORMULA_CAPS.openingLine,
  ) &&
    isStoredFormulaText(value.whyItWorks, NEW_TOPIC_FORMULA_CAPS.whyItWorks);
}

/**
 * Ledger／replay result 驗證（與 migration 的 validate_new_topic_result
 * 同組）：legacy 頂層恰三鍵、新 shape 恰四鍵（第四鍵只能是 formulaTopics，
 * 0–2 則深驗）、tier 投影一致、每題欄位白名單＋cap、ID 唯一且推薦存在。
 * settle 前與 replay 讀回都要過這關。
 */
export function isValidNewTopicLedgerResult(
  value: unknown,
): value is NewTopicLedgerResult {
  if (!isPlainObject(value)) return false;
  const keys = Object.keys(value);
  const hasFormula = "formulaTopics" in value;
  if (keys.length !== (hasFormula ? 4 : 3)) return false;
  if (!("topics" in value) || !("recommendation" in value)) return false;
  if (!("access" in value)) return false;

  if (hasFormula) {
    const formula = value.formulaTopics;
    if (
      !Array.isArray(formula) ||
      formula.length > NEW_TOPIC_FORMULA_MAX_COUNT ||
      !formula.every(isValidStoredFormulaReply)
    ) {
      return false;
    }
  }

  const access = value.access;
  if (!isPlainObject(access)) return false;
  const accessKeys = Object.keys(access);
  if (accessKeys.length !== LEDGER_ACCESS_KEYS.length) return false;
  for (const key of LEDGER_ACCESS_KEYS) {
    if (!(key in access)) return false;
  }
  const servedTier = access.servedTier;
  if (
    servedTier !== "free" && servedTier !== "starter" &&
    servedTier !== "essential"
  ) return false;
  if (access.totalCount !== NEW_TOPIC_TOPIC_COUNT) return false;
  const isFree = servedTier === "free";
  if (access.limited !== isFree) return false;
  if (access.unlockedCount !== (isFree ? 1 : NEW_TOPIC_TOPIC_COUNT)) {
    return false;
  }
  if (access.lockedCount !== (isFree ? NEW_TOPIC_TOPIC_COUNT - 1 : 0)) {
    return false;
  }

  const topics = value.topics;
  if (!Array.isArray(topics)) return false;
  if (topics.length !== (isFree ? 1 : NEW_TOPIC_TOPIC_COUNT)) return false;
  const seenIds = new Set<string>();
  for (const topic of topics) {
    if (!isPlainObject(topic)) return false;
    const topicKeys = Object.keys(topic);
    if (topicKeys.length !== LEDGER_TOPIC_KEYS.length) return false;
    for (const key of LEDGER_TOPIC_KEYS) {
      if (!(key in topic)) return false;
    }
    const id = topic.id;
    if (typeof id !== "string" || !TOPIC_ID_PATTERN.test(id)) return false;
    if (seenIds.has(id)) return false;
    seenIds.add(id);
    if (
      sanitizeVisibleText(topic.direction, NEW_TOPIC_FIELD_CAPS.direction) ===
        null ||
      sanitizeVisibleText(
          topic.openingLine,
          NEW_TOPIC_FIELD_CAPS.openingLine,
        ) === null ||
      sanitizeVisibleText(topic.whyItWorks, NEW_TOPIC_FIELD_CAPS.whyItWorks) ===
        null ||
      sanitizeVisibleText(topic.nextMove, NEW_TOPIC_FIELD_CAPS.nextMove) ===
        null
    ) {
      return false;
    }
  }

  const recommendation = value.recommendation;
  if (!isPlainObject(recommendation)) return false;
  const recKeys = Object.keys(recommendation);
  for (const key of recKeys) {
    if (key !== "topicId" && key !== "reason") return false;
  }
  const topicId = recommendation.topicId;
  if (typeof topicId !== "string" || !seenIds.has(topicId)) return false;
  if ("reason" in recommendation) {
    if (
      sanitizeVisibleText(
        recommendation.reason,
        NEW_TOPIC_FIELD_CAPS.recommendationReason,
      ) === null
    ) {
      return false;
    }
  }

  return true;
}
