import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const DEPLOY_VERSION = "2026-04-03-rc-webhook-v4";

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function getTierFromProductId(productId: string): string | null {
  const normalized = productId.trim().toLowerCase();
  if (!normalized) return null;
  if (normalized.includes("essential")) return "essential";
  if (normalized.includes("starter")) return "starter";
  return null;
}

function stripBearer(value: string): string {
  return value.trim().replace(/^Bearer\s+/i, "");
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isValidUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}

function normalizeExpirationAt(value: unknown): string | null {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) {
    return null;
  }

  return new Date(value).toISOString();
}

function extractValidUuidList(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .filter((item): item is string => typeof item === "string")
    .map((item) => item.trim())
    .filter((item) => item.length > 0 && isValidUuid(item));
}

function sanitizeWebhookPayload(
  body: Record<string, unknown>,
  options?: { ignoredReason?: string },
): Record<string, unknown> {
  const event = isPlainObject(body.event) ? body.event : {};

  const sanitized: Record<string, unknown> = {
    source: "revenuecat",
    type: typeof event.type === "string" ? event.type : null,
    app_user_id: typeof event.app_user_id === "string" ? event.app_user_id : null,
    product_id: typeof event.product_id === "string" ? event.product_id : null,
    new_product_id: typeof event.new_product_id === "string"
      ? event.new_product_id
      : null,
    entitlement_ids: Array.isArray(event.entitlement_ids)
      ? event.entitlement_ids
      : [],
    transferred_from: extractValidUuidList(event.transferred_from),
    transferred_to: extractValidUuidList(event.transferred_to),
    expiration_at_ms: typeof event.expiration_at_ms === "number"
      ? event.expiration_at_ms
      : null,
    environment: typeof event.environment === "string"
      ? event.environment
      : null,
    aliases: Array.isArray(event.aliases) ? event.aliases : [],
  };

  if (options?.ignoredReason) {
    sanitized.ignored_reason = options.ignoredReason;
  }

  return sanitized;
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
        receivedTokenHash12: receivedToken
          ? await sha256Prefix(receivedToken)
          : null,
        expectedTokenHash12: expectedToken
          ? await sha256Prefix(expectedToken)
          : null,
      };

      console.error(`Invalid webhook authorization: ${JSON.stringify(debug)}`);
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    if (!isPlainObject(body)) {
      return jsonResponse({ error: "Request body must be a JSON object" }, 400);
    }

    const { event } = body;

    if (!isPlainObject(event)) {
      console.error(
        "No event in body",
        JSON.stringify({
          bodyType: typeof body,
          bodyKeys: body && typeof body === "object" ? Object.keys(body) : null,
        }),
      );
      return jsonResponse({ error: "No event in body" }, 400);
    }

    const type = typeof event.type === "string" ? event.type.trim() : "";
    const app_user_id = typeof event.app_user_id === "string"
      ? event.app_user_id.trim()
      : "";
    const product_id = typeof event.product_id === "string"
      ? event.product_id.trim()
      : "";
    const new_product_id = typeof event.new_product_id === "string"
      ? event.new_product_id.trim()
      : "";
    const expiration_at_ms = event.expiration_at_ms;

    if (!type) {
      return jsonResponse({ error: "Invalid event type" }, 400);
    }

    const effectiveProductId =
      type === "PRODUCT_CHANGE" && typeof new_product_id === "string" &&
        new_product_id
        ? new_product_id
        : product_id;
    const expiresAt = normalizeExpirationAt(expiration_at_ms);

    console.log(
      `Event type: ${type}, User: ${app_user_id}, product_id: ${product_id}, new_product_id: ${new_product_id}`,
    );

    if (!app_user_id) {
      return jsonResponse({ error: "Missing app_user_id" }, 400);
    }

    if (app_user_id.startsWith("$RCAnonymousID")) {
      console.log("Skipping anonymous user event");
      return jsonResponse({ success: true, message: "Skipped anonymous user" });
    }

    if (!isValidUuid(app_user_id)) {
      console.error(`Invalid app_user_id format: ${app_user_id}`);
      return jsonResponse({ error: "Invalid app_user_id" }, 400);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !supabaseServiceKey) {
      console.error("Supabase env vars are missing");
      return jsonResponse({ error: "Server misconfigured" }, 500);
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);
    const { data: existingUser, error: userLookupError } = await supabase
      .from("users")
      .select("id")
      .eq("id", app_user_id)
      .maybeSingle();

    if (userLookupError) {
      console.error("Failed to verify webhook user:", userLookupError);
      return jsonResponse({ error: "Database error" }, 500);
    }

    if (!existingUser) {
      console.log(`Ignoring RevenueCat event for deleted user ${app_user_id}`);

      const { error: ignoredLogError } = await supabase.from("webhook_logs")
        .insert({
          source: "revenuecat",
          event_type: type,
          user_id: app_user_id,
          payload: sanitizeWebhookPayload(body, {
            ignoredReason: "user_not_found",
          }),
          created_at: new Date().toISOString(),
        });

      if (ignoredLogError) {
        console.error("Failed to log ignored webhook:", ignoredLogError);
      }

      return jsonResponse({
        success: true,
        ignored: true,
        reason: "user_not_found",
      });
    }

    const { data: existingSubscription, error: subscriptionLookupError } =
      await supabase
        .from("subscriptions")
        .select("tier")
        .eq("user_id", app_user_id)
        .maybeSingle();

    if (subscriptionLookupError) {
      console.error(
        "Failed to verify webhook subscription row:",
        subscriptionLookupError,
      );
      return jsonResponse({ error: "Database error" }, 500);
    }

    let newTier = "free";
    let shouldUpdate = false;
    let subscriptionUpdate: Record<string, unknown> | null = null;

    switch (type) {
      case "INITIAL_PURCHASE":
      case "RENEWAL":
      case "PRODUCT_CHANGE":
      case "UNCANCELLATION":
      case "SUBSCRIPTION_EXTENDED": {
        const derivedTier = getTierFromProductId(effectiveProductId);
        if (derivedTier == null) {
          console.error(
            `Unsupported product_id for ${type}: "${effectiveProductId}"`,
          );
          return jsonResponse({ error: "Unsupported product_id" }, 400);
        }

        newTier = derivedTier;
        shouldUpdate = true;
        subscriptionUpdate = {
          tier: newTier,
          status: "active",
          expires_at: expiresAt,
        };
        console.log(`Upgrading user ${app_user_id} to ${newTier}`);
        break;
      }

      case "EXPIRATION":
      case "BILLING_ISSUE":
        newTier = "free";
        shouldUpdate = true;
        subscriptionUpdate = {
          tier: newTier,
          status: "expired",
          expires_at: expiresAt,
        };
        console.log(`Downgrading user ${app_user_id} to free`);
        break;

      case "CANCELLATION":
        newTier = getTierFromProductId(effectiveProductId) ??
          (typeof existingSubscription?.tier === "string"
            ? existingSubscription.tier
            : "free");
        console.log(
          `User ${app_user_id} cancelled, will expire at ${expiration_at_ms}`,
        );
        shouldUpdate = true;
        subscriptionUpdate = {
          tier: newTier,
          status: "cancelled",
          expires_at: expiresAt,
        };
        break;

      case "NON_RENEWING_PURCHASE":
      case "SUBSCRIBER_ALIAS":
        console.log(`Event ${type} logged but no action taken`);
        shouldUpdate = false;
        break;

      case "TRANSFER": {
        const nowIso = new Date().toISOString();
        const transferTier = getTierFromProductId(effectiveProductId) ??
          (typeof existingSubscription?.tier === "string"
            ? existingSubscription.tier
            : "free");
        const transferredFrom = extractValidUuidList(event.transferred_from);
        const transferredTo = Array.from(
          new Set([
            ...extractValidUuidList(event.transferred_to),
            app_user_id,
          ]),
        );
        const transferredFromOnly = transferredFrom.filter((id) =>
          !transferredTo.includes(id)
        );

        if (transferredTo.length > 0) {
          const { data: existingRows, error: existingRowsError } = await supabase
            .from("subscriptions")
            .select("user_id")
            .in("user_id", transferredTo);

          if (existingRowsError) {
            console.error(
              "Failed to load transfer recipients:",
              existingRowsError,
            );
            return jsonResponse({ error: "Database error" }, 500);
          }

          const existingUserIds = new Set(
            (existingRows ?? [])
              .map((row) => typeof row.user_id === "string" ? row.user_id : "")
              .filter((userId) => userId.length > 0),
          );
          const missingUserIds = transferredTo.filter((userId) =>
            !existingUserIds.has(userId)
          );

          const { error: updateRecipientsError } = await supabase
            .from("subscriptions")
            .update({
              tier: transferTier,
              status: "active",
              expires_at: expiresAt,
            })
            .in("user_id", transferredTo);

          if (updateRecipientsError) {
            console.error(
              "Failed to update transfer recipients:",
              updateRecipientsError,
            );
            return jsonResponse({ error: "Database error" }, 500);
          }

          if (missingUserIds.length > 0) {
            const inserts = missingUserIds.map((userId) => ({
              user_id: userId,
              tier: transferTier,
              status: "active",
              expires_at: expiresAt,
              monthly_messages_used: 0,
              daily_messages_used: 0,
              daily_reset_at: nowIso,
              monthly_reset_at: nowIso,
              started_at: nowIso,
            }));

            const { error: insertRecipientsError } = await supabase
              .from("subscriptions")
              .insert(inserts);

            if (insertRecipientsError) {
              console.error(
                "Failed to insert transfer recipients:",
                insertRecipientsError,
              );
              return jsonResponse({ error: "Database error" }, 500);
            }
          }
        }

        if (transferredFromOnly.length > 0) {
          const { error: downgradeError } = await supabase
            .from("subscriptions")
            .update({
              tier: "free",
              status: "expired",
              expires_at: expiresAt ?? nowIso,
            })
            .in("user_id", transferredFromOnly);

          if (downgradeError) {
            console.error(
              "Failed to downgrade transfer source users:",
              downgradeError,
            );
            return jsonResponse({ error: "Database error" }, 500);
          }
        }

        console.log(
          `Processed transfer: tier=${transferTier}, to=${transferredTo.join(",")}, from=${transferredFromOnly.join(",")}`,
        );
        shouldUpdate = false;
        break;
      }

      default:
        console.log(`Unknown event type: ${type}`);
        shouldUpdate = false;
        break;
    }

    if (shouldUpdate) {
      const nowIso = new Date().toISOString();

      const { data: updatedRows, error: updateError } = await supabase
        .from("subscriptions")
        .update(subscriptionUpdate ?? { tier: newTier })
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
            ...(subscriptionUpdate ?? { tier: newTier }),
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

      console.log(
        `Successfully updated user ${app_user_id} to tier: ${newTier}`,
      );
    }

    const { error: logError } = await supabase.from("webhook_logs").insert({
      source: "revenuecat",
      event_type: type,
      user_id: app_user_id,
      payload: sanitizeWebhookPayload(body),
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
