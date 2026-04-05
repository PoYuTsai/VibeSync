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

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "Authorization, Content-Type, x-client-info, apikey",
};

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

function normalizeOptionalString(
  value: unknown,
  maxLength: number,
): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }

  const normalized = value.trim();
  if (!normalized) {
    return undefined;
  }

  if (normalized.length > maxLength) {
    throw new Error(`STRING_TOO_LONG:${maxLength}`);
  }

  return normalized;
}

function truncateForPreview(value: string, maxLength: number): string {
  return value.length > maxLength ? `${value.slice(0, maxLength)}...` : value;
}

function stripBearer(value: string): string {
  return value.trim().replace(/^Bearer\s+/i, "");
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

async function sendTelegramNotification(feedback: {
  userEmail: string;
  userTier: string;
  rating: string;
  category?: string;
  comment?: string;
  modelUsed?: string;
}) {
  if (!TELEGRAM_BOT_TOKEN || !TELEGRAM_CHAT_ID) {
    console.warn("Telegram credentials not configured");
    return;
  }

  if (feedback.rating !== "negative") {
    return;
  }

  const categoryLabels: Record<string, string> = {
    too_direct: "Too direct",
    too_long: "Too long",
    unnatural: "Unnatural",
    wrong_style: "Wrong style",
    other: "Other",
  };

  const maskedEmail = feedback.userEmail.replace(/(.{2})(.*)(@.*)/, "$1***$3");
  const messageParts: string[] = [
    "Negative feedback received\n\n",
    `User: ${maskedEmail} (${feedback.userTier})\n`,
    `Category: ${
      categoryLabels[feedback.category || "other"] || feedback.category
    }\n`,
  ];

  if (feedback.comment) {
    messageParts.push(
      `Comment: "${
        truncateForPreview(feedback.comment, TELEGRAM_COMMENT_PREVIEW)
      }"\n`,
    );
  }

  let message = messageParts.join("");
  message += `\nModel: ${feedback.modelUsed || "unknown"}`;
  message += `\nTime: ${new Date().toISOString()}`;

  try {
    const response = await fetch(
      `https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          chat_id: TELEGRAM_CHAT_ID,
          text: message,
        }),
      },
    );

    if (!response.ok) {
      const responseText = await response.text();
      console.error(
        "Telegram notification failed:",
        response.status,
        responseText,
      );
    }
  } catch (error) {
    console.error("Failed to send Telegram notification:", error);
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !/^Bearer\s+\S+/i.test(authHeader)) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const token = stripBearer(authHeader);
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return jsonResponse({ error: "Invalid token" }, 401);
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

    const rawRating = body.rating;
    const rawCategory = body.category;
    const rawAiResponse = body.aiResponse;

    if (
      typeof rawRating !== "string" ||
      !["positive", "negative"].includes(rawRating)
    ) {
      return jsonResponse({ error: "Invalid rating" }, 400);
    }

    if (
      rawCategory != null &&
      (typeof rawCategory !== "string" || !VALID_CATEGORIES.has(rawCategory))
    ) {
      return jsonResponse({ error: "Invalid category" }, 400);
    }

    if (rawAiResponse != null && !isPlainObject(rawAiResponse)) {
      return jsonResponse({ error: "Invalid aiResponse" }, 400);
    }

    const rating = rawRating;
    const category = typeof rawCategory === "string" ? rawCategory : undefined;
    const comment = normalizeOptionalString(body?.comment, COMMENT_MAX_LENGTH);
    const conversationSnippet = normalizeOptionalString(
      body?.conversationSnippet,
      SNIPPET_MAX_LENGTH,
    );
    const userTier = normalizeOptionalString(
      body?.userTier,
      USER_TIER_MAX_LENGTH,
    );
    const modelUsed = normalizeOptionalString(
      body?.modelUsed,
      MODEL_MAX_LENGTH,
    );
    const aiResponse = isPlainObject(rawAiResponse) ? rawAiResponse : undefined;

    if (
      aiResponse != null &&
      JSON.stringify(aiResponse).length > AI_RESPONSE_MAX_LENGTH
    ) {
      return jsonResponse({ error: "aiResponse too large" }, 400);
    }

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

    await sendTelegramNotification({
      userEmail: user.email || "unknown",
      userTier: userTier || "unknown",
      rating,
      category,
      comment,
      modelUsed,
    });

    return jsonResponse({ success: true });
  } catch (error) {
    if (
      error instanceof Error && error.message.startsWith("STRING_TOO_LONG:")
    ) {
      const maxLength = error.message.split(":")[1];
      return jsonResponse(
        { error: `Text field exceeds maximum length (${maxLength})` },
        400,
      );
    }

    console.error("Error:", error);
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
