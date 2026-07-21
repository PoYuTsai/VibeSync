import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import {
  callClaudeAPI,
  type CoachChatProgressUpdate,
  CoachChatQuotaExceededError,
  runCoachChat,
} from "./generation.ts";
import { logError, logInfo, logWarn, summarizeUser } from "./logger.ts";
import {
  coachProgressStreamResponse,
  wantsCoachProgressStream,
} from "./progress_stream.ts";
import {
  COACH_CONTRACT_VERSION,
  isStrongCoachReplayHmacKey,
  normalizeCoachRequestId,
} from "./billing.ts";
import { validateRequest } from "./validate.ts";
import {
  applyResetsIfNeeded,
  buildQuotaExceededPayload,
  checkQuota,
  classifyQuotaRpcError,
  isPlainObject,
  normalizeTier,
  parseRevenueCatSubscriber,
  type ResetResult,
  resolveLimits,
  type SubscriptionRow,
  TEST_EMAILS,
  tierRank,
} from "../_shared/quota.ts";
import { enforceModelRateLimit } from "../_shared/model_rate_limit.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const REVENUECAT_IOS_API_KEY = Deno.env.get("REVENUECAT_IOS_API_KEY");
const COACH_REPLAY_HMAC_KEY = Deno.env.get("COACH_REPLAY_HMAC_KEY") ?? "";

const COST_PER_GENERATION = 1;
const PREFLIGHT_QUOTA_COST = COST_PER_GENERATION;
const MAX_REQUEST_BODY_BYTES = 48 * 1024;
const SUBSCRIPTION_COLUMNS =
  "tier, monthly_messages_used, daily_messages_used, daily_reset_at, monthly_reset_at";

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

function getErrorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (typeof error === "string") return error;
  try {
    return JSON.stringify(error);
  } catch {
    return "unknown_error";
  }
}

// deno-lint-ignore no-explicit-any
async function fetchSubscription(
  supabase: any,
  userId: string,
): Promise<SubscriptionRow | null> {
  const { data, error } = await supabase
    .from("subscriptions")
    .select(SUBSCRIPTION_COLUMNS)
    .eq("user_id", userId)
    .maybeSingle();
  if (error) {
    logWarn("subscription_lookup_failed", {
      user: summarizeUser(userId),
      error: error.message,
    });
  }
  return data ?? null;
}

// deno-lint-ignore no-explicit-any
export async function selfHealSubscription(
  supabase: any,
  userId: string,
): Promise<SubscriptionRow | null> {
  const nowIso = new Date().toISOString();
  const { data, error } = await supabase
    .from("subscriptions")
    .insert({
      user_id: userId,
      tier: "free",
      monthly_messages_used: 0,
      daily_messages_used: 0,
      daily_reset_at: nowIso,
      monthly_reset_at: nowIso,
      started_at: nowIso,
    })
    .select(SUBSCRIPTION_COLUMNS)
    .single();
  if (error) {
    // 首次使用併發：另一請求已先插入同 user 的列（unique violation 23505）。
    // 回讀既有列，否則上游會把 null 映射成 403 鎖住新用戶。
    if (error.code === "23505") {
      const existing = await fetchSubscription(supabase, userId);
      if (existing) {
        logInfo("subscription_self_heal_raced", {
          user: summarizeUser(userId),
        });
        return existing;
      }
    }
    logError("subscription_self_heal_failed", {
      user: summarizeUser(userId),
      error: error.message,
    });
    return null;
  }
  logInfo("subscription_self_healed", { user: summarizeUser(userId) });
  return data;
}

async function persistResets(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userId: string,
  reset: ResetResult,
): Promise<void> {
  // Batch C#4：CAS 條件化——WHERE reset_at = 舊值（null 用 IS NULL），daily/
  // monthly 分開兩句。只有第一個跨窗口的請求能歸零；後到者 CAS 匹配 0 rows
  // ＝別人已 reset，放棄覆寫，才不會抹掉並發請求剛扣的額度。
  const casReset = async (
    update: Record<string, unknown>,
    column: "daily_reset_at" | "monthly_reset_at",
    previous: string | null,
    which: "daily" | "monthly",
  ) => {
    let query = supabase.from("subscriptions").update(update).eq(
      "user_id",
      userId,
    );
    query = previous === null
      ? query.is(column, null)
      : query.eq(column, previous);
    const { error } = await query;
    if (error) {
      logWarn("subscription_reset_persist_failed", {
        user: summarizeUser(userId),
        reset: which,
        error: error.message,
      });
    }
  };
  if (reset.dailyReset) {
    await casReset(
      { daily_messages_used: 0, daily_reset_at: reset.sub.daily_reset_at },
      "daily_reset_at",
      reset.previousDailyResetAt,
      "daily",
    );
  }
  if (reset.monthlyReset) {
    await casReset(
      {
        monthly_messages_used: 0,
        monthly_reset_at: reset.sub.monthly_reset_at,
      },
      "monthly_reset_at",
      reset.previousMonthlyResetAt,
      "monthly",
    );
  }
}

async function maybeRefreshTierFromRevenueCat(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userId: string,
  sub: SubscriptionRow,
  reason: string,
): Promise<SubscriptionRow | null> {
  if (!REVENUECAT_IOS_API_KEY) return null;
  const previousTier = normalizeTier(sub.tier);
  if (previousTier === "essential") return null;

  try {
    const res = await fetch(
      `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(userId)}`,
      {
        headers: {
          Authorization: `Bearer ${REVENUECAT_IOS_API_KEY}`,
          "Content-Type": "application/json",
        },
      },
    );
    if (!res.ok) return null;
    const payload = await res.json().catch(() => null);
    if (!isPlainObject(payload) || !isPlainObject(payload.subscriber)) {
      return null;
    }
    const parsed = parseRevenueCatSubscriber(payload.subscriber);
    if (!parsed || tierRank(parsed.tier) <= tierRank(previousTier)) {
      return null;
    }

    const update: Record<string, unknown> = {
      tier: parsed.tier,
      status: "active",
    };
    if (parsed.expiresAt) update.expires_at = parsed.expiresAt;

    const { data: refreshed, error } = await supabase
      .from("subscriptions")
      .update(update)
      .eq("user_id", userId)
      .select(SUBSCRIPTION_COLUMNS)
      .maybeSingle();
    if (error) {
      logError("subscription_revenuecat_refresh_persist_failed", {
        user: summarizeUser(userId),
        reason,
        previousTier,
        refreshedTier: parsed.tier,
        error: error.message,
      });
    }
    return refreshed ?? { ...sub, tier: parsed.tier };
  } catch (e) {
    logWarn("subscription_revenuecat_refresh_exception", {
      user: summarizeUser(userId),
      reason,
      previousTier,
      error: getErrorMessage(e),
    });
    return null;
  }
}

export async function handleRequest(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method === "GET") {
    // F9 fail-closed：帳本 migration 或金鑰不齊時不得自稱 ok——
    // health 由 DB-owned contract version 背書（同 keyboard 範本）。
    if (
      !SUPABASE_URL || !SUPABASE_SERVICE_KEY ||
      !isStrongCoachReplayHmacKey(COACH_REPLAY_HMAC_KEY)
    ) {
      return jsonResponse({ status: "unavailable" }, 503);
    }
    const healthClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
      auth: { persistSession: false },
    });
    const { data: databaseContractVersion, error } = await healthClient.rpc(
      "coach_contract_version",
    );
    if (error || databaseContractVersion !== COACH_CONTRACT_VERSION) {
      return jsonResponse({ status: "unavailable" }, 503);
    }
    return jsonResponse({
      status: "ok",
      function: "coach-chat",
      contractVersion: COACH_CONTRACT_VERSION,
    });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }
  const token = authHeader.slice(7);

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
    auth: { persistSession: false },
  });
  const { data: { user }, error: userError } = await supabase.auth.getUser(
    token,
  );
  if (userError || !user) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  const contentLengthHeader = req.headers.get("content-length");
  const contentLength = contentLengthHeader ? Number(contentLengthHeader) : NaN;
  if (
    Number.isFinite(contentLength) && contentLength > MAX_REQUEST_BODY_BYTES
  ) {
    return jsonResponse({ error: "Request body too large" }, 413);
  }

  let rawBody: unknown;
  try {
    rawBody = await req.json();
  } catch (e) {
    logWarn("coach_chat_body_parse_failed", {
      user: summarizeUser(user.id),
      error: getErrorMessage(e),
    });
    return jsonResponse({ error: "invalid_request_body" }, 400);
  }

  let payload;
  try {
    payload = validateRequest(rawBody);
  } catch (e) {
    return jsonResponse({ error: getErrorMessage(e) }, 400);
  }

  // Phase C：requestId 缺席（null/undefined）＝完全不觸帳本、走今日路徑。
  const requestId = normalizeCoachRequestId(payload.requestId ?? null);
  if (
    requestId !== null && !isStrongCoachReplayHmacKey(COACH_REPLAY_HMAC_KEY)
  ) {
    // 金鑰缺/弱時 fail-closed：不打模型不扣費（客戶端可去掉 requestId 重試）。
    logError("coach_chat_config_missing", {
      user: summarizeUser(user.id),
      missing: "COACH_REPLAY_HMAC_KEY",
    });
    return jsonResponse({ error: "config_missing" }, 500);
  }

  let sub = await fetchSubscription(supabase, user.id);
  if (!sub) sub = await selfHealSubscription(supabase, user.id);
  if (!sub) return jsonResponse({ error: "No subscription found" }, 403);

  const resetResult = applyResetsIfNeeded(sub, new Date());
  sub = resetResult.sub;
  if (resetResult.dailyReset || resetResult.monthlyReset) {
    await persistResets(supabase, user.id, resetResult);
  }

  const accountIsTest = TEST_EMAILS.includes(user.email || "");
  // D1 拍板：checkQuota preflight 恆跑。釐清仍不扣費，但額度歸零者直接 429。
  // 已知取捨：有額度者偽造 turns 可多蹭免費釐清（不做 server ledger）。
  let limits = resolveLimits(sub.tier);
  let gate = checkQuota({
    sub,
    cost: PREFLIGHT_QUOTA_COST,
    isTestAccount: accountIsTest,
    monthlyLimit: limits.monthly,
    dailyLimit: limits.daily,
  });

  if (!gate.ok) {
    const refreshed = await maybeRefreshTierFromRevenueCat(
      supabase,
      user.id,
      sub,
      gate.reason,
    );
    if (refreshed) {
      sub = refreshed;
      limits = resolveLimits(sub.tier);
      gate = checkQuota({
        sub,
        cost: PREFLIGHT_QUOTA_COST,
        isTestAccount: accountIsTest,
        monthlyLimit: limits.monthly,
        dailyLimit: limits.daily,
      });
    }
  }

  if (!gate.ok) {
    logWarn("coach_chat_quota_exceeded", {
      user: summarizeUser(user.id),
      tier: normalizeTier(sub.tier),
      reason: gate.reason,
      used: gate.used,
      limit: gate.limit,
    });
    return jsonResponse(
      buildQuotaExceededPayload({
        sub,
        cost: COST_PER_GENERATION,
        reason: gate.reason,
        monthlyLimit: limits.monthly,
        dailyLimit: limits.daily,
      }),
      429,
    );
  }

  // 模型呼叫限流（docs/plans/2026-07-03-model-rate-limit-design.md）：
  // coach_chat 10/分、300/日。放在 quota gate 後（額度 429 語義優先）、
  // runCoachChat 模型呼叫前。與訂閱額度零交集。
  const rateVerdict = await enforceModelRateLimit({
    supabase,
    userId: user.id,
    scope: "coach_chat",
    isTestAccount: accountIsTest,
  });
  if (rateVerdict.kind === "limited") {
    logWarn("model_rate_limited", {
      user: summarizeUser(user.id),
      scope: "coach_chat",
      reason: rateVerdict.reason,
    });
    return jsonResponse(rateVerdict.payload, 429);
  }
  if (rateVerdict.kind === "failOpen") {
    // fail-open：infra 錯誤（非超限 RAISE）不擋核心流程，必留 telemetry。
    logError("model_rate_limit_check_failed", {
      user: summarizeUser(user.id),
      scope: "coach_chat",
      error: rateVerdict.errorMessage,
    });
  }

  const apiKey = Deno.env.get("CLAUDE_API_KEY");
  if (!apiKey) {
    logError("coach_chat_config_missing", { user: summarizeUser(user.id) });
    return jsonResponse({ error: "config_missing" }, 500);
  }

  const tier = normalizeTier(sub.tier);
  const runGeneration = (
    onProgress?: (update: CoachChatProgressUpdate) => void,
  ) =>
    runCoachChat(
      {
        userId: user.id,
        request: payload,
        tier,
        accountIsTest,
        apiKey,
      },
      {
        callClaude: callClaudeAPI,
        deductCredit: async ({ userId }) => {
          let latestSub = await fetchSubscription(supabase, userId);
          if (!latestSub) throw new Error("No subscription found");

          const latestReset = applyResetsIfNeeded(latestSub, new Date());
          latestSub = latestReset.sub;
          if (latestReset.dailyReset || latestReset.monthlyReset) {
            await persistResets(supabase, userId, latestReset);
          }

          let latestLimits = resolveLimits(latestSub.tier);
          let deductGate = checkQuota({
            sub: latestSub,
            cost: COST_PER_GENERATION,
            isTestAccount: accountIsTest,
            monthlyLimit: latestLimits.monthly,
            dailyLimit: latestLimits.daily,
          });
          if (!deductGate.ok) {
            const refreshed = await maybeRefreshTierFromRevenueCat(
              supabase,
              userId,
              latestSub,
              deductGate.reason,
            );
            if (refreshed) {
              latestSub = refreshed;
              latestLimits = resolveLimits(latestSub.tier);
              deductGate = checkQuota({
                sub: latestSub,
                cost: COST_PER_GENERATION,
                isTestAccount: accountIsTest,
                monthlyLimit: latestLimits.monthly,
                dailyLimit: latestLimits.daily,
              });
            }
          }
          if (!deductGate.ok) {
            throw new CoachChatQuotaExceededError(
              deductGate.reason,
              deductGate.used,
              deductGate.limit,
            );
          }

          // Batch C#2：帶 tier 上限讓 increment_usage 鎖內複檢，兜住上面
          // checkQuota 與真正扣費之間的並發競態；RAISE 映射回 429 語義。
          const { error } = await supabase.rpc("increment_usage", {
            p_user_id: userId,
            p_messages: COST_PER_GENERATION,
            p_monthly_limit: latestLimits.monthly,
            p_daily_limit: latestLimits.daily,
          });
          if (error) {
            const quotaReason = classifyQuotaRpcError(error.message);
            if (quotaReason) {
              const isMonthly = quotaReason === "monthly_limit_exceeded";
              throw new CoachChatQuotaExceededError(
                quotaReason,
                isMonthly
                  ? latestSub.monthly_messages_used
                  : latestSub.daily_messages_used,
                isMonthly ? latestLimits.monthly : latestLimits.daily,
              );
            }
            logWarn("coach_chat_deduct_db_error", {
              user: summarizeUser(userId),
              error: error.message,
            });
            throw new Error("credit_deduct_failed");
          }
        },
        logger: { info: logInfo, warn: logWarn },
        onProgress,
      },
    );
  if (wantsCoachProgressStream(req)) {
    return coachProgressStreamResponse(runGeneration, corsHeaders);
  }
  const result = await runGeneration();
  return jsonResponse(result.body, result.status);
}

if (import.meta.main) {
  serve(handleRequest);
}
