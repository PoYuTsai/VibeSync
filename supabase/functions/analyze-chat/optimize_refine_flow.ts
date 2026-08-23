// Optimize（草稿潤飾）／Refine（回覆微調）金流流程：
// requestId 冪等身分與 replay preflight、replay 無扣費回應、結果驗證
// fail-closed、微調免費額度權威授權、exactly-once settlement。
// 這裡只有「決策與帳」，模型呼叫與 prompt 組裝留在 legacy 管線。

import {
  buildOptimizeMessageLedgerResult,
  computeOptimizeMessageInputHash,
  hasUsableOptimizedMessage,
  hydrateOptimizeMessageReplayResult,
  isOptimizeDraftUnreadable,
  isValidOptimizeMessageRequestId,
  OPTIMIZE_MESSAGE_COST,
  optimizeMessageReplayCutoffIso,
  type OptimizeMessageReplayRow,
  settleOptimizeMessageRequest,
} from "./optimize_message_billing.ts";
import { classifyOptimizeMessageReplayPreflight } from "./optimize_message_billing.ts";
import { findClientShapeViolations } from "./client_shape_validator.ts";
import {
  exceedsRefineOutputLimit,
  refineMaxOutputChars,
} from "./refine_output.ts";
import {
  classifyRefineFreeConsumption,
  projectRefineFreeAllowance,
  REFINE_FREE_DAILY_LIMIT,
  type RefineFreeProjection,
  refineQuotaOutcomeFor,
  utcDayString,
} from "./refine_allowance.ts";
import { hasOutboundSafetyWarning } from "./guardrails.ts";
import { buildQuotaExceededPayload } from "../_shared/quota.ts";
import { resolveSourceAwareSubscriptionRow } from "../_shared/subscription_store_state.ts";
import { jsonResponse } from "./http_response.ts";
import { logError, logInfo, logWarn, summarizeUser } from "./logger.ts";
import type {
  AnalyzeMessage,
  SessionContextInput,
} from "./analysis_input_compiler.ts";

export interface OptimizeQuotaUsage {
  shouldChargeQuota: boolean;
  quotaReason: string;
  quotaUnit: string;
  chargedMessageCount: number;
  estimatedMessageCount: number;
}

export type OptimizeIdentityResolution =
  | {
    kind: "ok";
    requestId: string | null;
    inputHash: string | null;
    replayResult: Record<string, unknown> | null;
  }
  | { kind: "response"; response: Response };

/// requestId 冪等身分：缺席只容忍舊 client（微調必帶）、非法 fail-closed、
/// 帶 id 時做 24h replay preflight（讀失敗 fail-closed，絕不當 fresh）。
export async function resolveOptimizeIdentity(args: {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  userId: string;
  rawRequestId: unknown;
  isRefineReplyMode: boolean;
  userDraft: string | undefined;
  hashContext: {
    messages: AnalyzeMessage[];
    sessionContext: SessionContextInput | undefined;
    conversationSummary: string | undefined;
    partnerSummary: string | undefined;
    effectiveStyleContext: string | undefined;
    knownContactName: string | undefined;
    forceModel: string | null;
    refineInstruction: string | null;
  };
}): Promise<OptimizeIdentityResolution> {
  // Missing requestId is allowed only for old clients. Current clients
  // always send a UUID; malformed identities fail closed instead of
  // silently losing retry idempotency.
  if (
    args.rawRequestId != null &&
    !isValidOptimizeMessageRequestId(args.rawRequestId)
  ) {
    return {
      kind: "response",
      response: jsonResponse({
        error: "INVALID_OPTIMIZE_MESSAGE_REQUEST_ID",
        code: "INVALID_OPTIMIZE_MESSAGE_REQUEST_ID",
        message: "草稿潤飾請求格式有誤，請重新送出。本次不會扣額度。",
      }, 400),
    };
  }
  const requestId = isValidOptimizeMessageRequestId(args.rawRequestId)
    ? args.rawRequestId
    : null;

  // Draft polish tolerates a missing requestId for old clients. Reply
  // refinement has none -- it never shipped without one -- so a refine
  // request without a durable identity is rejected instead of being run
  // with no idempotency at all. Without it the free-allowance claim has no
  // key, and concurrent retries would each take a slot.
  if (args.isRefineReplyMode && requestId === null) {
    return {
      kind: "response",
      response: jsonResponse({
        error: "INVALID_OPTIMIZE_MESSAGE_REQUEST_ID",
        code: "INVALID_OPTIMIZE_MESSAGE_REQUEST_ID",
        message: "這次微調請求無法安全重送，請重新操作。本次不會扣額度。",
      }, 400),
    };
  }

  if (requestId === null || !args.userDraft) {
    logWarn("optimize_message_request_id_missing_legacy", {
      user: summarizeUser(args.userId),
    });
    return { kind: "ok", requestId, inputHash: null, replayResult: null };
  }

  const inputHash = await computeOptimizeMessageInputHash({
    messages: args.hashContext.messages,
    userDraft: args.userDraft,
    sessionContext: args.hashContext.sessionContext,
    conversationSummary: args.hashContext.conversationSummary,
    partnerSummary: args.hashContext.partnerSummary,
    effectiveStyleContext: args.hashContext.effectiveStyleContext,
    knownContactName: args.hashContext.knownContactName,
    forceModel: args.hashContext.forceModel,
    // 指令必須綁進冪等鍵，否則同一句草稿的兩種不同微調會共用同一顆
    // request id 的帳本列，第二次會 replay 出第一次的結果。
    refineInstruction: args.hashContext.refineInstruction,
  });
  const { data: replayRow, error: replayReadError } = await args.supabase
    .from("optimize_message_requests")
    .select("input_hash, result_json, created_at")
    .eq("user_id", args.userId)
    .eq("request_id", requestId)
    .gte("created_at", optimizeMessageReplayCutoffIso())
    .maybeSingle();
  if (replayReadError) {
    // A paid result may already exist. Treating a failed read as fresh
    // can strand the final credit behind the projected quota gate, so
    // fail closed and let the client retry with the same durable UUID.
    logError("optimize_message_replay_preflight_read_failed", {
      user: summarizeUser(args.userId),
      error: replayReadError.message,
    });
    return {
      kind: "response",
      response: jsonResponse({
        error: "OPTIMIZE_MESSAGE_SETTLEMENT_RETRYABLE",
        code: "OPTIMIZE_MESSAGE_SETTLEMENT_RETRYABLE",
        message: "草稿潤飾安全重試確認中斷，請再試一次。本次不會重複扣額度。",
        retryable: true,
      }, 503),
    };
  }
  const replay = classifyOptimizeMessageReplayPreflight(
    replayRow as OptimizeMessageReplayRow | null,
    inputHash,
  );
  if (replay.kind === "mismatch") {
    return {
      kind: "response",
      response: jsonResponse({
        error: "OPTIMIZE_MESSAGE_REQUEST_REPLAY_MISMATCH",
        code: "OPTIMIZE_MESSAGE_REQUEST_REPLAY_MISMATCH",
        message: "這次草稿和先前的重試不一致，請重新送出。本次不會扣額度。",
      }, 400),
    };
  }
  if (replay.kind === "replay") {
    const hydratedReplay = hydrateOptimizeMessageReplayResult(
      replay.result,
      args.userDraft,
    );
    const replayShapeViolations = findClientShapeViolations(hydratedReplay);
    if (
      hydratedReplay === null ||
      !hasUsableOptimizedMessage(hydratedReplay) ||
      replayShapeViolations.length > 0
    ) {
      logError("optimize_message_replay_result_invalid", {
        user: summarizeUser(args.userId),
        requestId,
        violationCount: replayShapeViolations.length,
        violationPaths: replayShapeViolations
          .slice(0, 8)
          .map((violation) => violation.path),
      });
      return {
        kind: "response",
        response: jsonResponse({
          error: "OPTIMIZE_MESSAGE_REPLAY_INVALID",
          code: "OPTIMIZE_MESSAGE_REPLAY_INVALID",
          message: "草稿潤飾結果暫時無法恢復，請重新送出。本次不會扣額度。",
        }, 500),
      };
    }
    return { kind: "ok", requestId, inputHash, replayResult: hydratedReplay };
  }
  return { kind: "ok", requestId, inputHash, replayResult: null };
}

/// 已付費 replay 的無扣費回應：同步權威用量後回 stored result。
export async function buildOptimizeReplayResponse(args: {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  userId: string;
  accountIsTest: boolean;
  requestId: string | null;
  replayResult: Record<string, unknown>;
  subMonthlyUsed: number;
  subDailyUsed: number;
  monthlyLimit: number;
  dailyLimit: number;
  model: string;
  effectiveTier: string;
  requestType: string;
}): Promise<Response> {
  let replayMonthlyUsed = args.subMonthlyUsed;
  let replayDailyUsed = args.subDailyUsed;
  if (!args.accountIsTest) {
    const { data: replayUsage, error: replayUsageError } = await args.supabase
      .from("subscriptions")
      .select("monthly_messages_used, daily_messages_used")
      .eq("user_id", args.userId)
      .maybeSingle();
    if (replayUsageError || !replayUsage) {
      logError("optimize_message_replay_usage_sync_failed", {
        user: summarizeUser(args.userId),
        requestId: args.requestId,
        error: replayUsageError?.message ?? "subscription missing",
      });
      return jsonResponse({
        error: "OPTIMIZE_MESSAGE_SETTLEMENT_RETRYABLE",
        code: "OPTIMIZE_MESSAGE_SETTLEMENT_RETRYABLE",
        message: "草稿潤飾額度確認回應中斷，正在安全重試。",
        retryable: true,
      }, 503);
    }
    const sourceAwareUsage = await resolveSourceAwareSubscriptionRow(
      args.supabase,
      args.userId,
      replayUsage as Record<string, unknown>,
      new Date(),
    );
    replayMonthlyUsed = Number(sourceAwareUsage.row.monthly_messages_used ?? 0);
    replayDailyUsed = Number(sourceAwareUsage.row.daily_messages_used ?? 0);
  }
  const replayResponse = { ...args.replayResult };
  replayResponse.usage = {
    messagesUsed: 0,
    estimatedMessages: OPTIMIZE_MESSAGE_COST,
    monthlyRemaining: args.accountIsTest
      ? 999999
      : Math.max(0, args.monthlyLimit - replayMonthlyUsed),
    dailyRemaining: args.accountIsTest
      ? 999999
      : Math.max(0, args.dailyLimit - replayDailyUsed),
    model: args.model,
    imagesUsed: 0,
    tierUsed: args.effectiveTier,
    isTestAccount: args.accountIsTest,
    requestType: args.requestType,
    shouldChargeQuota: false,
    quotaReason: "optimize_message_idempotent_replay",
    quotaUnit: "messages",
  };
  replayResponse.telemetry = {
    requestType: args.requestType,
    shouldChargeQuota: false,
    chargedMessageCount: 0,
    estimatedMessageCount: 1,
    quotaReason: "optimize_message_idempotent_replay",
    idempotentReplay: true,
  };
  logInfo("optimize_message_replayed_without_charge", {
    user: summarizeUser(args.userId),
    requestId: args.requestId,
  });
  return jsonResponse(replayResponse);
}

/// 微調免費額度「投影」：純讀取，不授權（授權在拿到有效結果之後）。
/// 讀失敗一律樂觀當免費，最壞只是多打一次模型；權威授權仍說了算。
export async function projectRefineFreeAllowanceForUser(args: {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  userId: string;
}): Promise<RefineFreeProjection> {
  const { data: allowanceRow, error: allowanceReadError } = await args.supabase
    .from("refine_free_allowance")
    .select("day_utc, used_count")
    .eq("user_id", args.userId)
    .maybeSingle();
  if (allowanceReadError) {
    logWarn("refine_free_allowance_read_failed", {
      user: summarizeUser(args.userId),
      error: allowanceReadError.message,
    });
  }
  return projectRefineFreeAllowance({
    row: allowanceReadError ? null : allowanceRow,
    todayUtc: utcDayString(new Date()),
  });
}

/// 有效結果後的守門：unusable 亂碼防呆（只限草稿潤飾）、client shape、
/// 微調輸出過長、安全守門專屬文案。全部不扣費。
export function validateOptimizeOutcome(args: {
  result: Record<string, unknown>;
  isRefineReplyMode: boolean;
  userDraft: string | undefined;
  requestId: string | null;
  userId: string;
  actualModel: string;
}): Response | null {
  // 亂碼防呆：模型宣告 userDraft 無法理解（unusable: true）。必須在
  // hasUsableOptimizedMessage 之前攔——模型可能違規把說明文字塞進
  // optimized，讓結果看起來「可用」而被當成潤飾成果渲染。
  // 只限草稿潤飾：微調 schema 沒這個欄位。
  if (!args.isRefineReplyMode && isOptimizeDraftUnreadable(args.result)) {
    logWarn("optimize_message_draft_unreadable_no_charge", {
      user: summarizeUser(args.userId),
      model: args.actualModel,
      requestId: args.requestId,
    });
    return jsonResponse({
      error: "OPTIMIZE_MESSAGE_DRAFT_UNREADABLE",
      code: "OPTIMIZE_MESSAGE_DRAFT_UNREADABLE",
      message: "看不懂這段草稿，請換成想傳的訊息再試一次。本次不會扣額度。",
      shouldChargeQuota: false,
    }, 502);
  }
  const optimizeClientShapeViolations = findClientShapeViolations(args.result);
  // 只作用於微調。草稿潤飾的輸出長度行為一個字不改。
  const refineOutputTooLong = args.isRefineReplyMode &&
    hasUsableOptimizedMessage(args.result) &&
    exceedsRefineOutputLimit({
      sourceDraft: args.userDraft ?? "",
      optimized: (args.result.optimizedMessage as Record<string, unknown>)
        .optimized as string,
    });
  if (
    !hasUsableOptimizedMessage(args.result) ||
    optimizeClientShapeViolations.length > 0 ||
    refineOutputTooLong
  ) {
    logWarn("optimize_message_result_invalid_no_charge", {
      user: summarizeUser(args.userId),
      model: args.actualModel,
      requestId: args.requestId,
      // 安全守門攔下 vs 模型輸出格式壞掉，兩者都走這條「不扣費」路徑，
      // 但要能分辨——否則沒辦法知道守門到底有沒有在動。
      safetyBlocked: hasOutboundSafetyWarning(args.result),
      violationCount: optimizeClientShapeViolations.length,
      violationPaths: optimizeClientShapeViolations
        .slice(0, 8)
        .map((violation) => violation.path),
      // 「越調越長」是可預期的模型行為，不是格式壞掉，必須分得出來。
      refineOutputTooLong,
      refineMaxOutputChars: args.isRefineReplyMode
        ? refineMaxOutputChars(args.userDraft ?? "")
        : null,
    });
    // 安全守門攔下要有專屬文案（2026-08-16 Eric 拍板）：通用的「請稍後
    // 再試」會誤導使用者原句重送——這不是暫時性失敗，是內容問題。
    if (hasOutboundSafetyWarning(args.result)) {
      return jsonResponse({
        error: "OPTIMIZE_MESSAGE_SAFETY_BLOCKED",
        code: "OPTIMIZE_MESSAGE_SAFETY_BLOCKED",
        message:
          "這段內容帶有施壓或威脅的說法，安全守門已攔下，不提供結果。請改成尊重對方意願的說法。本次不會扣額度。",
        shouldChargeQuota: false,
      }, 502);
    }
    return jsonResponse({
      error: "OPTIMIZE_MESSAGE_RESULT_INVALID",
      code: "OPTIMIZE_MESSAGE_RESULT_INVALID",
      message: "這次沒有產生可用的潤飾結果，請稍後再試。本次不會扣額度。",
      shouldChargeQuota: false,
    }, 502);
  }
  return null;
}

export interface RefineFreeConsumptionOutcome {
  granted: boolean | null;
  remaining: number | null;
}

/// 免費額度的權威授權。位置很重要：必須在所有「結果無效就不扣費」的檢查
/// 之後，計數才不會被一次失敗的生成吃掉；replay 早已返回，走不到這裡。
/// 授權結果直接改寫 quotaUsage（與既有行為一字不差）。
export async function consumeRefineFreeAllowanceForUser(args: {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  userId: string;
  requestId: string | null;
  quotaUsage: OptimizeQuotaUsage;
  projectedRemaining: number | null;
}): Promise<RefineFreeConsumptionOutcome> {
  let remaining = args.projectedRemaining;
  const { data: allowanceData, error: allowanceError } = await args.supabase
    .rpc(
      "consume_refine_free_allowance",
      {
        p_user_id: args.userId,
        p_daily_limit: REFINE_FREE_DAILY_LIMIT,
        // 冪等鍵。同一 requestId 的並行重試都會走到這裡（ledger 尚未寫入，
        // replay preflight 兩邊都看不到），少了這個參數免費次數會被扣兩次。
        p_request_id: args.requestId,
      },
    );
  const consumption = classifyRefineFreeConsumption(
    allowanceData,
    allowanceError,
  );
  if (consumption.kind === "unavailable") {
    // 不扣費。分不出「額度已扣但回應中斷」與「完全沒扣到」時，改為扣錢
    // 的風險是使用者同時被吃掉一次免費額度又被扣 1 則。
    logError("refine_free_allowance_consume_failed", {
      user: summarizeUser(args.userId),
      requestId: args.requestId,
      error: consumption.message,
    });
  } else {
    remaining = consumption.remaining;
  }
  const refineOutcome = refineQuotaOutcomeFor(consumption);
  const refineShouldCharge = refineOutcome.shouldCharge;
  args.quotaUsage.shouldChargeQuota = refineShouldCharge;
  args.quotaUsage.quotaReason = refineOutcome.quotaReason;
  args.quotaUsage.chargedMessageCount = refineShouldCharge
    ? OPTIMIZE_MESSAGE_COST
    : 0;
  args.quotaUsage.estimatedMessageCount = refineShouldCharge
    ? OPTIMIZE_MESSAGE_COST
    : 0;
  return { granted: refineOutcome.granted, remaining };
}

export type OptimizeSettlementOutcome =
  | { kind: "response"; response: Response }
  | {
    kind: "settled";
    result: Record<string, unknown>;
    reportedCharge: number;
    monthlyUsed: number;
    dailyUsed: number;
  };

/// exactly-once settlement：驗證過的結果與固定 1 則扣費原子落帳。
/// 成功後改寫 quotaUsage（shouldChargeQuota=false＋回報用 quotaReason），
/// 與既有行為一字不差。
export async function settleOptimizeMessage(args: {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  userId: string;
  accountIsTest: boolean;
  isRefineReplyMode: boolean;
  refineFreeGranted: boolean | null;
  requestId: string;
  inputHash: string;
  result: Record<string, unknown>;
  userDraft: string | undefined;
  monthlyLimit: number;
  dailyLimit: number;
  quotaUsage: OptimizeQuotaUsage;
}): Promise<OptimizeSettlementOutcome> {
  const optimizeLedgerResult = buildOptimizeMessageLedgerResult(args.result);
  if (optimizeLedgerResult === null) {
    logError("optimize_message_ledger_snapshot_invalid", {
      user: summarizeUser(args.userId),
      requestId: args.requestId,
    });
    return {
      kind: "response",
      response: jsonResponse({
        error: "OPTIMIZE_MESSAGE_RESULT_INVALID",
        code: "OPTIMIZE_MESSAGE_RESULT_INVALID",
        message: "這次沒有產生可用的潤飾結果，本次不會扣額度。",
      }, 500),
    };
  }
  const settlement = await settleOptimizeMessageRequest({
    // deno-lint-ignore no-explicit-any
    rpc: (fn: string, params: Record<string, unknown>): any =>
      args.supabase.rpc(fn, params),
    userId: args.userId,
    requestId: args.requestId,
    inputHash: args.inputHash,
    result: optimizeLedgerResult,
    monthlyLimit: args.monthlyLimit,
    dailyLimit: args.dailyLimit,
    chargeQuota: args.quotaUsage.shouldChargeQuota && !args.accountIsTest,
  });
  if (settlement.kind === "quota_exceeded") {
    const { data: authoritativeSub, error: authoritativeSubError } = await args
      .supabase
      .from("subscriptions")
      .select(
        "tier, monthly_messages_used, daily_messages_used, daily_reset_at, monthly_reset_at",
      )
      .eq("user_id", args.userId)
      .maybeSingle();
    if (authoritativeSubError || !authoritativeSub) {
      logError("optimize_message_quota_usage_sync_failed", {
        user: summarizeUser(args.userId),
        requestId: args.requestId,
        reason: settlement.reason,
        error: authoritativeSubError?.message ?? "subscription missing",
      });
      return {
        kind: "response",
        response: jsonResponse({
          error: "OPTIMIZE_MESSAGE_SETTLEMENT_RETRYABLE",
          code: "OPTIMIZE_MESSAGE_SETTLEMENT_RETRYABLE",
          message: "草稿潤飾額度確認回應中斷，正在安全重試。",
          retryable: true,
        }, 503),
      };
    }
    const sourceAwareSub = await resolveSourceAwareSubscriptionRow(
      args.supabase,
      args.userId,
      authoritativeSub as Record<string, unknown>,
      new Date(),
    );
    return {
      kind: "response",
      response: jsonResponse(
        buildQuotaExceededPayload({
          sub: sourceAwareSub.row as {
            tier: string;
            monthly_messages_used: number;
            daily_messages_used: number;
            daily_reset_at: string | null;
            monthly_reset_at: string | null;
          },
          cost: OPTIMIZE_MESSAGE_COST,
          reason: settlement.reason,
          monthlyLimit: args.monthlyLimit,
          dailyLimit: args.dailyLimit,
        }),
        429,
      ),
    };
  }
  if (settlement.kind === "mismatch") {
    return {
      kind: "response",
      response: jsonResponse({
        error: "OPTIMIZE_MESSAGE_REQUEST_REPLAY_MISMATCH",
        code: "OPTIMIZE_MESSAGE_REQUEST_REPLAY_MISMATCH",
        message: "這次草稿和先前的重試不一致，請重新送出。本次不會扣額度。",
      }, 409),
    };
  }
  if (settlement.kind === "retryable") {
    logError("optimize_message_settlement_transport_unknown", {
      user: summarizeUser(args.userId),
      requestId: args.requestId,
      error: settlement.message,
    });
    return {
      kind: "response",
      response: jsonResponse({
        error: "OPTIMIZE_MESSAGE_SETTLEMENT_RETRYABLE",
        code: "OPTIMIZE_MESSAGE_SETTLEMENT_RETRYABLE",
        message: "草稿潤飾額度確認回應中斷，正在安全重試。",
        retryable: true,
      }, 503),
    };
  }
  if (settlement.kind === "failed") {
    logError("optimize_message_settlement_failed", {
      user: summarizeUser(args.userId),
      requestId: args.requestId,
      error: settlement.message,
    });
    return {
      kind: "response",
      response: jsonResponse({
        error: "OPTIMIZE_MESSAGE_SETTLEMENT_FAILED",
        code: "OPTIMIZE_MESSAGE_SETTLEMENT_FAILED",
        message: "草稿潤飾額度確認失敗，請稍後再試。本次不會扣額度。",
      }, 500),
    };
  }

  const hydratedSettlement = hydrateOptimizeMessageReplayResult(
    settlement.result,
    args.userDraft ?? "",
  );
  if (hydratedSettlement === null) {
    logError("optimize_message_settlement_result_invalid", {
      user: summarizeUser(args.userId),
      requestId: args.requestId,
    });
    return {
      kind: "response",
      response: jsonResponse({
        error: "OPTIMIZE_MESSAGE_SETTLEMENT_RETRYABLE",
        code: "OPTIMIZE_MESSAGE_SETTLEMENT_RETRYABLE",
        message: "草稿潤飾結果恢復中斷，正在安全重試。",
        retryable: true,
      }, 503),
    };
  }
  args.quotaUsage.shouldChargeQuota = false;
  args.quotaUsage.quotaReason = settlement.charged
    ? (args.isRefineReplyMode
      ? "refine_reply_fixed_1"
      : "optimize_message_fixed_1")
    : args.accountIsTest
    ? "test_account_waived"
    // 微調的免費輪次是刻意帶 chargeQuota:false 進帳本的，不是冪等重播。
    : args.refineFreeGranted === true
    ? "refine_free_daily"
    : "optimize_message_idempotent_replay";
  return {
    kind: "settled",
    result: hydratedSettlement,
    reportedCharge: settlement.charged ? OPTIMIZE_MESSAGE_COST : 0,
    monthlyUsed: settlement.monthlyUsed,
    dailyUsed: settlement.dailyUsed,
  };
}
