// supabase/functions/coach-follow-up/index.ts
//
// Spec 5 Coach Follow-up v1 — independent Edge function (sibling to analyze-chat).
// MUST NOT import from supabase/functions/analyze-chat/** (OCR baseline isolation).
// JWT-verified deploy (no --no-verify-jwt). Cost = 1 credit, deducted only on success.
//
// T6: auth + quota gate. Pure quota machinery lives in quota.ts (see quota_test.ts
// for the full edge-case matrix per Codex P1 #3). Real Supabase + RC HTTP are wired
// here so the pure helpers stay trivially testable.
//
// Generation path (prompt + Claude call + truncate + assertCardSafe + deduct +
// persist + JSON response) lands in T7. Until then, requests that pass the gate
// hit a 501 not_implemented sentinel.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { logError, logInfo, logWarn, summarizeUser } from "./logger.ts";
import { validateRequest } from "./validate.ts";
import { callClaudeAPI, runCoachFollowUp } from "./generation.ts";
import {
  applyResetsIfNeeded,
  checkQuota,
  isPlainObject,
  normalizeTier,
  parseRevenueCatSubscriber,
  resolveLimits,
  type SubscriptionRow,
  TEST_EMAILS,
  tierRank,
} from "./quota.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const REVENUECAT_IOS_API_KEY = Deno.env.get("REVENUECAT_IOS_API_KEY");

const COST_PER_GENERATION = 1;
const MAX_REQUEST_BODY_BYTES = 32 * 1024; // 32 KB — coach-follow-up has no images, tiny payload

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// CORS headers — mirrors analyze-chat:3256-3260. Browsers issue preflight
// OPTIONS for cross-origin POSTs from web/iOS, so every response (preflight,
// auth-fail, body-error, quota, success) MUST carry these.
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

const SUBSCRIPTION_COLUMNS =
  "tier, monthly_messages_used, daily_messages_used, daily_reset_at, monthly_reset_at";

// ---------------------------------------------------------------------------
// Supabase wrappers (DB-touching; not unit-tested — verified by T10 curl smoke)
// ---------------------------------------------------------------------------

// deno-lint-ignore no-explicit-any
async function fetchSubscription(supabase: any, userId: string): Promise<SubscriptionRow | null> {
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
async function selfHealSubscription(supabase: any, userId: string): Promise<SubscriptionRow | null> {
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
  } else {
    if (dailyReset) logInfo("daily_quota_reset", { user: summarizeUser(userId) });
    if (monthlyReset) logInfo("monthly_quota_reset", { user: summarizeUser(userId) });
  }
}

/**
 * Attempts to refresh the user's tier from RevenueCat when they hit a cap.
 * Returns the refreshed sub on successful upgrade, null otherwise.
 */
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
    if (!res.ok) {
      logWarn("subscription_revenuecat_refresh_failed", {
        user: summarizeUser(userId),
        reason,
        previousTier,
        status: res.status,
      });
      return null;
    }
    const payload = await res.json().catch(() => null);
    if (!isPlainObject(payload) || !isPlainObject(payload.subscriber)) {
      logWarn("subscription_revenuecat_refresh_invalid_payload", {
        user: summarizeUser(userId),
        reason,
        previousTier,
      });
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

    logInfo("subscription_revenuecat_refresh_applied", {
      user: summarizeUser(userId),
      reason,
      previousTier,
      refreshedTier: parsed.tier,
      persisted: !error,
    });
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

// ---------------------------------------------------------------------------
// Request handler
// ---------------------------------------------------------------------------

export async function handleRequest(req: Request): Promise<Response> {
  // CORS preflight — must return CORS headers without auth (browser fires this
  // before any cross-origin POST from web/iOS clients).
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method === "GET") {
    return jsonResponse({ status: "ok", function: "coach-follow-up" });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  // ── Auth ──
  const authHeader = req.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }
  const token = authHeader.slice(7);

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
    auth: { persistSession: false },
  });

  const { data: { user }, error: userError } = await supabase.auth.getUser(token);
  if (userError || !user) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  // ── Body size guard + JSON parse ──
  const contentLengthHeader = req.headers.get("content-length");
  const contentLength = contentLengthHeader ? Number(contentLengthHeader) : NaN;
  if (Number.isFinite(contentLength) && contentLength > MAX_REQUEST_BODY_BYTES) {
    return jsonResponse({ error: "Request body too large" }, 413);
  }

  let rawBody: unknown;
  try {
    rawBody = await req.json();
  } catch (e) {
    logWarn("request_body_parse_failed", {
      user: summarizeUser(user.id),
      error: getErrorMessage(e),
    });
    return jsonResponse({ error: "invalid_request_body" }, 400);
  }

  // ── Schema validation (rejects images for v1) ──
  let payload;
  try {
    payload = validateRequest(rawBody);
  } catch (e) {
    return jsonResponse({ error: getErrorMessage(e) }, 400);
  }

  // ── Subscription self-heal ──
  let sub = await fetchSubscription(supabase, user.id);
  if (!sub) {
    sub = await selfHealSubscription(supabase, user.id);
  }
  if (!sub) {
    return jsonResponse({ error: "No subscription found" }, 403);
  }

  // ── Daily / monthly resets ──
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

  // ── Tier resolution + cap check ──
  const accountIsTest = TEST_EMAILS.includes(user.email || "");
  let limits = resolveLimits(sub.tier);

  let gate = checkQuota({
    sub,
    cost: COST_PER_GENERATION,
    isTestAccount: accountIsTest,
    monthlyLimit: limits.monthly,
    dailyLimit: limits.daily,
  });

  if (!gate.ok) {
    // Try RevenueCat refresh once before 429ing — covers the "user upgraded
    // but webhook hasn't landed" case (Codex P1 #3 RC refresh path).
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
        cost: COST_PER_GENERATION,
        isTestAccount: accountIsTest,
        monthlyLimit: limits.monthly,
        dailyLimit: limits.daily,
      });
    }
  }

  if (!gate.ok) {
    logWarn("coach_follow_up_quota_exceeded", {
      user: summarizeUser(user.id),
      tier: normalizeTier(sub.tier),
      reason: gate.reason,
      used: gate.used,
      limit: gate.limit,
    });
    return jsonResponse(
      {
        error: gate.reason === "monthly_limit_exceeded"
          ? "Monthly limit exceeded"
          : "Daily limit exceeded",
        quotaNeeded: COST_PER_GENERATION,
        used: gate.used,
        limit: gate.limit,
      },
      429,
    );
  }

  // ── T7: generate via Claude, validate + safety check, deduct on success. ──
  const apiKey = Deno.env.get("CLAUDE_API_KEY");
  if (!apiKey) {
    logError("coach_follow_up_config_missing", { user: summarizeUser(user.id) });
    return jsonResponse({ error: "config_missing" }, 500);
  }

  const tier = normalizeTier(sub.tier);
  const subAtCall = sub;
  const result = await runCoachFollowUp(
    {
      userId: user.id,
      phase: payload.phase,
      answers: payload.answers,
      partnerHint: payload.partnerHint,
      tier,
      accountIsTest,
      apiKey,
    },
    {
      callClaude: callClaudeAPI,
      deductCredit: async ({ userId }) => {
        // Codex P1: Supabase update on {error} doesn't throw — must surface
        // explicitly or generation.ts will treat it as success and the user
        // gets a free card. Internal Supabase error message stays here in a
        // warn log; only the stable bucket name "credit_deduct_failed"
        // propagates upward to telemetry / response.
        const { error } = await supabase
          .from("subscriptions")
          .update({
            monthly_messages_used: (subAtCall.monthly_messages_used || 0) + 1,
            daily_messages_used: (subAtCall.daily_messages_used || 0) + 1,
          })
          .eq("user_id", userId);
        if (error) {
          logWarn("coach_follow_up_deduct_db_error", {
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

serve(handleRequest);
