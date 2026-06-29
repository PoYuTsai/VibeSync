import {
  applyResetsIfNeeded,
  buildQuotaExceededPayload,
  checkQuota,
  isPlainObject,
  resolveLimits,
  type SubscriptionRow,
  TEST_EMAILS,
} from "../_shared/quota.ts";
import { validateDrawRequest, validateRequest } from "./validate.ts";
import { type DrawSupabaseClient, handleDrawProfile } from "./draw_handler.ts";
import { buildChatMessages, buildDebriefMessages } from "./prompt.ts";
import {
  decideChatGate,
  decideContinuationGate,
  decideDebriefGate,
  decideHintGate,
  isSessionComplete,
  MAX_AI_REPLIES,
  MAX_DEBRIEFS,
  MAX_HINTS_PER_ROUND,
  PRACTICE_QUOTA_COST,
  type PracticeLearningMode,
  type SessionLedger,
} from "./quota_decision.ts";
import { DEEPSEEK_MODEL, type DeepSeekArgs } from "./deepseek.ts";
import { type DebriefCard, parseDebriefCard } from "./debrief_card.ts";
import { buildHintMessages, parseHintResult } from "./hint.ts";
import { logError, logInfo, logWarn, summarizeUser } from "./logger.ts";
import {
  applyLearningClassification,
  buildTurnClassifierMessages,
  clampTemperature,
  type LearningJudgement,
  parseTurnClassification,
  relationshipStageFor,
  temperatureBandFor,
  type TurnClassification,
} from "./temperature.ts";

const MAX_BODY_BYTES = 64 * 1024;
const CHAT_MAX_TOKENS = 200;
const CHAT_TEMPERATURE = 0.9;
const CHAT_GENERATION_ATTEMPTS = 2;
const DEBRIEF_MAX_TOKENS = 800;
const DEBRIEF_TEMPERATURE = 0.5;
const DEBRIEF_GENERATION_ATTEMPTS = 2;
const HINT_MAX_TOKENS = 650;
const HINT_TEMPERATURE = 0.45;
const HINT_GENERATION_ATTEMPTS = 2;
const TEMPERATURE_JUDGE_MAX_TOKENS = 450;
const TEMPERATURE_JUDGE_TEMPERATURE = 0.2;
const DEEPSEEK_TIMEOUT_MS = 30000;

function appliedHintHeatFloor(appliedHintType: string | undefined): number {
  if (appliedHintType === "warm_up") return 3;
  if (appliedHintType === "steady") return 2;
  return Number.NEGATIVE_INFINITY;
}

function normalizedHintText(text: string): string {
  return text
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[\s\p{P}\p{S}]+/gu, "");
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
  return value === "beginner" ? "beginner" : "standard";
}

function explicitPracticeModeFromLedger(
  value: unknown,
): PracticeLearningMode | null {
  return value === "beginner" || value === "standard" ? value : null;
}

function temperatureFromLedger(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function familiarityFromLedger(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
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
  };
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
    stageLabel: judgement.stageLabel,
  };
}

function shouldProtectAppliedHint(opts: {
  request: ReturnType<typeof validateRequest>;
  classification: TurnClassification;
}): boolean {
  if (!opts.request.appliedHintType) return false;
  const source = opts.request.appliedHintText;
  if (!source) return true;
  if (
    normalizedHintText(source) ===
      normalizedHintText(lastUserText(opts.request.turns))
  ) {
    return true;
  }
  return opts.classification.hintAlignment === "aligned";
}

function protectAppliedHintTemperature(
  judgement: LearningJudgement,
  currentTemperature: number,
  currentFamiliarity: number,
  appliedHintType: string | undefined,
): LearningJudgement {
  const heatFloor = appliedHintHeatFloor(appliedHintType);
  if (
    heatFloor === Number.NEGATIVE_INFINITY
  ) {
    return judgement;
  }
  const protectedHeatDelta = Math.max(judgement.delta, heatFloor);
  const protectedFamiliarityDelta = Math.max(judgement.familiarityDelta, 0);
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
  return {
    ...judgement,
    score,
    delta: protectedHeatDelta,
    band: temperatureBandFor(score),
    familiarityScore,
    familiarityDelta: protectedFamiliarityDelta,
    stage: stage.stage,
    stageLabel: stage.label,
    reason: "套用提示回覆，維持不降溫",
  };
}

function fallbackLearningJudgement(
  currentTemperature: number,
  currentFamiliarity: number,
): LearningJudgement {
  const score = clampTemperature(currentTemperature + 1);
  const familiarityScore = clampTemperature(currentFamiliarity + 1);
  const stage = relationshipStageFor(familiarityScore, score);
  return {
    score,
    delta: 1,
    band: temperatureBandFor(score),
    reason: "低影響回合，先保守調整",
    familiarityScore,
    familiarityDelta: 1,
    stage: stage.stage,
    stageLabel: stage.label,
    classification: {
      category: "event",
      quality: "ordinary",
      impact: "minor",
      overstep: false,
      hintAlignment: "none",
    },
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
    },
  );
  if (error) {
    throw new Error(error.message);
  }
  return learningStateUpdateResultFromData(data);
}

async function judgeLearningState(opts: {
  deps: PracticeChatHandlerDeps;
  apiKey: string;
  supabase: PracticeSupabaseClient;
  userId: string;
  sessionId: string;
  currentTemperature: number;
  currentFamiliarity: number;
  request: ReturnType<typeof validateRequest>;
  reply: string;
}): Promise<LearningJudgement> {
  const fallback = fallbackLearningJudgement(
    opts.currentTemperature,
    opts.currentFamiliarity,
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
      }),
      maxTokens: TEMPERATURE_JUDGE_MAX_TOKENS,
      temperature: TEMPERATURE_JUDGE_TEMPERATURE,
      jsonMode: true,
      timeoutMs: DEEPSEEK_TIMEOUT_MS,
    });
    const classification: TurnClassification = parseTurnClassification(
      rawClassification,
      {
        requireImpact: opts.request.appliedHintText !== undefined,
        requireHintAlignment: opts.request.appliedHintText !== undefined,
      },
    );
    const judgement = applyLearningClassification({
      heatScore: opts.currentTemperature,
      familiarityScore: opts.currentFamiliarity,
    }, classification);
    const protectedHintType = shouldProtectAppliedHint({
        request: opts.request,
        classification,
      })
      ? opts.request.appliedHintType
      : undefined;
    const protectedJudgement = protectAppliedHintTemperature(
      judgement,
      opts.currentTemperature,
      opts.currentFamiliarity,
      protectedHintType,
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
      const retryJudgement = applyLearningClassification({
        heatScore: firstUpdate.temperatureScore,
        familiarityScore: firstUpdate.familiarityScore,
      }, classification);
      const protectedRetryJudgement = protectAppliedHintTemperature(
        retryJudgement,
        firstUpdate.temperatureScore,
        firstUpdate.familiarityScore,
        protectedHintType,
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
        const retryFallback = fallbackLearningJudgement(
          fallbackUpdate.temperatureScore,
          fallbackUpdate.familiarityScore,
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
        "ai_count, charged, debrief_count, practice_mode, temperature_score, familiarity_score, hint_count",
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
      hintCount: hintCountFromLedger(ledgerRow?.hint_count),
    };

    if (request.mode === "hint") {
      if (request.practiceMode !== "beginner") {
        return jsonResponse({ error: "practice_hint_beginner_only" }, 403);
      }

      const gate = decideHintGate({ ledger, maxHints: MAX_HINTS_PER_ROUND });
      if (!gate.allowed) {
        logWarn("practice_chat_hint_rejected", {
          user: summarizeUser(user.id),
          reason: gate.reason,
        });
        return jsonResponse(
          { error: gate.reason ?? "practice_session_not_started" },
          403,
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

      const { error: claimHintError } = await supabase.rpc(
        "claim_practice_hint_generation",
        {
          p_user_id: user.id,
          p_session_id: request.sessionId,
          p_max_hints: MAX_HINTS_PER_ROUND,
        },
      );
      if (claimHintError) {
        const mapped = mapLedgerError(claimHintError.message);
        logWarn("practice_chat_hint_claim_failed", {
          user: summarizeUser(user.id),
          error: claimHintError.message,
        });
        return jsonResponse({ error: mapped.error }, mapped.status);
      }

      let hintResult: ReturnType<typeof parseHintResult> | null = null;
      try {
        let lastError: unknown;
        for (
          let attempt = 1;
          attempt <= HINT_GENERATION_ATTEMPTS;
          attempt++
        ) {
          try {
            const rawHint = await deps.callDeepSeek({
              apiKey,
              messages: buildHintMessages({
                turns: request.turns,
                profile: request.profile,
                temperatureScore: ledger.temperatureScore ?? 30,
                familiarityScore: ledger.familiarityScore ?? 0,
              }),
              maxTokens: HINT_MAX_TOKENS,
              temperature: HINT_TEMPERATURE,
              jsonMode: true,
              timeoutMs: DEEPSEEK_TIMEOUT_MS,
            });
            hintResult = parseHintResult(rawHint);
            break;
          } catch (e) {
            lastError = e;
            logWarn("practice_chat_hint_generation_attempt_failed", {
              user: summarizeUser(user.id),
              attempt,
              error: getErrorMessage(e),
            });
          }
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

      const { data: recordData, error: recordError } = await supabase.rpc(
        "record_practice_hint",
        {
          p_user_id: user.id,
          p_session_id: request.sessionId,
          p_charge_quota: !accountIsTest,
          p_max_hints: MAX_HINTS_PER_ROUND,
        },
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

    const lockedPracticeMode = explicitPracticeModeFromLedger(
      ledgerRow?.practice_mode,
    );
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

    if (request.mode === "debrief") {
      const gate = decideDebriefGate({ ledger });
      if (!gate.allowed) {
        logWarn("practice_chat_debrief_rejected", {
          user: summarizeUser(user.id),
          reason: gate.reason,
        });
        return jsonResponse({ error: gate.reason }, 403);
      }

      const debriefBeginnerMode = ledger.practiceMode === "beginner";
      if (debriefBeginnerMode) {
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
                debriefBeginnerMode
                  ? {
                    practiceMode: "beginner",
                    temperatureScore: ledger.temperatureScore ?? 30,
                    familiarityScore: ledger.familiarityScore ?? 0,
                  }
                  : {},
              ),
              maxTokens: DEBRIEF_MAX_TOKENS,
              temperature: DEBRIEF_TEMPERATURE,
              jsonMode: true,
              timeoutMs: DEEPSEEK_TIMEOUT_MS,
            });
            debriefCard = parseDebriefCard(rawCard);
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
          throw lastError instanceof Error
            ? lastError
            : new Error("debrief_generation_failed");
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

    const beginnerMode = request.practiceMode === "beginner";
    const currentTemperature = beginnerMode
      ? ledger.temperatureScore ?? 30
      : null;
    const currentFamiliarity = beginnerMode
      ? ledger.familiarityScore ?? 0
      : null;

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
              beginnerMode
                ? {
                  practiceMode: request.practiceMode,
                  temperatureScore: currentTemperature ?? 30,
                  familiarityScore: currentFamiliarity ?? 0,
                }
                : {},
            ),
            maxTokens: CHAT_MAX_TOKENS,
            temperature: CHAT_TEMPERATURE,
            timeoutMs: DEEPSEEK_TIMEOUT_MS,
          });
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
        p_temperature_score: currentTemperature ?? request.temperatureScore,
        p_familiarity_score: currentFamiliarity,
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
    if (beginnerMode && currentTemperature !== null) {
      try {
        temperature = await judgeLearningState({
          deps,
          apiKey,
          supabase,
          userId: user.id,
          sessionId: request.sessionId,
          currentTemperature,
          currentFamiliarity: currentFamiliarity ?? 0,
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
      body.hintUsedCount = ledger.hintCount ?? 0;
    }
    return jsonResponse(body);
  };
}
