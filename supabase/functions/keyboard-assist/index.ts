// Single-screenshot Keyboard Assist.
// Additive and flag-off by default; independent from analyze-chat and the
// legacy clipboard keyboard-reply endpoint.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { withOperationalErrorMonitoring } from "../_shared/operational_error_monitor.ts";
import {
  applyResetsIfNeeded,
  checkQuota,
  isPlainObject,
  normalizeTier,
  parseRevenueCatSubscriber,
  quotaExceededMessage,
  resolveLimits,
  type SubscriptionRow,
  TEST_EMAILS,
  tierRank,
} from "../_shared/quota.ts";
import { enforceModelRateLimit } from "../_shared/model_rate_limit.ts";
import {
  buildRevenueCatStoreEvents,
  persistSubscriptionStoreState,
  resolveSourceAwareSubscriptionRow,
} from "../_shared/subscription_store_state.ts";
import {
  claimKeyboardAssistRequest,
  expireKeyboardAssistRequest,
  hasAllKeyboardAssistHmacVersions,
  type KeyboardAssistReplayRow,
  parseKeyboardAssistHmacKeyring,
  releaseKeyboardAssistClaim,
  renewKeyboardAssistClaim,
  settleKeyboardAssistRequest,
} from "./billing.ts";
import {
  createKeyboardAssistHandler,
  type KeyboardAssistHandlerDependencies,
  type KeyboardAssistUser,
} from "./handler.ts";
import {
  KeyboardAssistPipelineError,
  runKeyboardAssistPipeline,
} from "./pipeline.ts";
import { createAnthropicKeyboardAssistProvider } from "./provider.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const CLAUDE_API_KEY = Deno.env.get("CLAUDE_API_KEY") ?? "";
const KEYBOARD_ASSIST_COMPILER_MODEL =
  Deno.env.get("KEYBOARD_ASSIST_COMPILER_MODEL") ?? "";
const KEYBOARD_ASSIST_MODEL_ID = "claude-sonnet-5";
// One call, not two. The version is part of the ledger key, so a stored result
// from the two-stage pipeline stays distinguishable from this one on replay.
const KEYBOARD_SCREENSHOT_PIPELINE_VERSION =
  Deno.env.get("KEYBOARD_SCREENSHOT_PIPELINE_VERSION") ??
    "compiler-only-v1";
const KEYBOARD_SCREENSHOT_V1_ENABLED =
  Deno.env.get("KEYBOARD_SCREENSHOT_V1_ENABLED") === "true";
const KEYBOARD_SCREENSHOT_V1_ALLOWLIST = new Set(
  (Deno.env.get("KEYBOARD_SCREENSHOT_V1_ALLOWLIST") ?? "")
    .split(",")
    .map((value) => value.trim().toLowerCase())
    .filter(Boolean),
);
const REVENUECAT_IOS_API_KEY = Deno.env.get("REVENUECAT_IOS_API_KEY") ?? "";
const SUBSCRIPTION_COLUMNS =
  "tier, status, expires_at, active_product_id, store, revenuecat_environment, " +
  "monthly_messages_used, daily_messages_used, daily_reset_at, monthly_reset_at";

const parsedKeyring = parseKeyboardAssistHmacKeyring({
  currentVersion: Deno.env.get("KEYBOARD_ASSIST_HMAC_CURRENT_VERSION"),
  keysJson: Deno.env.get("KEYBOARD_ASSIST_HMAC_KEYS_JSON"),
});
// Empty keyring leaves authenticated image-free GET status replay available
// while every POST fails closed during a configuration incident.
const keyring = parsedKeyring ?? {
  currentVersion: 1,
  keys: new Map<number, string>(),
};

const client = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

// Fail capability negotiation closed on model aliases or accidental
// whitespace. The Sonnet 5 wire contract intentionally differs from older
// models, so a configuration typo must not become a provider-time 400.
const provider = CLAUDE_API_KEY &&
    KEYBOARD_ASSIST_COMPILER_MODEL === KEYBOARD_ASSIST_MODEL_ID
  ? createAnthropicKeyboardAssistProvider({
    apiKey: CLAUDE_API_KEY,
    compilerModel: KEYBOARD_ASSIST_COMPILER_MODEL,
  })
  : null;

async function fetchSubscription(
  userId: string,
): Promise<SubscriptionRow | null> {
  const { data, error } = await client.from("subscriptions")
    .select(SUBSCRIPTION_COLUMNS)
    .eq("user_id", userId)
    .maybeSingle();
  if (!error && data) {
    const sourceAware = await resolveSourceAwareSubscriptionRow(
      client,
      userId,
      data as unknown as Record<string, unknown>,
      new Date(),
    );
    return sourceAware.row as unknown as SubscriptionRow;
  }
  if (error) console.warn("keyboard_assist_subscription_lookup_failed");

  const now = new Date().toISOString();
  const inserted = await client.from("subscriptions").insert({
    user_id: userId,
    tier: "free",
    monthly_messages_used: 0,
    daily_messages_used: 0,
    daily_reset_at: now,
    monthly_reset_at: now,
    started_at: now,
  }).select(SUBSCRIPTION_COLUMNS).single();
  if (!inserted.error && inserted.data) {
    const sourceAware = await resolveSourceAwareSubscriptionRow(
      client,
      userId,
      inserted.data as unknown as Record<string, unknown>,
      new Date(),
    );
    return sourceAware.row as unknown as SubscriptionRow;
  }
  if (inserted.error?.code === "23505") {
    const retry = await client.from("subscriptions")
      .select(SUBSCRIPTION_COLUMNS)
      .eq("user_id", userId)
      .maybeSingle();
    if (!retry.data) return null;
    const sourceAware = await resolveSourceAwareSubscriptionRow(
      client,
      userId,
      retry.data as unknown as Record<string, unknown>,
      new Date(),
    );
    return sourceAware.row as unknown as SubscriptionRow;
  }
  console.warn("keyboard_assist_subscription_self_heal_failed");
  return null;
}

async function persistResets(
  userId: string,
  reset: ReturnType<typeof applyResetsIfNeeded>,
): Promise<void> {
  const updateWithCas = async (
    values: Record<string, unknown>,
    column: "daily_reset_at" | "monthly_reset_at",
    previous: string | null,
  ) => {
    let query = client.from("subscriptions")
      .update(values)
      .eq("user_id", userId);
    query = previous == null
      ? query.is(column, null)
      : query.eq(column, previous);
    const { error } = await query;
    if (error) console.warn("keyboard_assist_reset_persist_failed");
  };
  if (reset.dailyReset) {
    await updateWithCas(
      {
        daily_messages_used: 0,
        daily_reset_at: reset.sub.daily_reset_at,
      },
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

async function maybeRefreshTier(
  userId: string,
  sub: SubscriptionRow,
): Promise<SubscriptionRow | null> {
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
    const payload: unknown = await response.json().catch(() => null);
    if (!isPlainObject(payload) || !isPlainObject(payload.subscriber)) {
      return null;
    }
    const parsed = parseRevenueCatSubscriber(payload.subscriber);
    if (!parsed || tierRank(parsed.tier) <= tierRank(previousTier)) return null;
    const snapshotEvents = buildRevenueCatStoreEvents(payload.subscriber, {});
    if (snapshotEvents.length === 0) return null;
    for (const snapshotEvent of snapshotEvents) {
      const persistResult = await persistSubscriptionStoreState(
        client,
        userId,
        snapshotEvent,
      );
      if (
        !persistResult.accepted && persistResult.reason !== "duplicate" &&
        persistResult.reason !== "stale"
      ) {
        return null;
      }
    }
    const { data, error: refreshedReadError } = await client.from(
      "subscriptions",
    )
      .select(SUBSCRIPTION_COLUMNS)
      .eq("user_id", userId)
      .maybeSingle();
    if (refreshedReadError || !data) return null;
    const sourceAware = await resolveSourceAwareSubscriptionRow(
      client,
      userId,
      data as unknown as Record<string, unknown>,
      new Date(),
    );
    return sourceAware.row as unknown as SubscriptionRow;
  } catch {
    console.warn("keyboard_assist_revenuecat_refresh_failed");
    return null;
  }
}

async function quotaCheck(
  user: KeyboardAssistUser,
): ReturnType<KeyboardAssistHandlerDependencies["quota"]["check"]> {
  let sub = await fetchSubscription(user.id);
  if (!sub) {
    return { kind: "unavailable", message: "subscription unavailable" };
  }
  const reset = applyResetsIfNeeded(sub, new Date());
  sub = reset.sub;
  if (reset.dailyReset || reset.monthlyReset) {
    await persistResets(user.id, reset);
  }
  const isTestAccount = user.email != null &&
    TEST_EMAILS.includes(user.email.toLowerCase());
  let limits = resolveLimits(sub.tier);
  let gate = checkQuota({
    sub,
    cost: 1,
    isTestAccount,
    monthlyLimit: limits.monthly,
    dailyLimit: limits.daily,
  });
  if (!gate.ok) {
    const refreshed = await maybeRefreshTier(user.id, sub);
    if (refreshed) {
      sub = refreshed;
      limits = resolveLimits(sub.tier);
      gate = checkQuota({
        sub,
        cost: 1,
        isTestAccount,
        monthlyLimit: limits.monthly,
        dailyLimit: limits.daily,
      });
    }
  }
  if (!gate.ok) {
    return {
      kind: "limited",
      message: quotaExceededMessage(gate.reason),
    };
  }
  return {
    kind: "allowed",
    monthlyLimit: limits.monthly,
    dailyLimit: limits.daily,
    chargeQuota: !isTestAccount,
  };
}

function isUserAllowlisted(user: KeyboardAssistUser): boolean {
  if (KEYBOARD_SCREENSHOT_V1_ALLOWLIST.size === 0) return true;
  return KEYBOARD_SCREENSHOT_V1_ALLOWLIST.has(user.id.toLowerCase()) ||
    user.email != null &&
      KEYBOARD_SCREENSHOT_V1_ALLOWLIST.has(user.email.toLowerCase());
}

async function featureEnabled(user: KeyboardAssistUser): Promise<boolean> {
  if (
    !KEYBOARD_SCREENSHOT_V1_ENABLED || !isUserAllowlisted(user) ||
    !parsedKeyring || !provider
  ) return false;
  const [contract, versions] = await Promise.all([
    client.rpc("keyboard_assist_contract_version"),
    client.rpc("keyboard_assist_hmac_key_versions"),
  ]);
  if (
    contract.error || contract.data !== "keyboard-assist-v1" ||
    versions.error
  ) return false;
  return hasAllKeyboardAssistHmacVersions(versions.data, keyring);
}

const dependencies: KeyboardAssistHandlerDependencies = {
  authenticate: async (request) => {
    const authorization = request.headers.get("authorization") ?? "";
    const match = authorization.match(/^Bearer\s+(.+)$/i);
    if (!match) return null;
    const { data, error } = await client.auth.getUser(match[1]);
    if (error || !data.user) return null;
    return {
      id: data.user.id,
      email: data.user.email ?? null,
    };
  },
  ledger: {
    lookup: async (userId, requestId) => {
      const { data, error } = await client.from("keyboard_assist_requests")
        .select(
          "input_hash, hmac_key_version, state, lease_expires_at, created_at, result_json",
        )
        .eq("user_id", userId)
        .eq("request_id", requestId)
        .maybeSingle();
      if (error) throw new Error("keyboard assist lookup failed");
      return data as KeyboardAssistReplayRow | null;
    },
    claim: (input) =>
      claimKeyboardAssistRequest({
        rpc: (fn, params) => client.rpc(fn, params),
        ...input,
      }),
    renew: (input) =>
      renewKeyboardAssistClaim({
        rpc: (fn, params) => client.rpc(fn, params),
        ...input,
      }),
    release: (input) =>
      releaseKeyboardAssistClaim({
        rpc: (fn, params) => client.rpc(fn, params),
        ...input,
      }),
    settle: (input) =>
      settleKeyboardAssistRequest({
        rpc: (fn, params) => client.rpc(fn, params),
        ...input,
      }),
    expire: (userId, requestId) =>
      expireKeyboardAssistRequest({
        rpc: (fn, params) => client.rpc(fn, params),
        userId,
        requestId,
      }),
  },
  quota: { check: quotaCheck },
  rateLimit: async (user) => {
    const isTestAccount = user.email != null &&
      TEST_EMAILS.includes(user.email.toLowerCase());
    const result = await enforceModelRateLimit({
      supabase: client,
      userId: user.id,
      scope: "keyboard_assist",
      isTestAccount,
    });
    if (result.kind === "limited") {
      return {
        kind: "limited",
        retryAfterMs: result.reason === "minute" ? 60_000 : undefined,
      };
    }
    if (result.kind === "failOpen") {
      console.warn("keyboard_assist_model_rate_limit_fail_open");
    }
    return { kind: "allowed" };
  },
  runPipeline: async (input) => {
    if (!provider) {
      throw new KeyboardAssistPipelineError(
        "provider_invalid_output",
        "provider is not configured",
      );
    }
    return await runKeyboardAssistPipeline({
      image: {
        bytes: input.imageBytes,
        base64: input.request.image.data,
        mediaType: input.request.image.mediaType,
      },
      speakerOverride: input.request.speakerOverride,
      voice: input.request.voice,
      priorTurn: input.request.priorTurn,
      pipelineVersion: KEYBOARD_SCREENSHOT_PIPELINE_VERSION,
      signal: input.signal,
      compiler: provider.compiler,
      renewLease: input.renewLease,
      recordStageTiming: input.recordStageTiming,
      nowMs: () => performance.now(),
      compilerDeadlineAtMs: input.compilerDeadlineAtMs,
      deadlineAtMs: input.deadlineAtMs,
    });
  },
  recordTelemetry: (record) => {
    console.info("keyboard_assist_telemetry", JSON.stringify(record));
  },
  featureEnabled,
  keyring,
  pipelineVersion: KEYBOARD_SCREENSHOT_PIPELINE_VERSION,
  now: () => new Date(),
  monotonicNow: () => performance.now(),
  randomUuid: () => crypto.randomUUID(),
};

export const handleRequest = createKeyboardAssistHandler(dependencies);

if (import.meta.main) {
  serve(withOperationalErrorMonitoring("keyboard-assist", handleRequest));
}
