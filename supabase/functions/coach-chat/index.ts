import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import {
  callClaudeAPI,
  CoachChatQuotaExceededError,
  runCoachChat,
} from "./generation.ts";
import { logError, logInfo, logWarn, summarizeUser } from "./logger.ts";
import { validateRequest } from "./validate.ts";
import {
  applyResetsIfNeeded,
  buildQuotaExceededPayload,
  checkQuota,
  isPlainObject,
  normalizeTier,
  parseRevenueCatSubscriber,
  resolveLimits,
  type SubscriptionRow,
  TEST_EMAILS,
  tierRank,
} from "../_shared/quota.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const REVENUECAT_IOS_API_KEY = Deno.env.get("REVENUECAT_IOS_API_KEY");

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
async function selfHealSubscription(
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
  sub: SubscriptionRow,
  dailyReset: boolean,
  monthlyReset: boolean,
): Promise<void> {
  const update: Record<string, unknown> = {};
  if (dailyReset) {
    update.daily_messages_used = 0;
    update.daily_reset_at = sub.daily_reset_at;
  }
  if (monthlyReset) {
    update.monthly_messages_used = 0;
    update.monthly_reset_at = sub.monthly_reset_at;
  }
  if (Object.keys(update).length === 0) return;
  const { error } = await supabase.from("subscriptions").update(update).eq(
    "user_id",
    userId,
  );
  if (error) {
    logWarn("subscription_reset_persist_failed", {
      user: summarizeUser(userId),
      dailyReset,
      monthlyReset,
      error: error.message,
    });
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
    return jsonResponse({ status: "ok", function: "coach-chat" });
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

  let sub = await fetchSubscription(supabase, user.id);
  if (!sub) sub = await selfHealSubscription(supabase, user.id);
  if (!sub) return jsonResponse({ error: "No subscription found" }, 403);

  const resetResult = applyResetsIfNeeded(sub, new Date());
  sub = resetResult.sub;
  if (resetResult.dailyReset || resetResult.monthlyReset) {
    await persistResets(
      supabase,
      user.id,
      sub,
      resetResult.dailyReset,
      resetResult.monthlyReset,
    );
  }

  const accountIsTest = TEST_EMAILS.includes(user.email || "");
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

  const apiKey = Deno.env.get("CLAUDE_API_KEY");
  if (!apiKey) {
    logError("coach_chat_config_missing", { user: summarizeUser(user.id) });
    return jsonResponse({ error: "config_missing" }, 500);
  }

  const tier = normalizeTier(sub.tier);
  const result = await runCoachChat(
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
          await persistResets(
            supabase,
            userId,
            latestSub,
            latestReset.dailyReset,
            latestReset.monthlyReset,
          );
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

        const { error } = await supabase.rpc("increment_usage", {
          p_user_id: userId,
          p_messages: COST_PER_GENERATION,
        });
        if (error) {
          logWarn("coach_chat_deduct_db_error", {
            user: summarizeUser(userId),
            error: error.message,
          });
          throw new Error("credit_deduct_failed");
        }
      },
      logger: { info: logInfo, warn: logWarn },
    },
  );
  return jsonResponse(result.body, result.status);
}

if (import.meta.main) {
  serve(handleRequest);
}
