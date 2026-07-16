// VibeSync AI keyboard quick reply.
// Independent from analyze-chat: clipboard text only, no OCR or conversation history.
// JWT verified. Cost = 1 shared credit, deducted only after a valid reply exists.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
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
import {
  callClaudeAPI,
  KeyboardReplyQuotaExceededError,
  runKeyboardReply,
} from "./generation.ts";
import { validateRequest } from "./validate.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const REVENUECAT_IOS_API_KEY = Deno.env.get("REVENUECAT_IOS_API_KEY");
const COST = 1;
const MAX_BODY_BYTES = 32 * 1024;
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

// deno-lint-ignore no-explicit-any
async function fetchSubscription(client: any, userId: string) {
  const { data, error } = await client.from("subscriptions")
    .select(SUBSCRIPTION_COLUMNS).eq("user_id", userId).maybeSingle();
  if (error) console.warn("keyboard_reply_subscription_lookup_failed");
  return data as SubscriptionRow | null;
}

// deno-lint-ignore no-explicit-any
async function selfHealSubscription(client: any, userId: string) {
  const now = new Date().toISOString();
  const { data, error } = await client.from("subscriptions").insert({
    user_id: userId,
    tier: "free",
    monthly_messages_used: 0,
    daily_messages_used: 0,
    daily_reset_at: now,
    monthly_reset_at: now,
    started_at: now,
  }).select(SUBSCRIPTION_COLUMNS).single();
  if (!error) return data as SubscriptionRow;
  if (error.code === "23505") return await fetchSubscription(client, userId);
  console.error("keyboard_reply_subscription_self_heal_failed");
  return null;
}

// deno-lint-ignore no-explicit-any
async function persistResets(
  client: any,
  userId: string,
  reset: ResetResult,
) {
  const updateWithCas = async (
    values: Record<string, unknown>,
    column: "daily_reset_at" | "monthly_reset_at",
    previous: string | null,
  ) => {
    let query = client.from("subscriptions").update(values).eq(
      "user_id",
      userId,
    );
    query = previous == null
      ? query.is(column, null)
      : query.eq(column, previous);
    const { error } = await query;
    if (error) console.warn("keyboard_reply_reset_persist_failed");
  };
  if (reset.dailyReset) {
    await updateWithCas(
      { daily_messages_used: 0, daily_reset_at: reset.sub.daily_reset_at },
      "daily_reset_at",
      reset.previousDailyResetAt,
    );
  }
  if (reset.monthlyReset) {
    await updateWithCas(
      {
        monthly_messages_used: 0,
        monthly_reset_at: reset.sub.monthly_reset_at,
      },
      "monthly_reset_at",
      reset.previousMonthlyResetAt,
    );
  }
}

// Paid users must not be treated as Free merely because the RevenueCat webhook
// is delayed. This mirrors the established coach-follow-up upgrade-only heal.
// deno-lint-ignore no-explicit-any
async function maybeRefreshTier(
  client: any,
  userId: string,
  sub: SubscriptionRow,
) {
  if (!REVENUECAT_IOS_API_KEY) return null;
  const previousTier = normalizeTier(sub.tier);
  if (previousTier === "essential") return null;
  try {
    const response = await fetch(
      `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(userId)}`,
      {
        headers: {
          Authorization: `Bearer ${REVENUECAT_IOS_API_KEY}`,
          "Content-Type": "application/json",
        },
      },
    );
    if (!response.ok) return null;
    const payload = await response.json().catch(() => null);
    if (!isPlainObject(payload) || !isPlainObject(payload.subscriber)) {
      return null;
    }
    const parsed = parseRevenueCatSubscriber(payload.subscriber);
    if (!parsed || tierRank(parsed.tier) <= tierRank(previousTier)) return null;
    const update: Record<string, unknown> = {
      tier: parsed.tier,
      status: "active",
    };
    if (parsed.expiresAt) update.expires_at = parsed.expiresAt;
    const { data } = await client.from("subscriptions").update(update)
      .eq("user_id", userId).select(SUBSCRIPTION_COLUMNS).maybeSingle();
    return (data ?? { ...sub, tier: parsed.tier }) as SubscriptionRow;
  } catch {
    console.warn("keyboard_reply_revenuecat_refresh_failed");
    return null;
  }
}

export async function handleRequest(request: Request): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method === "GET") {
    return jsonResponse({ status: "ok", function: "keyboard-reply" });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const authHeader = request.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }
  const contentLength = Number(request.headers.get("content-length"));
  if (Number.isFinite(contentLength) && contentLength > MAX_BODY_BYTES) {
    return jsonResponse({ error: "request_body_too_large" }, 413);
  }

  const client = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
    auth: { persistSession: false },
  });
  const { data: { user }, error: authError } = await client.auth.getUser(
    authHeader.slice(7),
  );
  if (authError || !user) return jsonResponse({ error: "unauthorized" }, 401);

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "invalid_request_body" }, 400);
  }
  let payload;
  try {
    payload = validateRequest(body);
  } catch (error) {
    return jsonResponse({
      error: error instanceof Error ? error.message : "invalid_request_body",
    }, 400);
  }

  let sub = await fetchSubscription(client, user.id);
  if (!sub) sub = await selfHealSubscription(client, user.id);
  if (!sub) return jsonResponse({ error: "subscription_unavailable" }, 503);

  const reset = applyResetsIfNeeded(sub, new Date());
  sub = reset.sub;
  if (reset.dailyReset || reset.monthlyReset) {
    await persistResets(client, user.id, reset);
  }
  let limits = resolveLimits(sub.tier);
  const accountIsTest = TEST_EMAILS.includes(user.email ?? "");
  let gate = checkQuota({
    sub,
    cost: COST,
    isTestAccount: accountIsTest,
    monthlyLimit: limits.monthly,
    dailyLimit: limits.daily,
  });
  if (!gate.ok) {
    const refreshed = await maybeRefreshTier(client, user.id, sub);
    if (refreshed) {
      sub = refreshed;
      limits = resolveLimits(sub.tier);
      gate = checkQuota({
        sub,
        cost: COST,
        isTestAccount: accountIsTest,
        monthlyLimit: limits.monthly,
        dailyLimit: limits.daily,
      });
    }
  }
  if (!gate.ok) {
    return jsonResponse(
      buildQuotaExceededPayload({
        sub,
        cost: COST,
        reason: gate.reason,
        monthlyLimit: limits.monthly,
        dailyLimit: limits.daily,
      }),
      429,
    );
  }

  const rate = await enforceModelRateLimit({
    supabase: client,
    userId: user.id,
    scope: "keyboard_reply",
    isTestAccount: accountIsTest,
  });
  if (rate.kind === "limited") return jsonResponse(rate.payload, 429);
  if (rate.kind === "failOpen") {
    console.error("keyboard_reply_model_rate_limit_check_failed");
  }

  const apiKey = Deno.env.get("CLAUDE_API_KEY");
  if (!apiKey) return jsonResponse({ error: "config_missing" }, 500);

  const result = await runKeyboardReply(
    {
      ...payload,
      userId: user.id,
      apiKey,
      accountIsTest,
    },
    {
      callClaude: callClaudeAPI,
      deductCredit: async (userId) => {
        let latest = await fetchSubscription(client, userId);
        if (!latest) throw new Error("subscription_unavailable");
        const latestReset = applyResetsIfNeeded(latest, new Date());
        latest = latestReset.sub;
        if (latestReset.dailyReset || latestReset.monthlyReset) {
          await persistResets(client, userId, latestReset);
        }
        let latestLimits = resolveLimits(latest.tier);
        let latestGate = checkQuota({
          sub: latest,
          cost: COST,
          isTestAccount: accountIsTest,
          monthlyLimit: latestLimits.monthly,
          dailyLimit: latestLimits.daily,
        });
        if (!latestGate.ok) {
          const refreshed = await maybeRefreshTier(client, userId, latest);
          if (refreshed) {
            latest = refreshed;
            latestLimits = resolveLimits(latest.tier);
            latestGate = checkQuota({
              sub: latest,
              cost: COST,
              isTestAccount: accountIsTest,
              monthlyLimit: latestLimits.monthly,
              dailyLimit: latestLimits.daily,
            });
          }
        }
        if (!latestGate.ok) {
          throw new KeyboardReplyQuotaExceededError(
            latestGate.reason,
            latestGate.used,
            latestGate.limit,
          );
        }
        const { error } = await client.rpc("increment_usage", {
          p_user_id: userId,
          p_messages: COST,
          p_monthly_limit: latestLimits.monthly,
          p_daily_limit: latestLimits.daily,
        });
        if (!error) return;
        const reason = classifyQuotaRpcError(error.message);
        if (reason) {
          const monthly = reason === "monthly_limit_exceeded";
          throw new KeyboardReplyQuotaExceededError(
            reason,
            monthly ? latest.monthly_messages_used : latest.daily_messages_used,
            monthly ? latestLimits.monthly : latestLimits.daily,
          );
        }
        throw new Error("credit_deduct_failed");
      },
    },
  );
  if (result.status === 200) {
    console.info(JSON.stringify({
      event: "keyboard_reply_succeeded",
      style: payload.style,
      tier: normalizeTier(sub.tier),
      costDeducted: accountIsTest ? 0 : 1,
    }));
  }
  return jsonResponse(result.body, result.status);
}

if (import.meta.main) serve(handleRequest);
