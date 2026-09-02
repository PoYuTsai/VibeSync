// 唯一的 AnalyzeStream handler：主 AnalyzeChat 只有這一條生成路徑。
// 依賴 narrow ports（run store／model 串流），不依賴 legacy JSON generator。
// Run 生命週期：resume（done/pending/charged 附掛）→ retry（reserveRetry＋
// precharged recommendation）→ fresh（createPendingRun）→ charge →
// markDone／markFailed。扣費語義：fresh 才扣，retry 沿用原扣費。

import { type AnalysisStreamRun } from "./stream_run_store.ts";
import {
  handleStreamAnalysisRequest,
  handleStreamAnalysisResume,
  type StreamAnalysisResumeSnapshot,
} from "./stream_handler.ts";
import { buildAnalyzeStreamSystemPrompt } from "./analyze_prompt.ts";
import {
  detectAnalyzeSocialKnowledgeSignals,
  selectAnalyzeSocialKnowledge,
} from "./knowledge_adapter.ts";
import { streamAnalyzeMaxTokensForStyleCount } from "./stream_budget.ts";
import { streamReplyStylesForTier } from "./tier_sync_contract.ts";
import {
  type AnalysisEvidenceLinkage,
  isThinRecommendationEvent,
  type StreamChargePayload,
  type StreamRecommendationForCharge,
} from "./reframer.ts";
import {
  isNoSendDecisionKind,
  noSendChargePayloadFromStored,
} from "./no_send_decision.ts";
import { isStreamStyle } from "./stream_events.ts";
import {
  calibratePhase0EvidenceLinkage,
  emitPhase0Observability,
} from "./phase0_observability.ts";
import { callClaudeStreaming } from "./streaming_fallback.ts";
import { hashConversation } from "./conversation_hash.ts";
import {
  type AnalysisResult as GuardrailAnalysisResult,
  checkAiOutput,
} from "./guardrails.ts";
import { postProcessAnalysisResult } from "./post_process.ts";
import { corsHeaders, jsonResponse } from "./http_response.ts";
import { isPlainObject } from "../_shared/quota.ts";
import {
  getErrorMessage,
  logAiCall,
  logError,
  logInfo,
  summarizeUser,
} from "./logger.ts";
import type {
  AnalyzeMessage,
  SessionContextInput,
} from "./analysis_input_compiler.ts";

const MAX_STREAM_RETRIES = 2;
const STREAM_CLAUDE_TIMEOUT_MS = 120000;
const STREAM_PROVIDER_MAX_ATTEMPTS = 3;

/// Run store 的 narrow port（AnalysisStreamRunStore 的使用面）。
export interface AnalyzeStreamRunPort {
  getRun(args: {
    runId: string;
    userId: string;
    conversationHash: string;
  }): Promise<AnalysisStreamRun>;
  reserveRetry(args: {
    runId: string;
    userId: string;
    conversationHash: string;
    maxRetries: number;
  }): Promise<AnalysisStreamRun>;
  createPendingRun(args: {
    userId: string;
    conversationHash: string;
    requestContext: Record<string, unknown>;
  }): Promise<AnalysisStreamRun>;
  chargeRun(args: {
    runId: string;
    userId: string;
    conversationHash: string;
    recommendation: StreamChargePayload;
    chargeQuota: boolean;
    messageCount: number;
  }): Promise<unknown>;
  markDone(args: {
    runId: string;
    userId: string;
    conversationHash: string;
    finalResult: Record<string, unknown>;
  }): Promise<unknown>;
  markFailed(args: {
    runId: string;
    userId: string;
    conversationHash: string;
    code: string;
  }): Promise<AnalysisStreamRun>;
}

export interface AnalyzeStreamDeps {
  store: AnalyzeStreamRunPort;
  userId: string;
  analysisRunId: string | null;
  requestType: string;
  analyzeMode: string;
  expectedTier: string;
  effectiveTier: string;
  accountIsTest: boolean;
  allowedFeatures: string[];
  /// Phase 1b: client declared analysisContractVersion >= 2, so the model may
  /// answer with a no-send decision (zero reply cards) instead of options.
  noSendDecisions?: boolean;
  quotaUsage: {
    shouldChargeQuota: boolean;
    quotaReason: string;
    quotaUnit: string;
    chargedMessageCount: number;
    estimatedMessageCount: number;
  };
  monthlyLimit: number;
  dailyLimit: number;
  subMonthlyUsed: number;
  subDailyUsed: number;
  selectedModel: string;
  userMessageContent:
    | string
    | Array<{
      type: string;
      text?: string;
      source?: { type: string; media_type: string; data: string };
    }>;
  requestObservability: Record<string, unknown>;
  messages: AnalyzeMessage[];
  hashInput: {
    messages: AnalyzeMessage[];
    userDraft: string | undefined;
    partnerSummary: string | undefined;
    sessionContext: SessionContextInput | undefined;
    conversationSummary: string | undefined;
    effectiveStyleContext: string | undefined;
    knownContactName: string | undefined;
    previousStage?: string;
    analysisFragmentStartIndex?: number;
  };
  claudeApiKey: string;
  supabaseUrl: string;
  supabaseServiceKey: string;
  /// 測試注入用；預設走 callClaudeStreaming（含 outage fallback 鏈）。
  callModel?: typeof callClaudeStreaming;
}

function mapStreamChargeFailure(error: unknown): {
  code: string;
  message: string;
} {
  const message = getErrorMessage(error);
  const normalized = message.toUpperCase();
  if (
    normalized.includes("QUOTA") ||
    normalized.includes("LIMIT") ||
    normalized.includes("INSUFFICIENT")
  ) {
    return {
      code: "QUOTA_EXHAUSTED",
      message: "額度已用完，請升級或下個週期再試。",
    };
  }

  return {
    code: "STREAM_CHARGE_FAILED",
    message: "額度扣除失敗，請稍後再試。本次不會扣額度。",
  };
}

function optionalRecordFrom(
  value: unknown,
): Record<string, unknown> | undefined {
  return isPlainObject(value) && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function optionalEvidenceLinkageFrom(
  value: unknown,
): AnalysisEvidenceLinkage | undefined {
  const record = optionalRecordFrom(value);
  return record?.schemaVersion === 1
    ? record as unknown as AnalysisEvidenceLinkage
    : undefined;
}

function streamRecommendationFromRun(
  run: AnalysisStreamRun,
): StreamChargePayload | null {
  const stored = run.recommendation_json;
  if (!isPlainObject(stored)) return null;

  // Phase 1b: a charged no-send run resumes from its persisted decision; it
  // never had (and never needs) a selected style.
  const noSend = noSendChargePayloadFromStored(stored);
  if (noSend) return noSend;

  const selectedStyle = stored.selectedStyle;
  const message = typeof stored.message === "string"
    ? stored.message.trim()
    : "";
  const reason = typeof stored.reason === "string" ? stored.reason.trim() : "";
  const quotedContext = typeof stored.quotedContext === "string"
    ? stored.quotedContext.trim()
    : "";
  const rawWarnings = Array.isArray(stored.warnings) ? stored.warnings : [];
  const warnings = rawWarnings
    .filter((warning): warning is string => typeof warning === "string")
    .map((warning) => warning.trim())
    .filter(Boolean);
  const raw = isPlainObject(stored.raw) ? stored.raw : stored;
  const storedDecision = optionalRecordFrom(stored.analysisDecisionV2);
  const storedInventory = optionalRecordFrom(stored.analysisInventory);
  const analysisEvidenceLinkage = optionalEvidenceLinkageFrom(
    stored.analysisEvidenceLinkage,
  );
  const analysisDecisionV2 = storedDecision?.schemaVersion === 2
    ? storedDecision
    : undefined;

  // Codex r1 P2：瘦卡 fallback 扣費（message 空、raw 是合法瘦卡形狀）的
  // 已扣費 run 必須可 resume——reframer init 會重掛 pendingThin，由 replay
  // 的 selected reply_option 綁卡回填。否則回 null → STREAM_RUN_NOT_RETRYABLE，
  // 已扣費卻不可續跑。
  const thinResume = message.length === 0 && reason.length > 0 &&
    isThinRecommendationEvent(raw);

  if (
    !isStreamStyle(selectedStyle) || (message.length === 0 && !thinResume)
  ) {
    return null;
  }

  return {
    selectedStyle,
    message,
    reason,
    quotedContext,
    warnings,
    raw,
    ...(analysisDecisionV2 ? { analysisDecisionV2 } : {}),
    ...(storedInventory ? { analysisInventory: storedInventory } : {}),
    ...(analysisEvidenceLinkage ? { analysisEvidenceLinkage } : {}),
  };
}

function isNoSendStreamRun(run: AnalysisStreamRun): boolean {
  if (isNoSendDecisionKind(run.decision_kind)) return true;
  const stored = run.recommendation_json;
  return isPlainObject(stored) &&
    noSendChargePayloadFromStored(stored) !== null;
}

function streamResumeSnapshotFromRun(
  run: AnalysisStreamRun,
  options: { noSendDecisions: boolean },
): StreamAnalysisResumeSnapshot {
  // The capability gate is re-applied on every resume poll: a v1 client that
  // attached while the run was still pending must not receive a no-send
  // result that a v2 request settles later. Surface it as a non-retryable
  // failure instead of a replay.
  if (!options.noSendDecisions && isNoSendStreamRun(run)) {
    return {
      status: "failed",
      finalResult: null,
      lastErrorCode: "STREAM_RUN_NOT_RETRYABLE",
      retriesRemaining: 0,
      wasCharged: run.charged_at !== null,
    };
  }
  return {
    status: run.status,
    finalResult: run.final_result_json,
    lastErrorCode: run.last_error_code,
    retriesRemaining: Math.max(0, MAX_STREAM_RETRIES - run.retry_count),
    wasCharged: run.charged_at !== null,
  };
}

export async function handleAnalyzeStream(
  deps: AnalyzeStreamDeps,
): Promise<Response> {
  const analysisRunId = deps.analysisRunId;
  const streamReplyStyles = streamReplyStylesForTier(deps.effectiveTier).filter(
    (style) => deps.allowedFeatures.includes(style),
  );
  const streamMaxOutputTokens = streamAnalyzeMaxTokensForStyleCount(
    streamReplyStyles.length,
    { divergencePlan: deps.noSendDecisions === true },
  );
  const conversationHashValue = await hashConversation(deps.hashInput);
  const shouldCharge = deps.quotaUsage.shouldChargeQuota &&
    !deps.accountIsTest &&
    !(analysisRunId !== null);

  let streamRun: AnalysisStreamRun;
  let prechargedRecommendation: StreamChargePayload | undefined;
  try {
    if (analysisRunId) {
      streamRun = await deps.store.getRun({
        runId: analysisRunId,
        userId: deps.userId,
        conversationHash: conversationHashValue,
      });
      if (Date.parse(streamRun.expires_at) <= Date.now()) {
        throw new Error("STREAM_RUN_EXPIRED");
      }
      // Capability gate also covers resume/retry: a request without
      // analysisContractVersion 2 never receives a no-send shape, not even by
      // attaching to a run a v2 client created.
      if (!deps.noSendDecisions && isNoSendStreamRun(streamRun)) {
        throw new Error("STREAM_RUN_NOT_RETRYABLE");
      }
      if (
        streamRun.status === "done" &&
        !streamRun.final_result_json
      ) {
        throw new Error("STREAM_DONE_RESULT_MISSING");
      }
      if (
        streamRun.final_result_json ||
        streamRun.status === "done" ||
        streamRun.status === "pending" ||
        streamRun.status === "charged"
      ) {
        logInfo("stream_run_resume_attached", {
          user: summarizeUser(deps.userId),
          analysisRunId: streamRun.id,
          status: streamRun.status,
          retryCount: streamRun.retry_count,
        });
        return handleStreamAnalysisResume({
          runId: streamRun.id,
          conversationHash: conversationHashValue,
          headers: corsHeaders,
          initialRun: streamResumeSnapshotFromRun(streamRun, {
            noSendDecisions: deps.noSendDecisions === true,
          }),
          loadRun: async () => {
            const currentRun = await deps.store.getRun({
              runId: analysisRunId,
              userId: deps.userId,
              conversationHash: conversationHashValue,
            });
            return streamResumeSnapshotFromRun(currentRun, {
              noSendDecisions: deps.noSendDecisions === true,
            });
          },
          onOutcome: (outcome, details) => {
            logInfo("stream_run_resume_outcome", {
              user: summarizeUser(deps.userId),
              analysisRunId: streamRun.id,
              outcome,
              ...details,
            });
          },
        });
      }
      streamRun = await deps.store.reserveRetry({
        runId: analysisRunId,
        userId: deps.userId,
        conversationHash: conversationHashValue,
        maxRetries: MAX_STREAM_RETRIES,
      });
      prechargedRecommendation = streamRecommendationFromRun(streamRun) ??
        undefined;
      if (!prechargedRecommendation) {
        throw new Error("STREAM_RUN_NOT_RETRYABLE");
      }
    } else {
      streamRun = await deps.store.createPendingRun({
        userId: deps.userId,
        conversationHash: conversationHashValue,
        requestContext: {
          responseMode: "stream",
          requestType: deps.requestType,
          analyzeMode: deps.analyzeMode,
          tier: deps.effectiveTier,
          isTestAccount: deps.accountIsTest,
          estimatedMessageCount: deps.quotaUsage.estimatedMessageCount,
          chargedMessageCount: shouldCharge
            ? deps.quotaUsage.chargedMessageCount
            : 0,
        },
      });
    }
  } catch (error) {
    const code = analysisRunId
      ? "STREAM_RUN_RETRY_UNAVAILABLE"
      : "STREAM_RUN_CREATE_FAILED";
    logError(
      analysisRunId ? "stream_run_retry_failed" : "stream_run_create_failed",
      {
        user: summarizeUser(deps.userId),
        analysisRunId: analysisRunId,
        error: getErrorMessage(error),
      },
    );
    return jsonResponse(
      {
        error: code,
        code,
        message: analysisRunId
          ? "這次串流分析無法接續，請重新分析。"
          : "串流分析暫時無法開始，請稍後再試。",
        retryable: false,
      },
      analysisRunId ? 409 : 500,
    );
  }

  let streamModel = deps.selectedModel;
  // Sonnet 5 enables adaptive thinking by default. This endpoint needs its
  // entire fixed output budget for the user-visible NDJSON contract; hidden
  // thinking can otherwise consume the visible-output budget and emit zero
  // contract events.
  let streamThinkingDisabled = deps.selectedModel === "claude-sonnet-5";
  const streamStartTime = Date.now();
  let streamTokenUsage = {
    inputTokens: 0,
    outputTokens: 0,
    cacheCreationTokens: 0,
    cacheReadTokens: 0,
  };
  const streamUsage = {
    messagesUsed: shouldCharge ? deps.quotaUsage.chargedMessageCount : 0,
    estimatedMessages: deps.quotaUsage.estimatedMessageCount,
    monthlyRemaining: deps.accountIsTest ? 999999 : Math.max(
      0,
      deps.monthlyLimit - deps.subMonthlyUsed -
        (shouldCharge ? deps.quotaUsage.chargedMessageCount : 0),
    ),
    dailyRemaining: deps.accountIsTest ? 999999 : Math.max(
      0,
      deps.dailyLimit - deps.subDailyUsed -
        (shouldCharge ? deps.quotaUsage.chargedMessageCount : 0),
    ),
    model: streamModel,
    tierUsed: deps.effectiveTier,
    isTestAccount: deps.accountIsTest,
    requestType: deps.requestType,
    shouldChargeQuota: shouldCharge,
    quotaReason: deps.quotaUsage.quotaReason,
    quotaUnit: deps.quotaUsage.quotaUnit,
  };

  // Phase 2 (§11)：v2 才挑情境 atoms；v1 prompt 一字不動。deterministic，
  // callClaude 重試時重算結果相同，所以只算一次。
  let situationKnowledge: readonly string[] = [];
  if (deps.noSendDecisions === true) {
    const knowledgeInput = {
      messages: deps.messages,
      previousStage: deps.hashInput.previousStage,
      userDraft: deps.hashInput.userDraft,
      conversationSummary: deps.hashInput.conversationSummary,
      effectiveStyleContext: deps.hashInput.effectiveStyleContext,
    };
    const atoms = selectAnalyzeSocialKnowledge(knowledgeInput);
    situationKnowledge = atoms.map((atom) => atom.guidance);
    logInfo("stream_knowledge_selected", {
      user: summarizeUser(deps.userId),
      analysisRunId: streamRun.id,
      knowledgeAtomIds: atoms.map((atom) => atom.id),
      knowledgeSignals: detectAnalyzeSocialKnowledgeSignals(knowledgeInput),
    });
  }

  logInfo("stream_request_started", {
    user: summarizeUser(deps.userId),
    analysisRunId: streamRun.id,
    model: deps.selectedModel,
    requestType: deps.requestType,
    expectedTier: deps.expectedTier,
    effectiveTier: deps.effectiveTier,
    allowedFeatureCount: deps.allowedFeatures.length,
    streamReplyStyleCount: streamReplyStyles.length,
    retrying: !!analysisRunId,
    chargedQuota: shouldCharge,
    thinkingDisabled: streamThinkingDisabled,
  });

  return handleStreamAnalysisRequest({
    runId: streamRun.id,
    conversationHash: conversationHashValue,
    etaSeconds: 18,
    headers: corsHeaders,
    callClaude: async () => {
      const claude = await (deps.callModel ?? callClaudeStreaming)(
        {
          model: deps.selectedModel,
          max_tokens: streamMaxOutputTokens,
          system: buildAnalyzeStreamSystemPrompt(streamReplyStyles, {
            noSendDecisions: deps.noSendDecisions === true,
            situationKnowledge,
            divergencePlan: deps.noSendDecisions === true,
          }),
          messages: [{ role: "user", content: deps.userMessageContent }],
          thinking: streamThinkingDisabled ? { type: "disabled" } : undefined,
        },
        deps.claudeApiKey,
        { timeout: STREAM_CLAUDE_TIMEOUT_MS },
      );
      streamModel = claude.model;
      streamThinkingDisabled = claude.model === "claude-sonnet-5";
      streamTokenUsage = claude.usage;
      streamUsage.model = claude.model;
      return claude;
    },
    chargeRun: async (recommendation) => {
      try {
        await deps.store.chargeRun({
          runId: streamRun.id,
          userId: deps.userId,
          conversationHash: conversationHashValue,
          recommendation,
          chargeQuota: shouldCharge,
          messageCount: shouldCharge ? deps.quotaUsage.chargedMessageCount : 0,
        });
        return { charged: true };
      } catch (error) {
        const mapped = mapStreamChargeFailure(error);
        logError("stream_charge_failed", {
          user: summarizeUser(deps.userId),
          analysisRunId: streamRun.id,
          code: mapped.code,
          error: getErrorMessage(error),
        });
        return {
          charged: false,
          code: mapped.code,
          message: mapped.message,
          recoverable: true,
        };
      }
    },
    prechargedRecommendation,
    requiredReplyStyles: streamReplyStyles,
    noSendDecisions: deps.noSendDecisions === true,
    markDone: async (finalResult) => {
      const guarded = checkAiOutput(
        finalResult as GuardrailAnalysisResult,
      ) as Record<string, unknown>;
      const postProcessed = postProcessAnalysisResult({
        result: guarded,
        recognizeOnly: false,
        isMyMessageMode: false,
        allowedFeatures: deps.allowedFeatures,
        requestMessages: deps.messages,
      });
      const latencyMs = Date.now() - streamStartTime;
      const finalPayload = {
        ...calibratePhase0EvidenceLinkage(postProcessed),
        usage: { ...streamUsage, model: streamModel },
        telemetry: {
          requestType: deps.requestType,
          responseMode: "stream",
          serverAiLatencyMs: latencyMs,
          timeoutMs: STREAM_CLAUDE_TIMEOUT_MS,
          model: streamModel,
          shouldChargeQuota: shouldCharge,
          chargedMessageCount: shouldCharge
            ? deps.quotaUsage.chargedMessageCount
            : 0,
          estimatedMessageCount: deps.quotaUsage.estimatedMessageCount,
        },
      };

      await deps.store.markDone({
        runId: streamRun.id,
        userId: deps.userId,
        conversationHash: conversationHashValue,
        finalResult: finalPayload,
      });

      emitPhase0Observability({
        finalResult: finalPayload,
        user: summarizeUser(deps.userId),
        analysisRunId: streamRun.id,
        emit: logInfo,
      });

      await logAiCall(deps.supabaseUrl, deps.supabaseServiceKey, {
        userId: deps.userId,
        model: streamModel,
        requestType: deps.requestType,
        inputTokens: streamTokenUsage.inputTokens,
        outputTokens: streamTokenUsage.outputTokens,
        cacheCreationTokens: streamTokenUsage.cacheCreationTokens,
        cacheReadTokens: streamTokenUsage.cacheReadTokens,
        latencyMs,
        status: "success",
        requestBody: {
          ...deps.requestObservability,
          responseMode: "stream",
          analysisRunId: streamRun.id,
          thinkingDisabled: streamThinkingDisabled,
          timeoutMs: STREAM_CLAUDE_TIMEOUT_MS,
          providerMaxAttempts: STREAM_PROVIDER_MAX_ATTEMPTS,
          maxOutputTokens: streamMaxOutputTokens,
        },
        responseBody: {
          streamRunStatus: "done",
          chargedQuota: shouldCharge,
          cacheCreationTokens: streamTokenUsage.cacheCreationTokens,
          cacheReadTokens: streamTokenUsage.cacheReadTokens,
        },
      });

      logInfo("stream_request_succeeded", {
        user: summarizeUser(deps.userId),
        analysisRunId: streamRun.id,
        model: streamModel,
        latencyMs,
      });

      return finalPayload;
    },
    markFailed: async (code, details) => {
      const failedRun = await deps.store.markFailed({
        runId: streamRun.id,
        userId: deps.userId,
        conversationHash: conversationHashValue,
        code,
      });

      const event = isPlainObject(details?.event) ? details.event : {};
      event.retriesRemaining = Math.max(
        0,
        MAX_STREAM_RETRIES - failedRun.retry_count,
      );
      const message = typeof event.message === "string" ? event.message : code;
      await logAiCall(deps.supabaseUrl, deps.supabaseServiceKey, {
        userId: deps.userId,
        model: streamModel,
        requestType: deps.requestType,
        inputTokens: streamTokenUsage.inputTokens,
        outputTokens: streamTokenUsage.outputTokens,
        cacheCreationTokens: streamTokenUsage.cacheCreationTokens,
        cacheReadTokens: streamTokenUsage.cacheReadTokens,
        latencyMs: Date.now() - streamStartTime,
        status: "failed",
        errorCode: code,
        errorMessage: message,
        requestBody: {
          ...deps.requestObservability,
          responseMode: "stream",
          analysisRunId: streamRun.id,
          thinkingDisabled: streamThinkingDisabled,
          timeoutMs: STREAM_CLAUDE_TIMEOUT_MS,
          providerMaxAttempts: STREAM_PROVIDER_MAX_ATTEMPTS,
          maxOutputTokens: streamMaxOutputTokens,
        },
        responseBody: {
          streamRunStatus: "failed",
          event,
          retryable: event.recoverable ?? true,
        },
      });
    },
  });
}
