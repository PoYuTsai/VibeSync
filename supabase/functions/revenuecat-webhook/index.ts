// supabase/functions/revenuecat-webhook/index.ts
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// RevenueCat Webhook 事件類型
type RevenueCatEventType =
  | "INITIAL_PURCHASE"
  | "RENEWAL"
  | "CANCELLATION"
  | "UNCANCELLATION"
  | "EXPIRATION"
  | "BILLING_ISSUE"
  | "PRODUCT_CHANGE"
  | "SUBSCRIBER_ALIAS"
  | "TRANSFER";

interface RevenueCatEvent {
  api_version: string;
  event: {
    type: RevenueCatEventType;
    app_user_id: string;
    product_id: string;
    entitlement_ids?: string[];
    period_type?: string;
    purchased_at_ms?: number;
    expiration_at_ms?: number;
    environment?: string;
    original_app_user_id?: string;
  };
}

// CORS headers
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-revenuecat-authorization",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// JSON response helper
function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// 從 product_id 判斷 tier
function getTierFromProductId(productId: string): string {
  if (productId.includes("essential")) return "essential";
  if (productId.includes("starter")) return "starter";
  return "free";
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const body: RevenueCatEvent = await req.json();
    const { event } = body;

    console.log(
      `RevenueCat webhook: ${event.type} for user ${event.app_user_id}`
    );
    console.log(
      `   Product: ${event.product_id}, Environment: ${event.environment}`
    );

    // 建立 Supabase client (使用 service role 以繞過 RLS)
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // 根據事件類型處理
    switch (event.type) {
      case "INITIAL_PURCHASE":
      case "RENEWAL":
      case "UNCANCELLATION":
      case "PRODUCT_CHANGE": {
        // 新訂閱、續訂、取消後恢復、換方案
        const tier = getTierFromProductId(event.product_id);

        const { error } = await supabase
          .from("subscriptions")
          .update({
            tier,
            status: "active",
            rc_customer_id: event.original_app_user_id || event.app_user_id,
            rc_entitlement_id: event.entitlement_ids?.[0] || null,
            monthly_messages_used: 0, // 重置額度
            daily_messages_used: 0,
            monthly_reset_at: new Date().toISOString(),
            daily_reset_at: new Date().toISOString(),
            started_at: event.purchased_at_ms
              ? new Date(event.purchased_at_ms).toISOString()
              : new Date().toISOString(),
            expires_at: event.expiration_at_ms
              ? new Date(event.expiration_at_ms).toISOString()
              : null,
          })
          .eq("user_id", event.app_user_id);

        if (error) {
          console.error("Update subscription error:", error);
          return jsonResponse({ error: error.message }, 500);
        }

        console.log(`Subscription updated: ${event.app_user_id} -> ${tier}`);
        break;
      }

      case "CANCELLATION": {
        // 用戶取消訂閱（但還沒到期）
        const { error } = await supabase
          .from("subscriptions")
          .update({
            status: "cancelled",
          })
          .eq("user_id", event.app_user_id);

        if (error) {
          console.error("Update cancellation error:", error);
          return jsonResponse({ error: error.message }, 500);
        }

        console.log(`Subscription cancelled: ${event.app_user_id}`);
        break;
      }

      case "EXPIRATION": {
        // 訂閱到期，降級為 Free
        const { error } = await supabase
          .from("subscriptions")
          .update({
            tier: "free",
            status: "expired",
            monthly_messages_used: 0,
            daily_messages_used: 0,
          })
          .eq("user_id", event.app_user_id);

        if (error) {
          console.error("Update expiration error:", error);
          return jsonResponse({ error: error.message }, 500);
        }

        console.log(`Subscription expired: ${event.app_user_id} -> free`);
        break;
      }

      case "BILLING_ISSUE": {
        // 付款問題
        const { error } = await supabase
          .from("subscriptions")
          .update({
            status: "billing_issue",
          })
          .eq("user_id", event.app_user_id);

        if (error) {
          console.error("Update billing issue error:", error);
          return jsonResponse({ error: error.message }, 500);
        }

        console.log(`Billing issue: ${event.app_user_id}`);
        break;
      }

      default:
        console.log(`Unhandled event type: ${event.type}`);
    }

    return jsonResponse({ success: true });
  } catch (error) {
    console.error("Webhook error:", error);
    return jsonResponse({ error: String(error) }, 500);
  }
});
