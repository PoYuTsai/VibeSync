import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2";
import { withOperationalErrorMonitoring } from "../_shared/operational_error_monitor.ts";
import {
  persistSubscriptionStoreState,
  type StoreSubscriptionEventInput,
} from "../_shared/subscription_store_state.ts";
import { buildRevenueCatWebhookStoreEvent } from "./webhook_store_event.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const DEPLOY_VERSION = "2026-08-28-rc-webhook-v6";
const REVENUE_EVENT_TYPES = new Set([
  "INITIAL_PURCHASE",
  "RENEWAL",
  "CANCELLATION",
  "BILLING_ISSUE",
  "PRODUCT_CHANGE",
]);

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
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

function normalizeTimestampMs(value: unknown): string | null {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) {
    return null;
  }

  return new Date(value).toISOString();
}

function normalizeNumber(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return null;
  }

  return value;
}

function optionalString(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function extractStringList(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .filter((item): item is string => typeof item === "string")
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
}

function buildWebhookLogPayload(
  event: Record<string, unknown>,
  options: {
    ignoredReason?: string;
    processedTier?: string;
    transferTo?: string[];
    transferFrom?: string[];
  } = {},
): Record<string, unknown> {
  return {
    version: DEPLOY_VERSION,
    type: typeof event.type === "string" ? event.type.trim() : null,
    app_user_id: typeof event.app_user_id === "string"
      ? event.app_user_id.trim()
      : null,
    original_app_user_id: typeof event.original_app_user_id === "string"
      ? event.original_app_user_id.trim()
      : null,
    aliases: extractValidUuidList(event.aliases),
    product_id: typeof event.product_id === "string"
      ? event.product_id.trim()
      : null,
    new_product_id: typeof event.new_product_id === "string"
      ? event.new_product_id.trim()
      : null,
    entitlement_ids: extractStringList(event.entitlement_ids),
    environment: typeof event.environment === "string"
      ? event.environment.trim()
      : null,
    store: typeof event.store === "string" ? event.store.trim() : null,
    expiration_at_ms: typeof event.expiration_at_ms === "number"
      ? event.expiration_at_ms
      : null,
    purchased_at_ms: typeof event.purchased_at_ms === "number"
      ? event.purchased_at_ms
      : null,
    transferred_to: options.transferTo ??
      extractValidUuidList(event.transferred_to),
    transferred_from: options.transferFrom ??
      extractValidUuidList(event.transferred_from),
    processed_tier: options.processedTier ?? null,
    ignored_reason: options.ignoredReason ?? null,
  };
}

function buildRevenueEventPayload(
  event: Record<string, unknown>,
): Record<string, unknown> {
  return {
    ...buildWebhookLogPayload(event),
    revenuecat_event_id: optionalString(event.id),
    price_usd: normalizeNumber(event.price),
    price_in_purchased_currency: normalizeNumber(
      event.price_in_purchased_currency,
    ),
    currency: optionalString(event.currency),
    transaction_id: optionalString(event.transaction_id),
    event_timestamp_ms: normalizeNumber(event.event_timestamp_ms),
  };
}

async function recordRevenueEvent(
  supabase: SupabaseClient,
  event: Record<string, unknown>,
  eventType: string,
  userId: string,
  productId: string,
) {
  if (!REVENUE_EVENT_TYPES.has(eventType) || !productId) {
    return;
  }

  const eventTimestamp = normalizeTimestampMs(event.event_timestamp_ms) ??
    normalizeTimestampMs(event.purchased_at_ms) ??
    new Date().toISOString();

  const { error } = await supabase.from("revenue_events").insert({
    user_id: userId,
    event_type: eventType,
    product_id: productId,
    price_usd: normalizeNumber(event.price) ?? 0,
    currency: optionalString(event.currency),
    transaction_id: optionalString(event.transaction_id),
    event_timestamp: eventTimestamp,
    revenuecat_event_id: optionalString(event.id),
    raw_payload: buildRevenueEventPayload(event),
  });

  if (!error) {
    return;
  }

  if (error.code === "23505") {
    console.log(
      `Skipped duplicate revenue event ${
        optionalString(event.id) ?? eventType
      }`,
    );
    return;
  }

  console.error("Failed to record revenue event (non-fatal):", error);
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

function hasInvalidUuidList(value: unknown): boolean {
  if (value == null) return false;
  if (!Array.isArray(value)) return true;
  return value.some((item) =>
    typeof item !== "string" || !isValidUuid(item.trim())
  );
}

async function sha256Prefix(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("")
    .slice(0, 12);
}

Deno.serve(withOperationalErrorMonitoring("revenuecat-webhook", async (req) => {
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
    if (!type) {
      return jsonResponse({ error: "Invalid event type" }, 400);
    }

    const effectiveProductId =
      type === "PRODUCT_CHANGE" && typeof new_product_id === "string" &&
        new_product_id
        ? new_product_id
        : product_id;
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
          payload: buildWebhookLogPayload(event, {
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

    let newTier = "free";
    let shouldUpdate = false;
    let webhookStateEvent: StoreSubscriptionEventInput | null = null;

    switch (type) {
      case "INITIAL_PURCHASE":
      case "RENEWAL":
      case "UNCANCELLATION":
      case "SUBSCRIPTION_EXTENDED":
      case "PRODUCT_CHANGE":
      case "EXPIRATION":
      case "BILLING_ISSUE":
      case "CANCELLATION":
      case "SUBSCRIPTION_PAUSED": {
        const built = buildRevenueCatWebhookStoreEvent(type, event);
        if (built.kind === "ignored") {
          console.log(`Ignored ${type}: ${built.reason}`);
          break;
        }
        if (built.kind !== "event") {
          console.error(`Invalid ${type} store event: ${built.reason}`);
          return jsonResponse({ error: "Invalid event provenance" }, 400);
        }
        webhookStateEvent = built.event;
        newTier = built.event.tier as string;
        shouldUpdate = true;
        console.log(
          `Prepared ${type} for ${app_user_id} store=${built.event.store} tier=${newTier}`,
        );
        break;
      }

      case "NON_RENEWING_PURCHASE":
      case "SUBSCRIBER_ALIAS":
        console.log(`Event ${type} logged but no action taken`);
        shouldUpdate = false;
        break;

      case "TRANSFER": {
        const built = buildRevenueCatWebhookStoreEvent(type, event);
        if (built.kind !== "event") {
          return jsonResponse({ error: "Invalid transfer provenance" }, 400);
        }
        if (
          hasInvalidUuidList(event.transferred_from) ||
          hasInvalidUuidList(event.transferred_to)
        ) {
          return jsonResponse({ error: "Invalid transfer targets" }, 400);
        }
        const transferEvent = built.event;
        const transferTier = transferEvent.tier as string;
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
        const transferTargetIds = Array.from(
          new Set([...transferredTo, ...transferredFromOnly]),
        );
        const { data: transferUsers, error: transferUsersError } =
          await supabase
            .from("users")
            .select("id")
            .in("id", transferTargetIds);
        if (transferUsersError) {
          console.error(
            "Failed to validate transfer targets",
            transferUsersError,
          );
          return jsonResponse({ error: "Database error" }, 500);
        }
        const existingTransferUsers = new Set(
          (transferUsers ?? [])
            .map((row) => typeof row.id === "string" ? row.id : null)
            .filter((id): id is string => id !== null),
        );
        if (existingTransferUsers.size !== transferTargetIds.length) {
          return jsonResponse({ error: "Invalid transfer targets" }, 400);
        }

        for (const recipientId of transferredTo) {
          const result = await persistSubscriptionStoreState(
            supabase,
            recipientId,
            {
              ...transferEvent,
              tier: transferTier,
              status: "active",
            },
          );
          if (
            !result.accepted && result.reason !== "duplicate" &&
            result.reason !== "stale"
          ) {
            console.error("Failed to persist transfer recipient state", {
              recipientId,
              reason: result.reason,
            });
            return jsonResponse({ error: "Database error" }, 500);
          }
        }

        for (const sourceId of transferredFromOnly) {
          const result = await persistSubscriptionStoreState(
            supabase,
            sourceId,
            {
              ...transferEvent,
              tier: "free",
              status: "expired",
              expiresAt: transferEvent.expiresAt ?? transferEvent.eventAt,
            },
            { resetUsage: true },
          );
          if (
            !result.accepted && result.reason !== "duplicate" &&
            result.reason !== "stale"
          ) {
            console.error("Failed to persist transfer source state", {
              sourceId,
              reason: result.reason,
            });
            return jsonResponse({ error: "Database error" }, 500);
          }
        }

        console.log(
          `Processed transfer: tier=${transferTier}, to=${
            transferredTo.join(",")
          }, from=${transferredFromOnly.join(",")}`,
        );
        shouldUpdate = false;
        break;
      }

      default:
        console.log(`Unknown event type: ${type}`);
        shouldUpdate = false;
        break;
    }

    await recordRevenueEvent(
      supabase,
      event,
      type,
      app_user_id,
      effectiveProductId,
    );

    if (shouldUpdate) {
      if (webhookStateEvent == null) {
        return jsonResponse({ error: "Invalid event provenance" }, 400);
      }

      const result = await persistSubscriptionStoreState(
        supabase,
        app_user_id,
        webhookStateEvent,
        {
          resetUsage: type === "EXPIRATION",
        },
      );

      if (
        !result.accepted && result.reason !== "duplicate" &&
        result.reason !== "stale"
      ) {
        console.error("Failed to persist subscription store state", {
          userId: app_user_id,
          reason: result.reason,
        });
        return jsonResponse({ error: "Database error" }, 500);
      }

      console.log(
        `Successfully updated user ${app_user_id} to tier: ${newTier}`,
      );
    }

    const { error: logError } = await supabase.from("webhook_logs").insert({
      source: "revenuecat",
      event_type: type,
      user_id: app_user_id,
      payload: buildWebhookLogPayload(event, {
        processedTier: shouldUpdate ? newTier : undefined,
      }),
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
}));
