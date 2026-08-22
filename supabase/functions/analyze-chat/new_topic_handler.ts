// NewTopic handler：破冰腦力（2026-07-24 計畫 §10.5）。
// 固定順序：sanitize→material→config→HMAC preflight→claim→quota(3)→
// rate limit→renew→generate(45s)→validate/project→settle(5s reserve)。
// Handler 永遠只回 settlement 的 stored result，本地候選一律丟棄。
// 2026-08-18 stream（transport-only）：模型輸出契約不變，僅逐塊接收＋進度事件。

import { enforceModelRateLimit } from "../_shared/model_rate_limit.ts";
import {
  AiServiceError,
  callClaudeWithFallback,
  extractClaudeText,
  type FallbackResult,
} from "./fallback.ts";
import {
  AiStreamingServiceError,
  callClaudeStreaming,
} from "./streaming_fallback.ts";
import { ndjsonStreamResponse } from "./ndjson_response.ts";
import {
  createStreamStageTracker,
  emitJsonResponseAsStreamOutcome,
  NEW_TOPIC_STREAM_STAGES,
} from "./opener_stream.ts";
import {
  claimNewTopicRequest,
  classifyNewTopicReplayPreflight,
  computeNewTopicInputHash,
  isStrongNewTopicReplayHmacKey,
  newTopicReplayCutoffIso,
  type NewTopicReplayRow,
  releaseNewTopicClaim,
  settleNewTopicRequest,
} from "./new_topic_billing.ts";
import {
  allowsNewTopicSharedFrame,
  buildNewTopicLedgerResult,
  hasNewTopicMaterial,
  mergeNewTopicRepairWithPrimaryOpeningLines,
  normalizeNewTopicModelPayload,
  sanitizeNewTopicRequest,
} from "./new_topic_payload.ts";
import {
  buildNewTopicRepairPrompt,
  buildNewTopicUserPrompt,
  NEW_TOPIC_GENERATION_DEADLINE_MS,
  NEW_TOPIC_MAX_TOKENS,
  NEW_TOPIC_PROMPT,
  NEW_TOPIC_REPAIR_PROMPT,
  NEW_TOPIC_REQUEST_DEADLINE_MS,
} from "./new_topic_prompt.ts";
import { hasAnalyzeChatPromptLeak } from "./prompt_leak.ts";
import {
  getErrorMessage,
  logError,
  logInfo,
  logWarn,
  summarizeUser,
} from "./logger.ts";
import { corsHeaders, jsonResponse } from "./http_response.ts";
import { parseJsonObjectFromText } from "./json_text.ts";
import {
  normalizeSubscriptionTier,
  type TierSyncRefreshStatus,
} from "./tier_sync_contract.ts";

export interface NewTopicQuotaView {
  // deno-lint-ignore no-explicit-any
  sub: any;
  monthlyLimit: number;
  dailyLimit: number;
  effectiveTier: string;
}

export interface NewTopicHandlerDeps {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  userId: string;
  requestBody: Record<string, unknown>;
  responseMode: "legacy" | "stream";
  requestStartedAtMs: number;
  accountIsTest: boolean;
  claudeApiKey: string;
  refreshTierFromRevenueCat: (
    reason: string,
  ) => Promise<TierSyncRefreshStatus>;
  /// 額度視圖 getter：RevenueCat refresh 會改寫 handler 端的 sub 與上限，
  /// 每次讀取都必須取當下值，不得快照。
  quota: () => NewTopicQuotaView;
}

export async function handleNewTopicRequest(
  deps: NewTopicHandlerDeps,
): Promise<Response> {
  const quota = deps.quota;
  const newTopicDeadlineAtMs = deps.requestStartedAtMs +
    NEW_TOPIC_REQUEST_DEADLINE_MS;
  const newTopicGenerationDeadlineAtMs = deps.requestStartedAtMs +
    NEW_TOPIC_GENERATION_DEADLINE_MS;

  // 1. Strict allowlist sanitize＋material readiness：全部發生在 claim、
  //    rate limit、模型與扣費之前（400/422 路徑扣 0、不佔限流名額）。
  //    2026-08-18：stream 模式放行；flag off 時
  //    stream 靜默降級 legacy，client 依 content-type 相容。
  if (deps.responseMode !== "legacy" && deps.responseMode !== "stream") {
    return jsonResponse({
      error: "NEW_TOPIC_REQUEST_INVALID",
      code: "NEW_TOPIC_REQUEST_INVALID",
      message:
        "新話題暫不支援這種回應模式，請更新 App 後再試。本次不會扣額度。",
      shouldChargeQuota: false,
    }, 400);
  }
  const newTopicStreamRequested = deps.responseMode === "stream" &&
    Deno.env.get("OPENER_STREAM_ENABLED") === "true";
  if (deps.responseMode === "stream" && !newTopicStreamRequested) {
    logInfo("new_topic_stream_fell_back_to_legacy", {
      user: summarizeUser(deps.userId),
    });
  }
  const newTopicSanitize = sanitizeNewTopicRequest(
    deps.requestBody,
  );
  if (!newTopicSanitize.ok) {
    logWarn("new_topic_request_invalid", {
      user: summarizeUser(deps.userId),
      reason: newTopicSanitize.reason,
    });
    return jsonResponse({
      error: "NEW_TOPIC_REQUEST_INVALID",
      code: "NEW_TOPIC_REQUEST_INVALID",
      message: "新話題請求格式異常，請更新 App 後再試。本次不會扣額度。",
      shouldChargeQuota: false,
    }, 400);
  }
  const newTopicRequest = newTopicSanitize.request;
  if (!hasNewTopicMaterial(newTopicRequest)) {
    return jsonResponse({
      error: "NEW_TOPIC_CONTEXT_REQUIRED",
      code: "NEW_TOPIC_CONTEXT_REQUIRED",
      message:
        "請先提供對象作戰板、關於我或目前狀況其中一項，才能生成新話題。本次不會扣額度。",
      shouldChargeQuota: false,
    }, 422);
  }
  // §14.1 telemetry：合法請求受理（sanitize＋material 過）才記，
  // 400/422 拒絕不佔 received 計數。
  logInfo("new_topic_request_received", {
    user: summarizeUser(deps.userId),
    requestId: newTopicRequest.requestId,
    situation: newTopicRequest.situation,
    hasPartnerSummary: newTopicRequest.partnerSummary !== null,
    hasStyleContext: newTopicRequest.effectiveStyleContext !== null,
  });

  // 2. Config：模型金鑰＋new-topic-only HMAC secret。缺 secret 只有
  //    new_topic fail closed，opener/analyze/OCR 不受影響。config 缺失
  //    絕不能發生在 claim 之後（會留 pending claim 卡同 requestId）。
  const newTopicHmacSecret = Deno.env.get("NEW_TOPIC_REPLAY_HMAC_KEY");
  if (!isStrongNewTopicReplayHmacKey(newTopicHmacSecret)) {
    logError("new_topic_config_missing", {
      user: summarizeUser(deps.userId),
      missing: "NEW_TOPIC_REPLAY_HMAC_KEY",
    });
    return jsonResponse({
      error: "NEW_TOPIC_REPLAY_NOT_CONFIGURED",
      code: "NEW_TOPIC_REPLAY_NOT_CONFIGURED",
      message: "新話題功能暫時無法使用，請稍後再試。本次不會扣額度。",
      retryable: true,
      shouldChargeQuota: false,
    }, 503);
  }
  if (!deps.claudeApiKey) {
    logError("new_topic_config_missing", {
      user: summarizeUser(deps.userId),
      missing: "CLAUDE_API_KEY",
    });
    return jsonResponse({
      error: "NEW_TOPIC_REPLAY_NOT_CONFIGURED",
      code: "NEW_TOPIC_REPLAY_NOT_CONFIGURED",
      message: "新話題功能暫時無法使用，請稍後再試。本次不會扣額度。",
      retryable: true,
      shouldChargeQuota: false,
    }, 503);
  }

  // 3. Server-keyed HMAC＋24h replay preflight（ledger read fail-closed）。
  const newTopicInputHash = await computeNewTopicInputHash({
    userId: deps.userId,
    partnerSummary: newTopicRequest.partnerSummary,
    effectiveStyleContext: newTopicRequest.effectiveStyleContext,
    situation: newTopicRequest.situation,
    secret: newTopicHmacSecret,
  });
  const newTopicSuccessBody = (
    result: Record<string, unknown>,
  ): Record<string, unknown> => ({
    // Fresh 與 replay 完全一致：stored result＋常數 usage.cost=3。
    // charged/replayed 只進 server telemetry，不外露（§5.6）。
    ...result,
    usage: { cost: 3 },
  });
  {
    const { data: replayRow, error: replayReadError } = await deps.supabase
      .from("new_topic_requests")
      .select("input_hash, state, lease_expires_at, result_json")
      .eq("user_id", deps.userId)
      .eq("request_id", newTopicRequest.requestId)
      .gte("created_at", newTopicReplayCutoffIso())
      .maybeSingle();
    if (replayReadError) {
      logError("new_topic_replay_preflight_read_failed", {
        user: summarizeUser(deps.userId),
        error: replayReadError.message,
      });
      return jsonResponse({
        error: "NEW_TOPIC_REPLAY_UNAVAILABLE",
        code: "NEW_TOPIC_REPLAY_UNAVAILABLE",
        message: "新話題服務暫時無法確認請求狀態，請稍後用同一筆請求重試。",
        retryable: true,
        shouldChargeQuota: false,
      }, 503);
    }
    const preflight = classifyNewTopicReplayPreflight(
      replayRow as NewTopicReplayRow | null,
      newTopicInputHash,
    );
    if (preflight.kind === "mismatch") {
      return jsonResponse({
        error: "NEW_TOPIC_REQUEST_REPLAY_MISMATCH",
        code: "NEW_TOPIC_REQUEST_REPLAY_MISMATCH",
        message: "這筆請求編號已用於不同內容，請重新生成一次。本次不會扣額度。",
        shouldChargeQuota: false,
      }, 409);
    }
    if (preflight.kind === "pending") {
      logInfo("new_topic_request_pending", {
        user: summarizeUser(deps.userId),
        requestId: newTopicRequest.requestId,
        stage: "preflight",
        retryAfterMs: preflight.retryAfterMs,
      });
      return jsonResponse({
        error: "NEW_TOPIC_REQUEST_IN_PROGRESS",
        code: "NEW_TOPIC_REQUEST_IN_PROGRESS",
        message: "這筆請求正在生成中，請稍候片刻再用同一筆請求重試。",
        retryable: true,
        retryAfterMs: preflight.retryAfterMs,
      }, 409);
    }
    if (preflight.kind === "replay") {
      logInfo("new_topic_replay_hit", {
        user: summarizeUser(deps.userId),
        requestId: newTopicRequest.requestId,
        servedTier: preflight.result.access.servedTier,
        costDeducted: 0,
      });
      return jsonResponse(newTopicSuccessBody(
        preflight.result as unknown as Record<string, unknown>,
      ));
    }
  }

  // 4. Claim 65s lease（claim 必須發生在 quota 429 終局回應之前，
  //    才能保證同 identity 併發收斂到單一決策）。
  const newTopicOwnerToken = crypto.randomUUID();
  const newTopicRpc = async (fn: string, params: Record<string, unknown>) =>
    await deps.supabase.rpc(fn, params);
  const releaseNewTopicCurrentClaim = async (): Promise<boolean> => {
    const released = await releaseNewTopicClaim({
      rpc: newTopicRpc,
      userId: deps.userId,
      requestId: newTopicRequest.requestId,
      inputHash: newTopicInputHash,
      ownerToken: newTopicOwnerToken,
    });
    // GLM review I4：lease/claim 生命週期是最高風險觀測面，release
    // 成敗都必留 telemetry（失敗＝pending row 留到 lease 過期/takeover）。
    logInfo("new_topic_claim_released", {
      user: summarizeUser(deps.userId),
      requestId: newTopicRequest.requestId,
      released,
    });
    return released;
  };
  const newTopicReleaseFailedResponse = () =>
    jsonResponse({
      error: "NEW_TOPIC_CLAIM_RELEASE_RETRYABLE",
      code: "NEW_TOPIC_CLAIM_RELEASE_RETRYABLE",
      message: "請求狀態暫時無法釋放，請稍後用同一筆請求重試。",
      retryable: true,
    }, 503);
  const handleNewTopicClaimOutcome = (
    claim: Awaited<ReturnType<typeof claimNewTopicRequest>>,
  ): Response | null => {
    if (claim.kind === "claimed") return null;
    if (claim.kind === "replay") {
      logInfo("new_topic_replay_hit", {
        user: summarizeUser(deps.userId),
        requestId: newTopicRequest.requestId,
        servedTier: claim.result.access.servedTier,
        costDeducted: 0,
      });
      return jsonResponse(newTopicSuccessBody(
        claim.result as unknown as Record<string, unknown>,
      ));
    }
    if (claim.kind === "pending") {
      logInfo("new_topic_request_pending", {
        user: summarizeUser(deps.userId),
        requestId: newTopicRequest.requestId,
        stage: "claim",
        retryAfterMs: claim.retryAfterMs,
      });
      return jsonResponse({
        error: "NEW_TOPIC_REQUEST_IN_PROGRESS",
        code: "NEW_TOPIC_REQUEST_IN_PROGRESS",
        message: "這筆請求正在生成中，請稍候片刻再用同一筆請求重試。",
        retryable: true,
        retryAfterMs: claim.retryAfterMs,
      }, 409);
    }
    if (claim.kind === "mismatch") {
      return jsonResponse({
        error: "NEW_TOPIC_REQUEST_REPLAY_MISMATCH",
        code: "NEW_TOPIC_REQUEST_REPLAY_MISMATCH",
        message: "這筆請求編號已用於不同內容，請重新生成一次。本次不會扣額度。",
        shouldChargeQuota: false,
      }, 409);
    }
    logError("new_topic_claim_failed", {
      user: summarizeUser(deps.userId),
      kind: claim.kind,
      error: claim.message,
    });
    return jsonResponse({
      error: "NEW_TOPIC_CLAIM_UNAVAILABLE",
      code: "NEW_TOPIC_CLAIM_UNAVAILABLE",
      message: "新話題服務暫時無法受理請求，請稍後用同一筆請求重試。",
      retryable: true,
      shouldChargeQuota: false,
    }, 503);
  };
  {
    const claim = await claimNewTopicRequest({
      rpc: newTopicRpc,
      userId: deps.userId,
      requestId: newTopicRequest.requestId,
      inputHash: newTopicInputHash,
      ownerToken: newTopicOwnerToken,
    });
    const claimResponse = handleNewTopicClaimOutcome(claim);
    if (claimResponse !== null) return claimResponse;
    logInfo("new_topic_claim_acquired", {
      user: summarizeUser(deps.userId),
      requestId: newTopicRequest.requestId,
    });
  }

  // 5. Fixed cost 3 quota gate（Free 只要月/日都剩 ≥3 就不得因 tier 先
  //    被 paywall 擋）。不足時先試 RevenueCat refresh，再 owner-bound
  //    release 後回真正 quota 429（絕不留 pending claim 卡 65 秒）。
  const newTopicCost = 3;
  if (!deps.accountIsTest) {
    const newTopicExceedsQuota = () =>
      quota().sub.monthly_messages_used + newTopicCost > quota().monthlyLimit ||
      quota().sub.daily_messages_used + newTopicCost > quota().dailyLimit;
    if (newTopicExceedsQuota()) {
      await deps.refreshTierFromRevenueCat(
        "new_topic_quota_exceeded",
      );
      // refresh applied 時，applyRefreshedSub 已在 handler 端
      // 重算 monthly/daily limit；quota() 取得的即是刷新後的值。
    }
    if (newTopicExceedsQuota()) {
      if (!await releaseNewTopicCurrentClaim()) {
        return newTopicReleaseFailedResponse();
      }
      const monthlyRemaining = Math.max(
        0,
        quota().monthlyLimit - quota().sub.monthly_messages_used,
      );
      const dailyRemaining = Math.max(
        0,
        quota().dailyLimit - quota().sub.daily_messages_used,
      );
      const message = monthlyRemaining < newTopicCost
        ? "本月額度不足，升級方案可取得更多新話題與分析額度。"
        : "今日額度不足，每天早上 8 點恢復；也可以升級取得更多額度。";
      logWarn("new_topic_quota_exceeded", {
        user: summarizeUser(deps.userId),
        tier: quota().sub.tier,
        monthlyRemaining,
        dailyRemaining,
      });
      return jsonResponse({
        error: "額度不足",
        message,
        quotaNeeded: newTopicCost,
        monthlyRemaining,
        dailyRemaining,
        monthlyLimit: quota().monthlyLimit,
        dailyLimit: quota().dailyLimit,
        monthlyUsed: quota().sub.monthly_messages_used,
        dailyUsed: quota().sub.daily_messages_used,
      }, 429);
    }
  }

  // 6. 模型呼叫限流：new_topic 3/分、30/日。quota 429 語義優先於限流。
  //    MODEL_RATE_LIMITED payload 絕不帶 quota keys、不開 paywall。
  {
    const rateVerdict = await enforceModelRateLimit({
      supabase: deps.supabase,
      userId: deps.userId,
      scope: "new_topic",
      isTestAccount: deps.accountIsTest,
    });
    if (rateVerdict.kind === "limited") {
      logWarn("model_rate_limited", {
        user: summarizeUser(deps.userId),
        scope: "new_topic",
        reason: rateVerdict.reason,
      });
      // §14.1 專名事件；generic model_rate_limited 是全 repo 跨 scope
      // 查詢慣例，兩者並存（一行雙記，dashboard 各取所需）。
      logWarn("new_topic_model_rate_limited", {
        user: summarizeUser(deps.userId),
        requestId: newTopicRequest.requestId,
        reason: rateVerdict.reason,
      });
      if (!await releaseNewTopicCurrentClaim()) {
        return newTopicReleaseFailedResponse();
      }
      return jsonResponse(rateVerdict.payload, 429);
    }
    if (rateVerdict.kind === "failOpen") {
      logError("model_rate_limit_check_failed", {
        user: summarizeUser(deps.userId),
        scope: "new_topic",
        error: rateVerdict.errorMessage,
      });
    }
  }

  // 7. 模型派發前 renew claim：若 gate RPC 拖過 lease、擁有權被奪，
  //    必須在放大 provider cost 之前停下。
  {
    const renewal = await claimNewTopicRequest({
      rpc: newTopicRpc,
      userId: deps.userId,
      requestId: newTopicRequest.requestId,
      inputHash: newTopicInputHash,
      ownerToken: newTopicOwnerToken,
    });
    const renewalResponse = handleNewTopicClaimOutcome(renewal);
    if (renewalResponse !== null) return renewalResponse;
  }

  // 8. 45 秒 generation deadline 內完成 primary／outage fallback。
  //    refusal、max_tokens、格式錯誤不走 outage fallback（fallback.ts
  //    既有分類）；deadline 前提早爆的 DEADLINE_EXCEEDED 也在這裡收。
  const newTopicUserPrompt = buildNewTopicUserPrompt({
    partnerSummary: newTopicRequest.partnerSummary,
    effectiveStyleContext: newTopicRequest.effectiveStyleContext,
    situation: newTopicRequest.situation,
    // 切入角度由 requestId 決定：同次 replay 一致、不同次生成才換。
    requestId: newTopicRequest.requestId,
  });
  const newTopicGroundingPolicy = {
    allowSharedFrame: allowsNewTopicSharedFrame({
      partnerSummary: newTopicRequest.partnerSummary,
      situation: newTopicRequest.situation,
    }),
  };
  const rejectNewTopicDeadline = async (
    stage: string,
  ): Promise<Response> => {
    logWarn("new_topic_deadline_exceeded", {
      user: summarizeUser(deps.userId),
      stage,
    });
    // 能證明 settle 尚未開始才可 owner-bound release；release 失敗時
    // 不得假裝已清除（回 retryable，lease 65 秒後自然可接手）。
    if (!await releaseNewTopicCurrentClaim()) {
      return newTopicReleaseFailedResponse();
    }
    return jsonResponse({
      error: "NEW_TOPIC_DEADLINE_EXCEEDED",
      code: "NEW_TOPIC_DEADLINE_EXCEEDED",
      message: "這次新話題生成逾時，請重新生成一次；本次不會扣額度。",
      shouldChargeQuota: false,
    }, 504);
  };

  // ── 2026-08-18 new_topic 串流（transport-only）───────────────────
  // 與 opener 同策略：模型輸出契約不變，stream 只改逐塊接收＋進度事件。
  // claim／quota／rate limit／renew 都已在上面用一般 HTTP 回應把關完；
  // 從這裡起的解析／repair／tier 投影／settle 與 legacy 共用同一個
  // completeNewTopicRequest（內部邏輯零改動，shim 同名變數），
  // exactly-once settle 語義不變。
  const completeNewTopicRequest = async (modelOutput: {
    rawText: string;
    model: string;
    stopReason?: string;
    inputTokens?: number;
    outputTokens?: number;
  }): Promise<Response> => {
    const newTopicApiResult = { model: modelOutput.model };
    const newTopicApiData = {
      usage: {
        input_tokens: modelOutput.inputTokens,
        output_tokens: modelOutput.outputTokens,
      },
      stop_reason: modelOutput.stopReason,
    };
    const newTopicRawText = modelOutput.rawText;

    // 反 prompt 外洩（2026-08-19）：同 opener——整包擋下、release claim、
    // 不扣費（settle 尚未開始，release 安全）。
    if (hasAnalyzeChatPromptLeak(newTopicRawText)) {
      logWarn("prompt_leak_blocked", {
        user: summarizeUser(deps.userId),
        surface: "new_topic",
        textLength: newTopicRawText.length,
      });
      if (!await releaseNewTopicCurrentClaim()) {
        return newTopicReleaseFailedResponse();
      }
      return jsonResponse({
        error: "NEW_TOPIC_RESPONSE_INVALID",
        code: "NEW_TOPIC_RESPONSE_INVALID",
        message:
          "這次 AI 沒有產出完整的五個新話題，請重新生成一次；本次不會扣額度。",
        shouldChargeQuota: false,
      }, 502);
    }

    // 9. 完整性驗證＋最多一次 same-model format repair（禁 model
    //    fallback、共享 generation deadline）。repair 後仍不合格→502
    //    release 不扣（絕不丟壞題只投影剩下的）。
    const newTopicPrimaryParsed = parseJsonObjectFromText(newTopicRawText);
    let newTopicNormalized = normalizeNewTopicModelPayload(
      newTopicPrimaryParsed,
      newTopicGroundingPolicy,
    );
    let newTopicRepaired = false;
    if (!newTopicNormalized.ok) {
      try {
        const repairResult = await callClaudeWithFallback(
          {
            model: newTopicApiResult.model,
            max_tokens: NEW_TOPIC_MAX_TOKENS,
            system: NEW_TOPIC_REPAIR_PROMPT,
            messages: [{
              role: "user",
              content: buildNewTopicRepairPrompt(newTopicRawText),
            }],
          },
          deps.claudeApiKey,
          {
            timeout: 60000,
            maxRetries: 0,
            allowModelFallback: false,
            absoluteDeadlineAtMs: newTopicGenerationDeadlineAtMs,
          },
        );
        const repairedText = extractClaudeText(
          repairResult.data as { content?: Array<{ text?: string }> },
        );
        const repairedParsed = mergeNewTopicRepairWithPrimaryOpeningLines(
          newTopicPrimaryParsed,
          parseJsonObjectFromText(repairedText),
        );
        const repairedNormalized = normalizeNewTopicModelPayload(
          repairedParsed,
          newTopicGroundingPolicy,
        );
        if (repairedNormalized.ok) {
          newTopicNormalized = repairedNormalized;
          newTopicRepaired = true;
          logInfo("new_topic_response_repaired", {
            user: summarizeUser(deps.userId),
            model: newTopicApiResult.model,
          });
        }
      } catch (repairError) {
        if (
          (repairError instanceof AiServiceError &&
            repairError.code === "DEADLINE_EXCEEDED") ||
          Date.now() >= newTopicGenerationDeadlineAtMs
        ) {
          return await rejectNewTopicDeadline("format_repair");
        }
        logWarn("new_topic_repair_error", {
          user: summarizeUser(deps.userId),
          error: getErrorMessage(repairError),
        });
      }
    }
    if (!newTopicNormalized.ok) {
      logWarn("new_topic_response_invalid", {
        user: summarizeUser(deps.userId),
        model: newTopicApiResult.model,
        reason: newTopicNormalized.reason,
        stopReason: newTopicApiData.stop_reason,
      });
      if (!await releaseNewTopicCurrentClaim()) {
        return newTopicReleaseFailedResponse();
      }
      return jsonResponse({
        error: "NEW_TOPIC_RESPONSE_INVALID",
        code: "NEW_TOPIC_RESPONSE_INVALID",
        message:
          "這次 AI 沒有產出完整的五個新話題，請重新生成一次；本次不會扣額度。",
        shouldChargeQuota: false,
      }, 502);
    }

    // 10. Tier 投影：server 權威 servedTier；Free 只留推薦一題，鎖定四題
    //     文字不進 ledger、不出 server。
    const newTopicServedTier = (() => {
      const tier = normalizeSubscriptionTier(quota().effectiveTier);
      return tier === "starter" || tier === "essential" ? tier : "free";
    })();
    const newTopicLedgerResult = buildNewTopicLedgerResult({
      topics: newTopicNormalized.topics,
      recommendationIndex: newTopicNormalized.recommendationIndex,
      recommendationReason: newTopicNormalized.recommendationReason,
      servedTier: newTopicServedTier,
    });

    // 11. Settlement（5 秒 reserve）：deadline 已過且 settle 未開始→504
    //     release；settle 一旦送出，結果不明絕不 release。
    if (Date.now() >= newTopicDeadlineAtMs) {
      return await rejectNewTopicDeadline("pre_settlement");
    }
    const settlement = await settleNewTopicRequest({
      rpc: newTopicRpc,
      userId: deps.userId,
      requestId: newTopicRequest.requestId,
      inputHash: newTopicInputHash,
      ownerToken: newTopicOwnerToken,
      result: newTopicLedgerResult,
      monthlyLimit: quota().monthlyLimit,
      dailyLimit: quota().dailyLimit,
      chargeQuota: !deps.accountIsTest,
    });
    if (settlement.kind === "settled") {
      // §14.1：settle 落帳成功／被先完成者搶先（stored winner 回放）分流。
      // 測試帳號 chargeQuota=false 屬正常免扣，不算 replayed。
      if (settlement.charged || deps.accountIsTest) {
        logInfo("new_topic_settlement_succeeded", {
          user: summarizeUser(deps.userId),
          requestId: newTopicRequest.requestId,
          charged: settlement.charged,
        });
      } else {
        logInfo("new_topic_settlement_replayed", {
          user: summarizeUser(deps.userId),
          requestId: newTopicRequest.requestId,
        });
      }
      logInfo("new_topic_success", {
        user: summarizeUser(deps.userId),
        requestId: newTopicRequest.requestId,
        model: newTopicApiResult.model,
        servedTier: newTopicServedTier,
        charged: settlement.charged,
        repaired: newTopicRepaired,
        situation: newTopicRequest.situation,
        hasPartnerSummary: newTopicRequest.partnerSummary !== null,
        hasStyleContext: newTopicRequest.effectiveStyleContext !== null,
        inputTokens: newTopicApiData.usage?.input_tokens,
        outputTokens: newTopicApiData.usage?.output_tokens,
        stopReason: newTopicApiData.stop_reason,
        // §8 telemetry：只記數量絕不記內容。
      });
      // Handler 永遠回 settlement 回傳的 stored result；即使本地候選不同
      // （late/stale owner race），也丟棄本地結果（設計鐵律 §4-8/9）。
      return jsonResponse(newTopicSuccessBody(
        settlement.result as unknown as Record<string, unknown>,
      ));
    }
    if (settlement.kind === "quota_exceeded") {
      // increment_usage RAISE＝transaction 已回滾（result 未落地），
      // 可安全 owner-bound release 後回真正 quota 429。
      if (!await releaseNewTopicCurrentClaim()) {
        return newTopicReleaseFailedResponse();
      }
      const monthlyRemaining = Math.max(
        0,
        quota().monthlyLimit - quota().sub.monthly_messages_used,
      );
      const dailyRemaining = Math.max(
        0,
        quota().dailyLimit - quota().sub.daily_messages_used,
      );
      logWarn("new_topic_settle_quota_race", {
        user: summarizeUser(deps.userId),
        reason: settlement.reason,
      });
      return jsonResponse({
        error: "額度不足",
        message: settlement.reason === "monthly_limit_exceeded"
          ? "本月額度不足，升級方案可取得更多新話題與分析額度。"
          : "今日額度不足，每天早上 8 點恢復；也可以升級取得更多額度。",
        quotaNeeded: newTopicCost,
        monthlyRemaining,
        dailyRemaining,
        monthlyLimit: quota().monthlyLimit,
        dailyLimit: quota().dailyLimit,
      }, 429);
    }
    if (settlement.kind === "mismatch") {
      return jsonResponse({
        error: "NEW_TOPIC_REQUEST_REPLAY_MISMATCH",
        code: "NEW_TOPIC_REQUEST_REPLAY_MISMATCH",
        message: "這筆請求編號已用於不同內容，請重新生成一次。本次不會扣額度。",
        shouldChargeQuota: false,
      }, 409);
    }
    if (settlement.kind === "retryable") {
      // Transport／結果不明：可能已 commit＋已扣一次，絕不 release、
      // 絕不宣稱「不會扣額度」；client 保留同 requestId 重試讀 ledger。
      logWarn("new_topic_settlement_pending", {
        user: summarizeUser(deps.userId),
        error: settlement.message,
      });
      return jsonResponse({
        error: "NEW_TOPIC_SETTLEMENT_PENDING",
        code: "NEW_TOPIC_SETTLEMENT_PENDING",
        message: "結果正在確認，請用同一筆請求重試。",
        retryable: true,
      }, 503);
    }
    // settlement.kind === "failed"：RPC 明確 RAISE＝transaction 已回滾，
    // 可 owner-bound release 後回 500。
    logError("new_topic_settlement_failed", {
      user: summarizeUser(deps.userId),
      error: settlement.message,
    });
    if (!await releaseNewTopicCurrentClaim()) {
      return newTopicReleaseFailedResponse();
    }
    return jsonResponse({
      error: "NEW_TOPIC_SETTLEMENT_FAILED",
      code: "NEW_TOPIC_SETTLEMENT_FAILED",
      message: "新話題結果入帳失敗，請重新生成一次；本次不會扣額度。",
      shouldChargeQuota: false,
    }, 500);
  };

  const newTopicModel = "claude-sonnet-5";
  if (newTopicStreamRequested) {
    logInfo("new_topic_stream_started", {
      user: summarizeUser(deps.userId),
      requestId: newTopicRequest.requestId,
      model: newTopicModel,
    });
    return ndjsonStreamResponse(async (emit, close) => {
      emit({
        type: "new_topic.started",
        etaSeconds: 20,
        label: "開始生成新話題",
      });
      const tracker = createStreamStageTracker({
        stages: NEW_TOPIC_STREAM_STAGES,
        eventType: "new_topic.progress",
        emit,
      });
      const heartbeat = setInterval(() => {
        emit({
          type: "new_topic.progress",
          phase: "heartbeat",
          label: "生成仍在進行",
          detail: "正在等待模型完成，請保持連線。",
        });
      }, 15000);
      // R2 主審 round-2 修正：try 只包 provider 呼叫與文字累積，
      // completeNewTopicRequest 在 catch 外——settle 之後的非預期例外
      // 走 ndjson fail（=連線中斷），絕不會被這裡的 catch 誤 release
      // 已 settle 的 claim（與 legacy 全域 500 同語義）。
      try {
        // deadline 先擋：剩餘預算 ≤0 不得再起 provider 呼叫（與 legacy
        // absoluteDeadlineAtMs 拒絕語義一致；不設 1 秒地板）。已知
        // transport 差異（flag-on 營運風險）：callClaudeStreaming 走
        // 自己的 pre-content fallback 鏈、無 maxRetries；settle 前仍有
        // complete 內 pre_settlement deadline 複檢把關。
        let modelOutput:
          | Parameters<typeof completeNewTopicRequest>[0]
          | null = null;
        let failureResponse: Response | null = null;
        const remainingBudgetMs = newTopicGenerationDeadlineAtMs -
          Date.now();
        if (remainingBudgetMs <= 0) {
          failureResponse = await rejectNewTopicDeadline(
            "primary_or_fallback",
          );
        } else {
          try {
            const claude = await callClaudeStreaming(
              {
                model: newTopicModel,
                max_tokens: NEW_TOPIC_MAX_TOKENS,
                system: NEW_TOPIC_PROMPT,
                messages: [{ role: "user", content: newTopicUserPrompt }],
              },
              deps.claudeApiKey,
              { timeout: remainingBudgetMs },
            );
            let fullText = "";
            for await (const chunk of claude.textStream) {
              fullText += chunk;
              tracker.push(chunk);
            }
            modelOutput = {
              rawText: fullText,
              model: claude.model,
              // SSE 不外露 stop_reason；complete 內它只進 telemetry log、
              // 無計費/驗證決策（R2 主審 round-2 已核）。
              inputTokens: claude.usage.inputTokens,
              outputTokens: claude.usage.outputTokens,
            };
          } catch (streamError) {
            // 與 legacy catch 同語義：deadline → rejectNewTopicDeadline
            // （owner-bound release）；其他 → release 後 503。此時
            // complete 尚未跑、settle 必然未開始，release 是安全的；
            // release 失敗回 retryable 不宣稱不扣。
            if (
              (streamError instanceof AiStreamingServiceError &&
                streamError.code === "TIMEOUT") ||
              Date.now() >= newTopicGenerationDeadlineAtMs
            ) {
              failureResponse = await rejectNewTopicDeadline(
                "primary_or_fallback",
              );
            } else {
              logWarn("new_topic_api_error", {
                user: summarizeUser(deps.userId),
                error: getErrorMessage(streamError),
                code: streamError instanceof AiStreamingServiceError
                  ? streamError.code
                  : "UNKNOWN",
                responseMode: "stream",
              });
              if (await releaseNewTopicCurrentClaim()) {
                failureResponse = jsonResponse({
                  error: "NEW_TOPIC_PROVIDER_UNAVAILABLE",
                  code: "NEW_TOPIC_PROVIDER_UNAVAILABLE",
                  message: "AI 暫時生成失敗，請稍後再試；本次不會扣額度。",
                  retryable: true,
                  shouldChargeQuota: false,
                }, 503);
              } else {
                failureResponse = newTopicReleaseFailedResponse();
              }
            }
          }
        }

        if (failureResponse !== null) {
          await emitJsonResponseAsStreamOutcome(
            failureResponse,
            emit,
            "new_topic",
          );
        } else if (modelOutput !== null) {
          emit({
            type: "new_topic.progress",
            phase: "finalizing",
            label: "整理與驗證結果",
          });
          const response = await completeNewTopicRequest(modelOutput);
          await emitJsonResponseAsStreamOutcome(
            response,
            emit,
            "new_topic",
          );
        }
      } finally {
        clearInterval(heartbeat);
        close();
      }
    }, corsHeaders);
  }

  let newTopicApiResult: FallbackResult;
  try {
    newTopicApiResult = await callClaudeWithFallback(
      {
        model: newTopicModel,
        max_tokens: NEW_TOPIC_MAX_TOKENS,
        system: NEW_TOPIC_PROMPT,
        messages: [{ role: "user", content: newTopicUserPrompt }],
      },
      deps.claudeApiKey,
      {
        timeout: 60000,
        maxRetries: 1,
        allowModelFallback: true,
        absoluteDeadlineAtMs: newTopicGenerationDeadlineAtMs,
      },
    );
  } catch (apiError) {
    if (
      (apiError instanceof AiServiceError &&
        apiError.code === "DEADLINE_EXCEEDED") ||
      Date.now() >= newTopicGenerationDeadlineAtMs
    ) {
      return await rejectNewTopicDeadline("primary_or_fallback");
    }
    logWarn("new_topic_api_error", {
      user: summarizeUser(deps.userId),
      error: getErrorMessage(apiError),
      code: apiError instanceof AiServiceError ? apiError.code : "UNKNOWN",
    });
    if (!await releaseNewTopicCurrentClaim()) {
      return newTopicReleaseFailedResponse();
    }
    return jsonResponse({
      error: "NEW_TOPIC_PROVIDER_UNAVAILABLE",
      code: "NEW_TOPIC_PROVIDER_UNAVAILABLE",
      message: "AI 暫時生成失敗，請稍後再試；本次不會扣額度。",
      retryable: true,
      shouldChargeQuota: false,
    }, 503);
  }

  const legacyNewTopicApiData = newTopicApiResult.data as {
    content?: Array<{ text?: string }>;
    usage?: { input_tokens?: number; output_tokens?: number };
    stop_reason?: string;
  };
  return await completeNewTopicRequest({
    rawText: extractClaudeText(legacyNewTopicApiData),
    model: newTopicApiResult.model,
    stopReason: legacyNewTopicApiData.stop_reason,
    inputTokens: legacyNewTopicApiData.usage?.input_tokens,
    outputTokens: legacyNewTopicApiData.usage?.output_tokens,
  });
}
