// supabase/functions/submit-feedback/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import {
  AI_RESPONSE_MAX_LENGTH,
  buildDiscordNotificationContent,
  isPlainObject,
  normalizeOptionalString,
  sanitizeFeedbackAiResponse,
  stripBearer,
} from "./feedback_utils.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const DISCORD_FEEDBACK_WEBHOOK_URL =
  Deno.env.get("DISCORD_FEEDBACK_WEBHOOK_URL") ??
    Deno.env.get("DISCORD_WEBHOOK_URL");
const DISCORD_BOT_TOKEN = Deno.env.get("DISCORD_BOT_TOKEN")?.replace(
  /^Bot\s+/i,
  "",
).trim();
const DISCORD_FEEDBACK_CHANNEL_ID =
  Deno.env.get("DISCORD_FEEDBACK_CHANNEL_ID") ??
    Deno.env.get("DISCORD_CHANNEL_ID");

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
const DISCORD_COMMENT_PREVIEW = 300;
const DISCORD_SNIPPET_PREVIEW = 500;

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

async function sendDiscordNotification(feedback: {
  userEmail: string;
  userTier: string;
  rating: string;
  category?: string;
  comment?: string;
  conversationSnippet?: string;
  aiResponse?: Record<string, unknown>;
  modelUsed?: string;
}) {
  if (!DISCORD_FEEDBACK_WEBHOOK_URL) {
    console.warn("Discord feedback webhook not configured");
    return;
  }

  if (feedback.rating !== "negative") {
    return;
  }

  const content = buildDiscordNotificationContent(feedback, {
    commentPreviewLength: DISCORD_COMMENT_PREVIEW,
    snippetPreviewLength: DISCORD_SNIPPET_PREVIEW,
  });

  try {
    if (DISCORD_FEEDBACK_WEBHOOK_URL) {
      const response = await fetch(
        DISCORD_FEEDBACK_WEBHOOK_URL,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            content,
            username: "VibeSync Feedback",
          }),
        },
      );

      if (!response.ok) {
        const responseText = await response.text();
        console.error(
          "Discord webhook notification failed:",
          response.status,
          responseText,
        );
      }

      return;
    }

    if (!DISCORD_BOT_TOKEN || !DISCORD_FEEDBACK_CHANNEL_ID) {
      console.warn("Discord notification not configured");
      return;
    }

    const response = await fetch(
      `https://discord.com/api/v10/channels/${DISCORD_FEEDBACK_CHANNEL_ID}/messages`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bot ${DISCORD_BOT_TOKEN}`,
        },
        body: JSON.stringify({
          content,
        }),
      },
    );

    if (!response.ok) {
      const responseText = await response.text();
      console.error(
        "Discord bot notification failed:",
        response.status,
        responseText,
      );
    }
  } catch (error) {
    console.error("Failed to send Discord notification:", error);
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
    const aiResponse = sanitizeFeedbackAiResponse(rawAiResponse);

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

    await sendDiscordNotification({
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
