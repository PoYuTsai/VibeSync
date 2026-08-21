// supabase/functions/analyze-chat/post_process.ts
//
// Shared post-processing for analyze-chat result payloads.
//
// CONTRACT — every successful AnalyzeChat result MUST run the same
// post-processing steps before persistence and emission. Shared non-Analyze
// request shapes may also reuse this helper, but cannot bypass entitlement or
// data-quality gates.
//
// Steps applied in order:
//   1. ensureNonEmptyAnalysisOutput  — backfill missing replies / pick
//      (skipped when recognizeOnly or isMyMessageMode, same as legacy)
//   2. allowedFeatures replies filter — strip keys outside the user's tier
//   3. finalRecommendation normalize  — guarantee non-empty pick/content/
//      reason/psychology, falling back to safe defaults
//   4. sanitizeCoachActionHint        — schema-check or remove
//   5. targetProfile evidence gate    — persist only source-matched memory
//   6. healthCheck entitlement gate   — strip when tier excludes health_check
//   7. enthusiasm score calibration   — display score = ceil(raw * 0.9)
//
// Invariants:
//   I1. result.healthCheck is absent unless allowedFeatures.includes("health_check")
//   I2. Object.keys(result.replies) ⊆ allowedFeatures
//   I3. result.finalRecommendation, if present, has non-empty pick/content/
//       reason/psychology (or is normalized to safe defaults)
//   I4. result.coachActionHint is either schema-valid or absent
//   I5. result.replies is non-empty unless recognizeOnly || isMyMessageMode
//   I6. returned enthusiasm.score is the calibrated 0–90 client score

import { getSafeReplies } from "./guardrails.ts";
import { normalizeStretchLevels } from "./opener_payload.ts";

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

/// 生成文字的文字系統白名單清洗（2026-08-17 Eric 實測：冷讀卡混出俄文
/// 「простее」——Sonnet 偶發外語 token 洩漏，prompt 條款擋不乾淨）。
/// 只套「模型生成」的欄位；sourceMessage、OCR content、球清單等引用
/// 使用者對話的欄位不得套用——對方真的用外文聊天是合法資料。
/// 只掃已知洩漏面（希臘、西里爾、希伯來、阿拉伯、天城文、泰文、諺文）；
/// CJK、假名（台灣常見「の」）、拉丁、數字、標點與 emoji 全保留。
/// 清法是「丟整個子句」而不是只摳外語詞：外語詞常是句子的謂語，摳掉會
/// 留殘句（「應該比妳自己糾結怎麼約[простее]」缺謂語，2026-08-17 Eric
/// 回饋）。整段只剩外語子句時才退回摳字，寧可短也不要空。
const FOREIGN_SCRIPT_CHAR =
  /[\u0370-\u03FF\u0400-\u052F\u0590-\u05FF\u0600-\u06FF\u0900-\u097F\u0E00-\u0E7F\u1100-\u11FF\u3130-\u318F\uAC00-\uD7AF]/;

export function stripForeignScriptChars(value: string): string {
  if (!FOREIGN_SCRIPT_CHAR.test(value)) {
    return value;
  }
  const clauses = value.split(/(?<=[，。！？；、!?…\n])/);
  let result = clauses
    .filter((clause) => !FOREIGN_SCRIPT_CHAR.test(clause))
    .join("")
    // 丟尾子句後殘留的逗頓號收掉；句號驚嘆號是完整句尾，保留。
    .replace(/[，、；,;]\s*$/, "");
  if (result.trim().length === 0) {
    result = value.replace(
      new RegExp(FOREIGN_SCRIPT_CHAR.source + "+", "g"),
      "",
    );
  }
  return result.replace(/[^\S\n]{2,}/g, " ").trim();
}

function normalizeReplyTextValue(value: unknown): string {
  if (typeof value === "string") {
    return stripForeignScriptChars(normalizeAiText(value));
  }

  if (!value || typeof value !== "object") {
    return "";
  }

  const record = value as Record<string, unknown>;
  const direct = stripForeignScriptChars(normalizeAiText(
    record.reply ?? record.content ?? record.text ?? record.suggestion,
  ));
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
  // 呼叫端全是生成欄位（approach／coachActionHint），一律清外語洩漏。
  const normalized = stripForeignScriptChars(normalizeAiText(value))
    .replace(/\s+/g, " ");
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
  // 方案二件1 D1：球判準 cap 3→5，server 端同步放寬。
  for (const item of value.slice(0, 5)) {
    if (!item || typeof item !== "object") {
      continue;
    }

    const record = item as Record<string, unknown>;
    // reply／label／reason 是生成欄位要清外語；sourceMessage 引用原文不清。
    const reply = stripForeignScriptChars(normalizeAiText(record.reply));
    if (reply.length === 0) {
      continue;
    }

    const rawSourceIndex = Number(record.sourceIndex);
    const sourceIndex = Number.isFinite(rawSourceIndex) && rawSourceIndex > 0
      ? Math.floor(rawSourceIndex)
      : undefined;

    segments.push({
      ...(sourceIndex != null ? { sourceIndex } : {}),
      label: stripForeignScriptChars(normalizeAiText(record.label))
        .slice(0, 24),
      sourceMessage: normalizeAiText(record.sourceMessage).slice(0, 120),
      reply,
      reason: stripForeignScriptChars(normalizeAiText(record.reason))
        .slice(0, 120),
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

export type BallListMessage = {
  isFromMe?: unknown;
  content?: unknown;
  blockType?: unknown;
};

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

// ---------------------------------------------------------------------------
// targetProfile evidence contract
//
// targetProfile 會跨對話持久化，並回灌後續分析／新話題；它不是本輪描述。
// 模型因此只能提出「值＋她的文字原句」，server 再把出處對回輸入。沒有
// provenance 的舊字串陣列、貼圖／emoji／媒體描述、或對不到原文的候選一律
// 不升格。這不是關鍵字黑名單，而是跨輪記憶的資料來源契約。
// ---------------------------------------------------------------------------

export const TARGET_PROFILE_PROVENANCE_VERSION = 1;

type TargetProfileKind = "interests" | "traits" | "notes";

type PartnerEvidenceMessage = {
  content: string;
  sourceIndex: number;
};

const TARGET_PROFILE_KINDS: TargetProfileKind[] = [
  "interests",
  "traits",
  "notes",
];

const MEDIA_ONLY_MARKER =
  /(?:貼圖|表情符號|emoji|sticker|photo|image|照片|圖片|影片|語音|通話|missed|ringtone)/i;
const STABLE_DECLARATION_CUE =
  /(?:喜歡|很愛|熱愛|討厭|不喜歡|興趣|平常|常常|通常|每天|每週|每個週末|固定|有在|習慣|都會|最近在學|養了?|家裡有)/;
const INTEREST_CUE =
  /(?:不是(?:很|超|最|熱)?愛|不是喜歡|不(?:太|怎麼)?(?:喜歡|愛)|不(?:常常|常|通常|每天|每週|固定|會|想|養)|不感興趣|沒(?:有)?(?:很|那麼)?喜歡|沒(?:有)?興趣|沒(?:有)?(?:在|每天|每週|固定|常常|通常|都會|養)|討厭|無興趣|喜歡|(?:很|超|最|熱)?愛|興趣|平常|常常|通常|每天|每週|每個週末|固定|有在|習慣|都會|最近在學|養了?|家裡有)/g;
const NEGATED_INTEREST_CUE = /^(?:不是|不|沒|討厭|無)/;
const INTEREST_CLAUSE_BREAK =
  /(?:[，,。；;！!？?\n]+|但(?:是)?|可是|不過|而是)/;

function meaningfulText(value: string): string {
  return [...value]
    .filter((char) => /[\p{L}\p{N}]/u.test(char))
    .join("")
    .toLowerCase();
}

function isSubstantiveProfileEvidence(value: string): boolean {
  const normalized = normalizeAiText(value);
  if (meaningfulText(normalized).length < 2) return false;
  if (
    MEDIA_ONLY_MARKER.test(normalized) &&
    !STABLE_DECLARATION_CUE.test(normalized)
  ) {
    return false;
  }
  return true;
}

function sourceMessagesForTargetProfile({ result, requestMessages }: {
  result?: Record<string, unknown>;
  requestMessages?: BallListMessage[];
}): PartnerEvidenceMessage[] {
  const recognized = (result?.recognizedConversation as
    | Record<string, unknown>
    | undefined)?.messages;
  const raw =
    (Array.isArray(recognized) && recognized.length > 0
      ? recognized
      : (requestMessages ?? [])) as BallListMessage[];

  const messages: PartnerEvidenceMessage[] = [];
  raw.forEach((item, sourceIndex) => {
    if (!item || typeof item !== "object") return;
    if (item.isFromMe !== false || item.blockType === "quoted_preview") return;
    const content = normalizeAiText(item.content);
    if (!isSubstantiveProfileEvidence(content)) return;
    messages.push({ content, sourceIndex });
  });
  return messages;
}

function normalizeTargetProfileValue(
  value: unknown,
  kind: TargetProfileKind,
): string {
  const maxLength = kind === "notes" ? 80 : 32;
  return clampNormalizedText(value, maxLength);
}

function evidenceMatchesSource(
  evidence: string,
  source: PartnerEvidenceMessage,
): boolean {
  return textMatchesBall(evidence, source.content);
}

function valueCoverage(value: string, sourceMessage: string): number {
  const valueChars = [...meaningfulText(value)];
  const sourceChars = [...meaningfulText(sourceMessage)];
  if (valueChars.length === 0) return 0;
  let matched = 0;
  for (const sourceChar of sourceChars) {
    if (sourceChar === valueChars[matched]) matched += 1;
    if (matched >= valueChars.length) break;
  }
  return matched / valueChars.length;
}

function sourceDirectlyNamesValue(
  value: string,
  sourceMessage: string,
): boolean {
  const normalizedValue = meaningfulText(value);
  const normalizedSource = meaningfulText(sourceMessage);
  return normalizedValue.length >= 2 &&
    normalizedSource.includes(normalizedValue);
}

function sourceDeclaresInterest(value: string, sourceMessage: string): boolean {
  const normalizedValue = meaningfulText(value);
  if (normalizedValue.length === 0) return false;
  for (const rawClause of sourceMessage.split(INTEREST_CLAUSE_BREAK)) {
    const clause = meaningfulText(rawClause);
    let searchFrom = 0;
    while (searchFrom <= clause.length - normalizedValue.length) {
      const valueIndex = clause.indexOf(normalizedValue, searchFrom);
      if (valueIndex < 0) break;
      const before = clause.slice(0, valueIndex);
      const after = clause.slice(valueIndex + normalizedValue.length);
      const beforeCues = before.match(INTEREST_CUE) ?? [];
      const afterCues = after.match(INTEREST_CUE) ?? [];
      const nearestCue = beforeCues[beforeCues.length - 1] ?? afterCues[0];
      // declaration cue 必須跟 value 在同一個語意小句；這同時保住
      // 「不喜歡爬山，但喜歡潛水」，並擋住「喜歡爬山，但潛水很危險」
      // 或「潛水我不喜歡」被錯標成潛水興趣。
      if (nearestCue != null && !NEGATED_INTEREST_CUE.test(nearestCue)) {
        return true;
      }
      searchFrom = valueIndex + normalizedValue.length;
    }
  }
  return false;
}

function sourceSelfDeclaresTrait(
  value: string,
  sourceMessage: string,
): boolean {
  const normalizedValue = meaningfulText(value);
  const normalizedSource = meaningfulText(sourceMessage);
  if (normalizedValue.length < 2) return false;
  return [
    `我是${normalizedValue}`,
    `我就是${normalizedValue}`,
    `我其實${normalizedValue}`,
    `我其實很${normalizedValue}`,
    `我很${normalizedValue}`,
    `我算${normalizedValue}`,
    `我算是${normalizedValue}`,
    `我比較${normalizedValue}`,
    `我有點${normalizedValue}`,
    `我蠻${normalizedValue}`,
    `我滿${normalizedValue}`,
    `我超${normalizedValue}`,
    `我個性${normalizedValue}`,
    `我的個性${normalizedValue}`,
    `我是個${normalizedValue}`,
    `我這個人${normalizedValue}`,
  ].some((pattern) => normalizedSource.includes(pattern));
}

function isSupportedTargetProfileCandidate({
  kind,
  value,
  evidence,
}: {
  kind: TargetProfileKind;
  value: string;
  evidence: PartnerEvidenceMessage[];
}): boolean {
  if (evidence.length === 0) return false;

  if (kind === "interests") {
    return evidence.some((source) =>
      sourceDirectlyNamesValue(value, source.content) &&
      sourceDeclaresInterest(value, source.content)
    );
  }

  if (kind === "notes") {
    return evidence.some((source) =>
      valueCoverage(value, source.content) >= 0.8
    );
  }

  // trait 只接受她直接自述。兩句真實原文只能證明「她說過這兩句」，server
  // 無法可靠判斷它們是否共同支持「幽默自信」等抽象人格；一律不替模型
  // 升格，避免把無關跨回合訊息寫進 v1 可信記憶。
  return evidence.some((source) =>
    sourceSelfDeclaresTrait(value, source.content)
  );
}

function sanitizeTargetProfileCandidates({
  rawCandidates,
  kind,
  sources,
}: {
  rawCandidates: unknown;
  kind: TargetProfileKind;
  sources: PartnerEvidenceMessage[];
}): Array<{ value: string; sourceMessages: string[] }> {
  if (!Array.isArray(rawCandidates)) return [];
  const accepted: Array<{ value: string; sourceMessages: string[] }> = [];
  const seenValues = new Set<string>();

  for (const rawCandidate of rawCandidates.slice(0, 5)) {
    // Legacy string arrays deliberately fail closed: they have no auditable
    // source and must not be re-labelled as verified by the server.
    if (
      !rawCandidate || typeof rawCandidate !== "object" ||
      Array.isArray(rawCandidate)
    ) {
      continue;
    }
    const candidate = rawCandidate as Record<string, unknown>;
    const value = normalizeTargetProfileValue(candidate.value, kind);
    if (value.length === 0) continue;
    const valueKey = meaningfulText(value);
    if (valueKey.length < 2 || seenValues.has(valueKey)) continue;

    const rawEvidence = Array.isArray(candidate.evidence)
      ? candidate.evidence
      : [];
    const matched: PartnerEvidenceMessage[] = [];
    const matchedIndices = new Set<number>();
    for (const item of rawEvidence.slice(0, 2)) {
      const evidenceText = normalizeAiText(item);
      if (!isSubstantiveProfileEvidence(evidenceText)) continue;
      const source = sources.find((candidateSource) =>
        !matchedIndices.has(candidateSource.sourceIndex) &&
        evidenceMatchesSource(evidenceText, candidateSource)
      );
      if (!source) continue;
      matched.push(source);
      matchedIndices.add(source.sourceIndex);
    }

    if (
      !isSupportedTargetProfileCandidate({
        kind,
        value,
        evidence: matched,
      })
    ) {
      continue;
    }

    seenValues.add(valueKey);
    accepted.push({
      value,
      sourceMessages: matched.map((source) => source.content.slice(0, 200)),
    });
  }
  return accepted;
}

export function sanitizeTargetProfile({
  rawProfile,
  result,
  requestMessages,
}: {
  rawProfile: unknown;
  result?: Record<string, unknown>;
  requestMessages?: BallListMessage[];
}): Record<string, unknown> | undefined {
  if (
    !rawProfile || typeof rawProfile !== "object" || Array.isArray(rawProfile)
  ) {
    return undefined;
  }
  const profile = rawProfile as Record<string, unknown>;
  const sources = sourceMessagesForTargetProfile({ result, requestMessages });
  const evidence = Object.fromEntries(
    TARGET_PROFILE_KINDS.map((kind) => [
      kind,
      sanitizeTargetProfileCandidates({
        rawCandidates: profile[kind],
        kind,
        sources,
      }),
    ]),
  ) as Record<
    TargetProfileKind,
    Array<{ value: string; sourceMessages: string[] }>
  >;

  return {
    provenanceVersion: TARGET_PROFILE_PROVENANCE_VERSION,
    interests: evidence.interests.map((item) => item.value),
    traits: evidence.traits.map((item) => item.value),
    notes: evidence.notes.map((item) => item.value),
    evidence,
  };
}

function normalizeForBallMatch(value: string): string {
  return value.replace(/\s+/g, "").toLowerCase();
}

function textMatchesBall(target: string, ball: string): boolean {
  const normalizedTarget = normalizeForBallMatch(target);
  const normalizedBall = normalizeForBallMatch(ball);
  return normalizedBall === normalizedTarget ||
    (normalizedTarget.length >= 4 &&
      normalizedBall.includes(normalizedTarget)) ||
    (normalizedBall.length >= 4 && normalizedTarget.includes(normalizedBall));
}

// 件5 contract 堵漏：回傳全部匹配的球（0-based）。完整原文引用（exact）
// 優先於 containment——球清單有重疊球（OCR dedup）時，整句引用不該被
// containment 撞出第二顆球而誤判 ambiguous。
function matchBallIndices(target: string, ballList: string[]): number[] {
  const normalizedTarget = normalizeForBallMatch(target);
  const exact: number[] = [];
  const fuzzy: number[] = [];
  ballList.forEach((ball, index) => {
    if (normalizeForBallMatch(ball) === normalizedTarget) {
      exact.push(index);
    } else if (textMatchesBall(target, ball)) {
      fuzzy.push(index);
    }
  });
  return exact.length > 0 ? exact : fuzzy;
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
        // 件5：同時匹配 ≥2 顆不同的球 = 「球A / 球B」併球指紋 → 不放行修復。
        const matches = matchBallIndices(sourceMessage, ballList);
        if (matches.length === 1) sourceIndex = matches[0] + 1;
      }
    } else if (sourceMessage.length > 0) {
      // r1-P2b + 件5：message 是 UI 引用與 #13 回填的主鍵。
      // 唯一匹配自己的球 → 原樣放行（片段引用）；唯一匹配別顆球 → 信
      // message 修 index；0 匹配（幻覺引用）或 ≥2 匹配（併球指紋）→ 以
      // index 球 canonical 回填，絕不流出假引用或串接引用。
      const matches = matchBallIndices(sourceMessage, ballList);
      if (matches.length === 1) {
        if (matches[0] !== sourceIndex! - 1) sourceIndex = matches[0] + 1;
      } else {
        sourceMessage = ballList[sourceIndex! - 1].slice(0, 120);
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

/**
 * Product calibration for the user-visible 「對方這次的投入度」 score.
 *
 * Claude's raw score remains available during reasoning. Only the finalized
 * response is scaled, so this does not silently change reply selection,
 * safety fallbacks, or model prompts. Fractional results always round up:
 * 82 -> 73.8 -> 74.
 */
export function calibrateEnthusiasmScore(value: unknown): number | null {
  if (
    typeof value !== "number" &&
    (typeof value !== "string" || value.trim().length === 0)
  ) {
    return null;
  }
  const numeric = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(numeric)) return null;
  const boundedRawScore = Math.max(0, Math.min(100, numeric));
  return Math.ceil(boundedRawScore * 0.9);
}

function applyEnthusiasmScoreCalibration(
  result: Record<string, unknown>,
): void {
  if (
    typeof result.enthusiasm !== "object" ||
    result.enthusiasm === null ||
    Array.isArray(result.enthusiasm)
  ) {
    return;
  }

  const enthusiasm = result.enthusiasm as Record<string, unknown>;
  const calibrated = calibrateEnthusiasmScore(enthusiasm.score);
  if (calibrated === null) return;
  result.enthusiasm = { ...enthusiasm, score: calibrated };
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
  const preferredContent = stripForeignScriptChars(normalizeAiText(
    (result.finalRecommendation as Record<string, unknown> | undefined)
      ?.content,
  ));
  const preferredReason = stripForeignScriptChars(normalizeAiText(
    (result.finalRecommendation as Record<string, unknown> | undefined)?.reason,
  ));
  const preferredPsychology = stripForeignScriptChars(normalizeAiText(
    (result.finalRecommendation as Record<string, unknown> | undefined)
      ?.psychology,
  ));
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
  // r1-P2a：多球（contract 後 ≥2 段）且 pick 未被 remap 時，舊 client 合併版
  // 必須是段落換行 join（規格 #4），不得被逗點 replies[pick] 蓋掉；
  // 單段維持既有 precedence（規格 #2 N=1 現狀）。
  const fallbackContent =
    contractSegments.length >= 2 && preferredPick === fallbackPick
      ? segmentMappedContent
      : (replyMappedContent.length > 0
        ? replyMappedContent
        : (preferredPick === fallbackPick
          ? (preferredContent.length > 0
            ? preferredContent
            : segmentMappedContent)
          : ""));
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

  // Step 2b — 2026-08 關於我重新定位案 批3：stretchLevels 先用跟 openers／
  // streaming 同一個 normalizeStretchLevels（單一事實來源）補齊全部五種
  // 風格＋值域白名單（缺欄或不合法值 fallback within，不整包拒絕），
  // 再比照 replies 做 tier 過濾，鎖定風格的延伸標記不外洩。
  const normalizedStretchLevels = normalizeStretchLevels(result);
  const filteredStretchLevels: Record<string, string> = {};
  for (const [key, value] of Object.entries(normalizedStretchLevels)) {
    if (allowedFeatures.includes(key)) {
      filteredStretchLevels[key] = value;
    }
  }
  result.stretchLevels = filteredStretchLevels;

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
    // r1-P2a：多球時合併版以段落換行 join 優先（規格 #4）——contract 段
    // 只可能來自 pick 未 remap 的 preferred segments 或 safe pick 自己的
    // replyOptions messages，無 pick 錯配風險；單段維持既有 precedence。
    const safeRecommendationContent = contractRecommendationSegments.length >= 2
      ? segmentRecommendationContent
      : normalizeAiText(
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

  // Step 3b — 風格卡則數對齊最終建議（2026-08-17 Eric）：五張風格卡的
  // messages 多於 finalRecommendation.replySegments 段數時裁掉多出的；
  // 少的無法無中生有補段，維持原樣（既知限制）。舊 client 合併版
  // replies[style] 同步用裁後訊息重建，兩種顯示路徑則數一致。
  const finalSegmentCount = Array.isArray(
      (result.finalRecommendation as { replySegments?: unknown } | undefined)
        ?.replySegments,
    )
    ? (result.finalRecommendation as { replySegments: unknown[] })
      .replySegments.length
    : 0;
  if (enforceSegmentContract && finalSegmentCount > 0 && result.replyOptions) {
    const options = result.replyOptions as Record<
      string,
      { approach?: string; messages?: { reply?: string }[] }
    >;
    const replies = (result.replies ?? {}) as Record<string, string>;
    for (const [feature, option] of Object.entries(options)) {
      const messages = Array.isArray(option?.messages) ? option.messages : [];
      if (messages.length <= finalSegmentCount) continue;
      option.messages = messages.slice(0, finalSegmentCount);
      const joined = option.messages
        .map((message) => (message?.reply ?? "").trim())
        .filter((reply) => reply.length > 0)
        .join("\n");
      if (joined.length > 0) {
        replies[feature] = joined;
      }
    }
    result.replies = replies;
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

  // Step 4b — targetProfile 是會跨輪回灌的長期記憶，必須先通過可核對
  // 出處契約；本輪策略／貼圖觀察不能直接原樣落盤。
  const sanitizedTargetProfile = sanitizeTargetProfile({
    rawProfile: result?.targetProfile,
    result,
    requestMessages,
  });
  if (sanitizedTargetProfile) {
    result.targetProfile = sanitizedTargetProfile;
  } else {
    delete result.targetProfile;
  }

  // Step 5 — healthCheck entitlement gate.
  if (!allowedFeatures.includes("health_check")) {
    delete result.healthCheck;
  }

  // Step 6 — calibrate only the finalized user-visible score. This runs after
  // fallback selection so the 0.9 display adjustment cannot alter AI advice.
  applyEnthusiasmScoreCalibration(result);

  return result;
}
