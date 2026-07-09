import {
  applyResetsIfNeeded,
  buildQuotaExceededPayload,
  checkQuota,
  isPlainObject,
  resolveLimits,
  type SubscriptionRow,
  TEST_EMAILS,
} from "../_shared/quota.ts";
import { enforceModelRateLimit } from "../_shared/model_rate_limit.ts";
import { validateDrawRequest, validateRequest } from "./validate.ts";
import { type DrawSupabaseClient, handleDrawProfile } from "./draw_handler.ts";
import {
  buildChatMessages,
  buildDebriefMessages,
  type ChatMessage,
} from "./prompt.ts";
import { difficultyTuningFor } from "./practice_persona.ts";
import {
  decideChatGate,
  decideContinuationGate,
  decideDebriefGate,
  decideHintGate,
  isAssistedPracticeMode,
  isSessionComplete,
  MAX_AI_REPLIES,
  MAX_DEBRIEFS,
  MAX_HINTS_PER_ROUND,
  PRACTICE_QUOTA_COST,
  type PracticeLearningMode,
  type SessionLedger,
} from "./quota_decision.ts";
import { DEEPSEEK_MODEL, type DeepSeekArgs } from "./deepseek.ts";
import {
  buildFallbackDebriefCard,
  type DebriefCard,
  parseDebriefCard,
} from "./debrief_card.ts";
import {
  buildFallbackHintResult,
  buildHintMessages,
  parseHintResult,
} from "./hint.ts";
import { buildPracticeSceneContext } from "./life_schedule.ts";
import { logError, logInfo, logWarn, summarizeUser } from "./logger.ts";
import {
  rejectL4UnsafeVisibleText,
  rejectVisibleInternalLabelLeak,
} from "./visible_text_guard.ts";
import { applyGameLearningDelta, evaluateGameFsm } from "./game_fsm.ts";
import {
  buildNextGameState,
  parsePersistedGameState,
  type PersistedGameState,
} from "./game_state.ts";
import { inviteMaturityFromLearningScores } from "./invite_maturity.ts";
import {
  buildRelationshipThreadRpcParams,
  parseRelationshipThreadRow,
  type PracticeRelationshipThreadState,
  threadIdForPracticeRequest,
} from "./relationship_thread.ts";
import {
  applyLearningClassification,
  applyPartnerStateUpdate,
  buildTurnClassifierMessages,
  clampTemperature,
  type LearningJudgement,
  parseTurnClassification,
  type PartnerMood,
  type PartnerState,
  relationshipStageFor,
  temperatureBandFor,
  type TurnClassification,
} from "./temperature.ts";
import { taipeiTimeContextFor } from "./time_context.ts";

const MAX_BODY_BYTES = 64 * 1024;
const CHAT_MAX_TOKENS = 200;
const CHAT_TEMPERATURE = 0.9;
const CHAT_GENERATION_ATTEMPTS = 2;
const DEBRIEF_MAX_TOKENS = 800;
const DEBRIEF_TEMPERATURE = 0.5;
const DEBRIEF_GENERATION_ATTEMPTS = 2;
const DEBRIEF_TIMEOUT_MS = 12000;
const HINT_MAX_TOKENS = 650;
const HINT_TEMPERATURE = 0.45;
const HINT_GENERATION_ATTEMPTS = 2;
// 9 秒：hint 有罐頭 fallback 兜底，逾時預算壓短讓用戶最壞等待更接近可忍受。
const HINT_TIMEOUT_MS = 9000;
const TEMPERATURE_JUDGE_MAX_TOKENS = 450;
const TEMPERATURE_JUDGE_TEMPERATURE = 0.2;
const DEEPSEEK_TIMEOUT_MS = 30000;

function appliedHintHeatFloor(
  appliedHintType: string | undefined,
  practiceMode: PracticeLearningMode,
): number {
  if (practiceMode === "game") {
    if (appliedHintType === "warm_up") return 2;
    if (appliedHintType === "steady") return 3;
    return Number.NEGATIVE_INFINITY;
  }
  if (appliedHintType === "warm_up") return 0;
  if (appliedHintType === "steady") return 1;
  return Number.NEGATIVE_INFINITY;
}

function appliedHintFamiliarityFloor(
  appliedHintType: string | undefined,
  practiceMode: PracticeLearningMode,
): number {
  if (practiceMode === "game") {
    if (appliedHintType === "warm_up") return 1;
    if (appliedHintType === "steady") return 2;
    return Number.NEGATIVE_INFINITY;
  }
  if (appliedHintType === "warm_up") return 0;
  if (appliedHintType === "steady") return 1;
  return Number.NEGATIVE_INFINITY;
}

function normalizedHintText(text: string): string {
  return text
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[\s\p{P}\p{S}]+/gu, "");
}

function commonSubsequenceRatio(left: string, right: string): number {
  const a = Array.from(left);
  const b = Array.from(right);
  const maxLength = Math.max(a.length, b.length);
  if (maxLength === 0) return 0;
  let previous = new Array(b.length + 1).fill(0);
  for (let i = 1; i <= a.length; i++) {
    const current = new Array(b.length + 1).fill(0);
    for (let j = 1; j <= b.length; j++) {
      current[j] = a[i - 1] === b[j - 1]
        ? previous[j - 1] + 1
        : Math.max(previous[j], current[j - 1]);
    }
    previous = current;
  }
  return previous[b.length] / maxLength;
}

function isLikelySmallHintEdit(
  request: ReturnType<typeof validateRequest>,
): boolean {
  const source = request.appliedHintText;
  if (!source) return false;
  const original = normalizedHintText(source);
  const edited = normalizedHintText(lastUserText(request.turns));
  if (!original || !edited) return false;
  if (original === edited) return true;
  return commonSubsequenceRatio(original, edited) >= 0.58;
}

function containsObviousOverstepInvite(text: string): boolean {
  const normalized = normalizedHintText(text);
  return [
    "來我家睡",
    "来我家睡",
    "去我家睡",
    "去你家睡",
    "去妳家睡",
    "開房",
    "开房",
    "上床",
    "一起睡",
    "睡你",
    "睡妳",
    "睡我",
    "sleepatmyplace",
    "comeoverandsleep",
    "sleepwithme",
  ].some((pattern) => normalized.includes(pattern));
}

function deterministicOverstepClassificationForSnapshot(opts: {
  request: ReturnType<typeof validateRequest>;
  currentTemperature: number;
  currentFamiliarity: number;
}): TurnClassification | null {
  const stage = relationshipStageFor(
    opts.currentFamiliarity,
    opts.currentTemperature,
  ).stage;
  if (
    stage !== "flirt_allowed" &&
    containsObviousOverstepInvite(lastUserText(opts.request.turns))
  ) {
    return {
      impact: "strong",
      connection: "overstepped",
      testHandling: "none",
      boundary: "overstep",
      hintAlignment: "diverged",
      partnerMood: "guarded",
      moodConfidence: 1,
      innerThought: "這個推進太快了，我會先退一步觀察。",
    };
  }
  return null;
}

function withDeterministicSafetyOverride(opts: {
  classification: TurnClassification;
  request: ReturnType<typeof validateRequest>;
  currentTemperature: number;
  currentFamiliarity: number;
}): TurnClassification {
  const deterministic = deterministicOverstepClassificationForSnapshot(opts);
  if (deterministic) {
    return deterministic;
  }
  return opts.classification;
}

function lastUserText(turns: Array<{ role: string; text: string }>): string {
  for (let index = turns.length - 1; index >= 0; index--) {
    if (turns[index].role === "user") return turns[index].text;
  }
  return "";
}

export type DeepSeekCaller = (args: DeepSeekArgs) => Promise<string>;

export interface PracticeSupabaseClient {
  auth: {
    getUser(token: string): Promise<{
      data: { user: { id: string; email?: string | null } | null };
      error: { message: string } | null;
    }>;
  };
  // deno-lint-ignore no-explicit-any
  from(table: string): any;
  rpc(
    fn: string,
    params: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export interface PracticeChatHandlerDeps {
  createSupabaseClient: () => PracticeSupabaseClient;
  callDeepSeek: DeepSeekCaller;
  getEnv: (name: string) => string | undefined;
  now?: () => Date;
}

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "Authorization, Content-Type, x-client-info, apikey",
};

export function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

function getErrorMessage(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

/** timeout 類失敗：上游慢，原樣重打大機率再逾時，直接跳 fallback 不重試。 */
function isHintTimeoutError(e: unknown): boolean {
  return getErrorMessage(e).includes("deepseek_timeout");
}

/**
 * 格式／驗證類失敗（JSON 壞掉或 hint guard 拒絕）才適合帶「上一版被拒絕」的
 * 重試指令；timeout／上游 5xx 帶這句是誤導（模型根本沒輸出被拒的 JSON）。
 */
function isHintFormatOrGuardError(e: unknown): boolean {
  const message = getErrorMessage(e);
  return message.includes("hint_") ||
    message.includes("JSON") ||
    message.includes("Unexpected token");
}

function hintRetryReason(e: unknown): string {
  const message = getErrorMessage(e);
  if (message.includes("hint_bossy_pasteable_reply")) {
    return "可貼回覆太像命令、面試官或叫她交作業";
  }
  if (message.includes("hint_l4_unsafe")) {
    return "可見文字越過安全邊界";
  }
  if (message.includes("hint_internal_label_leak")) {
    return "可見文字露出內部標籤";
  }
  if (
    message.includes("JSON") ||
    message.includes("Unexpected token") ||
    message.includes("hint_not_object") ||
    message.includes("hint_extra_keys") ||
    message.includes("hint_missing")
  ) {
    return "不是合格的唯一 JSON 物件";
  }
  return "格式或安全規則不合格";
}

function withHintRetryInstruction(
  messages: ChatMessage[],
  error: unknown,
): ChatMessage[] {
  return [
    ...messages,
    {
      role: "user",
      content:
        `上一版 Hint JSON 被拒絕：${hintRetryReason(error)}。請重新輸出唯一 JSON，` +
        'shape 必須仍是 {"warmUp":"...","steady":"...","coaching":"..."}。' +
        "可貼回覆要先接住她最新狀態，再給低壓接球；不要命令、不要面試官語氣、不要內部標籤、不要露骨或私密壓迫。",
    },
  ];
}

function isMissingPracticeHintRpc(message: string): boolean {
  const normalized = message.toLowerCase();
  const referencesHintRpc =
    normalized.includes("claim_practice_hint_generation") ||
    normalized.includes("record_practice_hint") ||
    normalized.includes("release_practice_hint_generation");
  return referencesHintRpc &&
    (normalized.includes("could not find the function") ||
      normalized.includes("schema cache"));
}

function isMissingBeginnerHintLedgerSchema(message: string): boolean {
  const normalized = message.toLowerCase();
  const referencesBeginnerHintLedger = normalized.includes("practice_mode") ||
    normalized.includes("temperature_score") ||
    normalized.includes("familiarity_score") ||
    normalized.includes("hint_count");
  return referencesBeginnerHintLedger &&
    (normalized.includes("schema cache") ||
      normalized.includes("could not find") ||
      normalized.includes("does not exist") ||
      normalized.includes("undefined_column"));
}

function isMissingDualAxisLearningSchema(message: string): boolean {
  const normalized = message.toLowerCase();
  const referencesDualAxisLearning = normalized.includes("familiarity_score") ||
    normalized.includes("partner_mood") ||
    normalized.includes("partner_inner_thought") ||
    normalized.includes("assert_practice_learning_ready") ||
    normalized.includes("update_practice_learning_state") ||
    normalized.includes("commit_practice_chat_turn");
  return referencesDualAxisLearning &&
    (normalized.includes("schema cache") ||
      normalized.includes("could not find") ||
      normalized.includes("does not exist") ||
      normalized.includes("undefined_column"));
}

function mapLedgerError(message: string): { error: string; status: number } {
  if (isMissingPracticeHintRpc(message)) {
    return { error: "practice_hint_not_ready", status: 503 };
  }
  if (message.includes("PRACTICE_LEARNING_NOT_READY")) {
    return { error: "practice_learning_not_ready", status: 503 };
  }
  if (isMissingDualAxisLearningSchema(message)) {
    return { error: "practice_learning_not_ready", status: 503 };
  }
  if (message.includes("PRACTICE_SESSION_COMPLETE")) {
    return { error: "practice_session_complete", status: 409 };
  }
  if (message.includes("PRACTICE_SESSION_NOT_STARTED")) {
    return { error: "practice_session_not_started", status: 403 };
  }
  if (message.includes("PRACTICE_HINT_LIMIT")) {
    return { error: "practice_hint_limit", status: 403 };
  }
  if (message.includes("PRACTICE_HINT_BEGINNER_ONLY")) {
    return { error: "practice_hint_beginner_only", status: 403 };
  }
  if (message.includes("PRACTICE_HINT_IN_FLIGHT")) {
    return { error: "practice_hint_in_flight", status: 403 };
  }
  if (message.includes("PRACTICE_DEBRIEF_LIMIT")) {
    return { error: "practice_debrief_limit", status: 403 };
  }
  if (message.includes("PRACTICE_MODE_LOCKED")) {
    return { error: "practice_mode_locked", status: 409 };
  }
  if (message.includes("PRACTICE_INVALID_MODE")) {
    return { error: "invalid_practiceMode", status: 400 };
  }
  return { error: "session_state_failed", status: 500 };
}

function remainingFrom(
  sub: SubscriptionRow,
  limits: { monthly: number; daily: number },
  deducted: number,
): { monthlyRemaining: number; dailyRemaining: number } {
  return {
    monthlyRemaining: Math.max(
      0,
      limits.monthly - sub.monthly_messages_used - deducted,
    ),
    dailyRemaining: Math.max(
      0,
      limits.daily - sub.daily_messages_used - deducted,
    ),
  };
}

function practiceModeFromLedger(value: unknown): PracticeLearningMode {
  return value === "beginner" || value === "game" ? value : "standard";
}

function explicitPracticeModeFromLedger(
  value: unknown,
): PracticeLearningMode | null {
  return value === "beginner" || value === "standard" || value === "game"
    ? value
    : null;
}

function gameModeAllowedForProfile(
  request: ReturnType<typeof validateRequest>,
): boolean {
  return request.practiceMode !== "game" ||
    request.profile.girl.rarity === "sr";
}

async function gameModeUnlockedForUser(opts: {
  supabase: PracticeSupabaseClient;
  userId: string;
  profileId: string;
}): Promise<boolean> {
  const { data, error } = await opts.supabase
    .from("practice_profile_draw_events")
    .select("profile_id")
    .eq("user_id", opts.userId)
    .eq("profile_id", opts.profileId);
  if (error) {
    logWarn("practice_chat_game_unlock_check_failed", {
      user: summarizeUser(opts.userId),
      profileId: opts.profileId,
      error: error.message,
    });
    return false;
  }
  return Array.isArray(data) && data.length > 0;
}

function temperatureFromLedger(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function familiarityFromLedger(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function partnerMoodFromLedger(value: unknown): PartnerMood | null {
  if (
    value === "neutral" ||
    value === "curious" ||
    value === "amused" ||
    value === "comfortable" ||
    value === "guarded" ||
    value === "annoyed"
  ) {
    return value;
  }
  return null;
}

function partnerInnerThoughtFromLedger(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim().replace(/\s+/g, " ").slice(0, 80);
  return trimmed.length > 0 ? trimmed : null;
}

function partnerStateFromLedger(row: SessionLedger): PartnerState | null {
  const mood = partnerMoodFromLedger(row.partnerMood);
  const innerThought = partnerInnerThoughtFromLedger(row.partnerInnerThought);
  if (!mood && !innerThought) return null;
  return {
    mood: mood ?? "neutral",
    innerThought: innerThought ?? "",
  };
}

function requestLooksLikeContinuation(
  request: ReturnType<typeof validateRequest>,
): boolean {
  return request.roundIndex > 1 ||
    !!request.memorySummary ||
    request.turns.length > 1 ||
    request.turns.some((turn) => turn.role === "ai") ||
    (!!request.visiblePracticeThreadId &&
      request.visiblePracticeThreadId !== request.sessionId);
}

function promptPartnerStateForRequest(
  ledger: SessionLedger,
  request: ReturnType<typeof validateRequest>,
  threadState?: PracticeRelationshipThreadState | null,
): PartnerState | null {
  const authoritative = partnerStateFromLedger(ledger);
  if (authoritative) return authoritative;
  if (threadState?.partnerState) return threadState.partnerState;
  if (ledger.exists || !requestLooksLikeContinuation(request)) return null;
  return request.continuationPartnerState ?? null;
}

async function fetchRelationshipThreadState(opts: {
  supabase: PracticeSupabaseClient;
  userId: string;
  visibleThreadId: string;
}): Promise<PracticeRelationshipThreadState | null> {
  const { data, error } = await opts.supabase
    .from("practice_relationship_threads")
    .select(
      "memory_summary, partner_mood, partner_inner_thought, temperature_score, familiarity_score, profile_id, practice_mode, invite_stage",
    )
    .eq("user_id", opts.userId)
    .eq("visible_thread_id", opts.visibleThreadId)
    .maybeSingle();
  if (error) {
    throw new Error(error.message);
  }
  return parseRelationshipThreadRow(data);
}

function hintCountFromLedger(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value)
    ? Math.max(0, Math.trunc(value))
    : 0;
}

interface LearningStateUpdateResult {
  updated: boolean;
  temperatureScore: number | null;
  familiarityScore: number | null;
  partnerMood: PartnerMood | null;
  partnerInnerThought: string | null;
}

function learningStateUpdateResultFromData(
  data: unknown,
): LearningStateUpdateResult {
  const row = Array.isArray(data) ? data[0] : data;
  return {
    updated: !(isPlainObject(row) && row.updated === false),
    temperatureScore: isPlainObject(row)
      ? temperatureFromLedger(row.temperature_score)
      : null,
    familiarityScore: isPlainObject(row)
      ? familiarityFromLedger(row.familiarity_score)
      : null,
    partnerMood: isPlainObject(row)
      ? partnerMoodFromLedger(row.partner_mood)
      : null,
    partnerInnerThought: isPlainObject(row)
      ? partnerInnerThoughtFromLedger(row.partner_inner_thought)
      : null,
  };
}

function partnerStateFromUpdateResult(
  result: LearningStateUpdateResult,
): PartnerState | null {
  if (!result.partnerMood && !result.partnerInnerThought) return null;
  return {
    mood: result.partnerMood ?? "neutral",
    innerThought: result.partnerInnerThought ?? "",
  };
}

function defaultPartnerState(): PartnerState {
  return { mood: "neutral", innerThought: "" };
}

function withAuthoritativeLearningScores(
  judgement: LearningJudgement,
  result: LearningStateUpdateResult,
): LearningJudgement {
  const score = result.temperatureScore ?? judgement.score;
  const familiarityScore = result.familiarityScore ??
    judgement.familiarityScore;
  const stage = relationshipStageFor(familiarityScore, score);
  return {
    ...judgement,
    score,
    band: temperatureBandFor(score),
    familiarityScore,
    stage: stage.stage,
    stageLabel: stage.label,
    partnerState: partnerStateFromUpdateResult(result) ??
      judgement.partnerState ?? defaultPartnerState(),
  };
}

function learningJudgementResponse(
  judgement: LearningJudgement,
): Record<string, unknown> {
  return {
    score: judgement.score,
    delta: judgement.delta,
    band: judgement.band,
    reason: judgement.reason,
    familiarityScore: judgement.familiarityScore,
    familiarityDelta: judgement.familiarityDelta,
    stageLabel: judgement.stageLabel,
    partnerState: judgement.partnerState,
  };
}

function shouldProtectAppliedHint(opts: {
  request: ReturnType<typeof validateRequest>;
  classification: TurnClassification;
  currentTemperature: number;
  currentFamiliarity: number;
}): boolean {
  if (!opts.request.appliedHintType) return false;
  if (
    deterministicOverstepClassificationForSnapshot({
      request: opts.request,
      currentTemperature: opts.currentTemperature,
      currentFamiliarity: opts.currentFamiliarity,
    })
  ) {
    return false;
  }
  if (isExactAppliedHint(opts.request)) {
    return true;
  }
  if (!opts.request.appliedHintText) return false;
  return opts.classification.hintAlignment === "aligned" &&
    opts.classification.boundary === "safe" &&
    opts.classification.connection !== "defensive" &&
    opts.classification.connection !== "overstepped" &&
    opts.classification.testHandling !== "failed" &&
    isLikelySmallHintEdit(opts.request);
}

function isExactAppliedHint(
  request: ReturnType<typeof validateRequest>,
): boolean {
  if (!request.appliedHintType) return false;
  const source = request.appliedHintText;
  if (!source) return false;
  return normalizedHintText(source) === normalizedHintText(
    lastUserText(request.turns),
  );
}

function protectAppliedHintTemperature(
  judgement: LearningJudgement,
  currentTemperature: number,
  currentFamiliarity: number,
  appliedHintType: string | undefined,
  practiceMode: PracticeLearningMode,
): LearningJudgement {
  const heatFloor = appliedHintHeatFloor(appliedHintType, practiceMode);
  if (
    heatFloor === Number.NEGATIVE_INFINITY
  ) {
    return judgement;
  }
  const visibleHintFloor = judgement.familiarityDelta > 0
    ? Math.max(heatFloor, 1)
    : heatFloor;
  const familiarityFloor = appliedHintFamiliarityFloor(
    appliedHintType,
    practiceMode,
  );
  const protectedHeatDelta = Math.max(judgement.delta, visibleHintFloor);
  const protectedFamiliarityDelta = Math.max(
    judgement.familiarityDelta,
    familiarityFloor,
  );
  if (
    protectedHeatDelta === judgement.delta &&
    protectedFamiliarityDelta === judgement.familiarityDelta
  ) {
    return judgement;
  }
  const score = clampTemperature(currentTemperature + protectedHeatDelta);
  const familiarityScore = clampTemperature(
    currentFamiliarity + protectedFamiliarityDelta,
  );
  const stage = relationshipStageFor(familiarityScore, score);
  const protectedReason =
    protectedHeatDelta > 0 || protectedFamiliarityDelta > 0
      ? "套用提示回覆，穩定推進關係"
      : "套用提示回覆，維持不降溫";
  return {
    ...judgement,
    score,
    delta: protectedHeatDelta,
    band: temperatureBandFor(score),
    familiarityScore,
    familiarityDelta: protectedFamiliarityDelta,
    stage: stage.stage,
    stageLabel: stage.label,
    reason: protectedReason,
  };
}

function fallbackLearningJudgement(
  currentTemperature: number,
  currentFamiliarity: number,
  currentPartnerState?: PartnerState | null,
): LearningJudgement {
  const score = clampTemperature(currentTemperature);
  const familiarityScore = clampTemperature(currentFamiliarity);
  const stage = relationshipStageFor(familiarityScore, score);
  return {
    score,
    delta: 0,
    band: temperatureBandFor(score),
    reason: "低影響回合，先保守調整",
    familiarityScore,
    familiarityDelta: 0,
    stage: stage.stage,
    stageLabel: stage.label,
    classification: {
      impact: "minor",
      connection: "neutral",
      testHandling: "none",
      boundary: "safe",
      hintAlignment: "none",
      partnerMood: "neutral",
      moodConfidence: 0,
      innerThought: "",
    },
    partnerState: currentPartnerState ?? defaultPartnerState(),
  };
}

async function assertPracticeLearningReady(opts: {
  supabase: PracticeSupabaseClient;
  userId: string;
  sessionId: string;
}): Promise<void> {
  const { error } = await opts.supabase.rpc("assert_practice_learning_ready", {
    p_user_id: opts.userId,
    p_session_id: opts.sessionId,
  });
  if (error) {
    throw new Error(error.message);
  }
}

async function updateLearningState(opts: {
  supabase: PracticeSupabaseClient;
  userId: string;
  sessionId: string;
  expectedTemperature: number;
  expectedFamiliarity: number;
  judgement: LearningJudgement;
}): Promise<LearningStateUpdateResult> {
  const { data, error } = await opts.supabase.rpc(
    "update_practice_learning_state",
    {
      p_user_id: opts.userId,
      p_session_id: opts.sessionId,
      p_expected_temperature_score: opts.expectedTemperature,
      p_expected_familiarity_score: opts.expectedFamiliarity,
      p_temperature_delta: opts.judgement.delta,
      p_familiarity_delta: opts.judgement.familiarityDelta,
      p_partner_mood: opts.judgement.partnerState?.mood ?? "neutral",
      p_partner_inner_thought: opts.judgement.partnerState?.innerThought ?? "",
    },
  );
  if (error) {
    throw new Error(error.message);
  }
  return learningStateUpdateResultFromData(data);
}

async function persistGameStateFailOpen(opts: {
  supabase: PracticeSupabaseClient;
  userId: string;
  sessionId: string;
  gameState: PersistedGameState;
}): Promise<void> {
  const { error } = await opts.supabase.rpc("update_practice_game_state", {
    p_user_id: opts.userId,
    p_session_id: opts.sessionId,
    p_game_state: opts.gameState,
  });
  if (error) {
    logWarn("practice_game_state_update_failed", {
      user: summarizeUser(opts.userId),
      error: error.message,
    });
  }
}

async function upsertRelationshipThreadFailOpen(opts: {
  supabase: PracticeSupabaseClient;
  params: ReturnType<typeof buildRelationshipThreadRpcParams>;
}): Promise<void> {
  const { error } = await opts.supabase.rpc(
    "upsert_practice_relationship_thread",
    opts.params,
  );
  if (error) {
    logWarn("practice_relationship_thread_upsert_failed", {
      user: summarizeUser(String(opts.params.p_user_id)),
      error: error.message,
    });
  }
}

async function judgeLearningState(opts: {
  deps: PracticeChatHandlerDeps;
  apiKey: string;
  supabase: PracticeSupabaseClient;
  userId: string;
  sessionId: string;
  currentTemperature: number;
  currentFamiliarity: number;
  currentPartnerState?: PartnerState | null;
  request: ReturnType<typeof validateRequest>;
  reply: string;
}): Promise<LearningJudgement> {
  // 難度接線（槓桿 A）：正負 delta 倍率只在 beginner 溫度管線生效，作用域內解析一次。
  const tuning = difficultyTuningFor(opts.request.profile.difficulty);
  const applyGameLearningIfNeeded = (
    judgement: LearningJudgement,
    currentTemperature: number,
    currentFamiliarity: number,
    partnerState: PartnerState | null | undefined,
  ): LearningJudgement => {
    if (opts.request.practiceMode !== "game") return judgement;
    const snapshot = evaluateGameFsm({
      turns: opts.request.turns,
      temperatureScore: currentTemperature,
      familiarityScore: currentFamiliarity,
      partnerMood: judgement.partnerState?.mood ?? partnerState?.mood ?? null,
      classification: judgement.classification,
    });
    return applyGameLearningDelta({
      judgement,
      currentTemperature,
      currentFamiliarity,
      snapshot,
    });
  };
  const fallbackForSnapshot = (
    currentTemperature: number,
    currentFamiliarity: number,
    currentPartnerState: PartnerState | null | undefined =
      opts.currentPartnerState,
  ): LearningJudgement => {
    const deterministic = deterministicOverstepClassificationForSnapshot({
      request: opts.request,
      currentTemperature,
      currentFamiliarity,
    });
    if (deterministic) {
      const judgement = applyLearningClassification(
        {
          heatScore: currentTemperature,
          familiarityScore: currentFamiliarity,
        },
        deterministic,
        tuning,
      );
      const withPartnerState = {
        ...judgement,
        partnerState: applyPartnerStateUpdate(
          currentPartnerState,
          deterministic,
        ),
      };
      return applyGameLearningIfNeeded(
        withPartnerState,
        currentTemperature,
        currentFamiliarity,
        currentPartnerState,
      );
    }
    const base = fallbackLearningJudgement(
      currentTemperature,
      currentFamiliarity,
      currentPartnerState,
    );
    const protectedFallback = protectAppliedHintTemperature(
      base,
      currentTemperature,
      currentFamiliarity,
      isExactAppliedHint(opts.request)
        ? opts.request.appliedHintType
        : undefined,
      opts.request.practiceMode,
    );
    return applyGameLearningIfNeeded(
      protectedFallback,
      currentTemperature,
      currentFamiliarity,
      currentPartnerState,
    );
  };
  const protectedJudgementForSnapshot = (
    currentTemperature: number,
    currentFamiliarity: number,
    currentPartnerState: PartnerState | null | undefined,
    parsedClassification: TurnClassification,
  ): LearningJudgement => {
    const classification = withDeterministicSafetyOverride({
      classification: parsedClassification,
      request: opts.request,
      currentTemperature,
      currentFamiliarity,
    });
    const judgement = applyLearningClassification(
      {
        heatScore: currentTemperature,
        familiarityScore: currentFamiliarity,
      },
      classification,
      tuning,
    );
    const protectedHintType = shouldProtectAppliedHint({
        request: opts.request,
        classification,
        currentTemperature,
        currentFamiliarity,
      })
      ? opts.request.appliedHintType
      : undefined;
    const protectedJudgement = protectAppliedHintTemperature(
      judgement,
      currentTemperature,
      currentFamiliarity,
      protectedHintType,
      opts.request.practiceMode,
    );
    const withPartnerState = {
      ...protectedJudgement,
      partnerState: applyPartnerStateUpdate(
        currentPartnerState,
        classification,
      ),
    };
    return applyGameLearningIfNeeded(
      withPartnerState,
      currentTemperature,
      currentFamiliarity,
      currentPartnerState,
    );
  };
  const fallback = fallbackForSnapshot(
    opts.currentTemperature,
    opts.currentFamiliarity,
    opts.currentPartnerState,
  );
  try {
    const rawClassification = await opts.deps.callDeepSeek({
      apiKey: opts.apiKey,
      messages: buildTurnClassifierMessages({
        turns: opts.request.turns,
        profile: opts.request.profile,
        heatScore: opts.currentTemperature,
        familiarityScore: opts.currentFamiliarity,
        appliedHintType: opts.request.appliedHintType,
        appliedHintText: opts.request.appliedHintText,
        assistantReply: opts.reply,
      }),
      maxTokens: TEMPERATURE_JUDGE_MAX_TOKENS,
      temperature: TEMPERATURE_JUDGE_TEMPERATURE,
      jsonMode: true,
      timeoutMs: DEEPSEEK_TIMEOUT_MS,
    });
    const parsedClassification: TurnClassification = parseTurnClassification(
      rawClassification,
      {
        requireImpact: opts.request.appliedHintText !== undefined,
        requireHintAlignment: opts.request.appliedHintText !== undefined,
      },
    );
    const protectedJudgement = protectedJudgementForSnapshot(
      opts.currentTemperature,
      opts.currentFamiliarity,
      opts.currentPartnerState,
      parsedClassification,
    );
    const updateLearning = async (
      expectedTemperature: number,
      expectedFamiliarity: number,
      learningJudgement: LearningJudgement,
    ): Promise<LearningStateUpdateResult> => {
      const { data, error } = await opts.supabase.rpc(
        "update_practice_learning_state",
        {
          p_user_id: opts.userId,
          p_session_id: opts.sessionId,
          p_expected_temperature_score: expectedTemperature,
          p_expected_familiarity_score: expectedFamiliarity,
          p_temperature_delta: learningJudgement.delta,
          p_familiarity_delta: learningJudgement.familiarityDelta,
          p_partner_mood: learningJudgement.partnerState?.mood ?? "neutral",
          p_partner_inner_thought:
            learningJudgement.partnerState?.innerThought ?? "",
        },
      );
      if (error) {
        throw new Error(error.message);
      }
      return learningStateUpdateResultFromData(data);
    };

    const firstUpdate = await updateLearning(
      opts.currentTemperature,
      opts.currentFamiliarity,
      protectedJudgement,
    );
    if (!firstUpdate.updated) {
      if (
        firstUpdate.temperatureScore === null ||
        firstUpdate.familiarityScore === null
      ) {
        throw new Error("learning_state_update_not_applied");
      }
      const protectedRetryJudgement = protectedJudgementForSnapshot(
        firstUpdate.temperatureScore,
        firstUpdate.familiarityScore,
        partnerStateFromUpdateResult(firstUpdate) ?? opts.currentPartnerState,
        parsedClassification,
      );
      const secondUpdate = await updateLearning(
        firstUpdate.temperatureScore,
        firstUpdate.familiarityScore,
        protectedRetryJudgement,
      );
      if (!secondUpdate.updated) {
        throw new Error("learning_state_update_not_applied");
      }
      return withAuthoritativeLearningScores(
        protectedRetryJudgement,
        secondUpdate,
      );
    }
    return withAuthoritativeLearningScores(protectedJudgement, firstUpdate);
  } catch (e) {
    if (isMissingDualAxisLearningSchema(getErrorMessage(e))) {
      throw e;
    }
    logWarn("practice_chat_learning_classifier_failed", {
      user: summarizeUser(opts.userId),
      error: getErrorMessage(e),
    });
    try {
      const fallbackUpdate = await updateLearningState({
        supabase: opts.supabase,
        userId: opts.userId,
        sessionId: opts.sessionId,
        expectedTemperature: opts.currentTemperature,
        expectedFamiliarity: opts.currentFamiliarity,
        judgement: fallback,
      });
      if (fallbackUpdate.updated) {
        return withAuthoritativeLearningScores(fallback, fallbackUpdate);
      }
      if (
        fallbackUpdate.temperatureScore !== null &&
        fallbackUpdate.familiarityScore !== null
      ) {
        const retryFallback = fallbackForSnapshot(
          fallbackUpdate.temperatureScore,
          fallbackUpdate.familiarityScore,
          partnerStateFromUpdateResult(fallbackUpdate) ??
            opts.currentPartnerState,
        );
        const retryUpdate = await updateLearningState({
          supabase: opts.supabase,
          userId: opts.userId,
          sessionId: opts.sessionId,
          expectedTemperature: fallbackUpdate.temperatureScore,
          expectedFamiliarity: fallbackUpdate.familiarityScore,
          judgement: retryFallback,
        });
        if (retryUpdate.updated) {
          return withAuthoritativeLearningScores(retryFallback, retryUpdate);
        }
      }
    } catch (updateError) {
      logWarn("practice_chat_learning_fallback_update_failed", {
        user: summarizeUser(opts.userId),
        error: getErrorMessage(updateError),
      });
    }
    return fallback;
  }
}

async function releaseHintGeneration(opts: {
  supabase: PracticeSupabaseClient;
  userId: string;
  sessionId: string;
}): Promise<void> {
  const { error } = await opts.supabase.rpc(
    "release_practice_hint_generation",
    {
      p_user_id: opts.userId,
      p_session_id: opts.sessionId,
    },
  );
  if (error) {
    logWarn("practice_chat_hint_release_failed", {
      user: summarizeUser(opts.userId),
      error: error.message,
    });
  }
}

export function createPracticeChatHandler(
  deps: PracticeChatHandlerDeps,
): (req: Request) => Promise<Response> {
  return async function handleRequest(req: Request): Promise<Response> {
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }
    if (req.method !== "POST") {
      return jsonResponse({ error: "method_not_allowed" }, 405);
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return jsonResponse({ error: "unauthorized" }, 401);
    }
    const token = authHeader.slice(7);
    const supabase = deps.createSupabaseClient();
    const { data: { user }, error: userError } = await supabase.auth.getUser(
      token,
    );
    if (userError || !user) {
      return jsonResponse({ error: "unauthorized" }, 401);
    }

    const rawText = await req.text();
    if (rawText.length > MAX_BODY_BYTES) {
      return jsonResponse({ error: "request_body_too_large" }, 413);
    }
    let rawBody: unknown;
    try {
      rawBody = JSON.parse(rawText);
    } catch {
      return jsonResponse({ error: "invalid_request_body" }, 400);
    }

    if (isPlainObject(rawBody) && rawBody.mode === "draw_profile") {
      let drawRequest;
      try {
        drawRequest = validateDrawRequest(rawBody);
      } catch (e) {
        return jsonResponse({ error: getErrorMessage(e) }, 400);
      }
      const drawResult = await handleDrawProfile({
        supabase: supabase as unknown as DrawSupabaseClient,
        userId: user.id,
        userEmail: user.email ?? null,
        request: drawRequest,
        now: deps.now?.() ?? new Date(),
      });
      return jsonResponse(drawResult.body, drawResult.status);
    }

    let request;
    try {
      request = validateRequest(rawBody);
    } catch (e) {
      return jsonResponse({ error: getErrorMessage(e) }, 400);
    }
    if (!gameModeAllowedForProfile(request)) {
      logWarn("practice_chat_game_rejected_non_sr", {
        user: summarizeUser(user.id),
        profileId: request.profile.girl.profileId,
      });
      return jsonResponse({ error: "practice_game_sr_only" }, 403);
    }
    // 難度接線（槓桿 A）：beginner 溫度初始值 fallback 隨難度變化（僅 beginner 生效）。
    const difficultyStartTemperature =
      difficultyTuningFor(request.profile.difficulty).startTemperature;
    const requestNow = deps.now?.() ?? new Date();
    const sceneContext = buildPracticeSceneContext({
      profile: request.profile,
      time: taipeiTimeContextFor(requestNow),
      visiblePracticeThreadId: request.visiblePracticeThreadId ??
        request.sessionId,
    });

    const apiKey = deps.getEnv("DEEPSEEK_API_KEY");
    if (!apiKey) {
      logError("practice_chat_config_missing", {
        user: summarizeUser(user.id),
      });
      return jsonResponse({ error: "config_missing" }, 500);
    }

    const { data: subRow, error: subError } = await supabase
      .from("subscriptions")
      .select(
        "tier, monthly_messages_used, daily_messages_used, daily_reset_at, monthly_reset_at",
      )
      .eq("user_id", user.id)
      .maybeSingle();
    if (subError) {
      logWarn("practice_chat_sub_fetch_error", {
        user: summarizeUser(user.id),
        error: subError.message,
      });
      return jsonResponse({ error: "subscription_fetch_failed" }, 500);
    }
    if (!subRow) {
      return jsonResponse({ error: "No subscription found" }, 403);
    }

    let sub = subRow as SubscriptionRow;
    const reset = applyResetsIfNeeded(sub, deps.now?.() ?? new Date());
    sub = reset.sub;
    if (reset.dailyReset || reset.monthlyReset) {
      await supabase
        .from("subscriptions")
        .update({
          daily_messages_used: sub.daily_messages_used,
          monthly_messages_used: sub.monthly_messages_used,
          daily_reset_at: sub.daily_reset_at,
          monthly_reset_at: sub.monthly_reset_at,
        })
        .eq("user_id", user.id);
    }

    const accountIsTest = TEST_EMAILS.includes(user.email || "");
    const limits = resolveLimits(sub.tier);

    const { data: ledgerRow, error: ledgerError } = await supabase
      .from("practice_chat_sessions")
      .select(
        "ai_count, charged, debrief_count, practice_mode, temperature_score, familiarity_score, partner_mood, partner_inner_thought, hint_count, game_state",
      )
      .eq("user_id", user.id)
      .eq("session_id", request.sessionId)
      .maybeSingle();
    if (ledgerError) {
      const mapped = isMissingDualAxisLearningSchema(ledgerError.message)
        ? { error: "practice_learning_not_ready", status: 503 }
        : request.mode === "hint" &&
            isMissingBeginnerHintLedgerSchema(ledgerError.message)
        ? { error: "practice_hint_not_ready", status: 503 }
        : { error: "session_state_failed", status: 500 };
      logWarn("practice_chat_ledger_fetch_error", {
        user: summarizeUser(user.id),
        error: ledgerError.message,
      });
      return jsonResponse({ error: mapped.error }, mapped.status);
    }
    const ledger: SessionLedger = {
      exists: !!ledgerRow,
      aiCount: (ledgerRow?.ai_count as number | undefined) ?? 0,
      charged: (ledgerRow?.charged as boolean | undefined) ?? false,
      debriefCount: (ledgerRow?.debrief_count as number | undefined) ?? 0,
      practiceMode: practiceModeFromLedger(ledgerRow?.practice_mode),
      temperatureScore: temperatureFromLedger(ledgerRow?.temperature_score),
      familiarityScore: familiarityFromLedger(ledgerRow?.familiarity_score),
      partnerMood: partnerMoodFromLedger(ledgerRow?.partner_mood),
      partnerInnerThought: partnerInnerThoughtFromLedger(
        ledgerRow?.partner_inner_thought,
      ),
      hintCount: hintCountFromLedger(ledgerRow?.hint_count),
    };
    const lockedPracticeMode = explicitPracticeModeFromLedger(
      ledgerRow?.practice_mode,
    );
    const ledgerGameState = parsePersistedGameState(ledgerRow?.game_state);
    const visibleThreadId = threadIdForPracticeRequest({
      sessionId: request.sessionId,
      visiblePracticeThreadId: request.visiblePracticeThreadId,
    });
    let relationshipThreadState: PracticeRelationshipThreadState | null = null;
    try {
      relationshipThreadState = await fetchRelationshipThreadState({
        supabase,
        userId: user.id,
        visibleThreadId,
      });
    } catch (e) {
      logWarn("practice_relationship_thread_fetch_failed", {
        user: summarizeUser(user.id),
        error: getErrorMessage(e),
      });
    }
    if (
      relationshipThreadState &&
      relationshipThreadState.profileId !== request.profile.girl.profileId
    ) {
      logWarn("practice_relationship_thread_profile_mismatch", {
        user: summarizeUser(user.id),
        requestedProfileId: request.profile.girl.profileId,
        threadProfileId: relationshipThreadState.profileId ?? null,
      });
      relationshipThreadState = null;
    }
    const promptMemorySummary = relationshipThreadState?.memorySummary ?? null;

    if (request.mode === "hint") {
      if (!isAssistedPracticeMode(request.practiceMode)) {
        return jsonResponse({ error: "practice_hint_beginner_only" }, 403);
      }

      if (
        ledger.exists && lockedPracticeMode !== null &&
        lockedPracticeMode !== request.practiceMode
      ) {
        logWarn("practice_chat_mode_locked", {
          user: summarizeUser(user.id),
          sessionId: request.sessionId,
          mode: "hint",
        });
        return jsonResponse({ error: "practice_mode_locked" }, 409);
      }

      if (
        request.practiceMode === "game" &&
        !(await gameModeUnlockedForUser({
          supabase,
          userId: user.id,
          profileId: request.profile.girl.profileId,
        }))
      ) {
        logWarn("practice_chat_game_rejected_not_unlocked", {
          user: summarizeUser(user.id),
          profileId: request.profile.girl.profileId,
          mode: "hint",
        });
        return jsonResponse({ error: "practice_game_sr_only" }, 403);
      }

      // Replay a completed hint request after mode/unlock checks, but before
      // cap and quota gates, so lost responses can be recovered idempotently.
      // Missing replay columns or query failures fail open to the claim path.
      if (request.requestId) {
        const { data: replayRow, error: replayError } = await supabase
          .from("practice_chat_sessions")
          .select("last_hint_request_id, last_hint_result")
          .eq("user_id", user.id)
          .eq("session_id", request.sessionId)
          .maybeSingle();
        if (replayError) {
          logWarn("practice_chat_hint_replay_preflight_failed", {
            user: summarizeUser(user.id),
            error: replayError.message,
          });
        } else if (
          replayRow?.last_hint_request_id === request.requestId &&
          isPlainObject(replayRow?.last_hint_result)
        ) {
          logInfo("practice_chat_hint_replayed", {
            user: summarizeUser(user.id),
            sessionId: request.sessionId,
            source: "preflight",
          });
          return jsonResponse(replayRow.last_hint_result);
        }
      }
      const gate = decideHintGate({
        ledger,
        maxHints: MAX_HINTS_PER_ROUND,
        maxReplies: MAX_AI_REPLIES,
      });
      if (!gate.allowed) {
        logWarn("practice_chat_hint_rejected", {
          user: summarizeUser(user.id),
          reason: gate.reason,
        });
        const reason = gate.reason ?? "practice_session_not_started";
        // 聊滿 session 對齊 chat 的 409 practice_session_complete，client 走既有
        // sessionComplete 分支；其餘 hint 拒絕維持 403。
        return jsonResponse(
          { error: reason },
          reason === "practice_session_complete" ? 409 : 403,
        );
      }

      const quotaGate = checkQuota({
        sub,
        cost: PRACTICE_QUOTA_COST,
        isTestAccount: accountIsTest,
        monthlyLimit: limits.monthly,
        dailyLimit: limits.daily,
      });
      if (!quotaGate.ok) {
        logWarn("practice_chat_quota_exceeded", {
          user: summarizeUser(user.id),
          reason: quotaGate.reason,
        });
        return jsonResponse(
          buildQuotaExceededPayload({
            sub,
            cost: PRACTICE_QUOTA_COST,
            reason: quotaGate.reason,
            monthlyLimit: limits.monthly,
            dailyLimit: limits.daily,
          }),
          429,
        );
      }

      // 模型呼叫限流：practice_hint 4/分、40/日。放在 replay preflight／
      // quota gate 後、claim latch 前——被限流的請求不占用 in-flight latch，
      // replay 回放（不打模型）不計限流。
      const hintRateVerdict = await enforceModelRateLimit({
        supabase,
        userId: user.id,
        scope: "practice_hint",
        isTestAccount: accountIsTest,
      });
      if (hintRateVerdict.kind === "limited") {
        logWarn("model_rate_limited", {
          user: summarizeUser(user.id),
          scope: "practice_hint",
          reason: hintRateVerdict.reason,
        });
        return jsonResponse(hintRateVerdict.payload, 429);
      }
      if (hintRateVerdict.kind === "failOpen") {
        logError("model_rate_limit_check_failed", {
          user: summarizeUser(user.id),
          scope: "practice_hint",
          error: hintRateVerdict.errorMessage,
        });
      }

      // p_request_id 只在 client 有送 requestId 時帶：舊 client 缺值時維持 3-arg
      // 呼叫形狀，與尚未套 idempotency migration 的舊 RPC 相容。
      const claimHintParams: Record<string, unknown> = {
        p_user_id: user.id,
        p_session_id: request.sessionId,
        p_max_hints: MAX_HINTS_PER_ROUND,
      };
      if (request.requestId) {
        claimHintParams.p_request_id = request.requestId;
      }
      const { data: claimHintData, error: claimHintError } = await supabase.rpc(
        "claim_practice_hint_generation",
        claimHintParams,
      );
      if (claimHintError) {
        const mapped = mapLedgerError(claimHintError.message);
        logWarn("practice_chat_hint_claim_failed", {
          user: summarizeUser(user.id),
          error: claimHintError.message,
        });
        return jsonResponse({ error: mapped.error }, mapped.status);
      }
      // claim 層 replay 後援：preflight 讀到 stale 快照、但 record 已在鎖內落帳的
      // 併發窗口由 RPC 以 FOR UPDATE 權威判定。replay 不動 latch、不扣費。
      const claimHintRow = Array.isArray(claimHintData)
        ? claimHintData[0]
        : claimHintData;
      if (
        isPlainObject(claimHintRow) &&
        claimHintRow.replay === true &&
        isPlainObject(claimHintRow.stored_result)
      ) {
        logInfo("practice_chat_hint_replayed", {
          user: summarizeUser(user.id),
          sessionId: request.sessionId,
          source: "claim",
        });
        return jsonResponse(claimHintRow.stored_result);
      }

      const hintTemperatureScore = ledger.temperatureScore ??
        difficultyStartTemperature;
      const hintFamiliarityScore = ledger.familiarityScore ?? 0;
      const hintPartnerMood = partnerStateFromLedger(ledger)?.mood ??
        relationshipThreadState?.partnerState?.mood ?? null;
      const hintGenerationAttempts = HINT_GENERATION_ATTEMPTS;
      const hintTimeoutMs = HINT_TIMEOUT_MS;
      let hintResult: ReturnType<typeof parseHintResult> | null = null;
      try {
        let lastError: unknown;
        for (
          let attempt = 1;
          attempt <= hintGenerationAttempts;
          attempt++
        ) {
          try {
            const hintMessages = buildHintMessages({
              turns: request.turns,
              profile: request.profile,
              practiceMode: request.practiceMode,
              temperatureScore: hintTemperatureScore,
              familiarityScore: hintFamiliarityScore,
              partnerMood: hintPartnerMood,
              sceneContext,
              memorySummary: promptMemorySummary,
            });
            const rawHint = await deps.callDeepSeek({
              apiKey,
              messages: attempt > 1 && lastError !== undefined &&
                  isHintFormatOrGuardError(lastError)
                ? withHintRetryInstruction(hintMessages, lastError)
                : hintMessages,
              maxTokens: HINT_MAX_TOKENS,
              temperature: HINT_TEMPERATURE,
              jsonMode: true,
              timeoutMs: hintTimeoutMs,
            });
            hintResult = parseHintResult(rawHint, {
              mode: request.practiceMode,
            });
            break;
          } catch (e) {
            lastError = e;
            logWarn("practice_chat_hint_generation_attempt_failed", {
              user: summarizeUser(user.id),
              attempt,
              error: getErrorMessage(e),
            });
            // timeout 不重試：上游慢時第 2 次大機率再等滿逾時，白耗用戶等待。
            if (isHintTimeoutError(e)) break;
          }
        }
        if (
          hintResult === null &&
          (request.practiceMode === "game" ||
            request.practiceMode === "beginner")
        ) {
          logWarn(
            request.practiceMode === "game"
              ? "practice_chat_game_hint_fallback_used"
              : "practice_chat_beginner_hint_fallback_used",
            {
              user: summarizeUser(user.id),
              error: getErrorMessage(lastError),
            },
          );
          hintResult = buildFallbackHintResult({
            turns: request.turns,
            profile: request.profile,
            practiceMode: request.practiceMode,
            temperatureScore: hintTemperatureScore,
            familiarityScore: hintFamiliarityScore,
            partnerMood: hintPartnerMood,
          });
        }
        if (hintResult === null) {
          throw lastError instanceof Error
            ? lastError
            : new Error("hint_generation_failed");
        }
      } catch (e) {
        logWarn("practice_chat_generation_failed", {
          user: summarizeUser(user.id),
          mode: "hint",
          personaId: request.profile.personaId,
          difficulty: request.profile.difficulty,
          error: getErrorMessage(e),
        });
        await releaseHintGeneration({
          supabase,
          userId: user.id,
          sessionId: request.sessionId,
        });
        return jsonResponse({ error: "practice_generation_failed" }, 500);
      }

      const recordHintParams: Record<string, unknown> = {
        p_user_id: user.id,
        p_session_id: request.sessionId,
        p_charge_quota: !accountIsTest,
        p_max_hints: MAX_HINTS_PER_ROUND,
      };
      if (request.requestId) {
        // 供之後同 requestId 重試回放的完整回應快照。hintUsedCount 不在此預填：
        // 由 RPC 在鎖內以權威 new_hint_count merge 進 stored result。
        // costDeducted 可預判：record 的 did_charge 恆等於 p_charge_quota。
        const predictedDeducted = accountIsTest ? 0 : PRACTICE_QUOTA_COST;
        recordHintParams.p_request_id = request.requestId;
        recordHintParams.p_result = {
          ...hintResult,
          costDeducted: predictedDeducted,
          provider: "deepseek",
          model: DEEPSEEK_MODEL,
          generatedAt: (deps.now?.() ?? new Date()).toISOString(),
          ...remainingFrom(sub, limits, predictedDeducted),
        };
      }
      const { data: recordData, error: recordError } = await supabase.rpc(
        "record_practice_hint",
        recordHintParams,
      );
      if (recordError) {
        const mapped = mapLedgerError(recordError.message);
        logWarn("practice_chat_hint_record_failed", {
          user: summarizeUser(user.id),
          error: recordError.message,
        });
        await releaseHintGeneration({
          supabase,
          userId: user.id,
          sessionId: request.sessionId,
        });
        return jsonResponse({ error: mapped.error }, mapped.status);
      }
      const recordRow = Array.isArray(recordData) ? recordData[0] : recordData;
      const didCharge = (recordRow?.did_charge as boolean | undefined) ?? false;
      const deducted = didCharge ? PRACTICE_QUOTA_COST : 0;
      const hintUsedCount = (recordRow?.new_hint_count as number | undefined) ??
        ((ledger.hintCount ?? 0) + 1);

      logInfo("practice_chat_succeeded", {
        user: summarizeUser(user.id),
        mode: "hint",
        personaId: request.profile.personaId,
        difficulty: request.profile.difficulty,
        costDeducted: deducted,
      });
      return jsonResponse({
        ...hintResult,
        costDeducted: deducted,
        hintUsedCount,
        provider: "deepseek",
        model: DEEPSEEK_MODEL,
        generatedAt: (deps.now?.() ?? new Date()).toISOString(),
        ...remainingFrom(sub, limits, deducted),
      });
    }

    if (
      request.mode === "chat" &&
      ledger.exists && lockedPracticeMode !== null &&
      lockedPracticeMode !== request.practiceMode
    ) {
      logWarn("practice_chat_mode_locked", {
        user: summarizeUser(user.id),
        sessionId: request.sessionId,
      });
      return jsonResponse({ error: "practice_mode_locked" }, 409);
    }

    if (
      request.practiceMode === "game" &&
      !(await gameModeUnlockedForUser({
        supabase,
        userId: user.id,
        profileId: request.profile.girl.profileId,
      }))
    ) {
      logWarn("practice_chat_game_rejected_not_unlocked", {
        user: summarizeUser(user.id),
        profileId: request.profile.girl.profileId,
        mode: request.mode,
      });
      return jsonResponse({ error: "practice_game_sr_only" }, 403);
    }

    if (request.mode === "debrief") {
      const gate = decideDebriefGate({ ledger });
      if (!gate.allowed) {
        logWarn("practice_chat_debrief_rejected", {
          user: summarizeUser(user.id),
          reason: gate.reason,
        });
        return jsonResponse({ error: gate.reason }, 403);
      }

      const debriefAssistedMode = isAssistedPracticeMode(
        ledger.practiceMode ?? "standard",
      );
      const ledgerAppliedHintTurns = debriefAssistedMode
        ? request.appliedHintTurns
        : undefined;
      if (debriefAssistedMode) {
        try {
          await assertPracticeLearningReady({
            supabase,
            userId: user.id,
            sessionId: request.sessionId,
          });
        } catch (e) {
          const mapped = mapLedgerError(getErrorMessage(e));
          logWarn("practice_chat_learning_not_ready", {
            user: summarizeUser(user.id),
            error: getErrorMessage(e),
          });
          return jsonResponse({ error: mapped.error }, mapped.status);
        }
      }

      // 模型呼叫限流：practice_debrief 4/分、40/日（Codex R1 P2：debrief
      // 也打 DeepSeek）。放在資格 gate 403 之後、claim 之前——被限流的
      // 請求不得吃掉 MAX_DEBRIEFS 名額。
      const debriefRateVerdict = await enforceModelRateLimit({
        supabase,
        userId: user.id,
        scope: "practice_debrief",
        isTestAccount: accountIsTest,
      });
      if (debriefRateVerdict.kind === "limited") {
        logWarn("model_rate_limited", {
          user: summarizeUser(user.id),
          scope: "practice_debrief",
          reason: debriefRateVerdict.reason,
        });
        return jsonResponse(debriefRateVerdict.payload, 429);
      }
      if (debriefRateVerdict.kind === "failOpen") {
        logError("model_rate_limit_check_failed", {
          user: summarizeUser(user.id),
          scope: "practice_debrief",
          error: debriefRateVerdict.errorMessage,
        });
      }

      const { error: claimError } = await supabase.rpc(
        "claim_practice_debrief",
        {
          p_user_id: user.id,
          p_session_id: request.sessionId,
          p_max_debriefs: MAX_DEBRIEFS,
        },
      );
      if (claimError) {
        const mapped = mapLedgerError(claimError.message);
        logWarn("practice_chat_debrief_claim_failed", {
          user: summarizeUser(user.id),
          error: claimError.message,
        });
        return jsonResponse({ error: mapped.error }, mapped.status);
      }

      let debriefCard: DebriefCard | null = null;
      try {
        let lastError: unknown;
        for (
          let attempt = 1;
          attempt <= DEBRIEF_GENERATION_ATTEMPTS;
          attempt++
        ) {
          try {
            const rawCard = await deps.callDeepSeek({
              apiKey,
              messages: buildDebriefMessages(
                request.turns,
                request.profile,
                debriefAssistedMode
                  ? {
                    practiceMode: ledger.practiceMode,
                    temperatureScore: ledger.temperatureScore ??
                      difficultyStartTemperature,
                    familiarityScore: ledger.familiarityScore ?? 0,
                    partnerState: partnerStateFromLedger(ledger) ??
                      relationshipThreadState?.partnerState ?? null,
                    sceneContext,
                    memorySummary: promptMemorySummary,
                    gameState: ledgerGameState,
                    appliedHintTurns: ledgerAppliedHintTurns,
                  }
                  : {
                    partnerState: partnerStateFromLedger(ledger) ??
                      relationshipThreadState?.partnerState ?? null,
                    sceneContext,
                    memorySummary: promptMemorySummary,
                  },
              ),
              maxTokens: DEBRIEF_MAX_TOKENS,
              temperature: DEBRIEF_TEMPERATURE,
              jsonMode: true,
              timeoutMs: DEBRIEF_TIMEOUT_MS,
            });
            debriefCard = parseDebriefCard(rawCard, {
              allowGameBreakdown: ledger.practiceMode === "game",
            });
            break;
          } catch (e) {
            lastError = e;
            logWarn("practice_chat_debrief_generation_attempt_failed", {
              user: summarizeUser(user.id),
              attempt,
              error: getErrorMessage(e),
            });
          }
        }
        if (debriefCard === null) {
          logWarn("practice_chat_debrief_fallback_used", {
            user: summarizeUser(user.id),
            mode: ledger.practiceMode ?? request.practiceMode,
            error: getErrorMessage(lastError),
          });
          debriefCard = buildFallbackDebriefCard({
            practiceMode: ledger.practiceMode,
            appliedHintTurns: ledgerAppliedHintTurns,
          });
        }
      } catch (e) {
        logWarn("practice_chat_generation_failed", {
          user: summarizeUser(user.id),
          mode: "debrief",
          personaId: request.profile.personaId,
          difficulty: request.profile.difficulty,
          error: getErrorMessage(e),
        });
        return jsonResponse({ error: "practice_generation_failed" }, 500);
      }

      logInfo("practice_chat_succeeded", {
        user: summarizeUser(user.id),
        mode: "debrief",
        personaId: request.profile.personaId,
        difficulty: request.profile.difficulty,
        costDeducted: 0,
      });
      return jsonResponse({
        card: debriefCard,
        costDeducted: 0,
        provider: "deepseek",
        model: DEEPSEEK_MODEL,
        generatedAt: (deps.now?.() ?? new Date()).toISOString(),
        ...remainingFrom(sub, limits, 0),
      });
    }

    const continuation = decideContinuationGate({
      tier: sub.tier,
      roundIndex: request.roundIndex,
      ledgerExists: ledger.exists,
      ledgerAiCount: ledger.aiCount,
      sessionId: request.sessionId,
      visiblePracticeThreadId: request.visiblePracticeThreadId,
      hasPriorAiTurns: request.turns.some((turn) => turn.role === "ai"),
      hasMemorySummary: !!request.memorySummary,
      hasMultipleTurns: request.turns.length > 1,
      requestAiTurnCount: request.turns.filter((turn) => turn.role === "ai")
        .length,
    });
    if (!continuation.allowed) {
      logInfo("practice_chat_upgrade_required", {
        user: summarizeUser(user.id),
        roundIndex: request.roundIndex,
        sessionId: request.sessionId,
        visiblePracticeThreadId: request.visiblePracticeThreadId,
      });
      return jsonResponse({ error: continuation.reason }, 402);
    }

    const { atCap, shouldChargePreview } = decideChatGate({
      ledger,
      isTestAccount: accountIsTest,
    });
    if (atCap) {
      return jsonResponse({ error: "practice_session_complete" }, 409);
    }

    if (shouldChargePreview) {
      const quotaGate = checkQuota({
        sub,
        cost: PRACTICE_QUOTA_COST,
        isTestAccount: accountIsTest,
        monthlyLimit: limits.monthly,
        dailyLimit: limits.daily,
      });
      if (!quotaGate.ok) {
        logWarn("practice_chat_quota_exceeded", {
          user: summarizeUser(user.id),
          reason: quotaGate.reason,
        });
        return jsonResponse(
          buildQuotaExceededPayload({
            sub,
            cost: PRACTICE_QUOTA_COST,
            reason: quotaGate.reason,
            monthlyLimit: limits.monthly,
            dailyLimit: limits.daily,
          }),
          429,
        );
      }
    }

    // 模型呼叫限流（docs/plans/2026-07-03-model-rate-limit-design.md）：
    // practice_turn 12/分、400/日。放在續聊 402／session cap 409／quota 429
    // 三道 gate 之後（各自語義優先）、DeepSeek 呼叫前。
    const turnRateVerdict = await enforceModelRateLimit({
      supabase,
      userId: user.id,
      scope: "practice_turn",
      isTestAccount: accountIsTest,
    });
    if (turnRateVerdict.kind === "limited") {
      logWarn("model_rate_limited", {
        user: summarizeUser(user.id),
        scope: "practice_turn",
        reason: turnRateVerdict.reason,
      });
      return jsonResponse(turnRateVerdict.payload, 429);
    }
    if (turnRateVerdict.kind === "failOpen") {
      // fail-open：infra 錯誤（非超限 RAISE）不擋核心流程，必留 telemetry。
      logError("model_rate_limit_check_failed", {
        user: summarizeUser(user.id),
        scope: "practice_turn",
        error: turnRateVerdict.errorMessage,
      });
    }

    const assistedMode = isAssistedPracticeMode(request.practiceMode);
    // 續聊保溫：只在 ledger 尚未建檔的新場首回合允許以 client 攜帶值 seed；
    // ledger 已建檔一律以 ledger 為準（欄位 null 的舊列 fallback 難度起始值，
    // 不吃 client 值——以建檔與否切分，堵舊列吃 seed 的洞）。
    const currentTemperature = assistedMode
      ? ledger.exists
        ? ledger.temperatureScore ?? difficultyStartTemperature
        : relationshipThreadState?.temperatureScore ??
          request.temperatureScore ?? difficultyStartTemperature
      : null;
    const currentFamiliarity = assistedMode
      ? ledger.exists
        ? ledger.familiarityScore ?? 0
        : relationshipThreadState?.familiarityScore ??
          request.familiarityScore ?? 0
      : null;
    const trustedPartnerState = partnerStateFromLedger(ledger) ??
      relationshipThreadState?.partnerState ?? null;
    const promptPartnerState = promptPartnerStateForRequest(
      ledger,
      request,
      relationshipThreadState,
    );

    try {
      await assertPracticeLearningReady({
        supabase,
        userId: user.id,
        sessionId: request.sessionId,
      });
    } catch (e) {
      const mapped = mapLedgerError(getErrorMessage(e));
      logWarn("practice_chat_learning_not_ready", {
        user: summarizeUser(user.id),
        error: getErrorMessage(e),
      });
      return jsonResponse({ error: mapped.error }, mapped.status);
    }

    let reply: string | null = null;
    try {
      let lastError: unknown;
      for (let attempt = 1; attempt <= CHAT_GENERATION_ATTEMPTS; attempt++) {
        try {
          reply = await deps.callDeepSeek({
            apiKey,
            messages: buildChatMessages(
              request.turns,
              request.profile,
              assistedMode
                ? {
                  practiceMode: request.practiceMode,
                  temperatureScore: currentTemperature ??
                    difficultyStartTemperature,
                  familiarityScore: currentFamiliarity ?? 0,
                  partnerState: promptPartnerState,
                  sceneContext,
                  memorySummary: promptMemorySummary,
                  gameState: ledgerGameState,
                }
                : {
                  partnerState: promptPartnerState,
                  sceneContext,
                  memorySummary: promptMemorySummary,
                },
            ),
            maxTokens: CHAT_MAX_TOKENS,
            temperature: CHAT_TEMPERATURE,
            timeoutMs: DEEPSEEK_TIMEOUT_MS,
          });
          rejectVisibleInternalLabelLeak(reply, "chat_internal_label_leak");
          rejectL4UnsafeVisibleText(reply, "chat_l4_unsafe");
          break;
        } catch (e) {
          lastError = e;
          logWarn("practice_chat_chat_generation_attempt_failed", {
            user: summarizeUser(user.id),
            attempt,
            error: getErrorMessage(e),
          });
        }
      }
      if (reply === null) {
        throw lastError instanceof Error
          ? lastError
          : new Error("chat_generation_failed");
      }
    } catch (e) {
      logWarn("practice_chat_generation_failed", {
        user: summarizeUser(user.id),
        mode: "chat",
        personaId: request.profile.personaId,
        difficulty: request.profile.difficulty,
        error: getErrorMessage(e),
      });
      return jsonResponse({ error: "practice_generation_failed" }, 500);
    }

    const { data: commitData, error: commitError } = await supabase.rpc(
      "commit_practice_chat_turn",
      {
        p_user_id: user.id,
        p_session_id: request.sessionId,
        p_charge_quota: !accountIsTest,
        p_max_replies: MAX_AI_REPLIES,
        p_practice_mode: request.practiceMode,
        // standard 模式一律 null：client 溫度值本就被 RPC 忽略（非 beginner 存
        // NULL）。beginner 由 ledger 權威值驅動；ledger 建檔前 fallback 為
        // client 攜帶值（續聊保溫）→ 難度起始值。
        p_temperature_score: currentTemperature,
        p_familiarity_score: currentFamiliarity,
        p_partner_mood: trustedPartnerState?.mood ?? null,
        p_partner_inner_thought: trustedPartnerState?.innerThought ?? null,
      },
    );
    if (commitError) {
      const mapped = mapLedgerError(commitError.message);
      logWarn("practice_chat_commit_failed", {
        user: summarizeUser(user.id),
        error: commitError.message,
      });
      return jsonResponse({ error: mapped.error }, mapped.status);
    }
    const commitRow = Array.isArray(commitData) ? commitData[0] : commitData;
    const newAiCount = (commitRow?.new_ai_count as number | undefined) ?? 0;
    const didCharge = (commitRow?.did_charge as boolean | undefined) ?? false;
    const deducted = didCharge ? PRACTICE_QUOTA_COST : 0;

    let temperature: LearningJudgement | null = null;
    if (assistedMode && currentTemperature !== null) {
      try {
        temperature = await judgeLearningState({
          deps,
          apiKey,
          supabase,
          userId: user.id,
          sessionId: request.sessionId,
          currentTemperature,
          currentFamiliarity: currentFamiliarity ?? 0,
          currentPartnerState: trustedPartnerState,
          request,
          reply,
        });
      } catch (e) {
        const mapped = mapLedgerError(getErrorMessage(e));
        logWarn("practice_chat_learning_not_ready", {
          user: summarizeUser(user.id),
          error: getErrorMessage(e),
        });
        return jsonResponse({ error: mapped.error }, mapped.status);
      }
    }

    if (request.practiceMode === "game" && temperature) {
      const snapshot = evaluateGameFsm({
        turns: request.turns,
        temperatureScore: temperature.score,
        familiarityScore: temperature.familiarityScore,
        partnerMood: temperature.partnerState?.mood ??
          trustedPartnerState?.mood ?? null,
        classification: temperature.classification,
      });
      await persistGameStateFailOpen({
        supabase,
        userId: user.id,
        sessionId: request.sessionId,
        gameState: buildNextGameState({
          previous: ledgerGameState,
          snapshot,
          now: deps.now?.(),
        }),
      });
    }

    if (assistedMode && temperature) {
      const inviteMaturity = inviteMaturityFromLearningScores({
        temperatureScore: temperature.score,
        familiarityScore: temperature.familiarityScore,
        partnerMood: temperature.partnerState?.mood ?? null,
      });
      if (inviteMaturity) {
        await upsertRelationshipThreadFailOpen({
          supabase,
          params: buildRelationshipThreadRpcParams({
            userId: user.id,
            visibleThreadId,
            profileId: request.profile.girl.profileId,
            practiceMode: request.practiceMode,
            relationshipScore: inviteMaturity.score,
            temperatureScore: temperature.score,
            familiarityScore: temperature.familiarityScore,
            partnerState: temperature.partnerState ?? trustedPartnerState,
            inviteStage: inviteMaturity.stage,
            memorySummary: null,
            aiTurnCount: newAiCount,
          }),
        });
      }
    }

    logInfo("practice_chat_succeeded", {
      user: summarizeUser(user.id),
      mode: "chat",
      aiTurnCount: newAiCount,
      personaId: request.profile.personaId,
      difficulty: request.profile.difficulty,
      costDeducted: deducted,
    });

    const body: Record<string, unknown> = {
      reply,
      aiTurnCount: newAiCount,
      sessionComplete: isSessionComplete(newAiCount),
      costDeducted: deducted,
      provider: "deepseek",
      model: DEEPSEEK_MODEL,
      generatedAt: (deps.now?.() ?? new Date()).toISOString(),
      ...remainingFrom(sub, limits, deducted),
    };
    if (temperature) {
      body.temperature = learningJudgementResponse(temperature);
      if (temperature.partnerState) {
        body.partnerState = temperature.partnerState;
      }
      body.hintUsedCount = ledger.hintCount ?? 0;
    }
    return jsonResponse(body);
  };
}
