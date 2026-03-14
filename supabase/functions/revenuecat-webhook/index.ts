// supabase/functions/revenuecat-webhook/index.ts
// RevenueCat Webhook 處理器
// 接收訂閱事件並更新 Supabase 訂閱狀態

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// 從 product_id 判斷 tier
function getTierFromProductId(productId: string): string {
  if (!productId) return "free";
  if (productId.includes("essential")) return "essential";
  if (productId.includes("starter")) return "starter";
  return "free";
}

// 取得 tier 的額度限制
function getTierLimits(tier: string): { monthly: number; daily: number } {
  const limits: Record<string, { monthly: number; daily: number }> = {
    free: { monthly: 30, daily: 15 },
    starter: { monthly: 300, daily: 50 },
    essential: { monthly: 1000, daily: 150 },
  };
  return limits[tier] || limits.free;
}

Deno.serve(async (req) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    // 驗證 Authorization header (RevenueCat Webhook Secret)
    const authHeader = req.headers.get("Authorization");
    const webhookSecret = Deno.env.get("REVENUECAT_WEBHOOK_SECRET");

    if (webhookSecret && authHeader !== `Bearer ${webhookSecret}`) {
      console.error("Invalid webhook authorization");
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    const body = await req.json();
    console.log("RevenueCat webhook received:", JSON.stringify(body, null, 2));

    const { event } = body;
    if (!event) {
      return jsonResponse({ error: "No event in body" }, 400);
    }

    const {
      type,
      app_user_id,
      product_id,
      entitlement_ids,
      expiration_at_ms,
    } = event;

    console.log(`Event type: ${type}, User: ${app_user_id}, Product: ${product_id}`);

    // app_user_id 是我們在 RevenueCat.login() 時傳入的 Supabase user id
    if (!app_user_id || app_user_id.startsWith("$RCAnonymousID")) {
      console.log("Skipping anonymous user event");
      return jsonResponse({ success: true, message: "Skipped anonymous user" });
    }

    // 初始化 Supabase Admin Client
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // 根據事件類型處理
    let newTier = "free";
    let shouldUpdate = false;

    switch (type) {
      // 購買相關事件 - 升級 tier
      case "INITIAL_PURCHASE":
      case "RENEWAL":
      case "PRODUCT_CHANGE":
      case "UNCANCELLATION":
      case "SUBSCRIPTION_EXTENDED":
        newTier = getTierFromProductId(product_id);
        shouldUpdate = true;
        console.log(`Upgrading user ${app_user_id} to ${newTier}`);
        break;

      // 取消/過期相關事件 - 降級到 free
      case "EXPIRATION":
      case "BILLING_ISSUE":
        newTier = "free";
        shouldUpdate = true;
        console.log(`Downgrading user ${app_user_id} to free`);
        break;

      // 取消訂閱 - 不立即降級，等到過期
      case "CANCELLATION":
        // 用戶取消但訂閱還沒過期，不需要立即改變 tier
        // 只記錄取消狀態，等 EXPIRATION 事件再處理
        console.log(`User ${app_user_id} cancelled, will expire at ${expiration_at_ms}`);
        shouldUpdate = false;
        break;

      // 其他事件 - 記錄但不處理
      case "NON_RENEWING_PURCHASE":
      case "SUBSCRIBER_ALIAS":
      case "TRANSFER":
        console.log(`Event ${type} logged but no action taken`);
        shouldUpdate = false;
        break;

      default:
        console.log(`Unknown event type: ${type}`);
        shouldUpdate = false;
    }

    if (shouldUpdate) {
      const limits = getTierLimits(newTier);

      // 更新 subscriptions 表
      const { error: updateError } = await supabase
        .from("subscriptions")
        .update({
          tier: newTier,
          // 升級時不重置用量，讓用戶保留已使用的額度
          updated_at: new Date().toISOString(),
        })
        .eq("user_id", app_user_id);

      if (updateError) {
        console.error("Failed to update subscription:", updateError);

        // 如果找不到記錄，嘗試插入新記錄
        if (updateError.code === "PGRST116") {
          const { error: insertError } = await supabase
            .from("subscriptions")
            .insert({
              user_id: app_user_id,
              tier: newTier,
              monthly_messages_used: 0,
              daily_messages_used: 0,
              created_at: new Date().toISOString(),
              updated_at: new Date().toISOString(),
            });

          if (insertError) {
            console.error("Failed to insert subscription:", insertError);
            return jsonResponse({ error: "Database error" }, 500);
          }
        } else {
          return jsonResponse({ error: "Database error" }, 500);
        }
      }

      console.log(`Successfully updated user ${app_user_id} to tier: ${newTier}`);
    }

    // 記錄 webhook 事件到 logs 表（可選）
    try {
      await supabase.from("webhook_logs").insert({
        source: "revenuecat",
        event_type: type,
        user_id: app_user_id,
        payload: body,
        created_at: new Date().toISOString(),
      });
    } catch (logError) {
      // 記錄失敗不影響主流程
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
