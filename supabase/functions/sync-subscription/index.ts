import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

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
  essential: { monthly: 1000, daily: 150 },
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

function tierFromProductId(productId: unknown): "free" | "starter" | "essential" {
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

function collectTiersFromRevenueCatPayload(
  subscriber: Record<string, unknown>,
): "free" | "starter" | "essential" {
  const activeTiers: Array<"free" | "starter" | "essential"> = [];

  const entitlements = isPlainObject(subscriber.entitlements)
    ? subscriber.entitlements
    : {};
  for (const value of Object.values(entitlements)) {
    if (!isPlainObject(value)) continue;
    if (!isActiveAt(value.expires_date)) continue;
    activeTiers.push(tierFromProductId(value.product_identifier));
  }

  const subscriptions = isPlainObject(subscriber.subscriptions)
    ? subscriber.subscriptions
    : {};
  for (const [productId, value] of Object.entries(subscriptions)) {
    if (!isPlainObject(value)) continue;
    if (!isActiveAt(value.expires_date)) continue;
    activeTiers.push(tierFromProductId(productId));
  }

  return highestTier(activeTiers);
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

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const token = stripBearer(authHeader);
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return jsonResponse({ error: "Invalid token" }, 401);
    }

    const revenueCatResponse = await fetch(
      `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(user.id)}`,
      {
        headers: {
          Authorization: `Bearer ${REVENUECAT_IOS_API_KEY}`,
          "Content-Type": "application/json",
        },
      },
    );

    if (!revenueCatResponse.ok) {
      const detail = await revenueCatResponse.text().catch(() => "");
      console.error("sync-subscription revenuecat error", {
        status: revenueCatResponse.status,
        detail,
      });
      return jsonResponse({
        error: "RevenueCat sync failed",
        detail: revenueCatResponse.status,
      }, 502);
    }

    const revenueCatPayload = await revenueCatResponse.json();
    if (!isPlainObject(revenueCatPayload)) {
      return jsonResponse({ error: "Invalid RevenueCat response" }, 502);
    }

    const subscriber = isPlainObject(revenueCatPayload.subscriber)
      ? revenueCatPayload.subscriber
      : null;
    if (!subscriber) {
      return jsonResponse({ error: "Missing RevenueCat subscriber" }, 502);
    }

    const { data: existingSub, error: existingError } = await supabase
      .from("subscriptions")
      .select("user_id, tier, monthly_messages_used, daily_messages_used")
      .eq("user_id", user.id)
      .maybeSingle();

    if (existingError) {
      console.error("sync-subscription lookup error", existingError);
      return jsonResponse({ error: "Subscription lookup failed" }, 500);
    }

    const previousTier = normalizeTier(existingSub?.tier);
    const revenueCatTier = collectTiersFromRevenueCatPayload(subscriber);
    let finalTier = revenueCatTier;

    // App Store same-group downgrades can be scheduled for the next renewal.
    // During that window we should keep the already-granted higher tier until
    // RevenueCat/Apple finalize the renewal and our subscription row changes.
    if (
      revenueCatTier !== "free" &&
      expectedTier === previousTier &&
      tierRank(previousTier) > tierRank(revenueCatTier)
    ) {
      finalTier = previousTier;
    }

    const limits = TIER_LIMITS[finalTier] ?? TIER_LIMITS.free;
    // Keep usage counters intact across tier sync / restore. Upgrading should
    // increase limits, not erase already-consumed usage.
    const shouldResetUsage = false;
    const nowIso = new Date().toISOString();
    const updatePayload: Record<string, unknown> = {
      tier: finalTier,
      status: finalTier == "free" ? "active" : "active",
    };

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
        "tier, monthly_messages_used, daily_messages_used, monthly_reset_at, daily_reset_at",
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
        "tier, monthly_messages_used, daily_messages_used, monthly_reset_at, daily_reset_at",
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
      expectedTier,
      tierConfirmedByRevenueCat: revenueCatTier === finalTier,
      monthlyMessagesUsed: syncedRow?.monthly_messages_used ?? 0,
      dailyMessagesUsed: syncedRow?.daily_messages_used ?? 0,
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
