import {
  buildQuotaExceededPayload,
  checkQuota,
  classifyQuotaRpcError,
  isPlainObject,
  resolveLimits,
  type SubscriptionRow,
  TEST_EMAILS,
} from "../_shared/quota.ts";
import { enforceModelRateLimit } from "../_shared/model_rate_limit.ts";
import {
  type AppliedHintDecision,
  type AppliedHintTurn,
  SEMANTIC_QUALITY_SCHEMA_VERSION,
  validateDrawRequest,
  validateRequest,
} from "./validate.ts";
import {
  buildHintPrefetchTelemetry,
  decideHintPrefetchReplay,
  HINT_QUALITY_SCHEMA_VERSION,
  HINT_REVIEW_SCHEMA_VERSION,
  hintPrefetchAck,
  type HintPrefetchTelemetryOutcome,
  type HintPrefetchTelemetryReason,
  hintRecordPolicy,
  type HintRequestLedgerRow,
  isExplicitModelHintResult,
  isHintPrefetchEnabled,
  isReplayableModelHintResult,
} from "./hint_prefetch.ts";
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
  DEBRIEF_QUALITY_SCHEMA_VERSION,
  DEBRIEF_TOOL_SCHEMA,
  type DebriefCard,
  parseDebriefCard,
} from "./debrief_card.ts";
import {
  buildHintDecision,
  buildHintMessages,
  HINT_TOOL_SCHEMA,
  hintTrustedFactualEvidence,
  parseHintResult,
} from "./hint.ts";
import {
  runSingleShot,
  type SingleShotAttemptFailure,
  SingleShotExhaustedError,
} from "./single_shot.ts";
import {
  CLAUDE_HAIKU_MODEL,
  CLAUDE_SONNET_MODEL,
  type ClaudeArgs,
} from "./claude.ts";
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
import {
  buildPracticeAiLogRow,
  buildPracticeGenerationTelemetry,
  classifyPracticeGenerationFailure,
  countPromptChars,
  type PracticeGenerationFailureClass,
  sanitizePracticeFailureCode,
} from "./telemetry.ts";

const MAX_BODY_BYTES = 64 * 1024;
const CHAT_MAX_TOKENS = 200;
const CHAT_TEMPERATURE = 0.9;
const CHAT_GENERATION_ATTEMPTS = 2;
const DEBRIEF_MAX_TOKENS = 1200;
const DEBRIEF_TEMPERATURE = 0.5;
// 新死線 45s＋緩衝；防 crash 的 in-flight 標記不再卡使用者 105 秒。
// 若觀測到重複生成，一行 revert 回 105000。
const DEBRIEF_IN_FLIGHT_STALE_MS = 60000;
// 單發重設計 v2：Sonnet 5 一發（15s）＋Haiku 4.5 補發（15s）＋record/回傳緩衝。
const HINT_REQUEST_DEADLINE_MS = 35000;
const HINT_SINGLE_SHOT_TIMEOUT_MS = 15000;
const LEGACY_CLIENT_QUALITY_SCHEMA_VERSION = "typed-facts-v1";
// 單發 tool_use 只輸出三段可見文字（無 DeepSeek thinking 洩流），500 足夠；
// 若 ai_logs 出現 max_tokens 截斷聚集再開小案調 500→700，不回加重試層。
const HINT_MAX_TOKENS = 500;
const HINT_TEMPERATURE = 0.45;
const SERVER_HINT_DECISION_RATIONALE =
  "只依據本場逐字稿與已知角色資料；貼句已依目前關係階段與邀約路線校驗。";
// 單發重設計 v2：Sonnet 5 一發（20s）＋Haiku 4.5 補發（20s）＋record/回傳緩衝。
const DEBRIEF_REQUEST_DEADLINE_MS = 45000;
const DEBRIEF_SINGLE_SHOT_TIMEOUT_MS = 20000;
const TEMPERATURE_JUDGE_MAX_TOKENS = 450;
const TEMPERATURE_JUDGE_TEMPERATURE = 0.2;
const DEEPSEEK_TIMEOUT_MS = 30000;
const TELEMETRY_PERSIST_TIMEOUT_MS = 1500;

function elapsedMilliseconds(startedAt: number): number {
  return Math.max(0, Math.round(performance.now() - startedAt));
}

function appendPracticeFailureCodes(
  target: string[],
  error: unknown,
): void {
  const codes = [sanitizePracticeFailureCode(error)].filter((
    value,
  ): value is string => value !== null);
  for (const code of codes) {
    if (target.length >= 3) break;
    if (!target.includes(code)) target.push(code);
  }
}

function isFreshDebriefGeneration(
  startedAt: unknown,
  now: Date,
): boolean {
  const timestamp = startedAt instanceof Date
    ? startedAt.getTime()
    : typeof startedAt === "string"
    ? Date.parse(startedAt)
    : Number.NaN;
  return Number.isFinite(timestamp) &&
    timestamp > now.getTime() - DEBRIEF_IN_FLIGHT_STALE_MS;
}

interface DebriefRequestLedgerEntry {
  result: Record<string, unknown> | null;
  startedAt: string | null;
  generationToken: string | null;
  counted: boolean;
}

function parseDebriefRequestLedger(
  value: unknown,
): Map<string, DebriefRequestLedgerEntry> | null {
  if (!isPlainObject(value)) return null;
  const rows = Object.entries(value);
  if (rows.length > MAX_DEBRIEFS) return null;

  const ledger = new Map<string, DebriefRequestLedgerEntry>();
  for (const [requestId, rawEntry] of rows) {
    if (requestId.length < 1 || requestId.length > 64) return null;
    if (!isPlainObject(rawEntry)) return null;
    const keys = Object.keys(rawEntry).sort();
    if (
      keys.length !== 4 ||
      keys.join(",") !== "counted,generation_token,result,started_at"
    ) {
      return null;
    }

    const result = rawEntry.result === null
      ? null
      : isPlainObject(rawEntry.result)
      ? rawEntry.result
      : undefined;
    const startedAt = rawEntry.started_at === null
      ? null
      : typeof rawEntry.started_at === "string" &&
          Number.isFinite(Date.parse(rawEntry.started_at))
      ? rawEntry.started_at
      : undefined;
    const generationToken = rawEntry.generation_token === null
      ? null
      : typeof rawEntry.generation_token === "string" &&
          rawEntry.generation_token.length >= 1 &&
          rawEntry.generation_token.length <= 64
      ? rawEntry.generation_token
      : undefined;
    const counted = typeof rawEntry.counted === "boolean"
      ? rawEntry.counted
      : undefined;
    if (
      result === undefined || startedAt === undefined ||
      generationToken === undefined || counted === undefined ||
      (startedAt !== null && generationToken === null) ||
      (result !== null && (startedAt !== null || !counted)) ||
      (!counted &&
        (result !== null || startedAt === null || generationToken === null))
    ) {
      return null;
    }
    ledger.set(requestId, { result, startedAt, generationToken, counted });
  }
  return ledger;
}

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
export type ClaudeCaller = (args: ClaudeArgs) => Promise<string>;

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
  callClaude?: ClaudeCaller;
  getEnv: (name: string) => string | undefined;
  now?: () => Date;
  monotonicNow?: () => number;
  randomUUID?: () => string;
  /** Production uses EdgeRuntime.waitUntil; tests may inject a collector. */
  waitUntil?: (task: Promise<void>) => void;
  telemetryPersistTimeoutMs?: number;
}

async function persistGenerationTelemetryFailOpen(opts: {
  supabase: PracticeSupabaseClient;
  userId: string;
  mode: "hint" | "debrief";
  practiceMode: PracticeLearningMode;
  attempt: number;
  totalDurationMs: number;
  promptChars: number;
  fallbackUsed: boolean;
  failoverUsed?: boolean;
  failureClass: PracticeGenerationFailureClass | null;
  attemptDurationsMs: number[];
  failureClasses: PracticeGenerationFailureClass[];
  failureCodes?: string[];
  semanticProviderCalls?: number;
  model?: string;
  timeoutMs?: number;
  pipeline?: string;
}): Promise<void> {
  let timeoutHandle: ReturnType<typeof setTimeout> | undefined;
  try {
    const row = buildPracticeAiLogRow({
      userId: opts.userId,
      model: opts.model ?? DEEPSEEK_MODEL,
      telemetry: {
        mode: opts.mode,
        practiceMode: opts.practiceMode,
        attempt: opts.attempt,
        attemptDurationMs: null,
        failureClass: opts.failureClass,
        fallbackUsed: opts.fallbackUsed,
        failoverUsed: opts.failoverUsed,
        semanticProviderCalls: opts.semanticProviderCalls,
        totalDurationMs: opts.totalDurationMs,
        promptChars: opts.promptChars,
      },
      attemptDurationsMs: opts.attemptDurationsMs,
      failureClasses: opts.failureClasses,
      failureCodes: opts.failureCodes,
      pipeline: opts.pipeline,
    });
    const abortController = new AbortController();
    const rawQuery = opts.supabase.from("ai_logs").insert(row);
    const boundedQuery = typeof rawQuery?.abortSignal === "function"
      ? rawQuery.abortSignal(abortController.signal)
      : rawQuery;
    const insert = Promise.resolve(boundedQuery).then((value) => ({
      kind: "insert" as const,
      value: value as { error: { message: string } | null },
    }));
    const timeout = new Promise<{ kind: "timeout" }>((resolve) => {
      timeoutHandle = setTimeout(() => {
        abortController.abort();
        resolve({ kind: "timeout" });
      }, Math.max(1, opts.timeoutMs ?? TELEMETRY_PERSIST_TIMEOUT_MS));
    });
    const result = await Promise.race([insert, timeout]);
    if (result.kind === "timeout") {
      logError("practice_chat_generation_telemetry_persist_failed", {
        mode: opts.mode,
        practiceMode: opts.practiceMode,
      });
      return;
    }
    const { error } = result.value;
    if (error) {
      logError("practice_chat_generation_telemetry_persist_failed", {
        mode: opts.mode,
        practiceMode: opts.practiceMode,
      });
    }
  } catch {
    logError("practice_chat_generation_telemetry_persist_failed", {
      mode: opts.mode,
      practiceMode: opts.practiceMode,
    });
  } finally {
    if (timeoutHandle !== undefined) clearTimeout(timeoutHandle);
  }
}

function scheduleGenerationTelemetry(
  deps: PracticeChatHandlerDeps,
  opts: Parameters<typeof persistGenerationTelemetryFailOpen>[0],
): void {
  const task = persistGenerationTelemetryFailOpen({
    ...opts,
    timeoutMs: deps.telemetryPersistTimeoutMs,
  });
  try {
    if (deps.waitUntil) {
      deps.waitUntil(task);
      return;
    }
    const edgeRuntime = (globalThis as unknown as {
      EdgeRuntime?: { waitUntil(task: Promise<void>): void };
    }).EdgeRuntime;
    if (edgeRuntime?.waitUntil) {
      edgeRuntime.waitUntil(task);
      return;
    }
  } catch {
    // A scheduler failure must not turn optional observability into a 5xx.
  }
  // Local Deno tests do not expose EdgeRuntime. The persistence promise catches
  // its own failures, so detaching it here cannot create an unhandled rejection.
  void task;
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

/**
 * 格式／驗證類失敗（JSON 壞掉或 hint guard 拒絕）才適合帶「上一版被拒絕」的
 * 重試指令；timeout／上游 5xx 帶這句是誤導（模型根本沒輸出被拒的 JSON）。
 */
function isMissingPracticeHintRpc(message: string): boolean {
  const normalized = message.toLowerCase();
  const referencesHintRpc =
    normalized.includes("claim_practice_hint_generation") ||
    normalized.includes("record_practice_hint") ||
    normalized.includes("settle_prefetched_practice_hint") ||
    normalized.includes("discard_prefetched_practice_hint") ||
    normalized.includes("claim_legacy_practice_hint_replacement") ||
    normalized.includes("record_legacy_practice_hint_replacement") ||
    normalized.includes("release_legacy_practice_hint_replacement") ||
    normalized.includes("prepare_practice_subscription_usage") ||
    normalized.includes("release_practice_hint_generation");
  return referencesHintRpc &&
    (normalized.includes("could not find the function") ||
      normalized.includes("schema cache"));
}

function isMissingPreparePracticeUsageRpc(message: string): boolean {
  const normalized = message.toLowerCase();
  return normalized.includes("prepare_practice_subscription_usage") &&
    (normalized.includes("could not find the function") ||
      normalized.includes("schema cache"));
}

function isMissingPracticeDebriefRpc(message: string): boolean {
  const normalized = message.toLowerCase();
  const referencesDebriefRpc = normalized.includes("claim_practice_debrief") ||
    normalized.includes("record_practice_debrief");
  return referencesDebriefRpc &&
    (normalized.includes("could not find the function") ||
      normalized.includes("schema cache"));
}

function isMissingPracticeDebriefReplaySchema(message: string): boolean {
  const normalized = message.toLowerCase();
  const referencesReplaySchema =
    normalized.includes("last_debrief_request_id") ||
    normalized.includes("last_debrief_result") ||
    normalized.includes("last_debrief_started_at") ||
    normalized.includes("debrief_request_ledger");
  return referencesReplaySchema &&
    (normalized.includes("schema cache") ||
      normalized.includes("could not find") ||
      normalized.includes("does not exist") ||
      normalized.includes("undefined_column"));
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
  if (isMissingPracticeDebriefRpc(message)) {
    return { error: "practice_debrief_not_ready", status: 503 };
  }
  if (message.includes("PRACTICE_DEBRIEF_LEDGER_INVALID")) {
    return { error: "practice_debrief_not_ready", status: 503 };
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
  if (message.includes("PRACTICE_HINT_PREFETCH_PENDING")) {
    return { error: "practice_hint_prefetch_pending", status: 409 };
  }
  if (message.includes("PRACTICE_HINT_OWNER_MISMATCH")) {
    return { error: "practice_hint_in_flight", status: 403 };
  }
  if (
    message.includes("PRACTICE_HINT_STALE") ||
    message.includes("PRACTICE_HINT_PREFETCH_NOT_FOUND") ||
    message.includes("PRACTICE_HINT_STATE_MISMATCH") ||
    message.includes("PRACTICE_HINT_NOT_CLAIMED") ||
    message.includes("PRACTICE_HINT_REPLACEMENT_NOT_READY")
  ) {
    return { error: "practice_hint_stale", status: 409 };
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

function preparedSubscriptionFromRpc(value: unknown): SubscriptionRow | null {
  const row = Array.isArray(value) ? value[0] : value;
  if (!isPlainObject(row)) return null;
  const tier = row.tier;
  const monthlyUsed = row.monthly_messages_used;
  const dailyUsed = row.daily_messages_used;
  const dailyResetAt = row.daily_reset_at;
  const monthlyResetAt = row.monthly_reset_at;
  if (
    (typeof tier !== "string" && tier !== null) ||
    typeof monthlyUsed !== "number" ||
    !Number.isInteger(monthlyUsed) ||
    monthlyUsed < 0 ||
    typeof dailyUsed !== "number" ||
    !Number.isInteger(dailyUsed) ||
    dailyUsed < 0 ||
    (typeof dailyResetAt !== "string" && dailyResetAt !== null) ||
    (typeof monthlyResetAt !== "string" && monthlyResetAt !== null)
  ) {
    return null;
  }
  return {
    tier,
    monthly_messages_used: monthlyUsed,
    daily_messages_used: dailyUsed,
    daily_reset_at: dailyResetAt,
    monthly_reset_at: monthlyResetAt,
  };
}

function firstRpcRow(value: unknown): unknown {
  return Array.isArray(value) ? value[0] : value;
}

function hintRequestLedgerRowFromDb(
  value: unknown,
): HintRequestLedgerRow | null | undefined {
  if (value === null || value === undefined) return null;
  if (!isPlainObject(value)) return undefined;
  const state = value.state;
  const charged = value.charged;
  if (
    (state !== "generating" && state !== "prefetched" &&
      state !== "settled") ||
    typeof charged !== "boolean"
  ) {
    return undefined;
  }
  return {
    state,
    charged,
    result: value.result ?? null,
    isPrefetch: value.is_prefetch === true,
    legacyReplacementPending: value.legacy_replacement_pending === true,
  };
}

function logHintPrefetchTelemetry(opts: {
  outcome: HintPrefetchTelemetryOutcome;
  reason: HintPrefetchTelemetryReason;
  practiceMode: PracticeLearningMode;
}): void {
  if (opts.practiceMode === "standard") return;
  logInfo(
    "practice_chat_hint_prefetch",
    buildHintPrefetchTelemetry({
      outcome: opts.outcome,
      reason: opts.reason,
      practiceMode: opts.practiceMode,
    }),
  );
}

function prefetchFailureReason(
  failure: PracticeGenerationFailureClass | null,
): HintPrefetchTelemetryReason {
  return failure ?? "unknown";
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
  requestId?: string;
  generationToken?: string;
  legacyReplacement?: boolean;
}): Promise<void> {
  const rpcName = opts.legacyReplacement
    ? "release_legacy_practice_hint_replacement"
    : "release_practice_hint_generation";
  const { error } = await opts.supabase.rpc(
    rpcName,
    {
      p_user_id: opts.userId,
      p_session_id: opts.sessionId,
      ...(opts.requestId ? { p_request_id: opts.requestId } : {}),
      ...(opts.generationToken
        ? { p_generation_token: opts.generationToken }
        : {}),
    },
  );
  if (error) {
    logWarn("practice_chat_hint_release_failed", {
      user: summarizeUser(opts.userId),
      error: error.message,
    });
  }
}

async function releaseDebriefGeneration(opts: {
  supabase: PracticeSupabaseClient;
  userId: string;
  sessionId: string;
  requestId?: string;
  generationToken?: string;
}): Promise<void> {
  if (!opts.requestId || !opts.generationToken) return;
  const { error } = await opts.supabase.rpc(
    "release_practice_debrief_generation",
    {
      p_user_id: opts.userId,
      p_session_id: opts.sessionId,
      p_request_id: opts.requestId,
      p_generation_token: opts.generationToken,
    },
  );
  if (error) {
    logWarn("practice_chat_debrief_release_failed", {
      user: summarizeUser(opts.userId),
      error: error.message,
    });
  }
}

function isCurrentGeneratedDebriefEnvelope(
  value: unknown,
): value is Record<string, unknown> {
  return isPlainObject(value) &&
    value.generationSource === "model" &&
    value.fallbackUsed === false &&
    value.qualitySchemaVersion === DEBRIEF_QUALITY_SCHEMA_VERSION;
}

async function invalidateLegacyPracticeAiSnapshot(opts: {
  supabase: PracticeSupabaseClient;
  userId: string;
  sessionId: string;
  requestId?: string;
  kind: "hint" | "debrief";
}): Promise<boolean> {
  if (!opts.requestId) return false;
  const { data, error } = await opts.supabase.rpc(
    "invalidate_legacy_practice_ai_snapshot",
    {
      p_user_id: opts.userId,
      p_session_id: opts.sessionId,
      p_request_id: opts.requestId,
      p_kind: opts.kind,
    },
  );
  if (error) {
    logWarn("practice_chat_legacy_snapshot_invalidation_failed", {
      user: summarizeUser(opts.userId),
      kind: opts.kind,
      error: error.message,
    });
    return false;
  }
  return data === true || (Array.isArray(data) && data[0] === true);
}

function parseAuthoritativeHintDecision(
  value: unknown,
): AppliedHintDecision | null {
  if (!isPlainObject(value)) return null;
  const fields = [
    value.phase,
    value.targetVariable,
    value.move,
    value.inviteRoute,
    value.rationale,
  ];
  if (
    fields.some((field) =>
      typeof field !== "string" || field.trim().length === 0
    ) ||
    String(value.phase).length > 80 ||
    String(value.targetVariable).length > 80 ||
    String(value.move).length > 80 ||
    String(value.inviteRoute).length > 80 ||
    String(value.rationale).length > 160
  ) {
    return null;
  }
  return {
    phase: String(value.phase).trim(),
    targetVariable: String(value.targetVariable).trim(),
    move: String(value.move).trim(),
    inviteRoute: String(value.inviteRoute).trim(),
    rationale: String(value.rationale).trim(),
  };
}

function isDisconnectedHintLineageError(message: string): boolean {
  const normalized = message.toUpperCase();
  return normalized.includes("PRACTICE_HINT_LINEAGE_MISMATCH") ||
    normalized.includes("PRACTICE_HINT_LINEAGE_NOT_READY") ||
    normalized.includes("PRACTICE_HINT_DECISION_NOT_READY");
}

async function hydrateAppliedHintDecisions(opts: {
  supabase: PracticeSupabaseClient;
  userId: string;
  sessionId: string;
  turns?: AppliedHintTurn[];
}): Promise<AppliedHintTurn[] | undefined> {
  if (!opts.turns || opts.turns.length === 0) return opts.turns;
  const hydrated: AppliedHintTurn[] = [];
  let dropped = 0;
  for (const turn of opts.turns) {
    if (!turn.hintRequestId) {
      dropped += 1;
      continue;
    }
    const { data, error } = await opts.supabase.rpc(
      "resolve_practice_hint_decision",
      {
        p_user_id: opts.userId,
        p_session_id: opts.sessionId,
        p_request_id: turn.hintRequestId,
        p_hint_type: turn.type,
        p_original_hint_text: turn.originalHintText,
      },
    );
    if (error) {
      if (isDisconnectedHintLineageError(error.message)) {
        dropped += 1;
        continue;
      }
      throw new Error("practice_hint_lineage_resolution_failed");
    }
    const decision = parseAuthoritativeHintDecision(data);
    if (!decision) {
      throw new Error("practice_hint_lineage_resolution_failed");
    }
    hydrated.push({ ...turn, decision });
  }
  if (dropped > 0) {
    logWarn("practice_chat_hint_lineage_dropped", {
      user: summarizeUser(opts.userId),
      sessionId: opts.sessionId,
      dropped,
    });
  }
  return hydrated.length > 0 ? hydrated : undefined;
}

export function createPracticeChatHandler(
  deps: PracticeChatHandlerDeps,
): (req: Request) => Promise<Response> {
  return async function handleRequest(req: Request): Promise<Response> {
    const monotonicNow = deps.monotonicNow ?? (() => performance.now());
    const requestStartedAtMs = monotonicNow();
    const hintAbsoluteDeadlineAtMs = requestStartedAtMs +
      HINT_REQUEST_DEADLINE_MS;
    const debriefAbsoluteDeadlineAtMs = requestStartedAtMs +
      DEBRIEF_REQUEST_DEADLINE_MS;
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

    const configuredDeepSeekApiKey = deps.getEnv("DEEPSEEK_API_KEY");
    const claudeApiKey = deps.getEnv("CLAUDE_API_KEY");
    const structuredGenerationAvailable = !!configuredDeepSeekApiKey ||
      (!!claudeApiKey && !!deps.callClaude);
    if (
      (request.mode === "chat" && !configuredDeepSeekApiKey) ||
      (request.mode !== "chat" && !structuredGenerationAvailable)
    ) {
      logError("practice_chat_config_missing", {
        user: summarizeUser(user.id),
      });
      return jsonResponse({ error: "config_missing" }, 500);
    }
    const apiKey = configuredDeepSeekApiKey ?? "";

    const { data: preparedSubData, error: subError } = await supabase.rpc(
      "prepare_practice_subscription_usage",
      { p_user_id: user.id },
    );
    if (subError) {
      logWarn("practice_chat_sub_fetch_error", {
        user: summarizeUser(user.id),
        error: subError.message,
      });
      if (subError.message.includes("PRACTICE_SUBSCRIPTION_NOT_FOUND")) {
        return jsonResponse({ error: "No subscription found" }, 403);
      }
      if (isMissingPreparePracticeUsageRpc(subError.message)) {
        return jsonResponse(
          {
            error: request.mode === "hint"
              ? "practice_hint_not_ready"
              : "practice_learning_not_ready",
          },
          503,
        );
      }
      return jsonResponse({ error: "subscription_fetch_failed" }, 500);
    }
    const sub = preparedSubscriptionFromRpc(preparedSubData);
    if (!sub) {
      logWarn("practice_chat_sub_fetch_error", {
        user: summarizeUser(user.id),
        error: "invalid prepare_practice_subscription_usage response",
      });
      return jsonResponse({ error: "subscription_fetch_failed" }, 500);
    }

    const accountIsTest = TEST_EMAILS.includes(user.email || "");
    const limits = resolveLimits(sub.tier);
    const responsePayloadWithCurrentUsage = (
      snapshot: Record<string, unknown>,
      deductedThisCall = 0,
    ): Record<string, unknown> => {
      const isSemanticQualitySnapshot =
        snapshot.qualitySchemaVersion === SEMANTIC_QUALITY_SCHEMA_VERSION;
      const visibleSnapshot = Object.fromEntries(
        Object.entries(snapshot).filter(([key]) =>
          key !== "hintReviewSchemaVersion"
        ),
      );
      return {
        ...visibleSnapshot,
        // The DB snapshot keeps the semantic-quality-v2 certification. Only
        // the HTTP envelope is downlevelled for build 322 and older clients;
        // generation and replay validation never fall back to typed-facts.
        ...(isSemanticQualitySnapshot
          ? {
            qualitySchemaVersion: request.acceptedQualitySchemaVersion ??
              LEGACY_CLIENT_QUALITY_SCHEMA_VERSION,
          }
          : {}),
        // A stored snapshot records historical billing provenance, not what this
        // HTTP call deducted. Replays must report zero; settle/record paths pass
        // the exact amount charged now. Remaining counters likewise come from
        // this request's freshly prepared subscription so another session or
        // device can never be rolled backwards by an old snapshot.
        costDeducted: deductedThisCall,
        ...remainingFrom(sub, limits, deductedThisCall),
      };
    };

    const baseLedgerColumns =
      "ai_count, charged, debrief_count, practice_mode, temperature_score, familiarity_score, partner_mood, partner_inner_thought, hint_count, game_state";
    const ledgerColumns = request.mode === "debrief"
      ? `${baseLedgerColumns}, last_debrief_request_id, last_debrief_result, last_debrief_started_at, debrief_request_ledger`
      : baseLedgerColumns;
    const { data: ledgerRow, error: ledgerError } = await supabase
      .from("practice_chat_sessions")
      .select(ledgerColumns)
      .eq("user_id", user.id)
      .eq("session_id", request.sessionId)
      .maybeSingle();
    if (ledgerError) {
      const mapped = isMissingDualAxisLearningSchema(ledgerError.message)
        ? { error: "practice_learning_not_ready", status: 503 }
        : request.mode === "debrief" &&
            isMissingPracticeDebriefReplaySchema(ledgerError.message)
        ? { error: "practice_debrief_not_ready", status: 503 }
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

      const requestIsPrefetch = request.prefetch === true;
      const prefetchEnabled = isHintPrefetchEnabled(
        deps.getEnv("PRACTICE_HINT_PREFETCH_ENABLED"),
      );
      const hintRequestId = request.requestId;

      const hintQuotaGateResponse = (): Response | null => {
        const quotaGate = checkQuota({
          sub,
          cost: PRACTICE_QUOTA_COST,
          isTestAccount: accountIsTest,
          monthlyLimit: limits.monthly,
          dailyLimit: limits.daily,
        });
        if (quotaGate.ok) return null;
        logWarn("practice_chat_quota_exceeded", {
          user: summarizeUser(user.id),
          reason: quotaGate.reason,
        });
        if (requestIsPrefetch) {
          logHintPrefetchTelemetry({
            outcome: "failed",
            reason: "quota",
            practiceMode: request.practiceMode,
          });
        }
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
      };

      const mutableHintGateResponse = (): Response | null => {
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
          if (requestIsPrefetch) {
            logHintPrefetchTelemetry({
              outcome: "failed",
              reason: "gate",
              practiceMode: request.practiceMode,
            });
          }
          const reason = gate.reason ?? "practice_session_not_started";
          return jsonResponse(
            { error: reason },
            reason === "practice_session_complete" ? 409 : 403,
          );
        }

        return hintQuotaGateResponse();
      };

      const quotaResponseForRpcError = async (
        message: string,
      ): Promise<Response | null> => {
        const reason = classifyQuotaRpcError(message);
        if (reason === null) return null;
        const { data: refreshedData, error: refreshedError } = await supabase
          .rpc("prepare_practice_subscription_usage", {
            p_user_id: user.id,
          });
        const refreshedSub = refreshedError
          ? null
          : preparedSubscriptionFromRpc(refreshedData);
        if (
          refreshedError &&
          isMissingPreparePracticeUsageRpc(refreshedError.message)
        ) {
          return jsonResponse({ error: "practice_hint_not_ready" }, 503);
        }
        if (!refreshedSub) {
          return jsonResponse({ error: "subscription_fetch_failed" }, 500);
        }
        return jsonResponse(
          buildQuotaExceededPayload({
            sub: refreshedSub,
            cost: PRACTICE_QUOTA_COST,
            reason,
            monthlyLimit: limits.monthly,
            dailyLimit: limits.daily,
          }),
          429,
        );
      };

      const settlePrefetchedHint = async (): Promise<
        | { kind: "response"; response: Response }
        | { kind: "legacyReplacement" }
      > => {
        if (!hintRequestId) {
          return {
            kind: "response",
            response: jsonResponse({ error: "practice_hint_not_ready" }, 503),
          };
        }
        const settleHintParams: Record<string, unknown> = {
          p_user_id: user.id,
          p_session_id: request.sessionId,
          p_request_id: hintRequestId,
          p_charge_quota: !accountIsTest,
          p_max_hints: MAX_HINTS_PER_ROUND,
          p_max_replies: MAX_AI_REPLIES,
          p_monthly_limit: limits.monthly,
          p_daily_limit: limits.daily,
        };
        if (request.expectedAiCount !== undefined) {
          settleHintParams.p_expected_ai_count = request.expectedAiCount;
        }
        const { data, error } = await supabase.rpc(
          "settle_prefetched_practice_hint",
          settleHintParams,
        );
        if (error) {
          const quotaResponse = await quotaResponseForRpcError(error.message);
          if (quotaResponse) {
            return { kind: "response", response: quotaResponse };
          }
          const mapped = mapLedgerError(error.message);
          return {
            kind: "response",
            response: jsonResponse({ error: mapped.error }, mapped.status),
          };
        }
        const row = firstRpcRow(data);
        if (
          !isPlainObject(row) ||
          !isPlainObject(row.stored_result) ||
          row.stored_charged !== true ||
          typeof row.did_charge !== "boolean" ||
          typeof row.new_hint_count !== "number" ||
          !Number.isInteger(row.new_hint_count) ||
          row.new_hint_count < 0
        ) {
          return {
            kind: "response",
            response: jsonResponse({ error: "practice_hint_not_ready" }, 503),
          };
        }
        if (!isExplicitModelHintResult(row.stored_result)) {
          return { kind: "legacyReplacement" };
        }
        logHintPrefetchTelemetry({
          outcome: "hit",
          reason: "unknown",
          practiceMode: request.practiceMode,
        });
        return {
          kind: "response",
          response: jsonResponse(
            responsePayloadWithCurrentUsage(
              row.stored_result,
              row.did_charge ? PRACTICE_QUOTA_COST : 0,
            ),
          ),
        };
      };

      const discardPrefetchedHint = async (): Promise<
        | { kind: "fresh" }
        | { kind: "legacyReplacement" }
        | { kind: "response"; response: Response }
      > => {
        if (!hintRequestId) return { kind: "fresh" };
        const { data, error } = await supabase.rpc(
          "discard_prefetched_practice_hint",
          {
            p_user_id: user.id,
            p_session_id: request.sessionId,
            p_request_id: hintRequestId,
          },
        );
        if (error) {
          const mapped = mapLedgerError(error.message);
          return {
            kind: "response",
            response: jsonResponse({ error: mapped.error }, mapped.status),
          };
        }
        const row = firstRpcRow(data);
        if (
          !isPlainObject(row) ||
          typeof row.discarded !== "boolean" ||
          typeof row.replay !== "boolean"
        ) {
          return {
            kind: "response",
            response: jsonResponse({ error: "practice_hint_not_ready" }, 503),
          };
        }
        if (
          row.replay === true &&
          row.stored_charged === true &&
          isPlainObject(row.stored_result)
        ) {
          if (!isExplicitModelHintResult(row.stored_result)) {
            return { kind: "legacyReplacement" };
          }
          logHintPrefetchTelemetry({
            outcome: "hit",
            reason: "unknown",
            practiceMode: request.practiceMode,
          });
          return {
            kind: "response",
            response: jsonResponse(
              responsePayloadWithCurrentUsage(row.stored_result),
            ),
          };
        }
        return { kind: "fresh" };
      };

      const hintGenerationToken = deps.randomUUID?.() ?? crypto.randomUUID();
      let hintLegacyReplacementClaimed = false;
      let hintReplacementQuotaAlreadyPaid = false;
      const claimLegacyHintReplacement = async (): Promise<
        | { kind: "claimed" }
        | { kind: "response"; response: Response }
      > => {
        if (!hintRequestId || request.expectedAiCount === undefined) {
          return {
            kind: "response",
            response: jsonResponse({ error: "practice_hint_not_ready" }, 503),
          };
        }
        const { data, error } = await supabase.rpc(
          "claim_legacy_practice_hint_replacement",
          {
            p_user_id: user.id,
            p_session_id: request.sessionId,
            p_request_id: hintRequestId,
            p_generation_token: hintGenerationToken,
            p_expected_ai_count: request.expectedAiCount,
          },
        );
        if (error) {
          const mapped = mapLedgerError(error.message);
          return {
            kind: "response",
            response: jsonResponse({ error: mapped.error }, mapped.status),
          };
        }
        const row = firstRpcRow(data);
        if (!isPlainObject(row)) {
          return {
            kind: "response",
            response: jsonResponse({ error: "practice_hint_not_ready" }, 503),
          };
        }
        if (
          row.replay === true &&
          isPlainObject(row.stored_result) &&
          isReplayableModelHintResult(row.stored_result)
        ) {
          return {
            kind: "response",
            response: jsonResponse(
              responsePayloadWithCurrentUsage(row.stored_result),
            ),
          };
        }
        if (
          row.claimed !== true ||
          row.replay !== false ||
          typeof row.current_hint_count !== "number" ||
          !Number.isInteger(row.current_hint_count) ||
          row.current_hint_count < 1 ||
          typeof row.quota_already_paid !== "boolean"
        ) {
          return {
            kind: "response",
            response: jsonResponse({ error: "practice_hint_not_ready" }, 503),
          };
        }
        hintLegacyReplacementClaimed = true;
        hintReplacementQuotaAlreadyPaid = row.quota_already_paid;
        logInfo("practice_chat_legacy_hint_replacement_claimed", {
          user: summarizeUser(user.id),
          quotaAlreadyPaid: hintReplacementQuotaAlreadyPaid,
        });
        return { kind: "claimed" };
      };

      let preflightState: HintRequestLedgerRow | null = null;
      let preflightWasPrefetch = false;
      if (hintRequestId) {
        const { data: requestRow, error: requestError } = await supabase
          .from("practice_hint_requests")
          .select(
            "state, result, charged, is_prefetch, claimed_ai_count, legacy_replacement_pending",
          )
          .eq("user_id", user.id)
          .eq("session_id", request.sessionId)
          .eq("request_id", hintRequestId)
          .maybeSingle();
        if (requestError) {
          logWarn("practice_chat_hint_replay_preflight_failed", {
            user: summarizeUser(user.id),
            error: requestError.message,
          });
          return jsonResponse({ error: "practice_hint_not_ready" }, 503);
        }
        const parsed = hintRequestLedgerRowFromDb(requestRow);
        if (
          parsed === undefined ||
          (requestRow !== null &&
            (!isPlainObject(requestRow) ||
              typeof requestRow.is_prefetch !== "boolean"))
        ) {
          return jsonResponse({ error: "practice_hint_not_ready" }, 503);
        }
        preflightState = parsed;
        preflightWasPrefetch = parsed?.isPrefetch === true;
      }

      const preflightDecision = decideHintPrefetchReplay({
        requestPrefetch: requestIsPrefetch,
        row: preflightState,
      });
      if (preflightDecision.kind === "invalid") {
        return jsonResponse({ error: "practice_hint_not_ready" }, 503);
      }
      if (preflightDecision.kind === "opaqueAck") {
        return jsonResponse(hintPrefetchAck());
      }
      if (preflightDecision.kind === "settledReplay") {
        if (preflightWasPrefetch) {
          logHintPrefetchTelemetry({
            outcome: "hit",
            reason: "unknown",
            practiceMode: request.practiceMode,
          });
        }
        return jsonResponse(
          responsePayloadWithCurrentUsage(preflightDecision.result),
        );
      }
      if (preflightDecision.kind === "legacyReplacementClaim") {
        const replacement = await claimLegacyHintReplacement();
        if (replacement.kind === "response") return replacement.response;
      } else if (preflightDecision.kind === "legacyPrefetchDiscard") {
        const discarded = await discardPrefetchedHint();
        if (discarded.kind === "response") return discarded.response;
        if (discarded.kind === "legacyReplacement") {
          const replacement = await claimLegacyHintReplacement();
          if (replacement.kind === "response") return replacement.response;
        }
      } else if (preflightDecision.kind === "prefetchedConsume") {
        const gateResponse = mutableHintGateResponse();
        if (gateResponse) return gateResponse;
        if (prefetchEnabled) {
          const settled = await settlePrefetchedHint();
          if (settled.kind === "response") return settled.response;
          const replacement = await claimLegacyHintReplacement();
          if (replacement.kind === "response") return replacement.response;
        } else {
          const discarded = await discardPrefetchedHint();
          if (discarded.kind === "response") return discarded.response;
          if (discarded.kind === "legacyReplacement") {
            const replacement = await claimLegacyHintReplacement();
            if (replacement.kind === "response") return replacement.response;
          }
        }
      } else if (
        preflightDecision.kind === "continueToClaim" &&
        !requestIsPrefetch &&
        !prefetchEnabled &&
        preflightWasPrefetch
      ) {
        const discarded = await discardPrefetchedHint();
        if (discarded.kind === "response") return discarded.response;
        if (discarded.kind === "legacyReplacement") {
          const replacement = await claimLegacyHintReplacement();
          if (replacement.kind === "response") return replacement.response;
        }
      }

      if (hintLegacyReplacementClaimed) {
        if (!hintReplacementQuotaAlreadyPaid) {
          const quotaResponse = hintQuotaGateResponse();
          if (quotaResponse) {
            await releaseHintGeneration({
              supabase,
              userId: user.id,
              sessionId: request.sessionId,
              requestId: hintRequestId,
              generationToken: hintGenerationToken,
              legacyReplacement: true,
            });
            return quotaResponse;
          }
        }
      } else {
        // Exact replay/settlement paths return above. Fresh generation must use
        // the same full-session AI count the client transcript was built from.
        // The RPC repeats this check under the session row lock to close a chat
        // commit racing between this read and the claim.
        if (
          request.expectedAiCount !== undefined &&
          request.expectedAiCount !== ledger.aiCount
        ) {
          if (requestIsPrefetch) {
            logHintPrefetchTelemetry({
              outcome: "failed",
              reason: "gate",
              practiceMode: request.practiceMode,
            });
          }
          logWarn("practice_chat_hint_stale_client_turn", {
            user: summarizeUser(user.id),
            expectedAiCount: request.expectedAiCount,
            serverAiCount: ledger.aiCount,
          });
          return jsonResponse({ error: "practice_hint_stale" }, 409);
        }

        const freshGateResponse = mutableHintGateResponse();
        if (freshGateResponse) return freshGateResponse;
        if (requestIsPrefetch && !prefetchEnabled) {
          logHintPrefetchTelemetry({
            outcome: "failed",
            reason: "disabled",
            practiceMode: request.practiceMode,
          });
          return jsonResponse(
            { error: "practice_hint_prefetch_disabled" },
            503,
          );
        }
        if (request.prefetch === false) {
          logHintPrefetchTelemetry({
            outcome: "miss",
            reason: "unknown",
            practiceMode: request.practiceMode,
          });
        }
      }

      const claimHintParams: Record<string, unknown> = {
        p_user_id: user.id,
        p_session_id: request.sessionId,
        p_max_hints: MAX_HINTS_PER_ROUND,
        p_prefetch: requestIsPrefetch,
        p_generation_token: hintGenerationToken,
      };
      if (hintRequestId) claimHintParams.p_request_id = hintRequestId;
      if (request.expectedAiCount !== undefined) {
        claimHintParams.p_expected_ai_count = request.expectedAiCount;
      }

      let freshHintClaimed = hintLegacyReplacementClaimed;
      for (
        let claimAttempt = 0;
        !freshHintClaimed && claimAttempt < 2;
        claimAttempt++
      ) {
        const { data: claimHintData, error: claimHintError } = await supabase
          .rpc("claim_practice_hint_generation", claimHintParams);
        if (claimHintError) {
          if (requestIsPrefetch) {
            logHintPrefetchTelemetry({
              outcome: "failed",
              reason: claimHintError.message.includes(
                  "PRACTICE_HINT_PREFETCH_PENDING",
                )
                ? "pending"
                : "unknown",
              practiceMode: request.practiceMode,
            });
          }
          const mapped = mapLedgerError(claimHintError.message);
          logWarn("practice_chat_hint_claim_failed", {
            user: summarizeUser(user.id),
            error: claimHintError.message,
          });
          return jsonResponse({ error: mapped.error }, mapped.status);
        }
        const claimHintRow = firstRpcRow(claimHintData);
        if (
          !isPlainObject(claimHintRow) ||
          typeof claimHintRow.replay !== "boolean"
        ) {
          await releaseHintGeneration({
            supabase,
            userId: user.id,
            sessionId: request.sessionId,
            requestId: hintRequestId,
            generationToken: hintGenerationToken,
            legacyReplacement: hintLegacyReplacementClaimed,
          });
          return jsonResponse({ error: "practice_hint_not_ready" }, 503);
        }
        if (claimHintRow.replay === false) {
          freshHintClaimed = true;
          break;
        }
        if (
          !isPlainObject(claimHintRow.stored_result) ||
          typeof claimHintRow.stored_charged !== "boolean"
        ) {
          await releaseHintGeneration({
            supabase,
            userId: user.id,
            sessionId: request.sessionId,
            requestId: hintRequestId,
            generationToken: hintGenerationToken,
            legacyReplacement: hintLegacyReplacementClaimed,
          });
          return jsonResponse({ error: "practice_hint_not_ready" }, 503);
        }
        if (requestIsPrefetch) return jsonResponse(hintPrefetchAck());
        if (claimHintRow.stored_charged) {
          if (!isExplicitModelHintResult(claimHintRow.stored_result)) {
            const replacement = await claimLegacyHintReplacement();
            if (replacement.kind === "response") {
              return replacement.response;
            }
            freshHintClaimed = true;
            break;
          }
          return jsonResponse(
            responsePayloadWithCurrentUsage(claimHintRow.stored_result),
          );
        }
        if (
          prefetchEnabled &&
          isExplicitModelHintResult(claimHintRow.stored_result)
        ) {
          const settled = await settlePrefetchedHint();
          if (settled.kind === "response") return settled.response;
          const replacement = await claimLegacyHintReplacement();
          if (replacement.kind === "response") return replacement.response;
          freshHintClaimed = true;
          break;
        }
        const discarded = await discardPrefetchedHint();
        if (discarded.kind === "response") return discarded.response;
        if (discarded.kind === "legacyReplacement") {
          const replacement = await claimLegacyHintReplacement();
          if (replacement.kind === "response") return replacement.response;
          freshHintClaimed = true;
          break;
        }
      }
      if (!freshHintClaimed) {
        return jsonResponse({ error: "practice_hint_not_ready" }, 503);
      }

      if (requestIsPrefetch) {
        logHintPrefetchTelemetry({
          outcome: "fired",
          reason: "unknown",
          practiceMode: request.practiceMode,
        });
      }

      // Fresh claims alone consume the model-rate budget. Claim-level replay
      // returns above without touching rate limits.
      const hintRateVerdict = await enforceModelRateLimit({
        supabase,
        userId: user.id,
        scope: "practice_hint",
        isTestAccount: accountIsTest,
      });
      if (hintRateVerdict.kind === "limited") {
        await releaseHintGeneration({
          supabase,
          userId: user.id,
          sessionId: request.sessionId,
          requestId: hintRequestId,
          generationToken: hintGenerationToken,
          legacyReplacement: hintLegacyReplacementClaimed,
        });
        if (requestIsPrefetch) {
          logHintPrefetchTelemetry({
            outcome: "failed",
            reason: "rate_limit",
            practiceMode: request.practiceMode,
          });
        }
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

      const hintTemperatureScore = ledger.temperatureScore ??
        difficultyStartTemperature;
      const hintFamiliarityScore = ledger.familiarityScore ?? 0;
      const hintPartnerMood = partnerStateFromLedger(ledger)?.mood ??
        relationshipThreadState?.partnerState?.mood ?? null;
      let hintResult: ReturnType<typeof parseHintResult> | null = null;
      const hintProvider = "anthropic";
      let hintModel = CLAUDE_SONNET_MODEL;
      let hintFailoverUsed = false;
      const hintGenerationStartedAt = performance.now();
      let hintAttemptCount = 0;
      let hintPromptChars = 0;
      let hintLastFailureClass: PracticeGenerationFailureClass | null = null;
      const hintAttemptDurationsMs: number[] = [];
      const hintFailureClasses: PracticeGenerationFailureClass[] = [];
      const hintFailureCodes: string[] = [];
      const recordHintAttemptFailure = (failure: SingleShotAttemptFailure) => {
        const failureError = new Error(failure.code);
        const failureClass = classifyPracticeGenerationFailure(failureError);
        hintLastFailureClass = failureClass;
        hintAttemptDurationsMs.push(failure.durationMs);
        hintAttemptCount = hintAttemptDurationsMs.length;
        hintFailureClasses.push(failureClass);
        appendPracticeFailureCodes(hintFailureCodes, failureError);
        logWarn("practice_chat_generation_attempt", {
          user: summarizeUser(user.id),
          provider: "anthropic",
          model: failure.model,
          ...buildPracticeGenerationTelemetry({
            mode: "hint",
            practiceMode: request.practiceMode,
            attempt: hintAttemptDurationsMs.length,
            attemptDurationMs: failure.durationMs,
            failureClass,
            fallbackUsed: false,
            totalDurationMs: null,
            promptChars: hintPromptChars,
          }),
        });
      };
      try {
        const baseHintMessages = buildHintMessages({
          turns: request.turns,
          profile: request.profile,
          practiceMode: request.practiceMode,
          temperatureScore: hintTemperatureScore,
          familiarityScore: hintFamiliarityScore,
          partnerMood: hintPartnerMood,
          sceneContext,
          memorySummary: promptMemorySummary,
          gameState: ledgerGameState,
        });
        const hintFactualEvidence = hintTrustedFactualEvidence({
          profile: request.profile,
          practiceMode: request.practiceMode,
          sceneContext,
          memorySummary: promptMemorySummary,
        });
        const generatedHintParseOptions = {
          mode: request.practiceMode,
          turns: request.turns,
          sharedFactualEvidence: hintFactualEvidence.shared,
          partnerFactualEvidence: hintFactualEvidence.partner,
          trustedFactClaims: hintFactualEvidence.claims,
          enforceGeneratedQuality: true,
        } as const;
        hintPromptChars = countPromptChars(baseHintMessages);
        if (!claudeApiKey || !deps.callClaude) {
          throw new Error("claude_unavailable");
        }
        const outcome = await runSingleShot<ReturnType<typeof parseHintResult>>(
          {
            callClaude: deps.callClaude,
            apiKey: claudeApiKey,
            messages: baseHintMessages,
            forcedTool: {
              name: "emit_hint",
              description:
                "輸出練習室提示：warmUp/steady 兩句可直接貼上的回覆與 coaching 教練講評。",
              inputSchema: HINT_TOOL_SCHEMA as Record<string, unknown>,
            },
            maxTokens: HINT_MAX_TOKENS,
            temperature: HINT_TEMPERATURE,
            perCallTimeoutMs: HINT_SINGLE_SHOT_TIMEOUT_MS,
            deadlineAtMs: hintAbsoluteDeadlineAtMs,
            now: monotonicNow,
            models: [CLAUDE_SONNET_MODEL, CLAUDE_HAIKU_MODEL],
            // 機械守門全套照舊：parseHintResult（結構/長度/守門詞表/接地/事實
            // ledger/白話 repair）＋server-authored decision 可建構性。丟錯＝該發
            // 判敗立即進補發，絕不 repair 復活、絕不保留候選原文。
            validate: (raw) => {
              const parsed = parseHintResult(raw, {
                ...generatedHintParseOptions,
              });
              return {
                ...parsed,
                replies: parsed.replies.map((reply) => ({
                  ...reply,
                  decision: buildHintDecision({
                    turns: request.turns,
                    profile: request.profile,
                    practiceMode: request.practiceMode,
                    temperatureScore: hintTemperatureScore,
                    familiarityScore: hintFamiliarityScore,
                    partnerMood: hintPartnerMood,
                    gameState: ledgerGameState,
                    replyType: reply.type,
                    replyText: reply.text,
                    rationale: SERVER_HINT_DECISION_RATIONALE,
                  }),
                })) as typeof parsed.replies,
              };
            },
          },
        );
        for (const failure of outcome.attemptFailures) {
          recordHintAttemptFailure(failure);
        }
        hintResult = outcome.result;
        hintModel = outcome.model;
        hintFailoverUsed = outcome.attemptFailures.length > 0;
        hintAttemptCount = outcome.attemptFailures.length + 1;
        hintLastFailureClass = null;
        hintAttemptDurationsMs.push(outcome.durationMs);
        logInfo("practice_chat_generation_attempt", {
          user: summarizeUser(user.id),
          provider: hintProvider,
          model: hintModel,
          ...buildPracticeGenerationTelemetry({
            mode: "hint",
            practiceMode: request.practiceMode,
            attempt: hintAttemptCount,
            attemptDurationMs: outcome.durationMs,
            failureClass: null,
            fallbackUsed: false,
            totalDurationMs: null,
            promptChars: hintPromptChars,
          }),
        });
      } catch (e) {
        if (e instanceof SingleShotExhaustedError) {
          for (const failure of e.attemptFailures) {
            recordHintAttemptFailure(failure);
          }
        }
        const failureClass = hintLastFailureClass ??
          classifyPracticeGenerationFailure(e);
        logWarn("practice_chat_generation_failed", {
          user: summarizeUser(user.id),
          mode: "hint",
          personaId: request.profile.personaId,
          difficulty: request.profile.difficulty,
          failureClass,
        });
        await releaseHintGeneration({
          supabase,
          userId: user.id,
          sessionId: request.sessionId,
          requestId: hintRequestId,
          generationToken: hintGenerationToken,
          legacyReplacement: hintLegacyReplacementClaimed,
        });
        const failureDurationMs = elapsedMilliseconds(
          hintGenerationStartedAt,
        );
        scheduleGenerationTelemetry(deps, {
          supabase,
          userId: user.id,
          mode: "hint",
          practiceMode: request.practiceMode,
          attempt: Math.max(1, hintAttemptCount),
          totalDurationMs: failureDurationMs,
          promptChars: hintPromptChars,
          fallbackUsed: false,
          failoverUsed: hintFailoverUsed,
          failureClass,
          attemptDurationsMs: hintAttemptDurationsMs,
          failureClasses: hintFailureClasses,
          failureCodes: hintFailureCodes,
          model: hintModel,
          pipeline: "single_shot_v2",
        });
        if (requestIsPrefetch) {
          logHintPrefetchTelemetry({
            outcome: "failed",
            reason: prefetchFailureReason(hintLastFailureClass),
            practiceMode: request.practiceMode,
          });
          return jsonResponse(
            { error: "practice_hint_prefetch_failed", retryable: true },
            503,
          );
        }
        return jsonResponse(
          { error: "practice_hint_generation_retryable", retryable: true },
          503,
        );
      }

      const hintTotalDurationMs = elapsedMilliseconds(
        hintGenerationStartedAt,
      );
      logInfo("practice_chat_generation_outcome", {
        user: summarizeUser(user.id),
        provider: hintProvider,
        model: hintModel,
        ...buildPracticeGenerationTelemetry({
          mode: "hint",
          practiceMode: request.practiceMode,
          attempt: hintAttemptCount,
          attemptDurationMs: null,
          failureClass: null,
          fallbackUsed: false,
          failoverUsed: hintFailoverUsed,
          totalDurationMs: hintTotalDurationMs,
          promptChars: hintPromptChars,
        }),
      });
      const recordPolicy = hintRecordPolicy({
        isPrefetch: requestIsPrefetch,
        isTestAccount: accountIsTest,
        quotaAlreadyPaid: hintReplacementQuotaAlreadyPaid,
      });
      const predictedDeducted = recordPolicy.chargeQuota
        ? PRACTICE_QUOTA_COST
        : 0;
      const generatedAt = (deps.now?.() ?? new Date()).toISOString();
      const generatedHintSnapshot = hintRequestId
        ? {
          ...hintResult,
          costDeducted: predictedDeducted,
          ...(requestIsPrefetch
            ? { hintUsedCount: ledger.hintCount ?? 0 }
            : {}),
          generationSource: "model",
          fallbackUsed: false,
          qualitySchemaVersion: HINT_QUALITY_SCHEMA_VERSION,
          hintReviewSchemaVersion: HINT_REVIEW_SCHEMA_VERSION,
          failoverUsed: hintFailoverUsed,
          provider: hintProvider,
          model: hintModel,
          generatedAt,
          ...remainingFrom(sub, limits, predictedDeducted),
        }
        : null;
      const recordHintParams: Record<string, unknown> =
        hintLegacyReplacementClaimed
          ? {
            p_user_id: user.id,
            p_session_id: request.sessionId,
            p_request_id: hintRequestId,
            p_generation_token: hintGenerationToken,
            p_result: generatedHintSnapshot,
            p_charge_quota: recordPolicy.chargeQuota,
            p_monthly_limit: limits.monthly,
            p_daily_limit: limits.daily,
            p_max_hints: MAX_HINTS_PER_ROUND,
          }
          : {
            p_user_id: user.id,
            p_session_id: request.sessionId,
            p_charge_quota: recordPolicy.chargeQuota,
            p_max_hints: MAX_HINTS_PER_ROUND,
            p_charged: recordPolicy.charged,
            p_monthly_limit: limits.monthly,
            p_daily_limit: limits.daily,
            p_max_replies: MAX_AI_REPLIES,
            p_generation_token: hintGenerationToken,
            ...(hintRequestId
              ? {
                p_request_id: hintRequestId,
                p_result: generatedHintSnapshot,
              }
              : {}),
          };
      const { data: recordData, error: recordError } = await supabase.rpc(
        hintLegacyReplacementClaimed
          ? "record_legacy_practice_hint_replacement"
          : "record_practice_hint",
        recordHintParams,
      );
      if (recordError) {
        logWarn("practice_chat_hint_record_failed", {
          user: summarizeUser(user.id),
          error: recordError.message,
        });
        await releaseHintGeneration({
          supabase,
          userId: user.id,
          sessionId: request.sessionId,
          requestId: hintRequestId,
          generationToken: hintGenerationToken,
          legacyReplacement: hintLegacyReplacementClaimed,
        });
        if (requestIsPrefetch) {
          logHintPrefetchTelemetry({
            outcome: "failed",
            reason: classifyQuotaRpcError(recordError.message) === null
              ? "unknown"
              : "quota",
            practiceMode: request.practiceMode,
          });
        }
        const quotaResponse = await quotaResponseForRpcError(
          recordError.message,
        );
        if (quotaResponse) return quotaResponse;
        const mapped = mapLedgerError(recordError.message);
        return jsonResponse({ error: mapped.error }, mapped.status);
      }
      const recordRow = firstRpcRow(recordData);
      if (
        !isPlainObject(recordRow) ||
        typeof recordRow.did_charge !== "boolean" ||
        typeof recordRow.new_hint_count !== "number" ||
        !Number.isInteger(recordRow.new_hint_count) ||
        recordRow.new_hint_count < 0 ||
        (hintRequestId !== undefined &&
          (!isPlainObject(recordRow.stored_result) ||
            recordRow.stored_charged !== recordPolicy.charged))
      ) {
        await releaseHintGeneration({
          supabase,
          userId: user.id,
          sessionId: request.sessionId,
          requestId: hintRequestId,
          generationToken: hintGenerationToken,
          legacyReplacement: hintLegacyReplacementClaimed,
        });
        if (requestIsPrefetch) {
          logHintPrefetchTelemetry({
            outcome: "failed",
            reason: "unknown",
            practiceMode: request.practiceMode,
          });
        }
        return jsonResponse({ error: "practice_hint_not_ready" }, 503);
      }
      const didCharge = recordRow.did_charge;
      const deducted = didCharge ? PRACTICE_QUOTA_COST : 0;
      const hintUsedCount = recordRow.new_hint_count;

      // 權威扣費／replay 快照先完成；觀測 side-channel 不得增加回應延遲。
      scheduleGenerationTelemetry(deps, {
        supabase,
        userId: user.id,
        mode: "hint",
        practiceMode: request.practiceMode,
        attempt: hintAttemptCount,
        totalDurationMs: hintTotalDurationMs,
        promptChars: hintPromptChars,
        fallbackUsed: false,
        failoverUsed: hintFailoverUsed,
        failureClass: null,
        attemptDurationsMs: hintAttemptDurationsMs,
        failureClasses: hintFailureClasses,
        failureCodes: hintFailureCodes,
        model: hintModel,
        pipeline: "single_shot_v2",
      });

      logInfo("practice_chat_succeeded", {
        user: summarizeUser(user.id),
        mode: "hint",
        personaId: request.profile.personaId,
        difficulty: request.profile.difficulty,
        costDeducted: deducted,
      });
      if (requestIsPrefetch) {
        return jsonResponse(hintPrefetchAck());
      }
      if (hintRequestId && isPlainObject(recordRow.stored_result)) {
        return jsonResponse(
          responsePayloadWithCurrentUsage(
            recordRow.stored_result,
            recordRow.did_charge ? PRACTICE_QUOTA_COST : 0,
          ),
        );
      }
      return jsonResponse(responsePayloadWithCurrentUsage({
        ...hintResult,
        hintUsedCount,
        generationSource: "model",
        fallbackUsed: false,
        qualitySchemaVersion: HINT_QUALITY_SCHEMA_VERSION,
        failoverUsed: hintFailoverUsed,
        provider: hintProvider,
        model: hintModel,
        generatedAt,
      }, deducted));
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

    const debriefRequestLedger = request.mode === "debrief" && ledgerRow != null
      ? parseDebriefRequestLedger(ledgerRow.debrief_request_ledger)
      : new Map<string, DebriefRequestLedgerEntry>();
    if (debriefRequestLedger === null) {
      logError("practice_chat_debrief_ledger_invalid", {
        user: summarizeUser(user.id),
        sessionId: request.sessionId,
      });
      return jsonResponse({ error: "practice_debrief_not_ready" }, 503);
    }
    const exactDebriefRequest = request.mode === "debrief" && request.requestId
      ? debriefRequestLedger.get(request.requestId)
      : undefined;
    const retryingClaimedDebrief = exactDebriefRequest !== undefined;
    if (retryingClaimedDebrief) {
      // Exact request-ledger replay/latch checks precede mutable Game unlock
      // and cap gates. This remains true after another logical ID becomes the
      // session's last slot (A -> B -> A).
      if (exactDebriefRequest.result !== null) {
        if (isCurrentGeneratedDebriefEnvelope(exactDebriefRequest.result)) {
          logInfo("practice_chat_debrief_replayed", {
            user: summarizeUser(user.id),
            sessionId: request.sessionId,
            source: "preflight",
          });
          return jsonResponse(
            responsePayloadWithCurrentUsage(exactDebriefRequest.result),
          );
        }
        const invalidated = await invalidateLegacyPracticeAiSnapshot({
          supabase,
          userId: user.id,
          sessionId: request.sessionId,
          requestId: request.requestId,
          kind: "debrief",
        });
        if (!invalidated) {
          return jsonResponse(
            { error: "practice_debrief_generation_retryable", retryable: true },
            503,
          );
        }
        logInfo("practice_chat_legacy_snapshot_invalidated", {
          user: summarizeUser(user.id),
          kind: "debrief",
        });
      }
      if (
        isFreshDebriefGeneration(
          exactDebriefRequest.startedAt,
          deps.now?.() ?? new Date(),
        )
      ) {
        logInfo("practice_chat_debrief_in_flight", {
          user: summarizeUser(user.id),
          sessionId: request.sessionId,
          source: "preflight",
        });
        return jsonResponse({ error: "practice_debrief_in_flight" }, 425);
      }
    }

    // Exact completed replay wins above. Otherwise the session-wide fresh
    // owner blocks every logical ID, including one with an older released row.
    if (
      request.mode === "debrief" &&
      ledgerRow?.last_debrief_result == null &&
      isFreshDebriefGeneration(
        ledgerRow?.last_debrief_started_at,
        deps.now?.() ?? new Date(),
      )
    ) {
      logInfo("practice_chat_debrief_in_flight", {
        user: summarizeUser(user.id),
        sessionId: request.sessionId,
        source: "global_preflight",
      });
      return jsonResponse({ error: "practice_debrief_in_flight" }, 425);
    }

    if (
      request.practiceMode === "game" &&
      !retryingClaimedDebrief &&
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
      if (
        !gate.allowed &&
        !(gate.reason === "practice_debrief_limit" && retryingClaimedDebrief)
      ) {
        logWarn("practice_chat_debrief_rejected", {
          user: summarizeUser(user.id),
          reason: gate.reason,
        });
        return jsonResponse({ error: gate.reason }, 403);
      }

      const debriefAssistedMode = isAssistedPracticeMode(
        ledger.practiceMode ?? "standard",
      );
      let ledgerAppliedHintTurns = debriefAssistedMode
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
        try {
          ledgerAppliedHintTurns = await hydrateAppliedHintDecisions({
            supabase,
            userId: user.id,
            sessionId: request.sessionId,
            turns: ledgerAppliedHintTurns,
          });
        } catch {
          logWarn("practice_chat_hint_lineage_resolution_failed", {
            user: summarizeUser(user.id),
            sessionId: request.sessionId,
            failureClass: "schema_invalid",
          });
          return jsonResponse({ error: "practice_debrief_not_ready" }, 503);
        }
      }

      const debriefGenerationToken = request.requestId
        ? deps.randomUUID?.() ?? crypto.randomUUID()
        : undefined;
      const claimDebriefParams: Record<string, unknown> = {
        p_user_id: user.id,
        p_session_id: request.sessionId,
        p_max_debriefs: MAX_DEBRIEFS,
      };
      if (request.requestId) {
        claimDebriefParams.p_request_id = request.requestId;
        claimDebriefParams.p_generation_token = debriefGenerationToken;
      }
      let debriefClaimed = false;
      for (let claimAttempt = 0; claimAttempt < 2; claimAttempt++) {
        const { data: claimData, error: claimError } = await supabase.rpc(
          "claim_practice_debrief",
          claimDebriefParams,
        );
        if (claimError) {
          const mapped = mapLedgerError(claimError.message);
          logWarn("practice_chat_debrief_claim_failed", {
            user: summarizeUser(user.id),
            error: claimError.message,
          });
          return jsonResponse({ error: mapped.error }, mapped.status);
        }
        const claimDataHasSingleRow = !Array.isArray(claimData) ||
          claimData.length === 1;
        const claimRow = Array.isArray(claimData) ? claimData[0] : claimData;
        const currentDebriefCount = isPlainObject(claimRow)
          ? claimRow.current_debrief_count
          : undefined;
        if (
          !claimDataHasSingleRow || !isPlainObject(claimRow) ||
          typeof claimRow.replay !== "boolean" ||
          typeof claimRow.in_flight !== "boolean" ||
          typeof currentDebriefCount !== "number" ||
          !Number.isInteger(currentDebriefCount) ||
          currentDebriefCount < 0 ||
          currentDebriefCount > MAX_DEBRIEFS
        ) {
          await releaseDebriefGeneration({
            supabase,
            userId: user.id,
            sessionId: request.sessionId,
            requestId: request.requestId,
            generationToken: debriefGenerationToken,
          });
          return jsonResponse(
            { error: "practice_debrief_not_ready", retryable: true },
            503,
          );
        }
        if (
          claimRow.replay === true && claimRow.in_flight === false &&
          isPlainObject(claimRow.stored_result)
        ) {
          if (isCurrentGeneratedDebriefEnvelope(claimRow.stored_result)) {
            logInfo("practice_chat_debrief_replayed", {
              user: summarizeUser(user.id),
              sessionId: request.sessionId,
              source: "claim",
            });
            return jsonResponse(
              responsePayloadWithCurrentUsage(claimRow.stored_result),
            );
          }
          const invalidated = await invalidateLegacyPracticeAiSnapshot({
            supabase,
            userId: user.id,
            sessionId: request.sessionId,
            requestId: request.requestId,
            kind: "debrief",
          });
          if (invalidated) continue;
          return jsonResponse(
            { error: "practice_debrief_generation_retryable", retryable: true },
            503,
          );
        }
        if (
          claimRow.replay === false && claimRow.in_flight === true &&
          claimRow.stored_result === null
        ) {
          logInfo("practice_chat_debrief_in_flight", {
            user: summarizeUser(user.id),
            sessionId: request.sessionId,
          });
          return jsonResponse({ error: "practice_debrief_in_flight" }, 425);
        }
        if (
          claimRow.replay !== false || claimRow.in_flight !== false ||
          claimRow.stored_result !== null
        ) {
          await releaseDebriefGeneration({
            supabase,
            userId: user.id,
            sessionId: request.sessionId,
            requestId: request.requestId,
            generationToken: debriefGenerationToken,
          });
          return jsonResponse(
            { error: "practice_debrief_not_ready", retryable: true },
            503,
          );
        }
        debriefClaimed = true;
        break;
      }
      if (!debriefClaimed) {
        return jsonResponse(
          { error: "practice_debrief_generation_retryable", retryable: true },
          503,
        );
      }

      // Claim-level replay and in-flight races returned above. Only a fresh
      // owner consumes a model-rate slot; a limited request releases the exact
      // token-fenced reservation before returning.
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
        await releaseDebriefGeneration({
          supabase,
          userId: user.id,
          sessionId: request.sessionId,
          requestId: request.requestId,
          generationToken: debriefGenerationToken,
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

      let debriefCard: DebriefCard | null = null;
      const debriefProvider = "anthropic";
      let debriefModel = CLAUDE_SONNET_MODEL;
      let debriefFailoverUsed = false;
      const debriefPracticeMode = ledger.practiceMode ?? request.practiceMode;
      const debriefGenerationStartedAt = performance.now();
      let debriefAttemptCount = 0;
      let debriefPromptChars = 0;
      let debriefLastFailureClass: PracticeGenerationFailureClass | null = null;
      const debriefAttemptDurationsMs: number[] = [];
      const debriefFailureClasses: PracticeGenerationFailureClass[] = [];
      const debriefFailureCodes: string[] = [];
      const recordDebriefAttemptFailure = (
        failure: SingleShotAttemptFailure,
      ) => {
        const failureError = new Error(failure.code);
        const failureClass = classifyPracticeGenerationFailure(failureError);
        debriefLastFailureClass = failureClass;
        debriefAttemptDurationsMs.push(failure.durationMs);
        debriefAttemptCount = debriefAttemptDurationsMs.length;
        debriefFailureClasses.push(failureClass);
        appendPracticeFailureCodes(debriefFailureCodes, failureError);
        logWarn("practice_chat_generation_attempt", {
          user: summarizeUser(user.id),
          provider: "anthropic",
          model: failure.model,
          ...buildPracticeGenerationTelemetry({
            mode: "debrief",
            practiceMode: debriefPracticeMode,
            attempt: debriefAttemptDurationsMs.length,
            attemptDurationMs: failure.durationMs,
            failureClass,
            fallbackUsed: false,
            totalDurationMs: null,
            promptChars: debriefPromptChars,
          }),
        });
      };
      try {
        const baseDebriefMessages = buildDebriefMessages(
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
        );
        const debriefFactualEvidence = hintTrustedFactualEvidence({
          profile: request.profile,
          practiceMode: debriefPracticeMode,
          sceneContext,
          memorySummary: promptMemorySummary,
        });
        const generatedDebriefParseOptions = {
          allowGameBreakdown: debriefPracticeMode === "game",
          requireCompleteCard: true,
          turns: request.turns,
          appliedHintTurns: ledgerAppliedHintTurns,
          repairPreservedHintCritique: false,
          sharedFactualEvidence: debriefFactualEvidence.shared,
          partnerFactualEvidence: debriefFactualEvidence.partner,
          trustedFactClaims: debriefFactualEvidence.claims,
          enforceGeneratedQuality: true,
        } as const;
        debriefPromptChars = countPromptChars(baseDebriefMessages);
        if (!claudeApiKey || !deps.callClaude) {
          throw new Error("claude_unavailable");
        }
        const outcome = await runSingleShot<DebriefCard>({
          callClaude: deps.callClaude,
          apiKey: claudeApiKey,
          messages: baseDebriefMessages,
          forcedTool: {
            name: "emit_debrief_card",
            description:
              "輸出練習拆解卡：總結、亮點、注意點、建議句與邀約評估（Game 模式含拆盤）。",
            inputSchema: DEBRIEF_TOOL_SCHEMA as Record<string, unknown>,
          },
          maxTokens: DEBRIEF_MAX_TOKENS,
          temperature: DEBRIEF_TEMPERATURE,
          perCallTimeoutMs: DEBRIEF_SINGLE_SHOT_TIMEOUT_MS,
          deadlineAtMs: debriefAbsoluteDeadlineAtMs,
          now: monotonicNow,
          models: [CLAUDE_SONNET_MODEL, CLAUDE_HAIKU_MODEL],
          // 機械守門全套照舊：parseDebriefCard（完整卡契約/守門詞表/接地/
          // hintAssessment/Game 拆盤）。丟錯＝該發判敗立即進補發，不 repair 復活。
          validate: (raw) =>
            parseDebriefCard(raw, { ...generatedDebriefParseOptions }),
        });
        for (const failure of outcome.attemptFailures) {
          recordDebriefAttemptFailure(failure);
        }
        debriefCard = outcome.result;
        debriefModel = outcome.model;
        debriefFailoverUsed = outcome.attemptFailures.length > 0;
        debriefAttemptCount = outcome.attemptFailures.length + 1;
        debriefLastFailureClass = null;
        debriefAttemptDurationsMs.push(outcome.durationMs);
        logInfo("practice_chat_generation_attempt", {
          user: summarizeUser(user.id),
          provider: debriefProvider,
          model: debriefModel,
          ...buildPracticeGenerationTelemetry({
            mode: "debrief",
            practiceMode: debriefPracticeMode,
            attempt: debriefAttemptCount,
            attemptDurationMs: outcome.durationMs,
            failureClass: null,
            fallbackUsed: false,
            totalDurationMs: null,
            promptChars: debriefPromptChars,
          }),
        });
      } catch (e) {
        if (e instanceof SingleShotExhaustedError) {
          for (const failure of e.attemptFailures) {
            recordDebriefAttemptFailure(failure);
          }
        }
        logWarn("practice_chat_generation_failed", {
          user: summarizeUser(user.id),
          mode: "debrief",
          personaId: request.profile.personaId,
          difficulty: request.profile.difficulty,
          failureClass: debriefLastFailureClass ??
            classifyPracticeGenerationFailure(e),
        });
        await releaseDebriefGeneration({
          supabase,
          userId: user.id,
          sessionId: request.sessionId,
          requestId: request.requestId,
          generationToken: debriefGenerationToken,
        });
        const failureClass = debriefLastFailureClass ??
          classifyPracticeGenerationFailure(e);
        scheduleGenerationTelemetry(deps, {
          supabase,
          userId: user.id,
          mode: "debrief",
          practiceMode: debriefPracticeMode,
          attempt: Math.max(1, debriefAttemptCount),
          totalDurationMs: elapsedMilliseconds(debriefGenerationStartedAt),
          promptChars: debriefPromptChars,
          fallbackUsed: false,
          failoverUsed: debriefFailoverUsed,
          failureClass,
          attemptDurationsMs: debriefAttemptDurationsMs,
          failureClasses: debriefFailureClasses,
          failureCodes: debriefFailureCodes,
          model: debriefModel,
          pipeline: "single_shot_v2",
        });
        return jsonResponse(
          { error: "practice_debrief_generation_retryable", retryable: true },
          503,
        );
      }

      const debriefTotalDurationMs = elapsedMilliseconds(
        debriefGenerationStartedAt,
      );
      logInfo("practice_chat_generation_outcome", {
        user: summarizeUser(user.id),
        provider: debriefProvider,
        model: debriefModel,
        ...buildPracticeGenerationTelemetry({
          mode: "debrief",
          practiceMode: debriefPracticeMode,
          attempt: debriefAttemptCount,
          attemptDurationMs: null,
          failureClass: null,
          fallbackUsed: false,
          failoverUsed: debriefFailoverUsed,
          totalDurationMs: debriefTotalDurationMs,
          promptChars: debriefPromptChars,
        }),
      });
      const debriefResponse = {
        card: debriefCard,
        costDeducted: 0,
        generationSource: "model",
        fallbackUsed: false,
        qualitySchemaVersion: DEBRIEF_QUALITY_SCHEMA_VERSION,
        failoverUsed: debriefFailoverUsed,
        provider: debriefProvider,
        model: debriefModel,
        generatedAt: (deps.now?.() ?? new Date()).toISOString(),
        ...remainingFrom(sub, limits, 0),
      };
      let authoritativeDebriefResponse: Record<string, unknown> =
        debriefResponse;
      if (request.requestId) {
        const { data: recordData, error: recordError } = await supabase.rpc(
          "record_practice_debrief",
          {
            p_user_id: user.id,
            p_session_id: request.sessionId,
            p_request_id: request.requestId,
            p_result: debriefResponse,
            p_generation_token: debriefGenerationToken,
          },
        );
        if (recordError || !isPlainObject(recordData)) {
          logWarn("practice_chat_debrief_record_failed", {
            user: summarizeUser(user.id),
            failureClass: recordError &&
                isMissingPracticeDebriefRpc(recordError.message)
              ? "schema_invalid"
              : "unknown",
          });
          await releaseDebriefGeneration({
            supabase,
            userId: user.id,
            sessionId: request.sessionId,
            requestId: request.requestId,
            generationToken: debriefGenerationToken,
          });
          return jsonResponse(
            { error: "practice_debrief_persist_retryable", retryable: true },
            503,
          );
        } else {
          // first-writer-wins：stale takeover 若撞到仍存活的舊 worker，RPC 回傳
          // 已落帳的權威卡；本次 response 與之後 replay 必須完全一致。
          authoritativeDebriefResponse = recordData;
        }
      }

      // replay 快照先寫；telemetry 慢或掛都不得拖住使用者拿到拆解卡。
      scheduleGenerationTelemetry(deps, {
        supabase,
        userId: user.id,
        mode: "debrief",
        practiceMode: debriefPracticeMode,
        attempt: debriefAttemptCount,
        totalDurationMs: debriefTotalDurationMs,
        promptChars: debriefPromptChars,
        fallbackUsed: false,
        failoverUsed: debriefFailoverUsed,
        failureClass: null,
        attemptDurationsMs: debriefAttemptDurationsMs,
        failureClasses: debriefFailureClasses,
        failureCodes: debriefFailureCodes,
        model: debriefModel,
        pipeline: "single_shot_v2",
      });

      logInfo("practice_chat_succeeded", {
        user: summarizeUser(user.id),
        mode: "debrief",
        personaId: request.profile.personaId,
        difficulty: request.profile.difficulty,
        costDeducted: 0,
      });
      return jsonResponse(
        responsePayloadWithCurrentUsage(authoritativeDebriefResponse),
      );
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
