import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const DEPLOY_VERSION = "2026-03-16-rc-webhook-v3";

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function getTierFromProductId(productId: string): string {
  if (!productId) return "free";
  if (productId.includes("essential")) return "essential";
  if (productId.includes("starter")) return "starter";
  return "free";
}

function stripBearer(value: string): string {
  return value.trim().replace(/^Bearer\s+/i, "");
}

async function sha256Prefix(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("")
    .slice(0, 12);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  if (req.method === "GET") {
    return jsonResponse({
      ok: true,
      name: "revenuecat-webhook",
      version: DEPLOY_VERSION,
    });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const webhookSecret = Deno.env.get("REVENUECAT_WEBHOOK_SECRET");
    if (!webhookSecret) {
      console.error("REVENUECAT_WEBHOOK_SECRET is not configured");
      return jsonResponse({ error: "Server misconfigured" }, 500);
    }

    const authHeaderRaw = req.headers.get("Authorization") || "";
    const authHeader = authHeaderRaw.trim();
    const receivedToken = stripBearer(authHeader);
    const expectedToken = stripBearer(webhookSecret);

    if (!receivedToken || receivedToken !== expectedToken) {
      const debug = {
        version: DEPLOY_VERSION,
        hasAuth: authHeader.length > 0,
        startsWithBearer: /^Bearer\s+/i.test(authHeader),
        authHeaderLength: authHeader.length,
        receivedTokenLength: receivedToken.length,
        expectedTokenLength: expectedToken.length,
        receivedTokenHash12: receivedToken ? await sha256Prefix(receivedToken) : null,
        expectedTokenHash12: expectedToken ? await sha256Prefix(expectedToken) : null,
      };

      console.error(`Invalid webhook authorization: ${JSON.stringify(debug)}`);
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    const body = await req.json();
    const { event } = body ?? {};

    if (!event) {
      console.error(
        "No event in body",
        JSON.stringify({
          bodyType: typeof body,
          bodyKeys: body && typeof body === "object" ? Object.keys(body) : null,
        }),
      );
      return jsonResponse({ error: "No event in body" }, 400);
    }

    const {
      type,
      app_user_id,
      product_id,
      new_product_id,
      expiration_at_ms,
    } = event;

    const effectiveProductId =
      type === "PRODUCT_CHANGE" && typeof new_product_id === "string" && new_product_id
        ? new_product_id
        : product_id;

    console.log(
      `Event type: ${type}, User: ${app_user_id}, product_id: ${product_id}, new_product_id: ${new_product_id}`,
    );

    if (!app_user_id || app_user_id.startsWith("$RCAnonymousID")) {
      console.log("Skipping anonymous user event");
      return jsonResponse({ success: true, message: "Skipped anonymous user" });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !supabaseServiceKey) {
      console.error("Supabase env vars are missing");
      return jsonResponse({ error: "Server misconfigured" }, 500);
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    let newTier = "free";
    let shouldUpdate = false;

    switch (type) {
      case "INITIAL_PURCHASE":
      case "RENEWAL":
      case "PRODUCT_CHANGE":
      case "UNCANCELLATION":
      case "SUBSCRIPTION_EXTENDED":
        newTier = getTierFromProductId(effectiveProductId);
        shouldUpdate = true;
        console.log(`Upgrading user ${app_user_id} to ${newTier}`);
        break;

      case "EXPIRATION":
      case "BILLING_ISSUE":
        newTier = "free";
        shouldUpdate = true;
        console.log(`Downgrading user ${app_user_id} to free`);
        break;

      case "CANCELLATION":
        console.log(`User ${app_user_id} cancelled, will expire at ${expiration_at_ms}`);
        shouldUpdate = false;
        break;

      case "NON_RENEWING_PURCHASE":
      case "SUBSCRIBER_ALIAS":
      case "TRANSFER":
        console.log(`Event ${type} logged but no action taken`);
        shouldUpdate = false;
        break;

      default:
        console.log(`Unknown event type: ${type}`);
        shouldUpdate = false;
        break;
    }

    if (shouldUpdate) {
      const nowIso = new Date().toISOString();

      const { data: updatedRows, error: updateError } = await supabase
        .from("subscriptions")
        .update({ tier: newTier })
        .eq("user_id", app_user_id)
        .select("user_id")
        .limit(1);

      if (updateError) {
        console.error("Failed to update subscription:", updateError);
        return jsonResponse({ error: "Database error" }, 500);
      }

      if (!updatedRows || updatedRows.length === 0) {
        const { error: insertError } = await supabase
          .from("subscriptions")
          .insert({
            user_id: app_user_id,
            tier: newTier,
            monthly_messages_used: 0,
            daily_messages_used: 0,
            daily_reset_at: nowIso,
            monthly_reset_at: nowIso,
            started_at: nowIso,
          });

        if (insertError) {
          console.error("Failed to insert subscription:", insertError);
          return jsonResponse({ error: "Database error" }, 500);
        }

        console.log(`Inserted subscription record for user ${app_user_id}`);
      }

      console.log(`Successfully updated user ${app_user_id} to tier: ${newTier}`);
    }

    const { error: logError } = await supabase.from("webhook_logs").insert({
      source: "revenuecat",
      event_type: type,
      user_id: app_user_id,
      payload: body,
      created_at: new Date().toISOString(),
    });

    if (logError) {
      console.log("Failed to log webhook event (non-fatal):", logError);
    }

    return jsonResponse({
      success: true,
      event_type: type,
      user_id: app_user_id,
      new_tier: shouldUpdate ? newTier : undefined,
    });
  } catch (error) {
    console.error("Webhook error:", error);
    return jsonResponse({ error: (error as Error).message }, 500);
  }
});
