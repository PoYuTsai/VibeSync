// supabase/functions/submit-feedback/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const TELEGRAM_BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN");
const TELEGRAM_CHAT_ID = Deno.env.get("TELEGRAM_CHAT_ID");
const VALID_CATEGORIES = new Set([
  "too_direct",
  "too_long",
  "unnatural",
  "wrong_style",
  "other",
]);
const COMMENT_MAX_LENGTH = 2000;
const SNIPPET_MAX_LENGTH = 4000;
const MODEL_MAX_LENGTH = 120;
const USER_TIER_MAX_LENGTH = 50;
const AI_RESPONSE_MAX_LENGTH = 12000;
const TELEGRAM_COMMENT_PREVIEW = 300;
const TELEGRAM_SNIPPET_PREVIEW = 500;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization, Content-Type, x-client-info, apikey",
};

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

function normalizeOptionalString(value: unknown, maxLength: number): string | undefined {
  if (typeof value !== "string") return undefined;

  const normalized = value.trim();
  if (!normalized) return undefined;

  if (normalized.length > maxLength) {
    throw new Error(`STRING_TOO_LONG:${maxLength}`);
  }

  return normalized;
}

function truncateForPreview(value: string, maxLength: number): string {
  return value.length > maxLength ? `${value.slice(0, maxLength)}...` : value;
}

async function sendTelegramNotification(feedback: {
  userEmail: string;
  userTier: string;
  rating: string;
  category?: string;
  comment?: string;
  conversationSnippet?: string;
  aiResponse?: Record<string, unknown>;
  modelUsed?: string;
}) {
  if (!TELEGRAM_BOT_TOKEN || !TELEGRAM_CHAT_ID) {
    console.warn("Telegram credentials not configured");
    return;
  }

  // 只有負面反饋才發通知
  if (feedback.rating !== "negative") return;

  const categoryLabels: Record<string, string> = {
    too_direct: "太直接/不自然",
    too_long: "回覆太長",
    unnatural: "聽起來像機器人",
    wrong_style: "不符合我的風格",
    other: "其他",
  };

  // 遮蔽 email
  const maskedEmail = feedback.userEmail.replace(/(.{2})(.*)(@.*)/, "$1***$3");

  let message = `🔴 新的負面反饋\n\n`;
  message += `用戶：${maskedEmail} (${feedback.userTier})\n`;
  message += `問題類型：${categoryLabels[feedback.category || "other"] || feedback.category}\n`;

  if (feedback.comment) {
    message += `補充：「${truncateForPreview(feedback.comment, TELEGRAM_COMMENT_PREVIEW)}」\n`;
  }

  if (feedback.conversationSnippet) {
    message += `\n📝 對話片段：\n${truncateForPreview(feedback.conversationSnippet, TELEGRAM_SNIPPET_PREVIEW)}\n`;
  }

  if (feedback.aiResponse?.finalRecommendation) {
    const rec = feedback.aiResponse.finalRecommendation as Record<string, string>;
    message += `\n🤖 AI 推薦回覆：\n${rec.pick}: 「${rec.content}」\n`;
  }

  message += `\nModel: ${feedback.modelUsed || "unknown"}`;
  message += `\nTime: ${new Date().toISOString()}`;

  try {
    await fetch(`https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: TELEGRAM_CHAT_ID,
        text: message,
      }),
    });
  } catch (error) {
    console.error("Failed to send Telegram notification:", error);
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Verify auth
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: authError } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return jsonResponse({ error: "Invalid token" }, 401);
    }

    // Parse request
    const body = await req.json();
    const rating = body?.rating;
    const category = body?.category;
    const comment = normalizeOptionalString(body?.comment, COMMENT_MAX_LENGTH);
    const conversationSnippet = normalizeOptionalString(body?.conversationSnippet, SNIPPET_MAX_LENGTH);
    const userTier = normalizeOptionalString(body?.userTier, USER_TIER_MAX_LENGTH);
    const modelUsed = normalizeOptionalString(body?.modelUsed, MODEL_MAX_LENGTH);
    const aiResponse = body?.aiResponse;

    if (!rating || !["positive", "negative"].includes(rating)) {
      return jsonResponse({ error: "Invalid rating" }, 400);
    }

    if (category != null && (typeof category !== "string" || !VALID_CATEGORIES.has(category))) {
      return jsonResponse({ error: "Invalid category" }, 400);
    }

    if (aiResponse != null && (typeof aiResponse !== "object" || Array.isArray(aiResponse))) {
      return jsonResponse({ error: "Invalid aiResponse" }, 400);
    }

    if (aiResponse != null && JSON.stringify(aiResponse).length > AI_RESPONSE_MAX_LENGTH) {
      return jsonResponse({ error: "aiResponse too large" }, 400);
    }

    // Insert feedback
    const { error: insertError } = await supabase.from("feedback").insert({
      user_id: user.id,
      rating,
      category,
      comment,
      conversation_snippet: conversationSnippet,
      ai_response: aiResponse,
      user_tier: userTier,
      model_used: modelUsed,
    });

    if (insertError) {
      console.error("Insert error:", insertError);
      return jsonResponse({ error: "Failed to save feedback" }, 500);
    }

    // Send Telegram notification for negative feedback
    await sendTelegramNotification({
      userEmail: user.email || "unknown",
      userTier: userTier || "unknown",
      rating,
      category,
      comment,
      conversationSnippet,
      aiResponse,
      modelUsed,
    });

    return jsonResponse({ success: true });
  } catch (error) {
    if (error instanceof Error && error.message.startsWith("STRING_TOO_LONG:")) {
      const maxLength = error.message.split(":")[1];
      return jsonResponse({ error: `Text field exceeds maximum length (${maxLength})` }, 400);
    }
    console.error("Error:", error);
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
