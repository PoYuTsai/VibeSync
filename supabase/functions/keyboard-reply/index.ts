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
  claimKeyboardReplyRequest,
  classifyKeyboardReplyReplayPreflight,
  computeKeyboardReplyInputHash,
  isStrongKeyboardReplayHmacKey,
  KEYBOARD_REPLY_COST,
  keyboardReplyReplayCutoffIso,
  releaseKeyboardReplyClaim,
  settleKeyboardReplyRequest,
} from "./billing.ts";
import {
  callClaudeAPI,
  KEYBOARD_REQUEST_BUDGET_MS,
  keyboardGenerationBudgetRemaining,
  KeyboardReplyFinalizeError,
  KeyboardReplyQuotaExceededError,
  runKeyboardReply,
} from "./generation.ts";
import { validateRequest } from "./validate.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const KEYBOARD_REPLAY_HMAC_KEY = Deno.env.get("KEYBOARD_REPLAY_HMAC_KEY") ?? "";
const REVENUECAT_IOS_API_KEY = Deno.env.get("REVENUECAT_IOS_API_KEY");
const COST = KEYBOARD_REPLY_COST;
const MAX_BODY_BYTES = 32 * 1024;
const SUBSCRIPTION_COLUMNS =
  "tier, monthly_messages_used, daily_messages_used, daily_reset_at, monthly_reset_at";
export const KEYBOARD_REPLY_CONTRACT_VERSION = "keyboard-reply-exactly-once-v1";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
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
        signal: AbortSignal.timeout(5000),
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

async function handleRequestWithinDeadline(
  request: Request,
  requestDeadlineAt: number,
): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method === "GET") {
    if (
      !SUPABASE_URL || !SUPABASE_SERVICE_KEY ||
      !isStrongKeyboardReplayHmacKey(KEYBOARD_REPLAY_HMAC_KEY)
    ) {
      return jsonResponse({ status: "unavailable" }, 503);
    }
    const healthClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
      auth: { persistSession: false },
    });
    const { data: databaseContractVersion, error } = await healthClient.rpc(
      "keyboard_reply_contract_version",
    );
    if (
      error || databaseContractVersion !== KEYBOARD_REPLY_CONTRACT_VERSION
    ) {
      return jsonResponse({ status: "unavailable" }, 503);
    }
    return jsonResponse({
      status: "ok",
      function: "keyboard-reply",
      contractVersion: KEYBOARD_REPLY_CONTRACT_VERSION,
    });
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

  let inputHash: string | null = null;
  if (payload.requestId !== null) {
    if (!isStrongKeyboardReplayHmacKey(KEYBOARD_REPLAY_HMAC_KEY)) {
      return jsonResponse({ error: "config_missing" }, 500);
    }
    inputHash = await computeKeyboardReplyInputHash({
      userId: user.id,
      message: payload.message,
      style: payload.style,
      secret: KEYBOARD_REPLAY_HMAC_KEY,
    });
    const { data: replayRow, error: replayReadError } = await client
      .from("keyboard_reply_requests")
      .select("input_hash, state, lease_expires_at, result_json, created_at")
      .eq("user_id", user.id)
      .eq("request_id", payload.requestId)
      .gte("created_at", keyboardReplyReplayCutoffIso())
      .maybeSingle();
    if (replayReadError) {
      console.error("keyboard_reply_replay_preflight_read_failed");
      return jsonResponse({
        error: "KEYBOARD_REPLY_SETTLEMENT_RETRYABLE",
        code: "KEYBOARD_REPLY_SETTLEMENT_RETRYABLE",
        retryable: true,
      }, 503);
    }
    const replay = classifyKeyboardReplyReplayPreflight(
      replayRow,
      inputHash,
    );
    if (replay.kind === "mismatch") {
      return jsonResponse({
        error: "KEYBOARD_REPLY_REQUEST_REPLAY_MISMATCH",
        code: "KEYBOARD_REPLY_REQUEST_REPLAY_MISMATCH",
      }, 409);
    }
    if (replay.kind === "replay") {
      console.info(JSON.stringify({
        event: "keyboard_reply_replayed",
        style: replay.result.style,
        costDeducted: 0,
      }));
      return jsonResponse(replay.result);
    }
    if (replay.kind === "pending") {
      return jsonResponse({
        error: "KEYBOARD_REPLY_REQUEST_PENDING",
        code: "KEYBOARD_REPLY_REQUEST_PENDING",
        retryable: true,
        retryAfterMs: replay.retryAfterMs,
      }, 409);
    }
  }

  const apiKey = Deno.env.get("CLAUDE_API_KEY");
  if (!apiKey) return jsonResponse({ error: "config_missing" }, 500);
  const requestId = payload.requestId;
  const requestInputHash = inputHash;
  const requestOwnerToken = requestId === null ? null : crypto.randomUUID();

  const releaseCurrentClaim = async (): Promise<boolean> => {
    if (
      requestId === null || requestInputHash === null ||
      requestOwnerToken === null
    ) return true;
    return await releaseKeyboardReplyClaim({
      rpc: async (fn, params) => await client.rpc(fn, params),
      userId: user.id,
      requestId,
      inputHash: requestInputHash,
      ownerToken: requestOwnerToken,
    });
  };

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
  // Keep slow subscription/RevenueCat I/O outside the 45-second lease. Claim
  // only after entitlement refresh, but before any terminal gate response, so
  // one concurrent request cannot clear an identity another request owns.
  if (
    requestId !== null && requestInputHash !== null &&
    requestOwnerToken !== null
  ) {
    const claim = await claimKeyboardReplyRequest({
      rpc: async (fn, params) => await client.rpc(fn, params),
      userId: user.id,
      requestId,
      inputHash: requestInputHash,
      ownerToken: requestOwnerToken,
    });
    if (claim.kind === "replay") return jsonResponse(claim.result);
    if (claim.kind === "pending") {
      return jsonResponse({
        error: "KEYBOARD_REPLY_REQUEST_PENDING",
        code: "KEYBOARD_REPLY_REQUEST_PENDING",
        retryable: true,
        retryAfterMs: claim.retryAfterMs,
      }, 409);
    }
    if (claim.kind === "mismatch") {
      return jsonResponse({
        error: "KEYBOARD_REPLY_REQUEST_REPLAY_MISMATCH",
        code: "KEYBOARD_REPLY_REQUEST_REPLAY_MISMATCH",
      }, 409);
    }
    if (claim.kind === "retryable") {
      return jsonResponse({
        error: "KEYBOARD_REPLY_CLAIM_RETRYABLE",
        code: "KEYBOARD_REPLY_CLAIM_RETRYABLE",
        retryable: true,
      }, 503);
    }
    if (claim.kind === "failed") {
      console.error("keyboard_reply_claim_failed");
      return jsonResponse({ error: "KEYBOARD_REPLY_CLAIM_FAILED" }, 500);
    }
  }
  if (!gate.ok) {
    if (!await releaseCurrentClaim()) {
      return jsonResponse({
        error: "KEYBOARD_REPLY_CLAIM_RELEASE_RETRYABLE",
        code: "KEYBOARD_REPLY_CLAIM_RELEASE_RETRYABLE",
        retryable: true,
      }, 503);
    }
    return jsonResponse({
      ...buildQuotaExceededPayload({
        sub,
        cost: COST,
        reason: gate.reason,
        monthlyLimit: limits.monthly,
        dailyLimit: limits.daily,
      }),
      code: "QUOTA_EXCEEDED",
      safeToClear: true,
    }, 429);
  }

  const rate = await enforceModelRateLimit({
    supabase: client,
    userId: user.id,
    scope: "keyboard_reply",
    isTestAccount: accountIsTest,
  });
  if (rate.kind === "limited") {
    if (!await releaseCurrentClaim()) {
      return jsonResponse({
        error: "KEYBOARD_REPLY_CLAIM_RELEASE_RETRYABLE",
        code: "KEYBOARD_REPLY_CLAIM_RELEASE_RETRYABLE",
        retryable: true,
      }, 503);
    }
    return jsonResponse({ ...rate.payload, safeToClear: true }, 429);
  }
  if (rate.kind === "failOpen") {
    console.error("keyboard_reply_model_rate_limit_check_failed");
  }

  // Renew immediately before model dispatch. If the rate-limit RPC stalled
  // past the lease and another owner took over, this invocation must stop
  // before it can amplify provider cost.
  if (
    requestId !== null && requestInputHash !== null &&
    requestOwnerToken !== null
  ) {
    const renewal = await claimKeyboardReplyRequest({
      rpc: async (fn, params) => await client.rpc(fn, params),
      userId: user.id,
      requestId,
      inputHash: requestInputHash,
      ownerToken: requestOwnerToken,
    });
    if (renewal.kind === "replay") return jsonResponse(renewal.result);
    if (renewal.kind === "pending") {
      return jsonResponse({
        error: "KEYBOARD_REPLY_REQUEST_PENDING",
        code: "KEYBOARD_REPLY_REQUEST_PENDING",
        retryable: true,
        retryAfterMs: renewal.retryAfterMs,
      }, 409);
    }
    if (renewal.kind === "mismatch") {
      return jsonResponse({
        error: "KEYBOARD_REPLY_REQUEST_REPLAY_MISMATCH",
        code: "KEYBOARD_REPLY_REQUEST_REPLAY_MISMATCH",
      }, 409);
    }
    if (renewal.kind !== "claimed") {
      return jsonResponse({
        error: "KEYBOARD_REPLY_CLAIM_RENEW_RETRYABLE",
        code: "KEYBOARD_REPLY_CLAIM_RENEW_RETRYABLE",
        retryable: true,
      }, 503);
    }
  }

  const result = await runKeyboardReply(
    {
      ...payload,
      userId: user.id,
      apiKey,
      accountIsTest,
    },
    {
      generationBudgetMs: keyboardGenerationBudgetRemaining(
        requestDeadlineAt,
        performance.now(),
      ),
      callClaude: callClaudeAPI,
      finalizeReply: async (userId, generatedReply) => {
        if (requestId === null && accountIsTest) {
          return { reply: generatedReply, costDeducted: 0 as const };
        }
        if (performance.now() >= requestDeadlineAt) {
          throw new KeyboardReplyFinalizeError(
            503,
            "KEYBOARD_REPLY_PRESETTLEMENT_RETRYABLE",
            "request deadline reached before settlement",
          );
        }
        let latest = await fetchSubscription(client, userId);
        if (!latest) {
          throw new KeyboardReplyFinalizeError(
            503,
            "KEYBOARD_REPLY_PRESETTLEMENT_RETRYABLE",
            "subscription unavailable before settlement",
          );
        }
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

        if (
          requestId !== null && requestInputHash !== null &&
          requestOwnerToken !== null
        ) {
          if (performance.now() >= requestDeadlineAt) {
            throw new KeyboardReplyFinalizeError(
              503,
              "KEYBOARD_REPLY_PRESETTLEMENT_RETRYABLE",
              "request deadline reached before settlement",
            );
          }
          const settlement = await settleKeyboardReplyRequest({
            rpc: async (fn, params) => await client.rpc(fn, params),
            userId,
            requestId,
            inputHash: requestInputHash,
            ownerToken: requestOwnerToken,
            result: { reply: generatedReply, style: payload.style },
            monthlyLimit: latestLimits.monthly,
            dailyLimit: latestLimits.daily,
            chargeQuota: !accountIsTest,
          });
          if (settlement.kind === "settled") {
            return {
              reply: settlement.result.reply,
              costDeducted: settlement.charged ? 1 as const : 0 as const,
            };
          }
          if (settlement.kind === "quota_exceeded") {
            const monthly = settlement.reason === "monthly_limit_exceeded";
            throw new KeyboardReplyQuotaExceededError(
              settlement.reason,
              monthly
                ? latest.monthly_messages_used
                : latest.daily_messages_used,
              monthly ? latestLimits.monthly : latestLimits.daily,
            );
          }
          if (settlement.kind === "mismatch") {
            throw new KeyboardReplyFinalizeError(
              409,
              "KEYBOARD_REPLY_REQUEST_REPLAY_MISMATCH",
              "request identity reused for different input",
            );
          }
          if (settlement.kind === "retryable") {
            throw new KeyboardReplyFinalizeError(
              503,
              "KEYBOARD_REPLY_SETTLEMENT_RETRYABLE",
              settlement.message,
            );
          }
          throw new KeyboardReplyFinalizeError(
            500,
            "KEYBOARD_REPLY_SETTLEMENT_FAILED",
            settlement.message,
          );
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
        if (!error) {
          return { reply: generatedReply, costDeducted: 1 as const };
        }
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
  // These failures are known to precede settlement, so no reply or quota charge
  // can have committed. Release only this owner-bound claim, allowing an
  // immediate same-requestId retry. Settlement failures remain untouched
  // because their commit outcome may be ambiguous.
  const safeToReleaseAfterRun =
    result.status === 500 && result.body.error === "generation_failed" ||
    result.status === 503 &&
      result.body.code === "KEYBOARD_REPLY_PRESETTLEMENT_RETRYABLE";
  if (safeToReleaseAfterRun) {
    if (!await releaseCurrentClaim()) {
      return jsonResponse({
        error: "KEYBOARD_REPLY_CLAIM_RELEASE_RETRYABLE",
        code: "KEYBOARD_REPLY_CLAIM_RELEASE_RETRYABLE",
        retryable: true,
      }, 503);
    }
    result.body.retryable = true;
  }
  if (
    result.status === 429 && result.body.code === "QUOTA_EXCEEDED" &&
    result.body.safeToClear !== true
  ) {
    if (!await releaseCurrentClaim()) {
      return jsonResponse({
        error: "KEYBOARD_REPLY_CLAIM_RELEASE_RETRYABLE",
        code: "KEYBOARD_REPLY_CLAIM_RELEASE_RETRYABLE",
        retryable: true,
      }, 503);
    }
    result.body.safeToClear = true;
  }
  if (result.status === 200) {
    console.info(JSON.stringify({
      event: "keyboard_reply_succeeded",
      style: payload.style,
      tier: normalizeTier(sub.tier),
      costDeducted: result.costDeducted,
    }));
  }
  return jsonResponse(result.body, result.status);
}

export async function handleRequest(request: Request): Promise<Response> {
  const requestDeadlineAt = performance.now() + KEYBOARD_REQUEST_BUDGET_MS;
  let timeoutId: ReturnType<typeof setTimeout> | undefined;
  const deadlineResponse = new Promise<Response>((resolve) => {
    timeoutId = setTimeout(() => {
      resolve(jsonResponse({
        error: "KEYBOARD_REPLY_REQUEST_TIMEOUT",
        code: "KEYBOARD_REPLY_REQUEST_TIMEOUT",
        retryable: true,
      }, 503));
    }, Math.max(0, Math.ceil(requestDeadlineAt - performance.now())));
  });
  try {
    return await Promise.race([
      handleRequestWithinDeadline(request, requestDeadlineAt),
      deadlineResponse,
    ]);
  } finally {
    if (timeoutId !== undefined) clearTimeout(timeoutId);
  }
}

if (import.meta.main) serve(handleRequest);
