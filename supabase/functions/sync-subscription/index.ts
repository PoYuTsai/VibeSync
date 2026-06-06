import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

import { buildRevenueCatUserIdCandidates } from "./revenuecat_identity.ts";
import {
  latestActiveExpirationDateFromRevenueCatPayload,
  latestIsoDate,
} from "./revenuecat_expiration.ts";
import { shouldResetUsageOnTierSync } from "./usage_reset.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const REVENUECAT_IOS_API_KEY = Deno.env.get("REVENUECAT_IOS_API_KEY");

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "Authorization, Content-Type, x-client-info, apikey",
};

const TIER_LIMITS: Record<string, { monthly: number; daily: number }> = {
  free: { monthly: 30, daily: 15 },
  starter: { monthly: 300, daily: 50 },
  essential: { monthly: 800, daily: 120 },
};

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...corsHeaders,
    },
  });
}

function stripBearer(value: string): string {
  return value.trim().replace(/^Bearer\s+/i, "");
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function normalizeTier(value: unknown): "free" | "starter" | "essential" {
  if (typeof value !== "string") return "free";
  const normalized = value.trim().toLowerCase();
  if (normalized === "starter" || normalized === "essential") {
    return normalized;
  }
  return "free";
}

function tierFromProductId(
  productId: unknown,
): "free" | "starter" | "essential" {
  if (typeof productId !== "string") return "free";
  const normalized = productId.trim().toLowerCase();
  if (normalized.includes("essential")) return "essential";
  if (normalized.includes("starter")) return "starter";
  return "free";
}

function highestTier(
  tiers: Iterable<"free" | "starter" | "essential">,
): "free" | "starter" | "essential" {
  const all = Array.from(tiers);
  if (all.includes("essential")) return "essential";
  if (all.includes("starter")) return "starter";
  return "free";
}

function tierRank(value: "free" | "starter" | "essential"): number {
  switch (value) {
    case "essential":
      return 2;
    case "starter":
      return 1;
    case "free":
    default:
      return 0;
  }
}

function isActiveAt(expiresDate: unknown): boolean {
  if (expiresDate == null) return true;
  if (typeof expiresDate !== "string" || !expiresDate.trim()) return true;
  const parsed = new Date(expiresDate);
  if (Number.isNaN(parsed.getTime())) return false;
  return parsed.getTime() > Date.now();
}

function collectActiveProductIdsFromRevenueCatPayload(
  subscriber: Record<string, unknown>,
): string[] {
  const activeProductIds: string[] = [];

  const entitlements = isPlainObject(subscriber.entitlements)
    ? subscriber.entitlements
    : {};
  for (const value of Object.values(entitlements)) {
    if (!isPlainObject(value)) continue;
    if (!isActiveAt(value.expires_date)) continue;
    if (typeof value.product_identifier !== "string") continue;
    const productId = value.product_identifier.trim();
    if (productId) activeProductIds.push(productId);
  }

  const subscriptions = isPlainObject(subscriber.subscriptions)
    ? subscriber.subscriptions
    : {};
  for (const [productId, value] of Object.entries(subscriptions)) {
    if (!isPlainObject(value)) continue;
    if (!isActiveAt(value.expires_date)) continue;
    if (productId.trim()) activeProductIds.push(productId.trim());
  }

  return Array.from(new Set(activeProductIds));
}

function highestActiveProductId(productIds: string[]): string | null {
  const ranked = productIds
    .map((productId) => ({
      productId,
      tier: tierFromProductId(productId),
    }))
    .filter((entry) => entry.tier !== "free")
    .sort((a, b) => tierRank(b.tier) - tierRank(a.tier));

  return ranked[0]?.productId ?? null;
}

function inferBillingPeriod(
  productId: string | null | undefined,
): string | null {
  const normalized = productId?.trim().toLowerCase() ?? "";
  if (!normalized) return null;
  if (normalized.includes("quarter") || normalized.includes("p3m")) {
    return "quarterly";
  }
  if (normalized.includes("monthly") || normalized.includes("p1m")) {
    return "monthly";
  }
  return "unknown";
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    if (!REVENUECAT_IOS_API_KEY) {
      console.error("REVENUECAT_IOS_API_KEY is not configured");
      return jsonResponse({ error: "Server misconfigured" }, 500);
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !/^Bearer\s+\S+/i.test(authHeader)) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    let body: unknown = {};
    try {
      body = await req.json();
    } catch {
      body = {};
    }

    const requestBody = isPlainObject(body) ? body : {};
    const expectedTier = normalizeTier(requestBody.expectedTier);
    const resetUsage = requestBody.resetUsage === true;
    const revenueCatAppUserId = requestBody.revenueCatAppUserId;

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const token = stripBearer(authHeader);
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return jsonResponse({ error: "Invalid token" }, 401);
    }

    const revenueCatCandidates = buildRevenueCatUserIdCandidates(
      user.id,
      revenueCatAppUserId,
    );
    const subscriberSnapshots: Array<{
      appUserId: string;
      subscriber: Record<string, unknown>;
      activeProductIds: string[];
      activeExpiresAt: string | null;
    }> = [];
    let lastRevenueCatError: { status: number; detail: string } | null = null;

    for (const appUserId of revenueCatCandidates) {
      const revenueCatResponse = await fetch(
        `https://api.revenuecat.com/v1/subscribers/${
          encodeURIComponent(appUserId)
        }`,
        {
          headers: {
            Authorization: `Bearer ${REVENUECAT_IOS_API_KEY}`,
            "Content-Type": "application/json",
          },
        },
      );

      if (!revenueCatResponse.ok) {
        const detail = await revenueCatResponse.text().catch(() => "");
        lastRevenueCatError = { status: revenueCatResponse.status, detail };
        console.error("sync-subscription revenuecat error", {
          appUserId,
          status: revenueCatResponse.status,
          detail,
        });
        continue;
      }

      const revenueCatPayload = await revenueCatResponse.json();
      if (!isPlainObject(revenueCatPayload)) {
        continue;
      }

      const subscriber = isPlainObject(revenueCatPayload.subscriber)
        ? revenueCatPayload.subscriber
        : null;
      if (!subscriber) {
        continue;
      }

      subscriberSnapshots.push({
        appUserId,
        subscriber,
        activeProductIds: collectActiveProductIdsFromRevenueCatPayload(
          subscriber,
        ),
        activeExpiresAt: latestActiveExpirationDateFromRevenueCatPayload(
          subscriber,
        ),
      });
    }

    if (subscriberSnapshots.length === 0) {
      return jsonResponse({
        error: "RevenueCat sync failed",
        detail: lastRevenueCatError?.status ?? "invalid_payload",
      }, 502);
    }

    const { data: existingSub, error: existingError } = await supabase
      .from("subscriptions")
      .select(
        "user_id, tier, monthly_messages_used, daily_messages_used, expires_at, active_product_id, billing_period",
      )
      .eq("user_id", user.id)
      .maybeSingle();

    if (existingError) {
      console.error("sync-subscription lookup error", existingError);
      return jsonResponse({ error: "Subscription lookup failed" }, 500);
    }

    const previousTier = normalizeTier(existingSub?.tier);
    const activeProductIds = Array.from(
      new Set(
        subscriberSnapshots.flatMap((snapshot) => snapshot.activeProductIds),
      ),
    );
    const revenueCatTier = highestTier(activeProductIds.map(tierFromProductId));
    const revenueCatProductId = highestActiveProductId(activeProductIds);
    const revenueCatExpiresAt = latestIsoDate(
      subscriberSnapshots.map((snapshot) => snapshot.activeExpiresAt),
    );
    const matchedRevenueCatAppUserId = subscriberSnapshots.find(
      (snapshot) => snapshot.activeProductIds.length > 0,
    )?.appUserId ?? subscriberSnapshots[0].appUserId;

    if (
      tierRank(expectedTier) > tierRank("free") &&
      revenueCatTier === "free" &&
      previousTier === "free"
    ) {
      console.error("sync-subscription paid tier not confirmed", {
        expectedTier,
        checked: revenueCatCandidates.length,
        matchedRevenueCatAppUserId,
      });
      return jsonResponse({
        error: "Paid tier not confirmed by RevenueCat",
        expectedTier,
        revenueCatTier,
        matchedRevenueCatAppUserId,
        revenueCatAppUserIdsChecked: revenueCatCandidates.length,
      }, 409);
    }

    let finalTier = revenueCatTier;
    let tierPreservedReason: string | null = null;

    // App Store same-group downgrades can be scheduled for the next renewal.
    // During that window we should keep the already-granted higher tier until
    // RevenueCat/Apple finalize the renewal and our subscription row changes.
    if (
      revenueCatTier !== "free" &&
      tierRank(previousTier) > tierRank(revenueCatTier)
    ) {
      finalTier = previousTier;
      tierPreservedReason = "scheduled_paid_downgrade";
    }

    // Client-initiated refreshes can briefly see an empty RevenueCat subscriber
    // before aliases / entitlements settle. Do not let that transient free
    // snapshot erase an already-paid DB tier; true expiration / billing issues
    // are owned by RevenueCat webhook events.
    if (
      revenueCatTier === "free" &&
      tierRank(previousTier) > tierRank("free")
    ) {
      finalTier = previousTier;
      tierPreservedReason = "paid_tier_free_snapshot_guard";
    }

    const existingProductId = typeof existingSub?.active_product_id === "string"
      ? existingSub.active_product_id
      : null;
    const finalActiveProductId = finalTier === "free"
      ? null
      : revenueCatProductId ?? existingProductId;

    const limits = TIER_LIMITS[finalTier] ?? TIER_LIMITS.free;
    // A confirmed paid upgrade starts the new plan with a fresh usage bucket.
    // Same-tier restore / scheduled downgrade / transient RC free snapshot
    // still preserve counters to avoid accidental quota erasure.
    const shouldResetUsage = shouldResetUsageOnTierSync({
      resetUsageRequested: resetUsage,
      previousTier,
      finalTier,
      revenueCatTier,
      tierPreservedReason,
    });
    const nowIso = new Date().toISOString();
    const updatePayload: Record<string, unknown> = {
      tier: finalTier,
      status: finalTier == "free" ? "active" : "active",
      active_product_id: finalActiveProductId,
      billing_period: inferBillingPeriod(finalActiveProductId),
    };
    if (finalTier !== "free" && revenueCatExpiresAt !== null) {
      updatePayload.expires_at = revenueCatExpiresAt;
    }
    if (shouldResetUsage) {
      updatePayload.monthly_messages_used = 0;
      updatePayload.daily_messages_used = 0;
      updatePayload.monthly_reset_at = nowIso;
      updatePayload.daily_reset_at = nowIso;
    }

    let syncedRow: Record<string, unknown> | null = null;

    if (!existingSub) {
      const { data, error } = await supabase.from("subscriptions").insert({
        user_id: user.id,
        ...updatePayload,
        monthly_messages_used: 0,
        daily_messages_used: 0,
        monthly_reset_at: nowIso,
        daily_reset_at: nowIso,
        started_at: nowIso,
      }).select(
        "tier, monthly_messages_used, daily_messages_used, monthly_reset_at, daily_reset_at, expires_at, active_product_id, billing_period",
      ).single();

      if (error) {
        console.error("sync-subscription insert error", error);
        return jsonResponse({ error: "Subscription sync failed" }, 500);
      }
      syncedRow = data;
    } else {
      const { data, error } = await supabase.from("subscriptions").update(
        updatePayload,
      ).eq("user_id", user.id).select(
        "tier, monthly_messages_used, daily_messages_used, monthly_reset_at, daily_reset_at, expires_at, active_product_id, billing_period",
      ).single();

      if (error) {
        console.error("sync-subscription update error", error);
        return jsonResponse({ error: "Subscription sync failed" }, 500);
      }
      syncedRow = data;
    }

    return jsonResponse({
      success: true,
      tier: finalTier,
      previousTier,
      revenueCatTier,
      activeProductId: finalActiveProductId,
      billingPeriod: syncedRow?.billing_period ??
        inferBillingPeriod(finalActiveProductId),
      matchedRevenueCatAppUserId,
      revenueCatAppUserIdsChecked: revenueCatCandidates.length,
      expectedTier,
      tierConfirmedByRevenueCat: revenueCatTier === finalTier,
      tierPreservedReason,
      monthlyMessagesUsed: syncedRow?.monthly_messages_used ?? 0,
      dailyMessagesUsed: syncedRow?.daily_messages_used ?? 0,
      expiresAt: syncedRow?.expires_at ?? revenueCatExpiresAt ??
        existingSub?.expires_at ?? null,
      monthlyLimit: limits.monthly,
      dailyLimit: limits.daily,
      resetUsage: shouldResetUsage,
      source: "revenuecat_api",
    });
  } catch (error) {
    console.error("sync-subscription error", error);
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
