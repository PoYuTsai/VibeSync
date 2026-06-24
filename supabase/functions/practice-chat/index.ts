// practice-chat Edge Function — AI 實戰練習室後端。
//
// 模擬對象女生（DeepSeek deepseek-v4-flash），真人手機聊天口吻。
// 一場練習 = 扣 1 則 Coach 額度，只在 session 第一則 AI 回覆成功時扣；失敗不扣。
// 一場最多 10 則 AI 回覆。debrief 模式產一張教練拆解卡，同場不另扣。
//
// 不改 coach-chat / analyze-chat；只共用 _shared/quota.ts。
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import {
  applyResetsIfNeeded,
  buildQuotaExceededPayload,
  checkQuota,
  resolveLimits,
  type SubscriptionRow,
  TEST_EMAILS,
} from "../_shared/quota.ts";
import { countAiTurns, validateRequest } from "./validate.ts";
import { buildChatMessages, buildDebriefMessages } from "./prompt.ts";
import {
  decideDeduction,
  isSessionComplete,
  PRACTICE_QUOTA_COST,
} from "./quota_decision.ts";
import { callDeepSeek, DEEPSEEK_MODEL } from "./deepseek.ts";
import { type DebriefCard, parseDebriefCard } from "./debrief_card.ts";
import { logError, logInfo, logWarn, summarizeUser } from "./logger.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const MAX_BODY_BYTES = 16 * 1024;
const CHAT_MAX_TOKENS = 200;
const CHAT_TEMPERATURE = 0.9;
const DEBRIEF_MAX_TOKENS = 500;
const DEBRIEF_TEMPERATURE = 0.5;
const DEEPSEEK_TIMEOUT_MS = 30000;

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "Authorization, Content-Type, x-client-info, apikey",
};

export function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

function getErrorMessage(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

function remainingFrom(
  sub: SubscriptionRow,
  limits: { monthly: number; daily: number },
  deducted: number,
): { monthlyRemaining: number; dailyRemaining: number } {
  return {
    monthlyRemaining: Math.max(
      0,
      limits.monthly - sub.monthly_messages_used - deducted,
    ),
    dailyRemaining: Math.max(
      0,
      limits.daily - sub.daily_messages_used - deducted,
    ),
  };
}

async function handleRequest(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  // ── auth ──
  const authHeader = req.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }
  const token = authHeader.slice(7);
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
    auth: { persistSession: false },
  });
  const { data: { user }, error: userError } = await supabase.auth.getUser(
    token,
  );
  if (userError || !user) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  // ── body ──
  const rawText = await req.text();
  if (rawText.length > MAX_BODY_BYTES) {
    return jsonResponse({ error: "request_body_too_large" }, 413);
  }
  let rawBody: unknown;
  try {
    rawBody = JSON.parse(rawText);
  } catch {
    return jsonResponse({ error: "invalid_request_body" }, 400);
  }

  let request;
  try {
    request = validateRequest(rawBody);
  } catch (e) {
    const msg = getErrorMessage(e);
    // 已達 10 則上限是預期狀態，回 409 讓前端引導去拆解卡。
    if (msg === "practice_session_complete") {
      return jsonResponse({ error: msg }, 409);
    }
    return jsonResponse({ error: msg }, 400);
  }

  const apiKey = Deno.env.get("DEEPSEEK_API_KEY");
  if (!apiKey) {
    logError("practice_chat_config_missing", { user: summarizeUser(user.id) });
    return jsonResponse({ error: "config_missing" }, 500);
  }

  // ── subscription + resets ──
  const { data: subRow, error: subError } = await supabase
    .from("subscriptions")
    .select(
      "tier, monthly_messages_used, daily_messages_used, daily_reset_at, monthly_reset_at",
    )
    .eq("user_id", user.id)
    .maybeSingle();
  if (subError) {
    logWarn("practice_chat_sub_fetch_error", {
      user: summarizeUser(user.id),
      error: subError.message,
    });
    return jsonResponse({ error: "subscription_fetch_failed" }, 500);
  }
  if (!subRow) {
    return jsonResponse({ error: "No subscription found" }, 403);
  }

  let sub = subRow as SubscriptionRow;
  const reset = applyResetsIfNeeded(sub, new Date());
  sub = reset.sub;
  if (reset.dailyReset || reset.monthlyReset) {
    await supabase
      .from("subscriptions")
      .update({
        daily_messages_used: sub.daily_messages_used,
        monthly_messages_used: sub.monthly_messages_used,
        daily_reset_at: sub.daily_reset_at,
        monthly_reset_at: sub.monthly_reset_at,
      })
      .eq("user_id", user.id);
  }

  const accountIsTest = TEST_EMAILS.includes(user.email || "");
  const limits = resolveLimits(sub.tier);
  const aiTurnCount = countAiTurns(request.turns);
  const { shouldDeduct } = decideDeduction({
    mode: request.mode,
    aiTurnCount,
    isTestAccount: accountIsTest,
  });

  // ── quota preflight（只有要扣點時才擋）──
  if (shouldDeduct) {
    const gate = checkQuota({
      sub,
      cost: PRACTICE_QUOTA_COST,
      isTestAccount: accountIsTest,
      monthlyLimit: limits.monthly,
      dailyLimit: limits.daily,
    });
    if (!gate.ok) {
      logWarn("practice_chat_quota_exceeded", {
        user: summarizeUser(user.id),
        reason: gate.reason,
      });
      return jsonResponse(
        buildQuotaExceededPayload({
          sub,
          cost: PRACTICE_QUOTA_COST,
          reason: gate.reason,
          monthlyLimit: limits.monthly,
          dailyLimit: limits.daily,
        }),
        429,
      );
    }
  }

  // ── DeepSeek 生成 ──
  let reply: string;
  let debriefCard: DebriefCard | null = null;
  try {
    if (request.mode === "chat") {
      reply = await callDeepSeek({
        apiKey,
        messages: buildChatMessages(request.turns),
        maxTokens: CHAT_MAX_TOKENS,
        temperature: CHAT_TEMPERATURE,
        timeoutMs: DEEPSEEK_TIMEOUT_MS,
      });
    } else {
      const rawCard = await callDeepSeek({
        apiKey,
        messages: buildDebriefMessages(request.turns),
        maxTokens: DEBRIEF_MAX_TOKENS,
        temperature: DEBRIEF_TEMPERATURE,
        jsonMode: true,
        timeoutMs: DEEPSEEK_TIMEOUT_MS,
      });
      debriefCard = parseDebriefCard(rawCard);
      reply = "";
    }
  } catch (e) {
    // API / format 失敗 → 未扣額度。
    logWarn("practice_chat_generation_failed", {
      user: summarizeUser(user.id),
      mode: request.mode,
      error: getErrorMessage(e),
    });
    return jsonResponse({ error: "practice_generation_failed" }, 500);
  }

  // ── 扣點（只在生成成功後）──
  let deducted = 0;
  if (shouldDeduct) {
    const { error: rpcError } = await supabase.rpc("increment_usage", {
      p_user_id: user.id,
      p_messages: PRACTICE_QUOTA_COST,
    });
    if (rpcError) {
      logWarn("practice_chat_deduct_db_error", {
        user: summarizeUser(user.id),
        error: rpcError.message,
      });
      return jsonResponse({ error: "credit_deduct_failed" }, 500);
    }
    deducted = PRACTICE_QUOTA_COST;
  }

  const remaining = remainingFrom(sub, limits, deducted);
  const generatedAt = new Date().toISOString();

  logInfo("practice_chat_succeeded", {
    user: summarizeUser(user.id),
    mode: request.mode,
    aiTurnCount,
    costDeducted: deducted,
  });

  if (request.mode === "debrief") {
    return jsonResponse({
      card: debriefCard,
      costDeducted: 0,
      provider: "deepseek",
      model: DEEPSEEK_MODEL,
      generatedAt,
      ...remaining,
    });
  }

  const nextAiTurnCount = aiTurnCount + 1;
  return jsonResponse({
    reply,
    aiTurnCount: nextAiTurnCount,
    sessionComplete: isSessionComplete(nextAiTurnCount),
    costDeducted: deducted,
    provider: "deepseek",
    model: DEEPSEEK_MODEL,
    generatedAt,
    ...remaining,
  });
}

serve(handleRequest);
