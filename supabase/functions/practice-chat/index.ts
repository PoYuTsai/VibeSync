// practice-chat Edge Function — AI 實戰練習室後端。
//
// 模擬對象女生（DeepSeek deepseek-v4-flash），真人手機聊天口吻。
// 一場練習 = 扣 1 則 Coach 額度，只在 session 第一則 AI 回覆成功時扣；失敗不扣。
// 一場最多 10 則 AI 回覆。debrief 模式產一張教練拆解卡，同場不另扣。
//
// 安全模型（Codex 2026-06-24 BLOCKER 修復）：扣費與 10 則上限**一律以 server-side
// ledger（practice_chat_sessions）為準**，絕不信任 client 送的 turns。turns 只當
// prompt 資料；漏洞⑤（偽造 assistant 訊息越獄）由 prompt 硬化（見 prompt.ts）防。
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
import { validateRequest } from "./validate.ts";
import { buildChatMessages, buildDebriefMessages } from "./prompt.ts";
import {
  decideChatGate,
  decideDebriefGate,
  isSessionComplete,
  MAX_AI_REPLIES,
  MAX_DEBRIEFS,
  PRACTICE_QUOTA_COST,
  type SessionLedger,
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

/** 把 ledger RPC 的 RAISE 訊息映射成 client 狀態碼。 */
function mapLedgerError(message: string): { error: string; status: number } {
  if (message.includes("PRACTICE_SESSION_COMPLETE")) {
    return { error: "practice_session_complete", status: 409 };
  }
  if (message.includes("PRACTICE_SESSION_NOT_STARTED")) {
    return { error: "practice_session_not_started", status: 403 };
  }
  if (message.includes("PRACTICE_DEBRIEF_LIMIT")) {
    return { error: "practice_debrief_limit", status: 403 };
  }
  return { error: "session_state_failed", status: 500 };
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
    return jsonResponse({ error: getErrorMessage(e) }, 400);
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

  // ── server-side ledger preflight（權威狀態，不信任 client turns）──
  const { data: ledgerRow, error: ledgerError } = await supabase
    .from("practice_chat_sessions")
    .select("ai_count, charged, debrief_count")
    .eq("user_id", user.id)
    .eq("session_id", request.sessionId)
    .maybeSingle();
  if (ledgerError) {
    logWarn("practice_chat_ledger_fetch_error", {
      user: summarizeUser(user.id),
      error: ledgerError.message,
    });
    return jsonResponse({ error: "session_state_failed" }, 500);
  }
  const ledger: SessionLedger = {
    exists: !!ledgerRow,
    aiCount: (ledgerRow?.ai_count as number | undefined) ?? 0,
    charged: (ledgerRow?.charged as boolean | undefined) ?? false,
    debriefCount: (ledgerRow?.debrief_count as number | undefined) ?? 0,
  };

  // ── debrief 分支 ─────────────────────────────────────────────────
  if (request.mode === "debrief") {
    const gate = decideDebriefGate({ ledger });
    if (!gate.allowed) {
      logWarn("practice_chat_debrief_rejected", {
        user: summarizeUser(user.id),
        reason: gate.reason,
      });
      return jsonResponse({ error: gate.reason }, 403);
    }

    // 先 claim（原子預約 debrief 名額）再生成：claim_practice_debrief 在 FOR UPDATE
    // 下遞增 debrief_count，並發請求也只有 MAX_DEBRIEFS 個能通過，把 DeepSeek 成本
    // 硬界在上限內（Codex P2）。debrief 不扣 quota，故預約後生成失敗的代價僅是消耗
    // 一個免費名額（上限 3，可接受），換取 provider 花費被 server 權威界住。
    const { error: claimError } = await supabase.rpc("claim_practice_debrief", {
      p_user_id: user.id,
      p_session_id: request.sessionId,
      p_max_debriefs: MAX_DEBRIEFS,
    });
    if (claimError) {
      const mapped = mapLedgerError(claimError.message);
      logWarn("practice_chat_debrief_claim_failed", {
        user: summarizeUser(user.id),
        error: claimError.message,
      });
      return jsonResponse({ error: mapped.error }, mapped.status);
    }

    let debriefCard: DebriefCard;
    try {
      const rawCard = await callDeepSeek({
        apiKey,
        messages: buildDebriefMessages(request.turns, request.profile),
        maxTokens: DEBRIEF_MAX_TOKENS,
        temperature: DEBRIEF_TEMPERATURE,
        jsonMode: true,
        timeoutMs: DEEPSEEK_TIMEOUT_MS,
      });
      debriefCard = parseDebriefCard(rawCard);
    } catch (e) {
      // 預約已消耗一個 debrief 名額；debrief 不扣 quota，符合成本上限優先的取捨。
      logWarn("practice_chat_generation_failed", {
        user: summarizeUser(user.id),
        mode: "debrief",
        personaId: request.profile.personaId,
        difficulty: request.profile.difficulty,
        error: getErrorMessage(e),
      });
      return jsonResponse({ error: "practice_generation_failed" }, 500);
    }

    logInfo("practice_chat_succeeded", {
      user: summarizeUser(user.id),
      mode: "debrief",
      personaId: request.profile.personaId,
      difficulty: request.profile.difficulty,
      costDeducted: 0,
    });
    return jsonResponse({
      card: debriefCard,
      costDeducted: 0,
      provider: "deepseek",
      model: DEEPSEEK_MODEL,
      generatedAt: new Date().toISOString(),
      ...remainingFrom(sub, limits, 0),
    });
  }

  // ── chat 分支 ────────────────────────────────────────────────────
  const { atCap, shouldChargePreview } = decideChatGate({
    ledger,
    isTestAccount: accountIsTest,
  });
  if (atCap) {
    // 已達 10 則上限：引導前端去拆解卡。
    return jsonResponse({ error: "practice_session_complete" }, 409);
  }

  // 只有「本場尚未扣費且非測試帳號」才做 quota 429 preflight。
  if (shouldChargePreview) {
    const quotaGate = checkQuota({
      sub,
      cost: PRACTICE_QUOTA_COST,
      isTestAccount: accountIsTest,
      monthlyLimit: limits.monthly,
      dailyLimit: limits.daily,
    });
    if (!quotaGate.ok) {
      logWarn("practice_chat_quota_exceeded", {
        user: summarizeUser(user.id),
        reason: quotaGate.reason,
      });
      return jsonResponse(
        buildQuotaExceededPayload({
          sub,
          cost: PRACTICE_QUOTA_COST,
          reason: quotaGate.reason,
          monthlyLimit: limits.monthly,
          dailyLimit: limits.daily,
        }),
        429,
      );
    }
  }

  // ── DeepSeek 生成 ──
  let reply: string;
  try {
    reply = await callDeepSeek({
      apiKey,
      messages: buildChatMessages(request.turns, request.profile),
      maxTokens: CHAT_MAX_TOKENS,
      temperature: CHAT_TEMPERATURE,
      timeoutMs: DEEPSEEK_TIMEOUT_MS,
    });
  } catch (e) {
    // API / format 失敗 → 未 commit、未扣額度。
    logWarn("practice_chat_generation_failed", {
      user: summarizeUser(user.id),
      mode: "chat",
      personaId: request.profile.personaId,
      difficulty: request.profile.difficulty,
      error: getErrorMessage(e),
    });
    return jsonResponse({ error: "practice_generation_failed" }, 500);
  }

  // ── 生成成功後才原子 commit（結算扣費 + ai_count 遞增，FOR UPDATE 重判上限）──
  const { data: commitData, error: commitError } = await supabase.rpc(
    "commit_practice_chat_turn",
    {
      p_user_id: user.id,
      p_session_id: request.sessionId,
      p_charge_quota: !accountIsTest,
      p_max_replies: MAX_AI_REPLIES,
    },
  );
  if (commitError) {
    const mapped = mapLedgerError(commitError.message);
    logWarn("practice_chat_commit_failed", {
      user: summarizeUser(user.id),
      error: commitError.message,
    });
    return jsonResponse({ error: mapped.error }, mapped.status);
  }
  const commitRow = Array.isArray(commitData) ? commitData[0] : commitData;
  const newAiCount = (commitRow?.new_ai_count as number | undefined) ?? 0;
  const didCharge = (commitRow?.did_charge as boolean | undefined) ?? false;
  const deducted = didCharge ? PRACTICE_QUOTA_COST : 0;

  logInfo("practice_chat_succeeded", {
    user: summarizeUser(user.id),
    mode: "chat",
    aiTurnCount: newAiCount,
    personaId: request.profile.personaId,
    difficulty: request.profile.difficulty,
    costDeducted: deducted,
  });
  return jsonResponse({
    reply,
    aiTurnCount: newAiCount,
    sessionComplete: isSessionComplete(newAiCount),
    costDeducted: deducted,
    provider: "deepseek",
    model: DEEPSEEK_MODEL,
    generatedAt: new Date().toISOString(),
    ...remainingFrom(sub, limits, deducted),
  });
}

serve(handleRequest);
