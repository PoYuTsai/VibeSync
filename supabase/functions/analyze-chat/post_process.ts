// supabase/functions/analyze-chat/post_process.ts
//
// Shared post-processing for analyze-chat result payloads.
//
// CONTRACT — both the legacy (single-pass) and full (Phase 2.1 two-stage)
// branches MUST run the same set of post-processing steps before returning
// to the client. Skipping any step in one branch creates an entitlement or
// data-quality drift between modes (e.g. Free user receives a paid-tier
// healthCheck because full mode forgot to gate it).
//
// Steps applied in order:
//   1. ensureNonEmptyAnalysisOutput  — backfill missing replies / pick
//      (skipped when recognizeOnly or isMyMessageMode, same as legacy)
//   2. allowedFeatures replies filter — strip keys outside the user's tier
//   3. finalRecommendation normalize  — guarantee non-empty pick/content/
//      reason/psychology, falling back to safe defaults
//   4. sanitizeCoachActionHint        — schema-check or remove
//   5. healthCheck entitlement gate   — strip when tier excludes health_check
//
// Invariants (must hold in BOTH modes):
//   I1. result.healthCheck is absent unless allowedFeatures.includes("health_check")
//   I2. Object.keys(result.replies) ⊆ allowedFeatures
//   I3. result.finalRecommendation, if present, has non-empty pick/content/
//       reason/psychology (or is normalized to safe defaults)
//   I4. result.coachActionHint is either schema-valid or absent
//   I5. result.replies is non-empty unless recognizeOnly || isMyMessageMode

import { getSafeReplies } from "./guardrails.ts";

// ---------------------------------------------------------------------------
// Text normalization primitives
// ---------------------------------------------------------------------------

export function looksLikeRawModelPayload(value: string): boolean {
  const trimmed = value.trim();
  if (!trimmed) return false;

  const lower = trimmed.toLowerCase();
  if (trimmed.startsWith("```") || lower.includes("```json")) {
    return true;
  }

  if (!trimmed.startsWith("{") && !trimmed.startsWith("[")) {
    return false;
  }

  return [
    '"replies"',
    '"replyoptions"',
    '"finalrecommendation"',
    '"profileanalysis"',
    '"coachactionhint"',
    '"openers"',
    '"card"',
    '"responsetype"',
  ].some((marker) => lower.includes(marker));
}

export function normalizeAiText(value: unknown): string {
  if (typeof value !== "string") {
    return "";
  }

  const normalized = value
    .replace(/\r\n/g, "\n")
    .replace(/​/g, "")
    .trim();

  return looksLikeRawModelPayload(normalized) ? "" : normalized;
}

function normalizeReplyTextValue(value: unknown): string {
  if (typeof value === "string") {
    return normalizeAiText(value);
  }

  if (!value || typeof value !== "object") {
    return "";
  }

  const record = value as Record<string, unknown>;
  const direct = normalizeAiText(
    record.reply ?? record.content ?? record.text ?? record.suggestion,
  );
  if (direct.length > 0) {
    return direct;
  }

  return sanitizeReplySegments(
    record.messages ?? record.messageGroup ?? record.replySegments,
  )
    .map((segment) => segment.reply)
    .filter((reply) => reply.trim().length > 0)
    .join("\n")
    .trim();
}

function clampNormalizedText(value: unknown, maxLength: number): string {
  const normalized = normalizeAiText(value).replace(/\s+/g, " ");
  return normalized.length > maxLength
    ? normalized.slice(0, maxLength).trim()
    : normalized;
}

// ---------------------------------------------------------------------------
// Reply / replyOptions sanitization
// ---------------------------------------------------------------------------

export function sanitizeReplies(
  rawReplies: unknown,
  allowedFeatures: string[],
): Record<string, string> {
  if (!rawReplies || typeof rawReplies !== "object") {
    return {};
  }

  const filteredReplies: Record<string, string> = {};
  for (const feature of allowedFeatures) {
    const value = normalizeReplyTextValue(
      (rawReplies as Record<string, unknown>)[feature],
    );
    if (value.length > 0) {
      filteredReplies[feature] = value;
    }
  }

  return filteredReplies;
}

export function sanitizeReplySegments(value: unknown) {
  if (!Array.isArray(value)) {
    return [];
  }

  const segments = [];
  for (const item of value.slice(0, 3)) {
    if (!item || typeof item !== "object") {
      continue;
    }

    const record = item as Record<string, unknown>;
    const reply = normalizeAiText(record.reply);
    if (reply.length === 0) {
      continue;
    }

    const rawSourceIndex = Number(record.sourceIndex);
    const sourceIndex = Number.isFinite(rawSourceIndex) && rawSourceIndex > 0
      ? Math.floor(rawSourceIndex)
      : undefined;

    segments.push({
      ...(sourceIndex != null ? { sourceIndex } : {}),
      label: normalizeAiText(record.label).slice(0, 24),
      sourceMessage: normalizeAiText(record.sourceMessage).slice(0, 120),
      reply,
      reason: normalizeAiText(record.reason).slice(0, 120),
    });
  }

  return segments;
}

// ---------------------------------------------------------------------------
// #12 一球一回 — 球清單抽取 + 三層缺 source 規則
//
// 球清單 = 對方這一輪連發（trailing partner run）的訊息內容，1-based，
// 與 prompt 對 sourceIndex 的定義一致。vision 路徑優先用 OCR 結果
// recognizedConversation.messages。trailing run 為空（最後一則是我）時
// 回退最近 10 則對方訊息，讓「我已回一半再分析」的真實案例不至於全段被丟。
// ---------------------------------------------------------------------------

const BALL_LIST_FALLBACK_LIMIT = 10;

export type BallListMessage = { isFromMe?: unknown; content?: unknown };

export function extractPartnerBallList({ result, requestMessages }: {
  result?: Record<string, unknown>;
  requestMessages?: BallListMessage[];
}): string[] {
  const recognized = (result?.recognizedConversation as
    | Record<string, unknown>
    | undefined)?.messages;
  const source = Array.isArray(recognized) && recognized.length > 0
    ? recognized
    : (requestMessages ?? []);

  const trailingRun: string[] = [];
  for (let i = source.length - 1; i >= 0; i--) {
    const item = source[i];
    if (!item || typeof item !== "object") break;
    const record = item as Record<string, unknown>;
    if (record.isFromMe === true) break;
    const content = normalizeAiText(record.content);
    if (content.length > 0) trailingRun.unshift(content);
  }
  if (trailingRun.length > 0) return trailingRun;

  const fallback: string[] = [];
  for (let i = source.length - 1; i >= 0; i--) {
    const item = source[i];
    if (!item || typeof item !== "object") continue;
    const record = item as Record<string, unknown>;
    if (record.isFromMe === true) continue;
    const content = normalizeAiText(record.content);
    if (content.length > 0) fallback.unshift(content);
    if (fallback.length >= BALL_LIST_FALLBACK_LIMIT) break;
  }
  return fallback;
}

function normalizeForBallMatch(value: string): string {
  return value.replace(/\s+/g, "").toLowerCase();
}

export function enforceReplySegmentSourceContract(
  segments: ReturnType<typeof sanitizeReplySegments>,
  ballList: string[],
): ReturnType<typeof sanitizeReplySegments> {
  const repaired: ReturnType<typeof sanitizeReplySegments> = [];
  for (const segment of segments) {
    let sourceIndex = segment.sourceIndex;
    let sourceMessage = segment.sourceMessage;

    if (ballList.length === 0) {
      // 球清單不可得（防衛路徑）：只驗形狀，不驗範圍。
      if (sourceIndex != null && sourceIndex >= 1 && sourceMessage.length > 0) {
        repaired.push(segment);
      }
      continue;
    }

    const indexValid = sourceIndex != null && sourceIndex >= 1 &&
      sourceIndex <= ballList.length;

    if (!indexValid) {
      sourceIndex = undefined;
      if (sourceMessage.length > 0) {
        // 第一層：以 sourceMessage 文字回查球清單修復 sourceIndex。
        const target = normalizeForBallMatch(sourceMessage);
        const matched = ballList.findIndex((ball) => {
          const normalizedBall = normalizeForBallMatch(ball);
          return normalizedBall === target ||
            (target.length >= 4 && normalizedBall.includes(target)) ||
            (normalizedBall.length >= 4 && target.includes(normalizedBall));
        });
        if (matched >= 0) sourceIndex = matched + 1;
      }
    }

    if (sourceIndex != null && sourceMessage.length === 0) {
      sourceMessage = ballList[sourceIndex - 1].slice(0, 120);
    }

    if (sourceIndex == null || sourceMessage.length === 0) {
      // 第二層：兩者都缺 / 修不回 → drop 該段，絕不讓空 source 流出 server。
      continue;
    }

    repaired.push({ ...segment, sourceIndex, sourceMessage });
  }
  return repaired;
}

function buildReplyOptionFallbackApproach(feature: string): string {
  switch (feature) {
    case "resonate":
      return "接法：先接住她的情緒或狀態，再補一點你的感受，讓她覺得被理解。";
    case "tease":
      return "接法：用安全的誤讀或輕推拉增加互動感，但保留退路，不要突然升級。";
    case "humor":
      return "接法：用自嘲或荒謬畫面接住她的內容，讓對話變輕鬆、好回。";
    case "coldRead":
      return "接法：根據她剛說的線索做溫和猜測，留空間讓她修正或補充。";
    case "extend":
    default:
      return "接法：接住最有畫面或情緒的球，補一點你的反應，再丟回低壓下一球。";
  }
}

function sanitizeReplyOption(
  rawOption: unknown,
  feature: string,
  fallbackText = "",
) {
  const option = rawOption && typeof rawOption === "object"
    ? rawOption as Record<string, unknown>
    : {};
  const approach = clampNormalizedText(
    option.approach ?? option.strategy ?? option.why ?? option.reason,
    140,
  );
  let messages = sanitizeReplySegments(
    option.messages ?? option.messageGroup ?? option.replySegments,
  );

  if (messages.length === 0) {
    const reply = normalizeReplyTextValue(
      option.reply ?? option.content ?? option.text ?? fallbackText,
    );
    if (reply.length > 0) {
      messages = [
        {
          label: "建議訊息",
          sourceMessage: "",
          reply,
          reason: "",
        },
      ];
    }
  }

  const safeApproach = approach.length > 0
    ? approach
    : buildReplyOptionFallbackApproach(feature);

  if (messages.length === 0 && safeApproach.length === 0) {
    return undefined;
  }

  return {
    approach: safeApproach,
    messages,
  };
}

function sanitizeReplyOptions(
  rawOptions: unknown,
  allowedFeatures: string[],
  replies: Record<string, string>,
) {
  const filteredOptions: Record<
    string,
    { approach: string; messages: ReturnType<typeof sanitizeReplySegments> }
  > = {};

  const optionMap = rawOptions && typeof rawOptions === "object"
    ? rawOptions as Record<string, unknown>
    : {};

  for (const feature of allowedFeatures) {
    const option = sanitizeReplyOption(
      optionMap[feature],
      feature,
      replies[feature],
    );
    if (option != null) {
      filteredOptions[feature] = option;
    }
  }

  return filteredOptions;
}

function repliesFromReplyOptions(
  replyOptions: Record<
    string,
    { approach: string; messages: ReturnType<typeof sanitizeReplySegments> }
  >,
) {
  const replies: Record<string, string> = {};
  for (const [feature, option] of Object.entries(replyOptions)) {
    const text = option.messages
      .map((segment) => segment.reply)
      .filter((reply) => reply.trim().length > 0)
      .join("\n")
      .trim();
    if (text.length > 0) {
      replies[feature] = text;
    }
  }
  return replies;
}

// ---------------------------------------------------------------------------
// Coach action hint sanitization
// ---------------------------------------------------------------------------

const COACH_ACTION_HINT_ACTION_TYPES = new Set([
  "softInvite",
  "lowerPressureReply",
  "extendTopicStoryFrame",
  "emotionalResonance",
  "rightSizeReply",
  "playfulReply",
  "pausePursuit",
  "preferenceSignal",
  "fitCheck",
]);

const COACH_ACTION_HINT_CONFIDENCE = new Set(["high", "medium", "low"]);

export function sanitizeCoachActionHint(
  rawHint: unknown,
): Record<string, string> | undefined {
  if (!rawHint || typeof rawHint !== "object") {
    return undefined;
  }

  const hint = rawHint as Record<string, unknown>;
  const catchablePoint = clampNormalizedText(hint.catchablePoint, 80);
  const read = clampNormalizedText(hint.read, 120);
  const microMove = clampNormalizedText(hint.microMove, 120);
  const avoid = clampNormalizedText(hint.avoid, 100);
  const actionType = clampNormalizedText(hint.actionType, 40);
  const confidence = clampNormalizedText(hint.confidence, 20).toLowerCase();

  if (
    catchablePoint.length === 0 ||
    read.length === 0 ||
    microMove.length === 0 ||
    avoid.length === 0
  ) {
    return undefined;
  }

  return {
    catchablePoint,
    read,
    microMove,
    avoid,
    actionType: COACH_ACTION_HINT_ACTION_TYPES.has(actionType)
      ? actionType
      : "extendTopicStoryFrame",
    confidence: COACH_ACTION_HINT_CONFIDENCE.has(confidence)
      ? confidence
      : "medium",
  };
}

// ---------------------------------------------------------------------------
// Final recommendation fallback text
// ---------------------------------------------------------------------------

export function buildFallbackRecommendationText(
  pick: string,
): { reason: string; psychology: string } {
  switch (pick) {
    case "resonate":
      return {
        reason: "它先接住對方當下的感受，再留一個不吃力的下一球。",
        psychology: "對方會比較容易感覺你有在聽，而不是急著把話題帶走。",
      };
    case "tease":
      return {
        reason: "它有一點玩笑和張力，但沒有把尺度推太快。",
        psychology: "對方可以輕鬆接招，也保留轉回日常聊天的退路。",
      };
    case "humor":
      return {
        reason: "它用輕鬆畫面接住話題，讓對方比較容易順著笑一下再回。",
        psychology: "壓力低、畫面清楚的回覆，比硬問問題更容易延續聊天。",
      };
    case "coldRead":
      return {
        reason: "它根據對方剛給的線索做溫和猜測，讓她有空間補充或修正。",
        psychology: "好的猜測會讓對方覺得被看見，但不會像被貼標籤。",
      };
    case "extend":
    default:
      return {
        reason: "它順著目前最值得接的球往下聊，不會突然換題或查戶口。",
        psychology: "低壓、具體、好回的句子，更容易讓對方自然接下一輪。",
      };
  }
}

// ---------------------------------------------------------------------------
// Enthusiasm-to-safe-reply level (used by ensureNonEmptyAnalysisOutput)
// ---------------------------------------------------------------------------

function getSafeReplyLevelFromScore(score: number): string {
  if (score <= 30) return "cold";
  if (score <= 60) return "warm";
  if (score <= 80) return "hot";
  return "very_hot";
}

// ---------------------------------------------------------------------------
// ensureNonEmptyAnalysisOutput
//
// Backfills missing replies / finalRecommendation when the model returns
// sparse output. Skipped for recognize-only and my-message modes (same as
// the original legacy semantics — those flows don't need reply suggestions).
// ---------------------------------------------------------------------------

export function ensureNonEmptyAnalysisOutput({
  result,
  recognizeOnly,
  isMyMessageMode,
  allowedFeatures,
  ballList = [],
}: {
  result: Record<string, unknown>;
  recognizeOnly: boolean;
  isMyMessageMode: boolean;
  allowedFeatures: string[];
  ballList?: string[];
}) {
  if (recognizeOnly || isMyMessageMode) {
    return result;
  }

  const enthusiasmScore = Number(
    (result.enthusiasm as { score?: unknown } | undefined)?.score ?? 50,
  );
  let replyOptions = sanitizeReplyOptions(
    result.replyOptions,
    allowedFeatures,
    {},
  );
  let replies = sanitizeReplies(result.replies, allowedFeatures);
  if (
    Object.keys(replies).length === 0 &&
    Object.keys(replyOptions).length > 0
  ) {
    replies = repliesFromReplyOptions(replyOptions);
  }

  if (Object.keys(replies).length === 0) {
    const safeReplies = getSafeReplies(
      getSafeReplyLevelFromScore(enthusiasmScore),
    );
    replies = sanitizeReplies(safeReplies, allowedFeatures);
  }
  replyOptions = sanitizeReplyOptions(
    result.replyOptions,
    allowedFeatures,
    replies,
  );

  const preferredPick = normalizeAiText(
    (result.finalRecommendation as Record<string, unknown> | undefined)?.pick,
  );
  const preferredContent = normalizeAiText(
    (result.finalRecommendation as Record<string, unknown> | undefined)
      ?.content,
  );
  const preferredReason = normalizeAiText(
    (result.finalRecommendation as Record<string, unknown> | undefined)?.reason,
  );
  const preferredPsychology = normalizeAiText(
    (result.finalRecommendation as Record<string, unknown> | undefined)
      ?.psychology,
  );
  const preferredSegments = sanitizeReplySegments(
    (result.finalRecommendation as Record<string, unknown> | undefined)
      ?.replySegments,
  );

  const fallbackPick = preferredPick.length > 0 &&
      replies[preferredPick] != null
    ? preferredPick
    : (allowedFeatures.find(
      (feature) => (replies[feature]?.trim().length ?? 0) > 0,
    ) ?? "extend");
  const replyMappedContent = normalizeAiText(replies[fallbackPick]);
  const fallbackOptionSegments = replyOptions[fallbackPick]?.messages ?? [];
  const effectiveSegments = preferredSegments.length > 0
    ? preferredSegments
    : fallbackOptionSegments;
  // #12 一球一回：輸出段必過 source contract；第三層（全段被 drop）時
  // content 回退「現狀單段行為」用 drop 前的換行合併版。
  const contractSegments = enforceReplySegmentSourceContract(
    effectiveSegments,
    ballList,
  );
  const segmentMappedContent =
    (contractSegments.length > 0 ? contractSegments : effectiveSegments)
      .map((segment) => segment.reply)
      .join("\n");
  const fallbackContent = replyMappedContent.length > 0
    ? replyMappedContent
    : (preferredPick === fallbackPick
      ? (preferredContent.length > 0 ? preferredContent : segmentMappedContent)
      : "");
  const fallbackExplanation = buildFallbackRecommendationText(fallbackPick);
  const guaranteedContent = fallbackContent.length > 0
    ? fallbackContent
    : "先順著她這句往下接，保持自然、好回覆的節奏就好。";

  result.replies = replies;
  result.replyOptions = replyOptions;
  result.finalRecommendation = {
    pick: fallbackPick,
    content: guaranteedContent,
    reason: preferredReason.length > 0
      ? preferredReason
      : fallbackExplanation.reason,
    psychology: preferredPsychology.length > 0
      ? preferredPsychology
      : fallbackExplanation.psychology,
    replySegments: contractSegments,
  };

  return result;
}

// ---------------------------------------------------------------------------
// postProcessAnalysisResult — shared entry point
//
// Applies the 5 steps in legacy order to a checkAiOutput-guarded result.
// Caller is responsible for running checkAiOutput first, and for drift /
// observability / logging AFTER this returns.
// ---------------------------------------------------------------------------

export function postProcessAnalysisResult({
  result,
  recognizeOnly,
  isMyMessageMode,
  allowedFeatures,
  requestMessages,
}: {
  result: Record<string, unknown>;
  recognizeOnly: boolean;
  isMyMessageMode: boolean;
  allowedFeatures: string[];
  requestMessages?: BallListMessage[];
}): Record<string, unknown> {
  // #12 一球一回：球清單供 replySegments source contract 驗證/修復。
  // recognizeOnly / my-message 不產 segments，contract 不啟用（防誤傷）。
  const enforceSegmentContract = !recognizeOnly && !isMyMessageMode;
  const ballList = enforceSegmentContract
    ? extractPartnerBallList({ result, requestMessages })
    : [];

  // Step 1 — backfill empty fields (no-op for recognizeOnly / my-message).
  result = ensureNonEmptyAnalysisOutput({
    result,
    recognizeOnly,
    isMyMessageMode,
    allowedFeatures,
    ballList,
  });

  // Step 2 — entitlement: replies must be a subset of allowedFeatures.
  if (result?.replies) {
    const filteredReplies: Record<string, string> = {};
    for (const [key, value] of Object.entries(result.replies)) {
      if (allowedFeatures.includes(key)) {
        filteredReplies[key] = value as string;
      }
    }
    result.replies = filteredReplies;
  }

  // Step 3 — finalRecommendation normalization w/ safe fallbacks.
  if (result?.finalRecommendation) {
    const recommendation = result.finalRecommendation as Record<
      string,
      unknown
    >;
    const normalizedRecommendationPick = normalizeAiText(recommendation.pick);
    const normalizedRecommendationReason = normalizeAiText(
      recommendation.reason,
    );
    const normalizedRecommendationPsychology = normalizeAiText(
      recommendation.psychology,
    );
    const normalizedReplies = (result.replies ?? {}) as Record<
      string,
      string
    >;
    const safeRecommendationPick = normalizedRecommendationPick.length > 0 &&
        normalizedReplies[normalizedRecommendationPick]?.trim().length
      ? normalizedRecommendationPick
      : (allowedFeatures.find((feature) =>
        (normalizedReplies[feature]?.trim().length ?? 0) > 0
      ) ?? "extend");
    const normalizedRecommendationSegments =
      normalizedRecommendationPick === safeRecommendationPick
        ? sanitizeReplySegments(recommendation.replySegments)
        : [];
    const normalizedReplyOptions = (result.replyOptions ?? {}) as Record<
      string,
      { messages?: unknown }
    >;
    const fallbackOptionSegments = sanitizeReplySegments(
      normalizedReplyOptions[safeRecommendationPick]?.messages,
    );
    const safeRecommendationSegments =
      normalizedRecommendationSegments.length > 0
        ? normalizedRecommendationSegments
        : fallbackOptionSegments;
    // #12 一球一回：同 ensureNonEmpty——輸出段過 source contract，
    // 全段被 drop 時 content 回退 drop 前合併版（現狀單段行為）。
    const contractRecommendationSegments = enforceSegmentContract
      ? enforceReplySegmentSourceContract(safeRecommendationSegments, ballList)
      : safeRecommendationSegments;
    const segmentRecommendationContent = (contractRecommendationSegments
          .length > 0
      ? contractRecommendationSegments
      : safeRecommendationSegments)
      .map((segment) => segment.reply)
      .filter((reply) => reply.trim().length > 0)
      .join("\n")
      .trim();
    const safeRecommendationContent = normalizeAiText(
      normalizedReplies[safeRecommendationPick],
    ) || segmentRecommendationContent ||
      (normalizedRecommendationPick === safeRecommendationPick
        ? normalizeAiText(recommendation.content)
        : "");
    const fallbackExplanation = buildFallbackRecommendationText(
      safeRecommendationPick,
    );

    result.finalRecommendation = {
      pick: safeRecommendationPick,
      content: safeRecommendationContent,
      reason: normalizedRecommendationReason.length > 0
        ? normalizedRecommendationReason
        : fallbackExplanation.reason,
      psychology: normalizedRecommendationPsychology.length > 0
        ? normalizedRecommendationPsychology
        : fallbackExplanation.psychology,
      replySegments: contractRecommendationSegments,
    };
  }

  // Step 4 — coachActionHint: schema-valid or remove.
  const sanitizedCoachActionHint = sanitizeCoachActionHint(
    result?.coachActionHint,
  );
  if (sanitizedCoachActionHint) {
    result.coachActionHint = sanitizedCoachActionHint;
  } else {
    delete result.coachActionHint;
  }

  // Step 5 — healthCheck entitlement gate. THIS is the step full mode was
  // missing prior to extracting this helper (Codex Phase 2 P1).
  if (!allowedFeatures.includes("health_check")) {
    delete result.healthCheck;
  }

  return result;
}
