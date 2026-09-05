import {
  buildQuotaExceededPayload,
  checkQuota,
  classifyQuotaRpcError,
  isPlainObject,
  normalizeTier,
  resolveLimits,
  type SubscriptionRow,
  TEST_EMAILS,
} from "../_shared/quota.ts";
import { enforceModelRateLimit } from "../_shared/model_rate_limit.ts";
import {
  handlePracticeMoments,
  type MomentsSupabaseClient,
} from "./moments_handler.ts";
import { MOMENT_IMAGE_BUCKET } from "./moments_constants.ts";
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
import {
  type DrawSupabaseClient,
  handleDrawProfile,
  handleDrawStatus,
  handlePracticeCollection,
} from "./draw_handler.ts";
import {
  buildChatPromptBundle,
  buildDebriefMessages,
  type ChatAgencyDecision,
  PRACTICE_PROMPT_POLICY_VERSION,
} from "./prompt.ts";
import type { TurnResponsePlan } from "./turn_response_plan.ts";
import { nextReplyStyleState } from "./reply_style_state.ts";
import {
  type AgencyClassifierSignal,
  type AgencyMode,
  agencyModeFor,
  agencyShapeExperimentFor,
  chatModelFor,
  nextConversationAgencyState,
  type PracticeChatModel,
  truncateAgencyShape,
} from "./conversation_agency.ts";
import {
  debriefAgencyLedgerFor,
  hintAgencyCoachingFor,
} from "./agency_coaching.ts";
import { replyStyleFor, type ReplyStyleProfile } from "./reply_style.ts";
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
  type DebriefCard,
  debriefToolSchemaFor,
  parseDebriefCard,
  salvageDebriefCandidate,
} from "./debrief_card.ts";
import {
  buildHintDecision,
  buildHintMessages,
  degradeStructuralHintCandidate,
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
  type ClaudeUsage,
} from "./claude.ts";
import { buildPracticeSceneContext } from "./life_schedule.ts";
import { buildAcquaintanceOrigin } from "./acquaintance_origin.ts";
import { logError, logInfo, logWarn, summarizeUser } from "./logger.ts";
import {
  hasStageDirection,
  rejectL4UnsafeVisibleText,
  rejectVisibleInternalLabelLeak,
  REPLY_STYLE_HIDDEN_HEADINGS,
  stripStageDirections,
} from "./visible_text_guard.ts";
import {
  applyGameLearningDelta,
  containsCrudeSexualOffense,
  evaluateGameFsm,
  evaluateGameFsmForLedger,
} from "./game_fsm.ts";
import {
  buildNextGameState,
  parsePersistedGameState,
  type PersistedGameState,
} from "./game_state.ts";
import { inviteMaturityFromLearningScores } from "./invite_maturity.ts";
import { resolveLearningSeed } from "./learning_seed.ts";
import {
  buildRelationshipThreadRpcParams,
  parseRelationshipThreadRow,
  type PracticeRelationshipThreadState,
  threadIdForPracticeRequest,
} from "./relationship_thread.ts";
import {
  applyChallengeRewardGate,
  applyCoherenceDeltaCap,
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
  withMaxNegativeLearningDeltas,
  withNonPositiveLearningDeltas,
} from "./temperature.ts";
import { taipeiTimeContextFor } from "./time_context.ts";
import {
  fetchHerRecentMoments,
  herRecentMomentsPrompt,
  type MomentMemoryPost,
} from "./moments_memory.ts";
import { normalizeLiteralNewlines } from "./prompt_sanitizer.ts";
import { toTraditionalChinese } from "../_shared/traditional_chinese.ts";
import {
  buildPracticeAiLogRow,
  buildPracticeGenerationTelemetry,
  classifyPracticeGenerationFailure,
  countPromptChars,
  type PracticeGenerationFailureClass,
  practiceGenerationRetryAdvice,
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
  // 粗俗性冒犯（Eric 2026-08-08 拍板）：不看分類器、不看關係階段，直接判
  // 嚴重越界。動機：扣分靠 DeepSeek 分類器，它對這類句子會抖動（有時輕判
  // 甚至不扣），失敗時 fallback 又是 0 分——粗俗性辱罵沒有誤判空間，用硬
  // 規則兜底，每次命中扣滿（Game -18／新手 -12），連續冒犯一路扣到 0。
  if (containsCrudeSexualOffense(lastUserText(opts.request.turns))) {
    return {
      impact: "strong",
      connection: "overstepped",
      testHandling: "none",
      boundary: "overstep",
      hintAlignment: "diverged",
      partnerMood: "annoyed",
      moodConfidence: 1,
      innerThought: "這句話讓我覺得被冒犯，我不想再聊下去了。",
    };
  }
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

/**
 * 冒犯冷卻窗（2026-08-19）：嚴重冒犯的扣滿只罰當下那一句，下一句講正常話
 * 分類器就用乾淨脈絡評分回暖——真實女生不會被罵完下一句就熱回來。從
 * transcript 無狀態推導：最後一句**之前**的 K 句 user 內有粗俗冒犯＝
 * 冷卻中，正向 delta 夾 0、正向心情壓 guarded。最後一句自己命中走扣滿
 * 路徑，不歸這裡。
 */
const OFFENSE_COOLDOWN_USER_TURNS = 3;

function inCrudeOffenseCooldown(
  turns: Array<{ role: string; text: string }>,
): boolean {
  const users = turns.filter((turn) => turn.role === "user");
  return users
    .slice(0, -1)
    .slice(-OFFENSE_COOLDOWN_USER_TURNS)
    .some((turn) => containsCrudeSexualOffense(turn.text));
}

const COOLDOWN_DAMPED_MOODS: ReadonlySet<string> = new Set([
  "curious",
  "amused",
  "comfortable",
]);

function withCooldownDampedMood(
  classification: TurnClassification,
): TurnClassification {
  if (!COOLDOWN_DAMPED_MOODS.has(classification.partnerMood)) {
    return classification;
  }
  return { ...classification, partnerMood: "guarded" };
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
      data: {
        user:
          | { id: string; email?: string | null }
          | null;
      };
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
  /** 兩發全被 gate 打回後靠 salvage 端出＝仍是成功，但要跟「一次過」分得開。 */
  salvageUsed?: boolean;
  failureClass: PracticeGenerationFailureClass | null;
  attemptDurationsMs: number[];
  failureClasses: PracticeGenerationFailureClass[];
  failureCodes?: string[];
  semanticProviderCalls?: number;
  model?: string;
  timeoutMs?: number;
  pipeline?: string;
  /** gate 打回候選（含 raw）——failed row 落 response_body 診斷 TP/FP。 */
  rejectedCandidates?: readonly SingleShotAttemptFailure[];
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
        salvageUsed: opts.salvageUsed,
        semanticProviderCalls: opts.semanticProviderCalls,
        totalDurationMs: opts.totalDurationMs,
        promptChars: opts.promptChars,
      },
      attemptDurationsMs: opts.attemptDurationsMs,
      failureClasses: opts.failureClasses,
      failureCodes: opts.failureCodes,
      pipeline: opts.pipeline,
      rejectedCandidates: opts.rejectedCandidates,
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

/**
 * 動態生成配圖的 Storage 存取小轉接層：同一份型別宣告服務 upload／remove／
 * list 四個注入點（provider／基礎設施細節不進錯誤訊息，logger 端統一分類）。
 */
function momentImageStorage(supabase: unknown): {
  upload(
    path: string,
    bytes: Uint8Array,
    contentType: string,
  ): Promise<void>;
  remove(paths: readonly string[]): Promise<void>;
  list(prefix: string, opts: { limit: number }): Promise<readonly string[]>;
  listPrefixes(
    opts: { limit: number; offset: number },
  ): Promise<readonly string[]>;
} {
  const client = supabase as {
    storage: {
      from(bucket: string): {
        upload(
          path: string,
          body: Uint8Array,
          options: { contentType: string; upsert: boolean },
        ): Promise<{ error: { message: string } | null }>;
        remove(
          paths: readonly string[],
        ): Promise<{ error: { message: string } | null }>;
        list(
          prefix: string,
          options: {
            limit: number;
            offset?: number;
            sortBy?: { column: string; order: string };
          },
        ): Promise<{
          data: { name: string }[] | null;
          error: { message: string } | null;
        }>;
      };
    };
  };
  const bucket = () => client.storage.from(MOMENT_IMAGE_BUCKET);
  return {
    async upload(path, bytes, contentType) {
      const { error } = await bucket().upload(path, bytes, {
        contentType,
        upsert: false,
      });
      if (error) throw new Error("storage_upload_failed");
    },
    async remove(paths) {
      const { error } = await bucket().remove(paths);
      if (error) throw new Error("storage_remove_failed");
    },
    async list(prefix, opts) {
      // 清掃端每翻一頁就把該頁刪掉，所以永遠從 offset 0 列起。
      const { data, error } = await bucket().list(prefix, {
        limit: opts.limit,
        offset: 0,
      });
      if (error) throw new Error("storage_list_failed");
      return (data ?? []).map((entry) => `${prefix}/${entry.name}`);
    },
    async listPrefixes(opts) {
      // 根目錄列出來的是日期資料夾；名稱升冪＝日期由舊到新，出窗的排前面。
      const { data, error } = await bucket().list("", {
        limit: opts.limit,
        offset: opts.offset,
        sortBy: { column: "name", order: "asc" },
      });
      if (error) throw new Error("storage_list_failed");
      return (data ?? []).map((entry) => entry.name);
    },
  };
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

/// Game 只看角色稀有度＝SR（2026-08-13 拍板）。原本還要求 server 端有該位的
/// 翻牌紀錄，但圖鑑解鎖是裝置本機記錄、翻牌事件跟著帳號走，換帳號／刪帳號重建
/// 後兩邊必然對不上，使用者會看到一個點得下去卻永遠 403 的 Game。
/// 「要抽到才遇得到 SR」本來就由翻牌鏈路把關，這裡不再重複檢查。
function gameModeAllowedForProfile(
  request: ReturnType<typeof validateRequest>,
): boolean {
  return request.practiceMode !== "game" ||
    request.profile.girl.rarity === "sr";
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
      "memory_summary, partner_mood, partner_inner_thought, temperature_score, familiarity_score, profile_id, practice_mode, invite_stage, recent_facts",
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
  /** reply-style-v1（PR-4）：她的個人基準給 partnerMood 分類器；null＝逐字不變。 */
  replyStyle?: ReplyStyleProfile | null;
  /** conversation-agency-v1 Phase 2：off＝分類器 prompt／schema 與 delta 逐字不變。 */
  agencyMode?: AgencyMode;
  /** 這一輪 agency 證據算出的 unresolvedCount；旗標 off 時不使用。 */
  agencyEvidenceUnresolvedCount?: number;
  /**
   * 同一個詞原樣再丟一次（Codex round-2 P1-3）：這一格原本只走 planner 的
   * forced `end_low_value_loop`，永遠碰不到 delta cap，所以「連貫 ＋ 一直重複
   * 同一個詞」還是拿得到正分。現在餵進 cap，重複永遠壓成 repetitive。
   */
  agencyEvidenceRepeatedExactToken?: boolean;
  /** Phase 3.5：分類器的可信自我來源；旗標 off 時 buildTurnClassifierMessages 不用。 */
  memorySummary?: string | null;
  herRecentMoments?: readonly MomentMemoryPost[];
}): Promise<LearningJudgement> {
  // 難度接線（槓桿 A）：正負 delta 倍率只在 beginner 溫度管線生效，作用域內解析一次。
  const tuning = difficultyTuningFor(opts.request.profile.difficulty);
  // 粗俗性冒犯＝確定性扣滿，不吃難度倍率（Easy 0.75 會把 -12 軟化成 -9，
  // 這類句子沒有「簡單難度就輕罰」的空間）。分類器成功/失敗兩條路都要蓋。
  const crudeOffense = containsCrudeSexualOffense(
    lastUserText(opts.request.turns),
  );
  const offenseCooldown = !crudeOffense &&
    inCrudeOffenseCooldown(opts.request.turns);
  // 挑戰獎勵閘門（PR 2，修 D2）只接 challenge × beginner：Game 有自己的
  // 閘門（applyGameLearningDelta 的 canEarnPositive），standard 無分數，
  // easy／normal 完全不經過閘門、行為與改前一致。
  const challengeGateActive = opts.request.practiceMode === "beginner" &&
    opts.request.profile.difficulty === "challenge";
  // conversation-agency-v1 Phase 2：只有 `on` 才動分類器 prompt／schema／
  // delta。`shadow`（跟 prompt.ts 的 agencyPrompt 同規則）與 `off` 一樣
  // 逐字沿用舊行為——shadow 只能改 telemetry，不能改分類器實際送出的 prompt
  // 或分數（golden 的「未設／off／shadow 逐位元組相同」涵蓋分類器 prompt）。
  const agencyDeltaCapActive = opts.agencyMode === "on";
  const applyGameLearningIfNeeded = (
    judgement: LearningJudgement,
    currentTemperature: number,
    currentFamiliarity: number,
    partnerState: PartnerState | null | undefined,
    protectedAppliedHint: boolean,
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
      protectedAppliedHint,
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
      const enforcedJudgement = crudeOffense
        ? withMaxNegativeLearningDeltas(
          judgement,
          currentTemperature,
          currentFamiliarity,
        )
        : judgement;
      const withPartnerState = {
        ...enforcedJudgement,
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
        false,
      );
    }
    const base = fallbackLearningJudgement(
      currentTemperature,
      currentFamiliarity,
      currentPartnerState,
    );
    const protectedHintType = isExactAppliedHint(opts.request)
      ? opts.request.appliedHintType
      : undefined;
    const protectedFallback = protectAppliedHintTemperature(
      base,
      currentTemperature,
      currentFamiliarity,
      protectedHintType,
      opts.request.practiceMode,
    );
    // Codex round-1 P1-e：分類器解析失敗會走這條 fallback，而 delta cap 只掛在
    // 成功那條——等於「分類器壞掉」變成 agency 的免罰卡：applied-hint 保護可以
    // 在這裡把 delta 撐成正的，而沒有任何 coherence 判斷把它壓回去。
    // 沒有分類器結果時我們**不知道**玩家接上了沒有，`ambiguous`（不獎不罰）
    // 就是那個「不知道」的誠實表示；結構訊號（同詞重複／未解計數）仍照舊在
    // `applyCoherenceDeltaCap` 內部優先。旗標 off 時整段不套用，逐字沿用舊行為。
    // 順序跟成功那條一致：applied-hint 保護之後、challenge 閘門之前。
    const { judgement: cappedFallback, capApplied: fallbackCapApplied } =
      agencyDeltaCapActive
        ? applyCoherenceDeltaCap(
          protectedFallback,
          currentTemperature,
          currentFamiliarity,
          // Codex round-2 P1-4：分類器沒給判斷就傳 null（不是字面
          // "ambiguous"）——傳字面會讓 cap 內部的結構退路永遠選不到。
          null,
          {
            repeatedExactToken: opts.agencyEvidenceRepeatedExactToken ?? false,
            unresolvedCount: opts.agencyEvidenceUnresolvedCount ?? 0,
          },
        )
        : { judgement: protectedFallback, capApplied: "none" as const };
    const gatedFallback = challengeGateActive
      ? applyChallengeRewardGate({
        judgement: cappedFallback,
        currentHeat: currentTemperature,
        currentFamiliarity: currentFamiliarity,
        classification: cappedFallback.classification,
        protectedAppliedHint: protectedHintType !== undefined,
      })
      : cappedFallback;
    const cooledFallback = offenseCooldown
      ? withNonPositiveLearningDeltas(
        gatedFallback,
        currentTemperature,
        currentFamiliarity,
      )
      : gatedFallback;
    return applyGameLearningIfNeeded(
      { ...cooledFallback, deltaCapApplied: fallbackCapApplied },
      currentTemperature,
      currentFamiliarity,
      currentPartnerState,
      protectedHintType !== undefined,
    );
  };
  const protectedJudgementForSnapshot = (
    currentTemperature: number,
    currentFamiliarity: number,
    currentPartnerState: PartnerState | null | undefined,
    parsedClassification: TurnClassification,
  ): LearningJudgement => {
    const overridden = withDeterministicSafetyOverride({
      classification: parsedClassification,
      request: opts.request,
      currentTemperature,
      currentFamiliarity,
    });
    const classification = offenseCooldown
      ? withCooldownDampedMood(overridden)
      : overridden;
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
    // conversation-agency-v1 Phase 2（報告 §8.3）：coherence delta cap 放在
    // applied-hint 保護之後、challenge 閘門與 crude-offense／cooldown 強制
    // 扣分之前——後兩者是硬下限，會直接蓋過這裡的 clamp，precedence 不變。
    // 旗標 off 時 agencyDeltaCapActive 一律 false，逐字沿用舊行為。
    const { judgement: cappedJudgement, capApplied } = agencyDeltaCapActive
      ? applyCoherenceDeltaCap(
        protectedJudgement,
        currentTemperature,
        currentFamiliarity,
        classification.coherence ?? null,
        {
          repeatedExactToken: opts.agencyEvidenceRepeatedExactToken ?? false,
          unresolvedCount: opts.agencyEvidenceUnresolvedCount ?? 0,
        },
        // Phase 3.4：她捏造跟玩家的共同過去（認識／共同朋友／一起經歷過）時，
        // 這一輪不得換到正分。只有 assisted 有分類器，standard 走不到這裡。
        classification.sharedPastClaim,
        // Phase 3.6：她替自己補的設定跟來源矛盾、或明顯迎合玩家丟的詞時同樣不得換到正分。
        classification.accommodatingSelfFact,
      )
      : { judgement: protectedJudgement, capApplied: "none" as const };
    // 閘門在 delta cap 之後（豁免在閘門內判斷）、crude-offense 確定
    // 性扣滿之前——閘門只夾正向，扣滿與 cooldown 行為不受影響。
    const gatedJudgement = challengeGateActive
      ? applyChallengeRewardGate({
        judgement: cappedJudgement,
        currentHeat: currentTemperature,
        currentFamiliarity: currentFamiliarity,
        classification,
        protectedAppliedHint: protectedHintType !== undefined,
      })
      : cappedJudgement;
    // 放在 applied-hint 保護之後：使用者把 hint 改寫成粗俗冒犯句時，保護
    // 不得替它擋下扣分。
    const enforcedJudgement = crudeOffense
      ? withMaxNegativeLearningDeltas(
        gatedJudgement,
        currentTemperature,
        currentFamiliarity,
      )
      : offenseCooldown
      ? withNonPositiveLearningDeltas(
        gatedJudgement,
        currentTemperature,
        currentFamiliarity,
      )
      : gatedJudgement;
    const withPartnerState = {
      ...enforcedJudgement,
      partnerState: applyPartnerStateUpdate(
        currentPartnerState,
        classification,
      ),
      deltaCapApplied: capApplied,
    };
    return applyGameLearningIfNeeded(
      withPartnerState,
      currentTemperature,
      currentFamiliarity,
      currentPartnerState,
      protectedHintType !== undefined,
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
        replyStyle: opts.replyStyle,
        agencyEnabled: agencyDeltaCapActive,
        memorySummary: opts.memorySummary,
        herRecentMoments: opts.herRecentMoments,
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
        requireCoherence: agencyDeltaCapActive,
      },
    );
    // Phase 2.6：repair-first 用掉的欄位進 telemetry（只有欄位名，沒有內容）。
    // 這是「解析失敗率」的替代觀測——舊行為是整筆作廢走 fallback，看得到失敗
    // 卻看不到是哪個欄位；現在失敗率降下來了，改用這一筆看修了什麼。
    if (parsedClassification.repairedFields?.length) {
      logWarn("practice_chat_learning_classifier_repaired", {
        user: summarizeUser(opts.userId),
        fields: parsedClassification.repairedFields,
      });
    }
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

    if (
      isPlainObject(rawBody) &&
      rawBody.mode === "ensure_subscription_sr_ticket"
    ) {
      // 訂閱一次性 SR 限定翻牌券：grant 兼狀態查詢（2026-08-08 拍板）。
      // server 讀 subscriptions.tier 把關（不信 client 宣稱，與起步贈抽的
      // client 訊號不同——訂閱狀態 server 本來就有權威值）；冪等 upsert，
      // 既有訂閱者首次呼叫自然回溯補發。退訂不回收（granted = granted）。
      const { data: subRow, error: subReadError } = await supabase
        .from("subscriptions")
        .select("tier")
        .eq("user_id", user.id)
        .maybeSingle();
      if (subReadError) {
        logWarn("practice_sr_ticket_ensure_error", {
          user: summarizeUser(user.id),
          error: subReadError.message,
        });
        return jsonResponse({ error: "sr_ticket_ensure_failed" }, 500);
      }
      const tier = normalizeTier(
        typeof subRow?.tier === "string" ? subRow.tier : null,
      );
      if (tier === "free") {
        return jsonResponse({
          eligible: false,
          granted: false,
          consumed: false,
        });
      }
      const { error: grantError } = await supabase
        .from("practice_sr_draw_tickets")
        .upsert(
          { user_id: user.id, tier_at_grant: tier },
          { onConflict: "user_id", ignoreDuplicates: true },
        );
      if (grantError) {
        logWarn("practice_sr_ticket_ensure_error", {
          user: summarizeUser(user.id),
          error: grantError.message,
        });
        return jsonResponse({ error: "sr_ticket_ensure_failed" }, 500);
      }
      const { data: ticketRow, error: ticketReadError } = await supabase
        .from("practice_sr_draw_tickets")
        .select("consumed_at")
        .eq("user_id", user.id)
        .maybeSingle();
      if (ticketReadError || !ticketRow) {
        logWarn("practice_sr_ticket_ensure_error", {
          user: summarizeUser(user.id),
          error: ticketReadError?.message ?? "missing row after grant",
        });
        return jsonResponse({ error: "sr_ticket_ensure_failed" }, 500);
      }
      return jsonResponse({
        eligible: true,
        granted: true,
        consumed: ticketRow.consumed_at != null,
      });
    }

    if (
      isPlainObject(rawBody) && rawBody.mode === "grant_onboarding_draw_bonus"
    ) {
      // 起步清單全完成 → 一次性贈抽 grant（批 3，A 案）。冪等：一人一列
      // （PK user_id）＋ignoreDuplicates，client best-effort 重呼無害。
      // 清單完成訊號在 client 本機、server 不驗證——濫用面封頂每帳號一抽（拍板）。
      const { error: grantError } = await supabase
        .from("practice_draw_bonuses")
        .upsert(
          { user_id: user.id, source: "getting_started" },
          { onConflict: "user_id", ignoreDuplicates: true },
        );
      if (grantError) {
        logWarn("practice_draw_bonus_grant_error", {
          user: summarizeUser(user.id),
          error: grantError.message,
        });
        return jsonResponse({ error: "bonus_grant_failed" }, 500);
      }
      const { data: bonusRow, error: bonusReadError } = await supabase
        .from("practice_draw_bonuses")
        .select("consumed_at")
        .eq("user_id", user.id)
        .maybeSingle();
      if (bonusReadError || !bonusRow) {
        logWarn("practice_draw_bonus_grant_error", {
          user: summarizeUser(user.id),
          error: bonusReadError?.message ?? "missing row after grant",
        });
        return jsonResponse({ error: "bonus_grant_failed" }, 500);
      }
      return jsonResponse({
        granted: true,
        consumed: bonusRow.consumed_at != null,
      });
    }

    if (isPlainObject(rawBody) && rawBody.mode === "draw_status") {
      // 圖鑑額度列 v2：唯讀翻牌額度狀態（不 reset、不扣費、不寫任何東西）。
      const statusResult = await handleDrawStatus({
        supabase: supabase as unknown as DrawSupabaseClient,
        userId: user.id,
        now: deps.now?.() ?? new Date(),
      });
      return jsonResponse(statusResult.body, statusResult.status);
    }

    if (isPlainObject(rawBody) && rawBody.mode === "practice_collection") {
      // 角色圖鑑唯讀清單：server 是「翻到過誰」的唯一真相源。
      const collectionResult = await handlePracticeCollection({
        supabase: supabase as unknown as DrawSupabaseClient,
        userId: user.id,
      });
      return jsonResponse(collectionResult.body, collectionResult.status);
    }

    if (isPlainObject(rawBody) && rawBody.mode === "practice_moments") {
      // 模擬社群動態 feed：唯讀 + 有界補生成。與 chat/hint/debrief 完全隔離，
      // 生成輸入只有 server profile + 日期 + 題材（隱私鐵則）。
      //
      // 生成配圖（PR-3）的 kill switch 在這裡：MOMENT_IMAGE_GEN_ENABLED 非
      // "true" 或缺 FAL_API_KEY 就不組 imageGen deps → wantsImage slot 走
      // 現行 bundled 候選路徑，行為與導入前完全相同。storagePublicUrlBase
      // 刻意獨立於開關：已生成的圖在開關關閉後仍要露出。
      const momentsDeepSeekKey = deps.getEnv("DEEPSEEK_API_KEY") ?? "";
      const falApiKey = deps.getEnv("FAL_API_KEY") ?? "";
      const momentImageGenEnabled =
        (deps.getEnv("MOMENT_IMAGE_GEN_ENABLED") ?? "") === "true";
      const supabaseUrl = deps.getEnv("SUPABASE_URL") ?? "";
      const momentsResult = await handlePracticeMoments({
        supabase: supabase as unknown as MomentsSupabaseClient,
        userId: user.id,
        now: deps.now?.() ?? new Date(),
        isTestAccount: TEST_EMAILS.includes(user.email || ""),
        deps: {
          apiKey: momentsDeepSeekKey,
          callDeepSeek: deps.callDeepSeek,
          waitUntil: deps.waitUntil,
          // 貼文全域可見：只有 "true" 才開 style 層（"test" 不影響貼文）。
          replyStyleEnabled:
            deps.getEnv("PRACTICE_REPLY_STYLE_ENABLED") === "true",
          storagePublicUrlBase: supabaseUrl.length > 0
            ? `${supabaseUrl}/storage/v1/object/public/${MOMENT_IMAGE_BUCKET}`
            : undefined,
          imageGen: momentImageGenEnabled && falApiKey.length > 0 &&
              momentsDeepSeekKey.length > 0
            ? {
              falApiKey,
              deepSeekApiKey: momentsDeepSeekKey,
              callDeepSeek: deps.callDeepSeek,
              // upsert:false——路徑以 token 隔離、永不覆寫（複審 P1-1）。
              uploadImage: (path, bytes, contentType) =>
                momentImageStorage(supabase).upload(path, bytes, contentType),
              removeImage: (path) =>
                momentImageStorage(supabase).remove([path]),
            }
            : undefined,
          imageSweep: {
            listImages: (prefix, opts) =>
              momentImageStorage(supabase).list(prefix, opts),
            listPrefixes: (opts) =>
              momentImageStorage(supabase).listPrefixes(opts),
            removeImages: (paths) => momentImageStorage(supabase).remove(paths),
          },
        },
      });
      return jsonResponse(momentsResult.body, momentsResult.status);
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
    // 台北「現在」整趟請求只算一次：生活場景、貼文記憶窗、以及注入 chat/hint/
    // debrief 的時間錨點都吃同一份，三條路徑才不會在跨分鐘或跨日的請求上
    // 各報一個時間。
    const nowContext = taipeiTimeContextFor(requestNow);
    const sceneContext = buildPracticeSceneContext({
      profile: request.profile,
      time: nowContext,
      visiblePracticeThreadId: request.visiblePracticeThreadId ??
        request.sessionId,
    });
    // 認識管道：server 唯一真相源、無 DB 狀態，seed 綁 thread（同一段關係跨輪、
    // 跨 chat/hint/debrief 都是同一個場景），故舊 client 不需改動也拿得到一致背景。
    const acquaintanceOrigin = buildAcquaintanceOrigin({
      profile: request.profile,
      threadId: threadIdForPracticeRequest({
        sessionId: request.sessionId,
        visiblePracticeThreadId: request.visiblePracticeThreadId,
      }),
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
    // reply-style-v1：server-only 旗標。"true"＝全部使用者；"test"＝只有 TEST_EMAILS
    // 帳號（dogfood）；其他＝關。關閉或角色沒有 mapping 時，chat／hint／debrief／
    // partnerMood 分類器的 prompt 都與旗標接線前逐字相同。
    const replyStyleFlag = deps.getEnv("PRACTICE_REPLY_STYLE_ENABLED");
    const replyStyleEnabled = replyStyleFlag === "true" ||
      (replyStyleFlag === "test" && accountIsTest);
    const replyStyleProfile = replyStyleEnabled
      ? replyStyleFor(request.profile.girl.profileId)
      : null;
    // conversation-agency-v1：server-only 旗標，與 reply-style 獨立。
    // "true"＝全部；"test"＝只有 TEST_EMAILS；"shadow"＝只算 evidence 與 telemetry，
    // prompt／守門／回應／thread payload 都與旗標關閉逐字相同；其他＝關。
    const agencyMode = agencyModeFor(
      deps.getEnv("PRACTICE_CONVERSATIONAL_AGENCY_ENABLED"),
      accountIsTest,
    );
    // Phase 3.3 形狀實驗旋鈕：`off`（預設，與接線前逐字相同）／`truncate`。
    // 只有 agency 解析成 `on` 且這一輪真的介入時才會有效果，所以旗標
    // off／shadow 的行為與 telemetry 完全不受影響。
    const agencyShapeExperiment = agencyMode === "on"
      ? agencyShapeExperimentFor(
        deps.getEnv("PRACTICE_AGENCY_SHAPE_EXPERIMENT"),
      )
      : "off";
    // Phase 4.4 混合模型路由旗標：`mixed`＝她要介入的那一輪換 Claude Haiku 4.5、
    // 其餘 DeepSeek；未設／其他值＝chat 生成路徑逐位元組與接線前相同（連
    // telemetry 都不多一個 key）。與 agency 旗標獨立，但只在 agency `on` 且
    // 這一輪真的介入時才有效果（`chatModelFor`）。
    const chatModelRoutingFlag = deps.getEnv("PRACTICE_CHAT_MODEL_ROUTING");
    const chatModelRoutingOn = chatModelRoutingFlag === "mixed";
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
      // 兩發都被 gate 打回後靠結構 degrade pass 端出的結果；telemetry 要能跟
      // 「一次過」分開。
      let hintDegradeUsed = false;
      // 守門嚴重度分級（2026-08-07）：偏好門不否決、違規碼記 finding。只保留
      // 最終被端出那一發的 codes——失敗發的候選連卡帶碼一起丟棄，敗因已在
      // attemptFailures.code 有跡。
      let hintQualityFindingCodes: string[] = [];
      // validate 與 degrade pass 共用同一條解析路徑（含 server-authored
      // decision），兩邊各寫一份必然漂移。宣告在 try 外才進得了 catch；還沒
      // 建好就失敗（例如 claude_unavailable）時為 null＝不搶救。
      let hintParseCandidate:
        | ((
          raw: string,
          override?: { finalDegradePass?: boolean },
        ) => ReturnType<typeof parseHintResult>)
        | null = null;
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
      // Phase 4.1：教練要不要點出「你還沒回答她／連續丟詞」。旗標 off 時整個
      // 不算（純函式無副作用，但 off 路徑連 telemetry key 都不該多一個）。
      // hint 是 assisted 專用，thread state 讀不到時退回純結構近似（state=null）。
      // 門檻與 chat 路徑同源（難度／isGame／角色的 agency profile）。
      const hintAgencyCoaching = agencyMode === "off"
        ? null
        : hintAgencyCoachingFor(
          request.turns,
          relationshipThreadState?.agencyState ?? null,
          {
            difficulty: request.profile.difficulty,
            isGame: request.practiceMode === "game",
            profileId: request.profile.girl.profileId,
          },
        );
      try {
        const baseHintMessages = buildHintMessages({
          allowNoPasteableReply: request.acceptsNoPasteableHint === true,
          // 最後一顆球要順手鋪場景（Eric 2026-08-11）：回合下限最高只到 P4，
          // 第 5 發常常停在純升溫，但這場之後就沒有提示了。
          hintsRemaining: Math.max(
            0,
            MAX_HINTS_PER_ROUND - (ledger.hintCount ?? 0),
          ),
          turns: request.turns,
          profile: request.profile,
          practiceMode: request.practiceMode,
          temperatureScore: hintTemperatureScore,
          familiarityScore: hintFamiliarityScore,
          partnerMood: hintPartnerMood,
          sceneContext,
          acquaintanceOrigin,
          memorySummary: promptMemorySummary,
          timeContext: nowContext,
          gameState: ledgerGameState,
          replyStyle: replyStyleProfile,
          // Phase 4.1：只有旗標 `on` 才進 prompt。shadow 仍會算（下面的
          // telemetry），但 prompt 逐字與 off 相同——shadow 的契約。
          agencyCoaching: agencyMode === "on" ? hintAgencyCoaching : null,
        });
        const hintFactualEvidence = hintTrustedFactualEvidence({
          profile: request.profile,
          practiceMode: request.practiceMode,
          sceneContext,
          acquaintanceOrigin,
          memorySummary: promptMemorySummary,
        });
        // 第二刀 B6（2026-08-24）：兩顆球的尺度類熱度門，與 prompt 同源用
        // FSM snapshot 算，L3（天花板）才開；非 game 模式恆低熱。
        const hintSpicyAllowed = request.practiceMode === "game" &&
          evaluateGameFsm({
              turns: request.turns,
              temperatureScore: hintTemperatureScore,
              familiarityScore: hintFamiliarityScore,
              partnerMood: hintPartnerMood,
            }).spicyLevel === "L3";
        const generatedHintParseOptions = {
          mode: request.practiceMode,
          turns: request.turns,
          sharedFactualEvidence: hintFactualEvidence.shared,
          partnerFactualEvidence: hintFactualEvidence.partner,
          trustedFactClaims: hintFactualEvidence.claims,
          enforceGeneratedQuality: true,
          spicyAllowed: hintSpicyAllowed,
          // client 能力宣告；缺席＝舊 build，維持舊契約（server 也不會教模型
          // 輸出那個形狀，見 buildHintMessages）。
          allowNoPasteableReply: request.acceptsNoPasteableHint === true,
        } as const;
        hintParseCandidate = (raw, override) => {
          const findingCodes: string[] = [];
          const parsed = parseHintResult(raw, {
            ...generatedHintParseOptions,
            onQualityFinding: (code) => findingCodes.push(code),
            ...override,
          });
          const result = {
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
                // 這個 builder 跑在 parseHintResult 之後，parse 的旗標管不到
                // 它——degrade pass 要一起讓路，否則邀約階梯會自己造出 503。
                finalDegradePass: override?.finalDegradePass === true,
              }),
            })) as typeof parsed.replies,
          };
          // 走到這裡＝整條解析（含 decision）都成功，這一發就是要端出去的
          // 那一發；失敗發在上面 throw 掉，findings 隨候選一起丟棄。
          hintQualityFindingCodes = findingCodes;
          return result;
        };
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
            validate: (raw) => hintParseCandidate!(raw),
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
        const hintRejectedCandidates = e instanceof SingleShotExhaustedError
          ? e.attemptFailures.filter((failure) =>
            typeof failure.raw === "string"
          )
          : [];
        // 結構 degrade pass：兩發都沒過 gate 時，只救白名單敗因（形狀壞掉／
        // server 契約卡住）的候選端出，而不是讓使用者拿到 503（Eric
        // 2026-08-05：正常一定要有輸出）。偏好門已不殺卡，會走到這裡的偏好
        // 違規早已是 finding。走 hintParseCandidate 同一條路徑以保留
        // server-authored decision。必須排在 releaseHintGeneration 之前。
        const degradedHint =
          e instanceof SingleShotExhaustedError && hintParseCandidate
            ? degradeStructuralHintCandidate({
              failures: e.attemptFailures,
              parse: (raw) =>
                hintParseCandidate!(raw, { finalDegradePass: true }),
            })
            : null;
        if (degradedHint) {
          hintResult = degradedHint.result;
          hintModel = degradedHint.model;
          hintDegradeUsed = true;
          hintFailoverUsed = true;
          hintAttemptCount = Math.max(1, hintAttemptCount);
          hintLastFailureClass = null;
          hintQualityFindingCodes.push("hint_structural_degrade_served");
          logInfo("practice_chat_generation_degraded", {
            user: summarizeUser(user.id),
            mode: "hint",
            practiceMode: request.practiceMode,
            model: hintModel,
            failureCodes: hintFailureCodes,
          });
        } else {
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
            rejectedCandidates: hintRejectedCandidates,
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
            {
              error: "practice_hint_generation_retryable",
              retryable: true,
              // 2026-08-06 W3：讓 client 講真話。傳輸類重按會好，內容類重按多半
              // 拿到同一個結果——引導無效重試等於騙使用者多等一輪。舊 client
              // 沒讀這個鍵，維持原本的通用文案。
              failureReason: practiceGenerationRetryAdvice(
                hintFailureClasses.length > 0
                  ? hintFailureClasses
                  : [failureClass],
              ),
            },
            503,
          );
        }
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
          // 共用欄位名跟著 debrief 的 salvage 走；hint 側語意＝degrade pass。
          salvageUsed: hintDegradeUsed,
          totalDurationMs: hintTotalDurationMs,
          promptChars: hintPromptChars,
        }),
        // Phase 4.1：只有 enum 與小整數。旗標 off 時整個 key 不存在（與 chat
        // 路徑的 `conversationAgency` 同一個慣例，所以 flag-off golden 不變）。
        ...(hintAgencyCoaching === null ? {} : {
          conversationAgency: {
            applied: agencyMode === "on",
            coachingKind: hintAgencyCoaching.kind,
            unresolvedCount: hintAgencyCoaching.unresolvedCount,
          },
        }),
      });
      if (hintQualityFindingCodes.length > 0) {
        // 守門嚴重度分級：偏好門違規不否決，這裡是它們唯一的觀測出口。
        // finding 率長期偏高＝回頭修 prompt 或門本身，絕不加回否決權。
        logInfo("practice_chat_hint_quality_finding", {
          user: summarizeUser(user.id),
          practiceMode: request.practiceMode,
          model: hintModel,
          prefetch: requestIsPrefetch,
          // 同碼去重（Grok 首審 P2）：一發三欄都踩同一道門只算一「類」，
          // 否則 finding 率分母膨脹。
          codes: [...new Set(hintQualityFindingCodes)],
        });
      }
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
        salvageUsed: hintDegradeUsed,
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
      // 兩發都被 gate 打回後靠 salvage 端出的卡；telemetry 要能跟「一次過」分開，
      // 否則守門誤殺率會變成看不見的品質債（salvage 率長期偏高＝該回頭修 gate）。
      let debriefSalvageUsed = false;
      // 偏好門（grounding/主觀 rubric/fact ledger…）降級後的觀測通道：卡照端，
      // 違規碼記在這裡隨成功 log 出去（finding 率長期偏高＝回頭修 prompt 或門）。
      let debriefQualityFindingCodes: string[] = [];
      // salvage 在 catch 裡要用同一份解析設定，但它宣告在 try 內；hoist 一個
      // 參照出來。還沒建好就失敗（例如 claude_unavailable）時為 null＝不搶救。
      let debriefParseOptionsForSalvage:
        | Parameters<typeof parseDebriefCard>[1]
        | null = null;
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
      // Phase 4.1：結構回放出「她在補救」的輪次。旗標 off 時整個不算（連
      // telemetry key 都不該多一個）；shadow 算但不進 prompt。standard 沒有
      // 持久化狀態，本來就是純結構近似（見 `debriefAgencyLedgerFor` 註解）。
      // 門檻與 chat 路徑同源（難度／isGame／角色的 agency profile）。
      const debriefAgencyLedger = agencyMode === "off"
        ? null
        : debriefAgencyLedgerFor(request.turns, {
          difficulty: request.profile.difficulty,
          isGame: debriefPracticeMode === "game",
          profileId: request.profile.girl.profileId,
        });
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
              acquaintanceOrigin,
              memorySummary: promptMemorySummary,
              timeContext: nowContext,
              gameState: ledgerGameState,
              appliedHintTurns: ledgerAppliedHintTurns,
              replyStyle: replyStyleProfile,
              agencyLedger: agencyMode === "on" ? debriefAgencyLedger : null,
            }
            : {
              partnerState: partnerStateFromLedger(ledger) ??
                relationshipThreadState?.partnerState ?? null,
              sceneContext,
              acquaintanceOrigin,
              memorySummary: promptMemorySummary,
              timeContext: nowContext,
              replyStyle: replyStyleProfile,
              agencyLedger: agencyMode === "on" ? debriefAgencyLedger : null,
            },
        );
        const debriefFactualEvidence = hintTrustedFactualEvidence({
          profile: request.profile,
          practiceMode: debriefPracticeMode,
          sceneContext,
          acquaintanceOrigin,
          memorySummary: promptMemorySummary,
        });
        // 第二刀 B6（2026-08-24）：建議句欄的尺度類熱度門。與 prompt 同源用
        // FSM snapshot 算，L3（天花板）才開；非 game 模式恆低熱。
        const debriefSpicyAllowed = debriefPracticeMode === "game" &&
          evaluateGameFsm({
              turns: request.turns,
              temperatureScore: ledger.temperatureScore ??
                difficultyStartTemperature,
              familiarityScore: ledger.familiarityScore ?? 0,
              partnerMood: (partnerStateFromLedger(ledger) ??
                relationshipThreadState?.partnerState)?.mood ?? null,
            }).spicyLevel === "L3";
        const generatedDebriefParseOptions = {
          allowGameBreakdown: debriefPracticeMode === "game",
          requireCompleteCard: true,
          turns: request.turns,
          appliedHintTurns: ledgerAppliedHintTurns,
          sharedFactualEvidence: debriefFactualEvidence.shared,
          partnerFactualEvidence: debriefFactualEvidence.partner,
          trustedFactClaims: debriefFactualEvidence.claims,
          enforceGeneratedQuality: true,
          spicyAllowed: debriefSpicyAllowed,
        } as const;
        debriefParseOptionsForSalvage = generatedDebriefParseOptions;
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
            inputSchema: debriefToolSchemaFor({
              game: debriefPracticeMode === "game",
            }),
          },
          maxTokens: DEBRIEF_MAX_TOKENS,
          temperature: DEBRIEF_TEMPERATURE,
          perCallTimeoutMs: DEBRIEF_SINGLE_SHOT_TIMEOUT_MS,
          deadlineAtMs: debriefAbsoluteDeadlineAtMs,
          now: monotonicNow,
          models: [CLAUDE_SONNET_MODEL, CLAUDE_HAIKU_MODEL],
          // 否決權只剩紅線（罐頭/洩漏/L4）與結構性失敗（缺欄/壞 JSON/拆盤
          // 殘缺）；偏好門降級為 finding 隨成功卡回報（守門嚴重度分級，
          // 2026-08-06）。findings 逐發收集，只保留「被端出去那張卡」的。
          validate: (raw) => {
            const findingCodes: string[] = [];
            const card = parseDebriefCard(raw, {
              ...generatedDebriefParseOptions,
              onQualityFinding: (code) => findingCodes.push(code),
            });
            debriefQualityFindingCodes = findingCodes;
            return card;
          },
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
        const debriefRejectedCandidates = e instanceof SingleShotExhaustedError
          ? e.attemptFailures.filter((failure) =>
            typeof failure.raw === "string"
          )
          : [];
        // Salvage：兩發都被打回時端出最佳候選，而不是讓使用者拿到 503
        //（Eric 2026-08-05：正常一定要有輸出）。偏好門降級後會走到這裡的只剩
        // 結構性失敗與紅線；紅線（罐頭/洩漏/L4）與核心欄位完整性照擋，救不
        // 起來才落回下面的 503。
        // 必須排在 releaseDebriefGeneration 之前——成功搶救要繼續走成功路徑，
        // 不能先把 generation token 釋放掉。
        const salvagedDebrief =
          e instanceof SingleShotExhaustedError && debriefParseOptionsForSalvage
            ? salvageDebriefCandidate({
              failures: e.attemptFailures,
              parseOptions: debriefParseOptionsForSalvage,
            })
            : null;
        if (salvagedDebrief) {
          debriefCard = salvagedDebrief.card;
          debriefModel = salvagedDebrief.model;
          debriefSalvageUsed = true;
          debriefFailoverUsed = true;
          debriefAttemptCount = Math.max(1, debriefAttemptCount);
          debriefLastFailureClass = null;
          logInfo("practice_chat_generation_salvaged", {
            user: summarizeUser(user.id),
            mode: "debrief",
            practiceMode: debriefPracticeMode,
            model: debriefModel,
            failureCodes: debriefFailureCodes,
          });
        } else {
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
            rejectedCandidates: debriefRejectedCandidates,
          });
          return jsonResponse(
            {
              error: "practice_debrief_generation_retryable",
              retryable: true,
              // 同 hint：見 practiceGenerationRetryAdvice。
              failureReason: practiceGenerationRetryAdvice(
                debriefFailureClasses.length > 0
                  ? debriefFailureClasses
                  : [failureClass],
              ),
            },
            503,
          );
        }
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
          salvageUsed: debriefSalvageUsed,
          totalDurationMs: debriefTotalDurationMs,
          promptChars: debriefPromptChars,
        }),
        // Phase 4.1：只有計數，不記逐字稿內容。旗標 off 時整個 key 不存在。
        ...(debriefAgencyLedger === null ? {} : {
          conversationAgency: {
            applied: agencyMode === "on",
            fragmentTurns: debriefAgencyLedger.fragmentTurns,
            topicShiftTurns: debriefAgencyLedger.topicShiftTurns,
            loopTurns: debriefAgencyLedger.loopTurns,
            // Codex R1 P2：真實總數，不是被 10 截過的 `repairTurns.length`。
            repairTurnCount: debriefAgencyLedger.repairTurnCount,
          },
        }),
      });
      if (debriefQualityFindingCodes.length > 0) {
        logInfo("practice_chat_debrief_quality_finding", {
          user: summarizeUser(user.id),
          practiceMode: debriefPracticeMode,
          model: debriefModel,
          codes: debriefQualityFindingCodes,
        });
      }
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
        salvageUsed: debriefSalvageUsed,
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
    // 不吃 client 值——以建檔與否切分，堵舊列吃 seed 的洞）。優先序與 source
    // 標籤都在 resolveLearningSeed（PR 6）。
    const learningSeed = resolveLearningSeed({
      assistedMode,
      ledger: {
        exists: ledger.exists,
        temperatureScore: ledger.temperatureScore,
        familiarityScore: ledger.familiarityScore,
      },
      threadState: relationshipThreadState,
      clientTemperatureScore: request.temperatureScore,
      clientFamiliarityScore: request.familiarityScore,
      difficultyStartTemperature,
    });
    const currentTemperature = learningSeed.temperatureScore;
    const currentFamiliarity = learningSeed.familiarityScore;
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

    // 朋友圈記憶：她記得自己最近發過什麼（moments_memory.ts）。
    // 一次唯讀 RPC，走 feed 既有的 list_practice_moment_posts，不需要新 migration。
    // **fail-open**：拉不到就當作沒有貼文，聊天照常進行——記憶是加值，聊天是核心。
    // 隱私鐵則不變：貼文是全域的，輸入只有 server profile + 日期 + 題材，
    // 這裡也只用 profileId 去讀，不帶任何使用者對話或暱稱。
    const herRecentMoments = await fetchHerRecentMoments({
      supabase,
      profileId: request.profile.girl.profileId,
      isoDate: nowContext.isoDate,
      now: requestNow,
      onError: (message) =>
        logWarn("practice_moment_memory_read_failed", {
          user: summarizeUser(user.id),
          error: message,
        }),
    });
    const herRecentMomentsBlock = herRecentMomentsPrompt(
      herRecentMoments,
      agencyMode === "on",
    );

    let reply: string | null = null;
    let responsePlan: TurnResponsePlan | null = null;
    let agencyDecision: ChatAgencyDecision | null = null;
    let stageDirectionRepairs = 0;
    /** Phase 3.3 `truncate` 臂丟掉幾則（旋鈕 off 時永遠 0，也不進 telemetry）。 */
    let shapeTruncatedBubbles = 0;
    /** Phase 4.4：這一輪**最終採用**的回覆是哪支模型（旗標 off 時永遠 deepseek）。 */
    let chatModelUsed: PracticeChatModel = "deepseek";
    /** 這一輪有任何一次 Claude 呼叫失敗過（守門重試也算）。 */
    let chatModelFallback = false;
    /** Codex R1 P1：整輪**累加**，不是最後一次覆寫——守門退回後重打 Claude
     * 是真的付兩次錢，telemetry 不能只記後面那次。 */
    let chatModelUsage: ClaudeUsage | undefined;
    const chatModelCalls = { haiku: 0, deepseek: 0 };
    const addChatModelUsage = (usage: ClaudeUsage) => {
      chatModelUsage = {
        inputTokens: (chatModelUsage?.inputTokens ?? 0) + usage.inputTokens,
        cacheReadInputTokens: (chatModelUsage?.cacheReadInputTokens ?? 0) +
          usage.cacheReadInputTokens,
        cacheCreationInputTokens:
          (chatModelUsage?.cacheCreationInputTokens ?? 0) +
          usage.cacheCreationInputTokens,
        outputTokens: (chatModelUsage?.outputTokens ?? 0) + usage.outputTokens,
      };
    };
    try {
      // reply-style-v1（PR-2）：server-only 旗標；關閉或角色沒有 mapping 時
      // prompt／守門／回應逐字與舊版相同（index_test 對 fee76b87 golden bytes 比對）。
      // bundle 只算一次：兩次 attempt 共用同一份 plan，不會第二發換形狀；
      // 純函式建構若丟錯，走與舊版相同的 practice_generation_failed 邊界（不重試）。
      const chatPromptBundle = buildChatPromptBundle(
        request.turns,
        request.profile,
        assistedMode
          ? {
            replyStyle: replyStyleEnabled,
            visiblePracticeThreadId: visibleThreadId,
            practiceMode: request.practiceMode,
            temperatureScore: currentTemperature ??
              difficultyStartTemperature,
            familiarityScore: currentFamiliarity ?? 0,
            partnerState: promptPartnerState,
            sceneContext,
            acquaintanceOrigin,
            memorySummary: promptMemorySummary,
            timeContext: nowContext,
            herRecentMomentsBlock,
            gameState: ledgerGameState,
            styleState: relationshipThreadState?.styleState ?? null,
            agencyMode,
            agencyState: relationshipThreadState?.agencyState ?? null,
          }
          : {
            replyStyle: replyStyleEnabled,
            visiblePracticeThreadId: visibleThreadId,
            partnerState: promptPartnerState,
            sceneContext,
            acquaintanceOrigin,
            memorySummary: promptMemorySummary,
            timeContext: nowContext,
            herRecentMomentsBlock,
            agencyMode,
            // standard 沒有 thread 寫入，也不讀 assisted 留下的狀態（規格附錄：
            // standard 的 priorDecline 一律 false）；agency 短期狀態改從逐字稿現推。
          },
      );
      responsePlan = chatPromptBundle.responsePlan;
      // conversation-agency-v1（Codex P1）：獨立於 responsePlan，replyStyle 關閉
      // 或角色沒有 mapping 時一樣有值。
      agencyDecision = chatPromptBundle.agencyDecision;
      // Phase 4.4 混合模型路由：條件與黑箱 runner 的 `--chat-model=mixed` 臂
      // 逐字相同（`chatModelFor`）。沒有 Anthropic key／沒有注入 callClaude
      // 就當作沒開（chat 本來就要求 DeepSeek key 才進得來，退路一定在）。
      const useHaiku = chatModelFor(
            chatModelRoutingFlag,
            agencyMode,
            agencyDecision,
            request.practiceMode,
            chatPromptBundle.situation,
          ) === "haiku" && !!claudeApiKey && !!deps.callClaude;
      const generateWithDeepSeek = () => {
        chatModelCalls.deepseek++;
        return deps.callDeepSeek({
          apiKey,
          messages: chatPromptBundle.messages,
          maxTokens: CHAT_MAX_TOKENS,
          temperature: CHAT_TEMPERATURE,
          timeoutMs: DEEPSEEK_TIMEOUT_MS,
        });
      };
      let lastError: unknown;
      for (let attempt = 1; attempt <= CHAT_GENERATION_ATTEMPTS; attempt++) {
        try {
          if (useHaiku && !chatModelFallback) {
            try {
              // max_tokens／temperature 與 DeepSeek 路徑同值（成本護欄：Claude
              // 這一輪不會比 DeepSeek 那一輪更長），system 走 `callClaude` 內建
              // 的 ephemeral cache_control。
              chatModelCalls.haiku++;
              reply = await deps.callClaude!({
                apiKey: claudeApiKey!,
                model: CLAUDE_HAIKU_MODEL,
                messages: chatPromptBundle.messages,
                maxTokens: CHAT_MAX_TOKENS,
                temperature: CHAT_TEMPERATURE,
                timeoutMs: DEEPSEEK_TIMEOUT_MS,
                onUsage: addChatModelUsage,
              });
              chatModelUsed = "haiku";
            } catch (e) {
              // 逾時／4xx／5xx／解析失敗都退回 DeepSeek 同一輪重生，之後這一輪
              // 不再打 Claude（避免第二 attempt 又付一次同樣的失敗）。已經成功
              // 拿到過的 usage **不清掉**（那些 token 真的付了）。
              chatModelFallback = true;
              chatModelUsed = "deepseek";
              logWarn("practice_chat_model_fallback", {
                user: summarizeUser(user.id),
                attempt,
                error: getErrorMessage(e),
              });
              reply = await generateWithDeepSeek();
            }
          } else {
            reply = await generateWithDeepSeek();
          }
          // DeepSeek 偶爾在短/冒犯輸入下退回訓練分佈的簡體字，繁體鐵則守不住；
          // 其他 AI 輸出欄位（hint/debrief/temperature）都已過這道轉換，這裡補齊。
          reply = toTraditionalChinese(normalizeLiteralNewlines(reply));
          rejectVisibleInternalLabelLeak(reply, "chat_internal_label_leak", {
            // 第二刀 A 組：NPC 引用對話裡出現過的詞不是機制外洩。
            transcript: request.turns.map((turn) => turn.text).join("\n"),
            // style 層或 agency-only guidance 真的注入時才多攔 hidden heading
            // （旗標全關時兩者皆無，零改動）。
            ...(responsePlan || agencyDecision?.applied
              ? { extraChineseLabels: REPLY_STYLE_HIDDEN_HEADINGS }
              : {}),
          });
          // 第二刀（Eric 2026-08-24 拍板）：NPC 可以反撩——尺度類按本輪熱度
          // （與 prompt 的 allowSpicyLevel 同源），同意權類永遠攔。
          rejectL4UnsafeVisibleText(reply, "chat_l4_unsafe", {
            fieldClass: "strict",
            spicyAllowed: assistedMode && request.practiceMode === "game" &&
              evaluateGameFsm({
                  turns: request.turns,
                  temperatureScore: currentTemperature ??
                    difficultyStartTemperature,
                  familiarityScore: currentFamiliarity ?? 0,
                  partnerMood: promptPartnerState?.mood ?? null,
                }).spicyLevel === "L3",
          });
          // 括號旁白：style 層才會出現（run3–run5 量到 1–5%）；修補優先，
          // 整段剝到空才丟 chat_stage_direction 重試。
          if (responsePlan && hasStageDirection(reply)) {
            stageDirectionRepairs++;
            reply = stripStageDirections(reply, "chat_stage_direction");
          }
          // Phase 3.3 `truncate` 臂：她第一則就是問句時只留第一則（結構判斷，
          // 見 truncateAgencyShape）。放在最後一道後處理，`reply` 就地覆寫，
          // 所以 commit、classifier、hint／debrief 與回應 body 拿到的都是
          // 截斷後的文字。不重試、不再打模型。
          //
          // R1（Codex 精確性項目 3）既有優先權的界線：
          //   越界（boundary）、早／成熟邀約、記憶衝突那些輪次**進不來**——
          //   `computeAgencyDecision`（turn_response_plan.ts）只在 planner 判
          //   `situation === "neutral"` 時保留決策，其餘一律清成
          //   `situation: null` → `applied=false` → `truncateAgencyShape` 直接
          //   放行。唯一會落在 neutral 卻仍有既有優先權的是 Game FSM 的修復
          //   優先／現實旗標（`policyStanceFor` 只把 stance 拉到 cautious），
          //   所以那一輪用 bundle already 算好的 `gameFsmPriority` 關掉截斷。
          if (
            agencyShapeExperiment === "truncate" &&
            !chatPromptBundle.gameFsmPriority
          ) {
            const truncated = truncateAgencyShape(reply, agencyDecision);
            reply = truncated.text;
            shapeTruncatedBubbles = truncated.dropped;
          }
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
        // Codex R2 P2：整輪最後失敗時 `practice_chat_succeeded` 不會印，付掉的
        // Claude 錢就從單輪 telemetry 消失了；成本欄位補在失敗事件上。旗標不是
        // mixed 時整組 key 不存在（flag-off golden 不動）。
        ...(chatModelRoutingOn
          ? {
            chatModelCalls,
            ...(chatModelUsage ? { chatModelUsage } : {}),
          }
          : {}),
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
          replyStyle: replyStyleProfile,
          // conversation-agency-v1 Phase 2：coherence／delta cap 只在旗標
          // ≠ off 時生效；unresolvedCount 用這一輪已經算好的 agency 證據
          // （不重算，避免跟 prompt 用的證據分岔）。
          agencyMode,
          agencyEvidenceUnresolvedCount:
            agencyDecision?.decision.evidence.unresolvedCount ?? 0,
          agencyEvidenceRepeatedExactToken:
            agencyDecision?.decision.evidence.repeatedExactToken ?? false,
          // Phase 3.5：跟 chat prompt 同一份記憶／貼文餵分類器（旗標 off 不用）。
          memorySummary: promptMemorySummary,
          herRecentMoments,
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
      // 必須走 ForLedger 版：漏帶 inviteStage 會讓 ledger 記下錯的速約階梯，
      // 而 effectiveGameFsmSnapshot 會拿它蓋掉 hint 端算對的那個。
      const snapshot = evaluateGameFsmForLedger({
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
            // Codex round-2 P1-4：RPC 整包覆寫 recent_facts，所以要以讀回來的
            // 那一份為底，不能從零重建（不然別的功能／未來版本寫進去的 key
            // 每一輪都會被靜默清掉）。
            existingRecentFacts: relationshipThreadState?.recentFacts ?? null,
            // Codex round-1 P1-a：保留未知 key 只在 agency 旗標 ≠ off 時生效，
            // 旗標關著的 thread payload 必須跟 main 逐字相同（從零重建）。
            agencyMode,
            // reply-style-v1：她這輪的 act 與「明確拒絕過」進 recent_facts。
            // 旗標關（或角色沒 mapping）＝不算新狀態，但既有狀態原樣帶回——
            // RPC 是整包覆寫 recent_facts，省略就等於「關旗標即清空」（Codex R2）。
            // 從沒開過旗標的 thread 沒有狀態＝payload 與接線前逐字相同。
            replyStyleState: responsePlan
              ? nextReplyStyleState(
                relationshipThreadState?.styleState ?? null,
                responsePlan,
              )
              : relationshipThreadState?.styleState ?? undefined,
            // conversation-agency-v1：同一條規則。旗標關或 shadow＝不算新狀態，
            // 既有狀態原樣帶回（RPC 整包覆寫 recent_facts，省略等於清空）。
            // Phase 2：分類器讀了她這一輪實際生成文字後回報的 coherence／
            // aiChallengedThisTurn 一起餵進去（agencyDeltaCapActive 判斷同
            // 一支旗標；旗標 off 時 temperature.classification 沒有這兩個
            // 欄位，agencyClassifierSignal 為 null，退回純結構近似）。
            // Codex round-2 P0-3：旗標 off／shadow 時**一個 agency key 都不寫**。
            // 舊版在這兩種模式下會退回 `relationshipThreadState?.agencyState`
            // 再原樣寫回去，等於「這個 row 一旦有過 agency 狀態，旗標關了也
            // 會被重新寫進 payload」——`main` 不認識這個 key，從零重建時會丟掉
            // 它，所以有殘留狀態的 row 不可能 byte-identical。
            // Codex round-1（新項）P1-1：舊版的閘門是 `agencyDecision?.applied`，
            // 而 `applied` 只在「這一輪真的有介入」時為 true。修復路徑（有效短答、
            // 分類器判 connected、一般分享／問句）**恰好都是 applied=false**，
            // 所以 `nextConversationAgencyState()` 裡寫好的 `priorChallengeIssued`
            // 歸零在正式 handler 永遠跑不到，舊 episode 的質疑旗標會一路污染下去。
            // 改成「旗標 on 就一定推進狀態」：`applied` 從此純粹是 telemetry 上
            // 「有沒有注入 guidance」的意思，不再兼任狀態機的閘門。
            conversationAgencyState: agencyMode !== "on"
              ? undefined
              : agencyDecision
              ? nextConversationAgencyState(
                relationshipThreadState?.agencyState ?? null,
                agencyDecision.decision,
                {
                  coherence: temperature.classification.coherence,
                  aiChallengedThisTurn:
                    temperature.classification.aiChallengedThisTurn,
                } satisfies AgencyClassifierSignal,
                // Phase 3.8：這一輪 planner 強制她問他一件事 → 這場黏住不再強制。
                responsePlan?.askUserFocus !== undefined,
              )
              : relationshipThreadState?.agencyState ?? undefined,
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
      // 認識管道只記 id（allowlisted 常數，無使用者內容），供分佈與一致性觀測。
      acquaintanceOriginId: acquaintanceOrigin.id,
      costDeducted: deducted,
      // ── PR 6 無逐字稿觀測：只有 enums／數字／布林，不記 user 文字、
      // 女孩回覆或完整 prompt（innerThought 是生成文字，刻意不記）。──
      practiceMode: request.practiceMode ?? "standard",
      roundIndex: newAiCount,
      // sessionId 是 client 自由字串 → 照 user id 慣例截斷後才進 log，
      // 供「同一場」跨輪關聯（同 session 首回合＝ledgerExisted:false 那筆）。
      session: summarizeUser(request.sessionId),
      // seedSource／familiaritySeedSource＝本回合兩個分數各自的實際讀取層
      // （thread 承接的新場：首回合 relationship_thread、之後 ledger 是
      // 正常型態；偏離此型態才算「同一場 seed source 不穩定」）。
      seedSource: learningSeed.source,
      familiaritySeedSource: learningSeed.familiaritySource,
      ledgerExisted: ledger.exists,
      temperatureBefore: currentTemperature,
      temperatureAfter: temperature?.score ?? null,
      temperatureDelta: temperature?.delta ?? null,
      familiarityBefore: currentFamiliarity,
      familiarityAfter: temperature?.familiarityScore ?? null,
      familiarityDelta: temperature?.familiarityDelta ?? null,
      classification: temperature
        ? {
          connection: temperature.classification.connection,
          impact: temperature.classification.impact,
          testHandling: temperature.classification.testHandling,
          boundary: temperature.classification.boundary,
          hintAlignment: temperature.classification.hintAlignment,
          partnerMood: temperature.classification.partnerMood,
          // Codex round-1 P1-b：旗標 off 時分類器根本沒判這兩個欄位，
          // telemetry 就不該有這兩個 key（舊版填 "connected"／false，等於
          // 旗標關著的 log 也多出兩個欄位，跟 main 對拍不一樣）。
          ...(temperature.classification.coherence !== undefined
            ? {
              coherence: temperature.classification.coherence,
              aiChallengedThisTurn:
                temperature.classification.aiChallengedThisTurn ?? false,
            }
            : {}),
        }
        : null,
      // Phase 4.4：混合模型路由旗標開著才有這幾個 key（未設／off／亂填時
      // 整組不存在，flag-off golden 一個位元都不動）。`chatModelCalls` 是整輪
      // 每支模型真的被呼叫幾次（守門重試也算），`chatModelUsage` 是所有成功
      // Claude 呼叫的累加，`chatModel` 是最終採用的那一支。每日預算刻意不做，
      // 成本看 Anthropic console。
      ...(chatModelRoutingOn
        ? {
          chatModel: chatModelUsed,
          chatModelCalls,
          ...(chatModelFallback ? { chatModelFallback: true } : {}),
          ...(chatModelUsage ? { chatModelUsage } : {}),
        }
        : {}),
      // Phase 2：delta cap 是否真的壓過這一輪的 heat／familiarity delta。
      // Codex round-2 P0-2：旗標 off 時這個 key **根本不存在**（不是 "none"）
      // ——`main` 的 telemetry 沒有它，填預設值等於旗標關著的 log 也多一個欄位。
      ...(agencyMode !== "off"
        ? { deltaCapApplied: temperature?.deltaCapApplied ?? "none" }
        : {}),
      // 與計分管線同一判準（challenge × beginner 才有獎勵閘門）。
      challengeGateActive: request.practiceMode === "beginner" &&
        request.profile.difficulty === "challenge",
      // 本回合是否真的從上一場 thread 取到分數（thread 存在但欄位全無效
      // 而落到 client/預設時＝false）；「整場是否 continuation」看同 session
      // 首回合（ledgerExisted:false）那筆。
      continuation: learningSeed.source === "relationship_thread" ||
        learningSeed.familiaritySource === "relationship_thread",
      promptPolicyVersion: PRACTICE_PROMPT_POLICY_VERSION,
      // reply-style-v1：只記結構化代碼與數量（規格 §5.5），不記 style prompt 全文。
      replyStyle: responsePlan
        ? {
          styleVersion: responsePlan.styleVersion,
          presetId: responsePlan.presetId,
          policyStance: responsePlan.policyStance,
          situation: responsePlan.situation,
          primaryAct: responsePlan.primaryAct,
          bubbleCount: responsePlan.bubbleCount,
          questionBudget: responsePlan.questionBudget,
          stageDirectionRepairs,
        }
        : null,
      // conversation-agency-v1（計畫「發布與回滾」）：只有 enum／數字／布林。
      // Codex round-2 P0-2：旗標 off 時整個 key 不存在（舊版是
      // `conversationAgency: null`，那仍然是一個 `main` 沒有的欄位）；
      // shadow 才有值，且 applied=false。
      ...(agencyMode === "off" ? {} : {
        conversationAgency: agencyDecision
          ? {
            agencyVersion: agencyDecision.decision.version,
            applied: agencyDecision.applied,
            utteranceShape: agencyDecision.decision.evidence.utteranceShape,
            policyMode: agencyDecision.decision.policyMode,
            forcedAct: agencyDecision.decision.forcedAct,
            allowedActSetId: agencyDecision.decision.allowedActSetId,
            // Phase 4.0：這一輪套用的分人強弱（四個 0–4 的數字，沒有文字）。
            // 旗標 off 時整個 `conversationAgency` key 都不存在，所以這裡多一個
            // 欄位不會動到 flag-off golden；shadow 的契約允許只多 telemetry。
            profile: agencyDecision.profile,
            unresolvedCount: agencyDecision.decision.evidence.unresolvedCount,
            priorChallengeIssued:
              agencyDecision.decision.evidence.priorChallengeIssued,
            // Phase 3.8：這一輪有沒有強制她問他一件事（只記布林，不記好奇點文字）。
            askUserForced: responsePlan?.askUserFocus !== undefined,
            coherenceBefore:
              relationshipThreadState?.agencyState?.lastCoherence ??
                null,
            // Phase 2：分類器讀了實際生成文字後的判斷（旗標 off 時分類器不判，
            // 一律填預設值）。
            coherence: agencyMode === "on"
              ? temperature?.classification.coherence ?? null
              : null,
            aiChallengedThisTurn: agencyMode === "on"
              ? temperature?.classification.aiChallengedThisTurn ?? null
              : null,
            // Phase 3.4：只有旗標 on 且分類器真的判了才有這個 key（shadow／off
            // 連欄位都不多一個）。standard 沒有分類器，恆為缺席。
            // Codex R1 P1：repair 出來的 false（模型漏答／吐非布林）跟模型
            // 真的判「沒捏造」在值上長得一樣，但意思完全不同——多一個
            // `sharedPastClaimRepaired` key（只在真的修過時存在），ops 算
            // 盛行率時才知道分母該不該扣掉這一筆。
            ...(agencyMode === "on" &&
                temperature?.classification.sharedPastClaim !== undefined
              ? {
                sharedPastClaim: temperature.classification.sharedPastClaim,
                ...(temperature.classification.repairedFields?.includes(
                    "sharedPastClaim",
                  )
                  ? { sharedPastClaimRepaired: true }
                  : {}),
              }
              : {}),
            // Phase 3.6：accommodatingSelfFact 同一套規則（on 且分類器判了才有 key）。
            ...(agencyMode === "on" &&
                temperature?.classification.accommodatingSelfFact !== undefined
              ? {
                accommodatingSelfFact:
                  temperature.classification.accommodatingSelfFact,
                ...(temperature.classification.repairedFields?.includes(
                    "accommodatingSelfFact",
                  )
                  ? { accommodatingSelfFactRepaired: true }
                  : {}),
              }
              : {}),
            deltaCapApplied: temperature?.deltaCapApplied ?? "none",
            // Phase 3.3 `truncate` 臂：只有旋鈕開在 truncate 且這一輪 agency
            // 真的介入時這個 key 才存在（其他情形連欄位都不多一個）。
            ...(agencyShapeExperiment === "truncate" && agencyDecision.applied
              ? { shapeTruncatedBubbles }
              : {}),
          }
          : null,
      }),
    });

    const body: Record<string, unknown> = {
      reply,
      aiTurnCount: newAiCount,
      sessionComplete: isSessionComplete(newAiCount),
      costDeducted: deducted,
      // Phase 4.4：路由旗標關著時永遠是 deepseek／DEEPSEEK_MODEL（逐字舊行為）；
      // 真的走 Haiku 那一輪就照實回報，payload 不說謊（client 目前不讀這兩格）。
      provider: chatModelUsed === "haiku" ? "anthropic" : "deepseek",
      model: chatModelUsed === "haiku" ? CLAUDE_HAIKU_MODEL : DEEPSEEK_MODEL,
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
