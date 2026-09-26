// 開場救星兩段式 handler（附件 §12.2）。
//
// 第一段 opener_analyze：驗證請求與登入 → 取得分析作業資格（claim）→ 限流 →
//   讀取資料（模型）→ 驗證分析與問題 → 保存快照（settle）→ 回傳分析。
//   分析不扣費、不回任何開場白、不在背景預先生成五句。
// 第二段 opener_generate：驗證會話與本次回答 → 取得生成資格或重播既有結果 →
//   額度預查與限流 → 整理原料並生成 → 格式與內容檢核（各最多一次修復／修正）→
//   按權益選推薦 → 交易保存與扣費（settle）→ 回傳結果。
//
// 串流（responseMode=stream）是 transport-only：結算前只有 started/progress，
// 可交付內容只隨 *.done 出去（第一段本來就免費可見，但同樣不外流半成品）。
// 模型邊界透過 deps.invokeModel 可替換（測試替身只換這一層；claim／settle／
// 原料整理／投影都走正式路徑）。

import { ModelCallBudget } from "./model_call_budget.ts";
import { OPENER_GENERATE_REPAIR_PROMPT } from "./opener_flow_prompt.ts";
import { enforceModelRateLimit } from "../_shared/model_rate_limit.ts";
import { buildQuotaExceededPayload } from "../_shared/quota.ts";
import { AiServiceError, callClaudeWithFallback, type ClaudeMessageContent, extractClaudeText } from "./fallback.ts";
import { AiStreamingServiceError, callClaudeStreaming } from "./streaming_fallback.ts";
import { ndjsonStreamResponse } from "./ndjson_response.ts";
import {
  createStreamStageTracker,
  emitJsonResponseAsStreamOutcome,
  OPENER_ANALYZE_STREAM_STAGES,
  OPENER_CARDSET2_GENERATE_STREAM_STAGES,
  OPENER_GENERATE_STREAM_STAGES,
  type StreamStageSpec,
} from "./opener_stream.ts";
import {
  buildWrongSurfaceErrorBody,
  detectOpenerWrongSurface,
  OPENER_FREE_V1_TYPES,
  OPENER_FREE_V2_TYPES,
  OPENER_TYPES,
  type OpenerType,
  parseOpenerContractVersion,
} from "./opener_payload.ts";
import { hasOpenerProfileSubstance, normalizeOpenerProfileInfo } from "./opener_profile.ts";
import { validateOpenerImages } from "./opener_image_validation.ts";
import { type ImageData } from "./analysis_input_compiler.ts";
import { hasAnalyzeChatPromptLeak } from "./prompt_leak.ts";
import { getErrorMessage, logError, logInfo, logWarn, summarizeUser } from "./logger.ts";
import { corsHeaders, jsonResponse } from "./http_response.ts";
import { parseJsonObjectFromText } from "./json_text.ts";
import type { OpenerQuotaView } from "./opener_handler.ts";
import type { TierSyncRefreshStatus } from "./tier_sync_contract.ts";
import {
  buildOpenerAnalysisSnapshot,
  computeOpenerGenerationInputHash,
  graphemeLength,
  OPENER_ANALYSIS_LEASE_SECONDS,
  OPENER_FIRST_GENERATION_COST,
  OPENER_FLOW_PROMPT_VERSION,
  OPENER_FLOW_VERSION,
  OPENER_GENERATION_LEASE_SECONDS,
  OPENER_INCLUDED_GENERATION_COUNT,
  OPENER_SESSION_TTL_SECONDS,
  type OpenerAnalysisSnapshot,
  parseOpenerAnalyzeRequest,
  parseOpenerGenerateRequest,
  projectAnalysisForClient,
  validateContributionAgainstSnapshot,
} from "./opener_stage.ts";
import {
  buildOpenerMaterials,
  hardFlags,
  type OpenerMaterialSet,
  type OpenerQualityFlag,
} from "./opener_material.ts";
import {
  buildOpenerAnalyzeUserContent,
  buildOpenerContentCorrectionPrompt,
  buildOpenerFlowRepairPrompt,
  buildOpenerGenerateUserContent,
  OPENER_ANALYZE_DEADLINE_MS,
  OPENER_ANALYZE_MAX_TOKENS,
  OPENER_ANALYZE_PROMPT,
  OPENER_ANALYZE_SCHEMA_HINT,
  OPENER_FLOW_MODEL,
  OPENER_FLOW_REPAIR_PROMPT,
  OPENER_GENERATE_DEADLINE_MS,
  OPENER_GENERATE_MAX_TOKENS,
  OPENER_GENERATE_PROMPT,
  OPENER_GENERATE_SCHEMA_HINT,
} from "./opener_flow_prompt.ts";
import {
  planWriteEnabled,
  runOpenerPlanWrite,
  writerArmFromRequest,
} from "./opener_plan_write.ts";
import {
  mergeOpenerCorrection,
  normalizeOpenerGenerateOutput,
  checkOpenerGenerationContent,
  type OpenerGenerateLedgerResult,
  projectOpenerGenerateResult,
  type OpenerGenerateNormalized,
} from "./opener_flow_payload.ts";
import {
  buildReplayUsage,
  claimOpenerAnalysis,
  claimOpenerGeneration,
  OPENER_FLOW_DB_CONTRACT_VERSION,
  type OpenerFlowRpc,
  type OpenerFlowRpcFailure,
  type OpenerGenerationUsage,
  type OpenerSessionView,
  readOpenerFlowDbContractVersion,
  readPreviousPromptReplay,
  releaseOpenerAnalysisClaim,
  releaseOpenerGenerationClaim,
  settleOpenerAnalysis,
  settleOpenerGeneration,
} from "./opener_session.ts";

export type OpenerFlowModelMessage = { role: string; content: ClaudeMessageContent };

export interface OpenerFlowModelRequest {
  system: string;
  messages: OpenerFlowModelMessage[];
  maxTokens: number;
  deadlineAtMs: number;
  allowModelFallback: boolean;
  purpose?: string;
  onChunk?: (chunk: string) => void;
}

export interface OpenerFlowModelOutput {
  rawText: string;
  model: string;
  stopReason?: string;
  inputTokens?: number;
  outputTokens?: number;
}

export class OpenerFlowDeadlineError extends Error {
  constructor(stage: string) {
    super(`opener flow deadline exceeded at ${stage}`);
  }
}

export type OpenerFlowModelInvoker = (req: OpenerFlowModelRequest) => Promise<OpenerFlowModelOutput>;

export interface OpenerFlowHandlerDeps {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  userId: string;
  requestBody: Record<string, unknown>;
  responseMode: "legacy" | "stream";
  requestStartedAtMs: number;
  accountIsTest: boolean;
  claudeApiKey: string;
  refreshTierFromRevenueCat: (reason: string) => Promise<TierSyncRefreshStatus>;
  quota: () => OpenerQuotaView;
  /** 測試替身：只替換模型邊界。 */
  invokeModel?: OpenerFlowModelInvoker;
  /** 測試替身：旗標讀取。 */
  env?: (name: string) => string | undefined;
}

const defaultInvokeModel = (apiKey: string, budget: ModelCallBudget): OpenerFlowModelInvoker => async (req) => {
  const remainingMs = req.deadlineAtMs - Date.now();
  if (remainingMs <= 0) throw new OpenerFlowDeadlineError("before_model");
  if (req.onChunk) {
    try {
      const claude = await callClaudeStreaming(
        { model: OPENER_FLOW_MODEL, max_tokens: req.maxTokens, system: req.system, messages: req.messages },
        apiKey,
        { timeout: remainingMs, absoluteDeadlineAtMs: req.deadlineAtMs, budget,
          purpose: req.purpose, allowModelFallback: req.allowModelFallback },
      );
      let fullText = "";
      for await (const chunk of claude.textStream) {
        fullText += chunk;
        req.onChunk(chunk);
      }
      return {
        rawText: fullText,
        model: claude.model,
        inputTokens: claude.usage.inputTokens,
        outputTokens: claude.usage.outputTokens,
      };
    } catch (error) {
      if (error instanceof AiStreamingServiceError && error.code === "TIMEOUT") {
        throw new OpenerFlowDeadlineError("stream");
      }
      throw error;
    }
  }
  try {
    const result = await callClaudeWithFallback(
      { model: OPENER_FLOW_MODEL, max_tokens: req.maxTokens, system: req.system, messages: req.messages },
      apiKey,
      {
        timeout: Math.min(60000, remainingMs),
        maxRetries: 1,
        allowModelFallback: req.allowModelFallback,
        budget, purpose: req.purpose,
        absoluteDeadlineAtMs: req.deadlineAtMs,
      },
    );
    const data = result.data as {
      content?: Array<{ text?: string }>;
      usage?: { input_tokens?: number; output_tokens?: number };
      stop_reason?: string;
    };
    return {
      rawText: extractClaudeText(data),
      model: result.model,
      stopReason: data.stop_reason,
      inputTokens: data.usage?.input_tokens,
      outputTokens: data.usage?.output_tokens,
    };
  } catch (error) {
    if (error instanceof AiServiceError && error.code === "DEADLINE_EXCEEDED") {
      throw new OpenerFlowDeadlineError("legacy");
    }
    throw error;
  }
};

function flowError(
  code: string,
  message: string,
  status: number,
  extra: Record<string, unknown> = {},
): Response {
  return jsonResponse({ error: code, code, message, shouldChargeQuota: false, ...extra }, status);
}

function rpcFailureResponse(
  failure: OpenerFlowRpcFailure,
  stage: string,
  userId: string,
): Response {
  if (failure.kind === "business") {
    switch (failure.code) {
      case "OPENER_SESSION_INVALID":
        return flowError("OPENER_SESSION_INVALID", "找不到這份分析，請重新分析。本次不會扣額度。", 404);
      case "OPENER_SESSION_EXPIRED":
        return flowError("OPENER_SESSION_EXPIRED", "這份分析已到期，重新分析後可再生成。本次不會扣額度。", 410);
      case "OPENER_OPERATION_INPUT_MISMATCH":
        return flowError("OPENER_OPERATION_INPUT_MISMATCH", "這次輸入已改變，請重新送出。本次不會扣額度。", 409);
      case "OPENER_GENERATION_LIMIT_REACHED":
        return flowError("OPENER_GENERATION_LIMIT_REACHED", "這局的三組回覆已用完；重新分析可開始新的一局。", 409, {
          includedGenerationCount: OPENER_INCLUDED_GENERATION_COUNT,
          newSessionCost: OPENER_FIRST_GENERATION_COST,
        });
      case "OPENER_OPERATION_OWNER_MISMATCH":
        return flowError("OPENER_GENERATION_PENDING", "這組回覆還在生成，請稍候用同一筆請求重試。", 409, { retryable: true, retryAfterMs: 1500 });
      case "OPENER_OPERATION_LEASE_EXPIRED":
        // R1 fencing：本作業租約已過期（可能已被同局其他 ID 接手），本地結果丟棄；
        // 用同一筆請求重試會重新 claim（若同局已有有效工作則回 busy）。
        return flowError("OPENER_GENERATION_PENDING", "這組回覆已逾時，請用同一筆請求再試一次；本次不會扣額度。", 409, { retryable: true, retryAfterMs: 1500 });
      case "OPENER_SUBSCRIPTION_MISSING":
        return flowError("OPENER_SETTLEMENT_FAILED", "找不到訂閱資料，請重新登入後再試；本次不會扣額度。", 500);
    }
  }
  if (failure.kind === "quota_exceeded") {
    return flowError("額度不足", "額度不足，請先升級方案。", 429);
  }
  if (failure.kind === "retryable") {
    logWarn("opener_flow_rpc_retryable", { user: summarizeUser(userId), stage, error: failure.message });
    return flowError("OPENER_FLOW_RETRYABLE", "服務暫時無法確認狀態，請稍後用同一筆請求重試。", 503, { retryable: true });
  }
  logError("opener_flow_rpc_failed", { user: summarizeUser(userId), stage, error: failure.message });
  return flowError("OPENER_FLOW_FAILED", "服務暫時異常，請稍後再試；本次不會扣額度。", 503, { retryable: true });
}

function releaseFailedResponse(): Response {
  return flowError("OPENER_CLAIM_RELEASE_RETRYABLE", "請求狀態暫時無法釋放，請稍後用同一筆請求重試。", 503, { retryable: true });
}

function buildClaudeMessages(images: unknown, text: string): OpenerFlowModelMessage[] {
  if (Array.isArray(images) && images.length > 0) {
    const imageContents = images.map((img: ImageData | string) => {
      const data = typeof img === "string" ? img : (img as ImageData).data;
      const mediaType = typeof img === "string" ? "image/jpeg" : ((img as ImageData).mediaType || "image/jpeg");
      return { type: "image" as const, source: { type: "base64" as const, media_type: mediaType, data } };
    });
    return [{ role: "user", content: [...imageContents, { type: "text" as const, text }] }];
  }
  return [{ role: "user", content: text }];
}

function visibleTypesFor(tier: string, contractVersion: 1 | 2): readonly OpenerType[] {
  return tier === "free"
    ? (contractVersion >= 2 ? OPENER_FREE_V2_TYPES : OPENER_FREE_V1_TYPES)
    : OPENER_TYPES;
}

function analyzeResponseBody(input: {
  sessionId: string;
  analysisRevision: number;
  expiresAt: string;
  snapshot: OpenerAnalysisSnapshot;
  firstGenerationCost: number;
  quotaCharged: boolean;
  generationsUsed: number;
  replayed: boolean;
}): Record<string, unknown> {
  return {
    stage: "analyze",
    flowVersion: OPENER_FLOW_VERSION,
    sessionId: input.sessionId,
    analysisRevision: input.analysisRevision,
    expiresAt: input.expiresAt,
    ...projectAnalysisForClient(input.snapshot),
    usage: {
      chargedNow: 0,
      firstGenerationCost: input.firstGenerationCost,
      includedGenerationCount: OPENER_INCLUDED_GENERATION_COUNT,
      generationsUsed: input.generationsUsed,
      generationsRemaining: Math.max(0, OPENER_INCLUDED_GENERATION_COUNT - input.generationsUsed),
      quotaCharged: input.quotaCharged,
    },
    replayed: input.replayed,
  };
}

/**
 * 同一筆生成可能由另一版 App 重播（GPT 預審 R3）：舊版 App（沒帶 openerCardSet=2）不認得「方向＋範例」，
 * 會把範例當一般卡顯示、一鍵複製。回給它的投影拿掉範例卡（範例卡不會是推薦）；存著的結果不動、不重生、不重扣。
 */
export function resultForClient(result: OpenerGenerateLedgerResult, showsExamples: boolean): OpenerGenerateLedgerResult {
  const examples = Object.keys(result.access.directions ?? {}) as OpenerType[];
  if (showsExamples || examples.length === 0) return result;
  const out = structuredClone(result);
  for (const type of examples) {
    delete out.openers[type];
    delete out.cardReasons[type];
    delete out.stretchLevels[type];
  }
  delete out.access.directions;
  return out;
}

function generateResponseBody(input: {
  session: OpenerSessionView;
  generationId: string;
  result: OpenerGenerateLedgerResult;
  usage: OpenerGenerationUsage;
  showsExamples: boolean;
}): Record<string, unknown> {
  return {
    stage: "generate",
    flowVersion: OPENER_FLOW_VERSION,
    sessionId: input.session.sessionId,
    analysisRevision: input.session.analysisRevision,
    generationId: input.generationId,
    expiresAt: input.session.expiresAt,
    ...resultForClient(input.result, input.showsExamples),
    usage: {
      ...input.usage,
      cost: input.usage.chargedNow,
      includedGenerationCount: OPENER_INCLUDED_GENERATION_COUNT,
    },
  };
}

/** 串流包裝：pre-model 閘門已用一般 JSON 回完；這裡只包模型呼叫與 complete。 */
function streamOrRun(input: {
  deps: OpenerFlowHandlerDeps;
  prefix: string;
  stages: StreamStageSpec[];
  etaSeconds: number;
  startedLabel: string;
  run: (onChunk?: (chunk: string) => void, onFinalizing?: () => void) => Promise<Response>;
}): Promise<Response> {
  const env = input.deps.env ?? ((name) => Deno.env.get(name));
  const streamRequested = input.deps.responseMode === "stream" && env("OPENER_STREAM_ENABLED") === "true";
  if (!streamRequested) return input.run();
  return Promise.resolve(ndjsonStreamResponse(async (emit, close) => {
    emit({ type: `${input.prefix}.started`, etaSeconds: input.etaSeconds, label: input.startedLabel });
    const tracker = createStreamStageTracker({ stages: input.stages, eventType: `${input.prefix}.progress`, emit });
    const heartbeat = setInterval(() => {
      emit({ type: `${input.prefix}.progress`, phase: "heartbeat", label: "仍在進行", detail: "正在等待模型完成，請保持連線。" });
    }, 15000);
    try {
      const response = await input.run((chunk) => tracker.push(chunk), () => {
        emit({ type: `${input.prefix}.progress`, phase: "finalizing", label: "正在確認最後結果" });
      });
      await emitJsonResponseAsStreamOutcome(response, emit, input.prefix);
    } finally {
      clearInterval(heartbeat);
      close();
    }
  }, corsHeaders));
}

// ═══════════════════════════════════════════════════════════════════════════
// 第一段：opener_analyze
// ═══════════════════════════════════════════════════════════════════════════

export async function handleOpenerAnalyzeRequest(deps: OpenerFlowHandlerDeps): Promise<Response> {
  const env = deps.env ?? ((name) => Deno.env.get(name));
  const body = deps.requestBody;
  const user = summarizeUser(deps.userId);
  const rpc: OpenerFlowRpc = async (fn, params) => await deps.supabase.rpc(fn, params);

  // 0. DB 能力標記（migration 沒套齊＝根本沒有會話可重播）：新版 App 收到 503
  //    只在「尚未進入兩段式」時退回舊單段。停用新局的旗標放在 claim 之後（R6b）：
  //    已保存的分析同 analysisRequestId 重試仍能取回，旗標只擋真正的新局。
  const newSessionsDisabled = env("OPENER_TWO_STAGE_ENABLED") === "false";
  const dbContract = await readOpenerFlowDbContractVersion(rpc);
  if (dbContract !== OPENER_FLOW_DB_CONTRACT_VERSION) {
    logError("opener_flow_db_contract_missing", { user, dbContract });
    return flowError("OPENER_FLOW_UNAVAILABLE", "新版開場流程尚未就緒，改用一般生成。本次不會扣額度。", 503, { retryable: false });
  }

  // 1. 驗證請求（全部在 claim、限流、模型之前）。
  const contractParse = parseOpenerContractVersion(body.openerContractVersion);
  if (!contractParse.ok) {
    return flowError("OPENER_CONTRACT_VERSION_INVALID", "App 版本資訊異常，請更新 App 後再試。本次不會扣額度。", 400);
  }
  const parsed = parseOpenerAnalyzeRequest({
    rawFlowVersion: body.openerFlowVersion,
    rawAnalysisRequestId: body.analysisRequestId,
    rawInitialUserNote: body.initialUserNote,
    contractVersion: contractParse.version,
  });
  if (!parsed.ok) return flowError(parsed.code, parsed.message, 400);
  const request = parsed.request;
  const imageValidation = validateOpenerImages(body.images);
  if (imageValidation.error) {
    // 新版錯誤一律帶 code：App 靠「400 卻沒有 code」辨識舊 Edge 不支援兩段式。
    return flowError("OPENER_IMAGE_INVALID", imageValidation.error, imageValidation.status ?? 400);
  }
  const images = Array.isArray(body.images) ? body.images : [];
  const imageCount = images.length;
  const profile = normalizeOpenerProfileInfo(body.profileInfo);
  // 客觀零扣費判準沿用舊單段（無圖＋無對方實質資料）；用戶補充不冒充對方資料。
  const serverEligibleForNoCharge = imageCount === 0 && !hasOpenerProfileSubstance(profile);
  const firstGenerationCost = serverEligibleForNoCharge ? 0 : OPENER_FIRST_GENERATION_COST;
  if (!deps.claudeApiKey) {
    return flowError("OPENER_FLOW_UNAVAILABLE", "開場功能暫時無法使用，請稍後再試。本次不會扣額度。", 503, { retryable: true });
  }

  // 2. 會話輸入指紋：對方資料＋初稿（同 analysisRequestId 換任一項＝不同輸入）。
  const inputHash = await sha256Hex(JSON.stringify([
    "vibesync-opener-analysis-v1",
    body.images ?? null,
    body.profileInfo ?? null,
    request.initialUserNote,
    OPENER_FLOW_VERSION,
  ]));

  // 3. Claim 分析作業。
  const ownerToken = crypto.randomUUID();
  const claimArgs = {
    rpc,
    userId: deps.userId,
    analysisRequestId: request.analysisRequestId,
    inputHash,
    ownerToken,
    flowVersion: OPENER_FLOW_VERSION,
    contractVersion: request.contractVersion,
    leaseSeconds: OPENER_ANALYSIS_LEASE_SECONDS,
  };
  const release = async (): Promise<boolean> => {
    const released = await releaseOpenerAnalysisClaim({ rpc, userId: deps.userId, analysisRequestId: request.analysisRequestId, ownerToken });
    logInfo("opener_analyze_claim_released", { user, released });
    return released;
  };
  const handleClaim = (claim: Awaited<ReturnType<typeof claimOpenerAnalysis>>): Response | null => {
    switch (claim.kind) {
      case "claimed":
        return null;
      case "replay":
        logInfo("opener_analyze_replay_hit", { user });
        return jsonResponse(analyzeResponseBody({
          sessionId: claim.session.sessionId,
          analysisRevision: claim.session.analysisRevision,
          expiresAt: claim.session.expiresAt,
          snapshot: claim.session.snapshot,
          firstGenerationCost: claim.session.firstGenerationCost,
          quotaCharged: claim.session.quotaCharged,
          generationsUsed: claim.session.generationsUsed,
          replayed: true,
        }));
      case "pending":
        return flowError("OPENER_ANALYSIS_PENDING", "這份分析正在處理中，請稍候用同一筆請求重試。", 409, { retryable: true, retryAfterMs: claim.retryAfterMs });
      case "expired":
        return flowError("OPENER_SESSION_EXPIRED", "這份分析已到期，請重新分析。本次不會扣額度。", 410);
      case "error":
        return rpcFailureResponse(claim.failure, "analyze_claim", deps.userId);
    }
  };
  {
    const claimResponse = handleClaim(await claimOpenerAnalysis(claimArgs));
    if (claimResponse !== null) return claimResponse;
  }
  if (newSessionsDisabled) {
    // 走到這裡＝沒有可重播的快照、真的要開新局：停用中，釋放資格後退回舊單段。
    if (!await release()) return releaseFailedResponse();
    return flowError("OPENER_FLOW_UNAVAILABLE", "新版開場流程暫停中，改用一般生成。本次不會扣額度。", 503, { retryable: false });
  }

  // 4. 限流（scope 與第二段、舊單段共用 opener 3/分 30/日）。
  {
    const verdict = await enforceModelRateLimit({ supabase: deps.supabase, userId: deps.userId, scope: "opener", isTestAccount: deps.accountIsTest, failClosed: true });
    if (verdict.kind === "limited") {
      logWarn("model_rate_limited", { user, scope: "opener", stage: "analyze", reason: verdict.reason });
      if (!await release()) return releaseFailedResponse();
      return jsonResponse(verdict.payload, 429);
    }
    if (verdict.kind === "unavailable") {
      logError("model_rate_limit_check_failed", { user, scope: "opener", error: verdict.errorMessage });
      if (!await release()) return releaseFailedResponse();
      return jsonResponse(verdict.payload, 503);
    }
  }
  {
    const renewResponse = handleClaim(await claimOpenerAnalysis(claimArgs));
    if (renewResponse !== null) return renewResponse;
  }

  const deadlineAtMs = deps.requestStartedAtMs + OPENER_ANALYZE_DEADLINE_MS;
  const budget = new ModelCallBudget(deadlineAtMs, { user, stage: "analyze", operation: request.analysisRequestId, tier: deps.quota().effectiveTier, flowVersion: OPENER_FLOW_VERSION });
  const invokeModel = deps.invokeModel ?? defaultInvokeModel(deps.claudeApiKey, budget);
  const userContent = buildOpenerAnalyzeUserContent({ profile, imageCount, initialUserNote: request.initialUserNote });
  const messages = buildClaudeMessages(images, userContent);

  const rejectDeadline = async (stage: string): Promise<Response> => {
    logWarn("opener_analyze_deadline_exceeded", { user, stage });
    if (!await release()) return releaseFailedResponse();
    return flowError("OPENER_DEADLINE_EXCEEDED", "這次分析逾時，請重新分析一次；本次不會扣額度。", 504);
  };

  return streamOrRun({
    deps,
    prefix: "opener_analyze",
    stages: OPENER_ANALYZE_STREAM_STAGES,
    etaSeconds: 12,
    startedLabel: "開始分析對方資料",
    run: async (onChunk) => {
      let output: OpenerFlowModelOutput;
      try {
        output = await invokeModel({ system: OPENER_ANALYZE_PROMPT, messages, maxTokens: OPENER_ANALYZE_MAX_TOKENS, deadlineAtMs, allowModelFallback: true, onChunk });
      } catch (error) {
        if (error instanceof OpenerFlowDeadlineError || Date.now() >= deadlineAtMs) return await rejectDeadline("model");
        logWarn("opener_analyze_api_error", { user, error: getErrorMessage(error), imageCount });
        if (!await release()) return releaseFailedResponse();
        return flowError("OPENER_PROVIDER_UNAVAILABLE", "AI 暫時分析失敗，請稍後再試；本次不會扣額度。", 503, { retryable: true });
      }
      if (hasAnalyzeChatPromptLeak(output.rawText)) {
        logWarn("prompt_leak_blocked", { user, surface: "opener_analyze", textLength: output.rawText.length });
        if (!await release()) return releaseFailedResponse();
        return flowError("OPENER_RESPONSE_BLOCKED", "這次 AI 回傳格式異常，請重新分析一次；本次不會扣額度。", 502);
      }
      const primary = parseJsonObjectFromText(output.rawText);
      const wrongSurface = detectOpenerWrongSurface(primary, imageCount);
      if (wrongSurface) {
        logWarn("opener_wrong_surface", { user, surface: wrongSurface, imageCount, stage: "analyze" });
        if (!await release()) return releaseFailedResponse();
        return jsonResponse(buildWrongSurfaceErrorBody(wrongSurface), 422);
      }
      let snapshot = buildOpenerAnalysisSnapshot({ parsed: primary, rawProfileInfo: body.profileInfo, imageCount, initialUserNote: request.initialUserNote });
      let repaired = false;
      if (!snapshot) {
        try {
          const repair = await invokeModel({
            system: OPENER_FLOW_REPAIR_PROMPT,
            messages: [{ role: "user", content: buildOpenerFlowRepairPrompt(OPENER_ANALYZE_SCHEMA_HINT, output.rawText) }],
            maxTokens: OPENER_ANALYZE_MAX_TOKENS,
            deadlineAtMs,
            allowModelFallback: false,
            purpose: "repair",
          });
          snapshot = buildOpenerAnalysisSnapshot({ parsed: parseJsonObjectFromText(repair.rawText), rawProfileInfo: body.profileInfo, imageCount, initialUserNote: request.initialUserNote });
          repaired = snapshot !== null;
        } catch (error) {
          if (error instanceof OpenerFlowDeadlineError || Date.now() >= deadlineAtMs) return await rejectDeadline("repair");
          logWarn("opener_analyze_repair_error", { user, error: getErrorMessage(error) });
        }
      }
      if (!snapshot) {
        logWarn("opener_analyze_response_invalid", { user, model: output.model, stopReason: output.stopReason, textLength: output.rawText.length });
        if (!await release()) return releaseFailedResponse();
        return flowError("OPENER_ANALYSIS_INVALID", "這次分析格式異常，請重新分析一次；本次不會扣額度。", 502);
      }
      if (Date.now() >= deadlineAtMs) return await rejectDeadline("pre_settlement");

      const settlement = await settleOpenerAnalysis({
        rpc,
        userId: deps.userId,
        analysisRequestId: request.analysisRequestId,
        ownerToken,
        snapshot,
        firstGenerationCost,
        ttlSeconds: OPENER_SESSION_TTL_SECONDS,
      });
      if (settlement.kind === "error") {
        if (settlement.failure.kind === "retryable") {
          return rpcFailureResponse(settlement.failure, "analyze_settle", deps.userId);
        }
        if (settlement.failure.kind === "business" && settlement.failure.code === "OPENER_OPERATION_OWNER_MISMATCH") {
          return flowError("OPENER_ANALYSIS_PENDING", "這份分析已由另一個請求接手，請稍候用同一筆請求重試。", 409, { retryable: true, retryAfterMs: 1500 });
        }
        await release();
        return rpcFailureResponse(settlement.failure, "analyze_settle", deps.userId);
      }
      logInfo("opener_analyze_success", {
        user,
        imageCount,
        mode: settlement.snapshot.approach.mode,
        cueCount: settlement.snapshot.cues.length,
        hasQuestion: settlement.snapshot.question !== null,
        questionAffects: settlement.snapshot.question?.affects ?? null,
        initialNoteProvided: request.initialUserNote !== null,
        firstGenerationCost,
        replayed: settlement.replayed,
        repaired,
        model: output.model,
        inputTokens: output.inputTokens,
        outputTokens: output.outputTokens,
        elapsedMs: Date.now() - deps.requestStartedAtMs,
      });
      return jsonResponse(analyzeResponseBody({
        sessionId: settlement.sessionId,
        analysisRevision: settlement.analysisRevision,
        expiresAt: settlement.expiresAt,
        snapshot: settlement.snapshot,
        firstGenerationCost: settlement.firstGenerationCost,
        quotaCharged: false,
        generationsUsed: 0,
        replayed: settlement.replayed,
      }));
    },
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// 第二段：opener_generate
// ═══════════════════════════════════════════════════════════════════════════

export async function handleOpenerGenerateRequest(deps: OpenerFlowHandlerDeps): Promise<Response> {
  const body = deps.requestBody;
  const user = summarizeUser(deps.userId);
  const quota = deps.quota;
  const rpc: OpenerFlowRpc = async (fn, params) => await deps.supabase.rpc(fn, params);

  // 1. 驗證請求形狀（不看快照）。
  const contractParse = parseOpenerContractVersion(body.openerContractVersion);
  if (!contractParse.ok) {
    return flowError("OPENER_CONTRACT_VERSION_INVALID", "App 版本資訊異常，請更新 App 後再試。本次不會扣額度。", 400);
  }
  const contractVersion = contractParse.version;
  const parsed = parseOpenerGenerateRequest({
    rawFlowVersion: body.openerFlowVersion,
    rawSessionId: body.sessionId,
    rawAnalysisRevision: body.analysisRevision,
    rawGenerationId: body.generationId,
    rawContribution: body.userContribution,
  });
  if (!parsed.ok) return flowError(parsed.code, parsed.message, parsed.code === "OPENER_SESSION_INVALID" ? 404 : 400);
  const request = parsed.request;
  if (!deps.claudeApiKey) {
    return flowError("OPENER_FLOW_UNAVAILABLE", "開場功能暫時無法使用，請稍後再試。本次不會扣額度。", 503, { retryable: true });
  }
  // 結構刀（規劃→寫手→另外挑）旗標：關閉時舊路徑逐位元組不變。輸入指紋不分路徑，
  // 旗標切換時同一筆請求照常重播或重新取得（不會卡在 409 輸入已改變）。
  // 只給新版 App（openerCardSet=2，一句推薦＋四句備選）：舊版 App 旗標開了也走舊路徑，
  // 上線只影響新版，現有用戶不變（Bruce benchmark 只比過 B 與舊路徑）。
  const env = deps.env ?? ((name) => Deno.env.get(name));
  const showsExamples = writerArmFromRequest(body) === "free";
  const usePlanWrite = planWriteEnabled(env) && showsExamples;

  // 2. 生成輸入指紋（回答一定入 hash）＋ claim（同 ID 已完成→重播、進行中→pending、
  //    同局另一作業→busy、三組用完→擋，都在模型呼叫前）。
  const inputHash = await computeOpenerGenerationInputHash({
    sessionId: request.sessionId,
    analysisRevision: request.analysisRevision,
    contribution: request.contribution,
    promptVersion: OPENER_FLOW_PROMPT_VERSION,
    contractVersion,
  });
  const ownerToken = crypto.randomUUID();
  const claimArgs = {
    rpc,
    userId: deps.userId,
    sessionId: request.sessionId,
    generationId: request.generationId,
    inputHash,
    ownerToken,
    contribution: request.contribution,
    maxGenerations: OPENER_INCLUDED_GENERATION_COUNT,
    leaseSeconds: OPENER_GENERATION_LEASE_SECONDS,
  };
  const release = async (): Promise<boolean> => {
    const released = await releaseOpenerGenerationClaim({ rpc, userId: deps.userId, generationId: request.generationId, ownerToken });
    logInfo("opener_generate_claim_released", { user, released });
    return released;
  };
  let session: OpenerSessionView | null = null;
  const handleClaim = (claim: Awaited<ReturnType<typeof claimOpenerGeneration>>): Response | null => {
    switch (claim.kind) {
      case "claimed":
        session = claim.session;
        return null;
      case "replay":
        logInfo("opener_generate_replay_hit", { user, traceStatus: claim.result.materialUse.traceStatus });
        return jsonResponse(generateResponseBody({
          session: claim.session,
          generationId: request.generationId,
          result: claim.result,
          usage: buildReplayUsage(claim.session, OPENER_INCLUDED_GENERATION_COUNT),
          showsExamples,
        }));
      case "pending":
        return flowError("OPENER_GENERATION_PENDING", "這組回覆還在生成，請稍候用同一筆請求重試。", 409, { retryable: true, retryAfterMs: claim.retryAfterMs });
      case "session_busy":
        return flowError("OPENER_GENERATION_PENDING", "這局已有一組回覆正在生成，請等它完成。", 409, { retryable: true, retryAfterMs: claim.retryAfterMs, activeGenerationId: claim.generationId });
      case "error":
        return rpcFailureResponse(claim.failure, "generate_claim", deps.userId);
    }
  };
  {
    let claim = await claimOpenerGeneration(claimArgs);
    if (claim.kind === "error" && claim.failure.kind === "business" && claim.failure.code === "OPENER_OPERATION_INPUT_MISMATCH") {
      claim = await readPreviousPromptReplay({ supabase: deps.supabase, userId: deps.userId, ...request, contractVersion }) ?? claim;
    }
    const claimResponse = handleClaim(claim);
    if (claimResponse !== null) return claimResponse;
  }
  const activeSession = session as unknown as OpenerSessionView;

  // 3. 快照層驗證：版本、題目與選項屬於本局（F12）。
  if (activeSession.analysisRevision !== request.analysisRevision) {
    if (!await release()) return releaseFailedResponse();
    return flowError("OPENER_SESSION_INVALID", "這份分析已更新，請重新分析後再生成。本次不會扣額度。", 404);
  }
  const contributionCheck = validateContributionAgainstSnapshot(request.contribution, activeSession.snapshot);
  if (!contributionCheck.ok) {
    if (!await release()) return releaseFailedResponse();
    return flowError("OPENER_CONTRIBUTION_INVALID", contributionCheck.message, 400);
  }

  // 4. 額度預查（只在尚未扣費的會話）；已扣費的同局剩餘生成不因其他功能用完額度而擋。
  const cost = activeSession.firstGenerationCost;
  const needsCharge = !deps.accountIsTest && !activeSession.quotaCharged && cost > 0;
  if (needsCharge) {
    const exceeds = () =>
      quota().sub.monthly_messages_used + cost > quota().monthlyLimit ||
      quota().sub.daily_messages_used + cost > quota().dailyLimit;
    if (exceeds()) await deps.refreshTierFromRevenueCat("opener_generate_quota_exceeded");
    if (exceeds()) {
      if (!await release()) return releaseFailedResponse();
      const monthlyRemaining = Math.max(0, quota().monthlyLimit - quota().sub.monthly_messages_used);
      const dailyRemaining = Math.max(0, quota().dailyLimit - quota().sub.daily_messages_used);
      logWarn("opener_generate_quota_exceeded", { user, monthlyRemaining, dailyRemaining });
      return jsonResponse({
        error: "額度不足",
        message: monthlyRemaining < cost
          ? "本月額度不足，升級方案可取得更多開場與分析額度。"
          : "今日額度不足，每天早上 8 點恢復；也可以升級取得更多額度。",
        quotaNeeded: cost,
        monthlyRemaining,
        dailyRemaining,
        monthlyLimit: quota().monthlyLimit,
        dailyLimit: quota().dailyLimit,
        monthlyUsed: quota().sub.monthly_messages_used,
        dailyUsed: quota().sub.daily_messages_used,
      }, 429);
    }
  }

  // 5. 限流（新的模型作業才計次；重播已在 claim 回掉）。
  {
    const verdict = await enforceModelRateLimit({ supabase: deps.supabase, userId: deps.userId, scope: "opener", isTestAccount: deps.accountIsTest, failClosed: true });
    if (verdict.kind === "limited") {
      logWarn("model_rate_limited", { user, scope: "opener", stage: "generate", reason: verdict.reason });
      if (!await release()) return releaseFailedResponse();
      return jsonResponse(verdict.payload, 429);
    }
    if (verdict.kind === "unavailable") {
      logError("model_rate_limit_check_failed", { user, scope: "opener", error: verdict.errorMessage });
      if (!await release()) return releaseFailedResponse();
      return jsonResponse(verdict.payload, 503);
    }
  }
  {
    const renewResponse = handleClaim(await claimOpenerGeneration(claimArgs));
    if (renewResponse !== null) return renewResponse;
  }

  // 6. 原料整理（確定性）＋模型。
  const materials: OpenerMaterialSet = buildOpenerMaterials({
    snapshot: activeSession.snapshot,
    contribution: request.contribution,
    option: contributionCheck.option,
  });
  const deadlineAtMs = deps.requestStartedAtMs + OPENER_GENERATE_DEADLINE_MS;
  const budget = new ModelCallBudget(deadlineAtMs, { user, stage: "generate", operation: request.generationId, tier: deps.quota().effectiveTier, flowVersion: OPENER_FLOW_VERSION });
  const invokeModel = deps.invokeModel ?? defaultInvokeModel(deps.claudeApiKey, budget);
  const userContent = buildOpenerGenerateUserContent({ snapshot: activeSession.snapshot, materials, currentFreeText: request.contribution.freeText });
  const rejectDeadline = async (stage: string): Promise<Response> => {
    logWarn("opener_generate_deadline_exceeded", { user, stage });
    if (!await release()) return releaseFailedResponse();
    return flowError("OPENER_DEADLINE_EXCEEDED", "這次生成逾時，請重新生成一次；本次不會扣額度。", 504);
  };
  const failNoCharge = async (code: string, message: string, status: number): Promise<Response> => {
    if (!await release()) return releaseFailedResponse();
    return flowError(code, message, status);
  };

  // 8. 結算（新舊路徑共用）：保存結果＋首次扣費＋成功數＋完成，同一交易；再驗額度、期限、租約。
  const settleAndRespond = async (projected: OpenerGenerateLedgerResult, pathLog: Record<string, unknown>): Promise<Response> => {
    const settlement = await settleOpenerGeneration({
      rpc,
      userId: deps.userId,
      sessionId: request.sessionId,
      generationId: request.generationId,
      ownerToken,
      result: projected,
      monthlyLimit: quota().monthlyLimit,
      dailyLimit: quota().dailyLimit,
      chargeQuota: !deps.accountIsTest,
      maxGenerations: OPENER_INCLUDED_GENERATION_COUNT,
    });
    if (settlement.kind === "error") {
      const failure = settlement.failure;
      if (failure.kind === "retryable") {
        // 結果不明：可能已 commit＋已扣，絕不 release、絕不宣稱不扣。
        logWarn("opener_generate_settlement_pending", { user, error: failure.message });
        return flowError("OPENER_SETTLEMENT_PENDING", "結果正在確認，請用同一筆請求重試。", 503, { retryable: true });
      }
      if (failure.kind === "quota_exceeded") {
        if (!await release()) return releaseFailedResponse();
        logWarn("opener_generate_settle_quota_race", { user, reason: failure.reason });
        return jsonResponse(buildQuotaExceededPayload({ sub: quota().sub, cost, reason: failure.reason, monthlyLimit: quota().monthlyLimit, dailyLimit: quota().dailyLimit }), 429);
      }
      if (failure.kind === "business" && failure.code === "OPENER_OPERATION_OWNER_MISMATCH") {
        // 租約已被接手：本地結果丟棄，不 release（不是我們的）。
        logWarn("opener_generate_stale_owner", { user });
        return rpcFailureResponse(failure, "generate_settle", deps.userId);
      }
      if (failure.kind === "business" && failure.code === "OPENER_OPERATION_LEASE_EXPIRED") {
        // 租約過期但仍是我們的列：owner-bound release 讓同 ID 可重新取得資格。
        logWarn("opener_generate_lease_expired", { user });
        await release();
        return rpcFailureResponse(failure, "generate_settle", deps.userId);
      }
      await release();
      return rpcFailureResponse(failure, "generate_settle", deps.userId);
    }

    logInfo("opener_generate_success", {
      user,
      inputState: materials.inputState,
      materialCount: materials.materials.length,
      hasFreeText: request.contribution.freeText !== null,
      freeTextGraphemes: request.contribution.freeText ? graphemeLength(request.contribution.freeText) : 0,
      optionMeaning: contributionCheck.option?.meaning ?? null,
      ...pathLog,
      traceStatus: settlement.result.materialUse.traceStatus,
      referenceCount: settlement.result.materialUse.references.length,
      pick: settlement.result.recommendation.pick,
      chargedNow: settlement.usage.chargedNow,
      generationsUsed: settlement.usage.generationsUsed,
      replayed: settlement.usage.replayed,
      elapsedMs: Date.now() - deps.requestStartedAtMs,
    });
    // Handler 永遠回 settlement 的 stored result（stale race 時本地候選丟棄）。
    return jsonResponse(generateResponseBody({
      session: activeSession,
      generationId: request.generationId,
      result: settlement.result,
      usage: settlement.usage,
      showsExamples,
    }));
  };

  return streamOrRun({
    deps,
    prefix: "opener_generate",
    stages: usePlanWrite ? OPENER_CARDSET2_GENERATE_STREAM_STAGES : OPENER_GENERATE_STREAM_STAGES,
    etaSeconds: 20,
    startedLabel: "開始整理你的想法並生成回覆",
    run: async (onChunk, onFinalizing) => {
      if (usePlanWrite) {
        const servedTier = quota().effectiveTier;
        const outcome = await runOpenerPlanWrite({
          snapshot: activeSession.snapshot,
          freeText: request.contribution.freeText,
          option: contributionCheck.option,
          materials,
          visibleTypes: visibleTypesFor(servedTier, contractVersion),
          servedTier,
          contractVersion,
          arm: writerArmFromRequest(body),
        }, { invokeModel, deadlineAtMs, isDeadlineError: (error) => error instanceof OpenerFlowDeadlineError, onChunk });
        onFinalizing?.();
        // telemetry 只有代碼與計數，不含用戶原文。
        const { verdicts, ...planWriteLog } = outcome.telemetry;
        const pathLog = {
          path: "plan_write",
          servedTier,
          ...planWriteLog,
          vetoes: Object.fromEntries(Object.entries(verdicts).map(([k, v]) => [k, v?.vetoes ?? []])),
          demotions: Object.fromEntries(Object.entries(verdicts).map(([k, v]) => [k, v?.demotions ?? []])),
        };
        if (outcome.kind === "fail") {
          logWarn("opener_generate_plan_write_failed", { user, reason: outcome.reason, stage: outcome.stage, ...pathLog });
          switch (outcome.reason) {
            case "deadline":
              return await rejectDeadline(outcome.stage);
            case "provider":
              if (!await release()) return releaseFailedResponse();
              return flowError("OPENER_PROVIDER_UNAVAILABLE", "AI 暫時生成失敗，請稍後再試；本次不會扣額度。", 503, { retryable: true });
            case "leak":
              logWarn("prompt_leak_blocked", { user, surface: "opener_generate_plan_write" });
              return await failNoCharge("OPENER_RESPONSE_BLOCKED", "這次 AI 回傳格式異常，請重新生成一次；本次不會扣額度。", 502);
            case "incomplete":
              return await failNoCharge("OPENER_RESPONSE_INCOMPLETE", "這次沒生成成功，可以重試；本次不會扣額度。", 502);
            case "no_deliverable":
              return await failNoCharge("OPENER_CONTENT_CONFLICT", "這次沒生成成功，可以重試；本次不會扣額度。", 502);
          }
        }
        if (Date.now() >= deadlineAtMs) return await rejectDeadline("pre_settlement");
        return await settleAndRespond(outcome.result, pathLog);
      }
      let output: OpenerFlowModelOutput;
      try {
        output = await invokeModel({ system: OPENER_GENERATE_PROMPT, messages: [{ role: "user", content: userContent }], maxTokens: OPENER_GENERATE_MAX_TOKENS, deadlineAtMs, allowModelFallback: true, onChunk });
      } catch (error) {
        if (error instanceof OpenerFlowDeadlineError || Date.now() >= deadlineAtMs) return await rejectDeadline("model");
        logWarn("opener_generate_api_error", { user, error: getErrorMessage(error) });
        if (!await release()) return releaseFailedResponse();
        return flowError("OPENER_PROVIDER_UNAVAILABLE", "AI 暫時生成失敗，請稍後再試；本次不會扣額度。", 503, { retryable: true });
      }
      onFinalizing?.();
      if (hasAnalyzeChatPromptLeak(output.rawText)) {
        logWarn("prompt_leak_blocked", { user, surface: "opener_generate", textLength: output.rawText.length });
        return await failNoCharge("OPENER_RESPONSE_BLOCKED", "這次 AI 回傳格式異常，請重新生成一次；本次不會扣額度。", 502);
      }

      // R5：格式修復與內容修正共用「一次額外機會」（附件 §12.2：每個作業的修復／
      // 修正合計最多再做一次），並累加所有嘗試的 usage；拿不到的記 unknown，不當 0。
      let extraCallsRemaining = 1;
      const usageTotal = { inputTokens: 0, outputTokens: 0, complete: true, attempts: 0 };
      const addUsage = (out: OpenerFlowModelOutput) => {
        usageTotal.attempts += 1;
        if (typeof out.inputTokens === "number" && typeof out.outputTokens === "number") {
          usageTotal.inputTokens += out.inputTokens;
          usageTotal.outputTokens += out.outputTokens;
        } else {
          usageTotal.complete = false;
        }
      };
      addUsage(output);

      // 6a. 格式：解析／正規化；不齊五句就做一次格式修復（只修 JSON，不換意思）。
      let parsedJson = parseJsonObjectFromText(output.rawText);
      let normalized = normalizeOpenerGenerateOutput(parsedJson, materials, true);
      let repaired = false;
      if (!normalized.ok && extraCallsRemaining > 0) {
        extraCallsRemaining -= 1;
        try {
          const repair = await invokeModel({
            system: OPENER_GENERATE_REPAIR_PROMPT,
            messages: [{ role: "user", content: "修復下列生成契約；usage 必须依當次素材判斷，並同步修正受影響的句子與說明。\n" + OPENER_GENERATE_SCHEMA_HINT + "\n原始回覆：\n" + output.rawText.slice(0, 12000) + "\n\n當次素材與線索：\n" + userContent }],
            maxTokens: OPENER_GENERATE_MAX_TOKENS,
            deadlineAtMs,
            allowModelFallback: false,
            purpose: "repair",
          });
          addUsage(repair);
          const repairedJson = parseJsonObjectFromText(repair.rawText);
          const repairedNormalized = normalizeOpenerGenerateOutput(repairedJson, materials, true);
          if (repairedNormalized.ok) {
            parsedJson = repairedJson;
            normalized = repairedNormalized;
            repaired = true;
          }
        } catch (error) {
          if (error instanceof OpenerFlowDeadlineError || Date.now() >= deadlineAtMs) return await rejectDeadline("format_repair");
          logWarn("opener_generate_repair_error", { user, error: getErrorMessage(error) });
        }
      }
      if (!normalized.ok || !parsedJson) {
        logWarn("opener_generate_response_invalid", { user, reason: normalized.ok ? "no_json" : normalized.reason, missing: normalized.ok ? [] : normalized.missing, model: output.model, stopReason: output.stopReason });
        return await failNoCharge("OPENER_RESPONSE_INCOMPLETE", "這次沒生成成功，可以重試；本次不會扣額度。", 502);
      }

      // 6b. 內容硬檢查：沒有來源的自述、否定被反轉、排除話題被用——做一次有界
      //     內容修正（只改被標記的句子），仍有硬錯誤就回失敗，不交付假裝成功的卡。
      // 第五輪 A：方案可見卡在硬檢查前就要知道——原料採用是以用戶看得到的卡判定。
      const servedTier = quota().effectiveTier;
      const visibleTypes = visibleTypesFor(servedTier, contractVersion);
      const contentFlags = (value: OpenerGenerateNormalized): OpenerQualityFlag[] =>
        checkOpenerGenerationContent(value, materials, activeSession.snapshot, visibleTypes);
      let flags: OpenerQualityFlag[] = contentFlags(normalized.value);
      const hardBefore = hardFlags(flags);
      const reconsiderSelection = hardBefore.some((flag) => flag.code === "material_unused");
      let corrected = false;
      if (hardBefore.length > 0 && extraCallsRemaining > 0) {
        extraCallsRemaining -= 1;
        try {
          const correction = await invokeModel({
            system: OPENER_GENERATE_PROMPT,
            messages: [{ role: "user", content: buildOpenerContentCorrectionPrompt({ previousJson: JSON.stringify(parsedJson), flags: hardBefore, materials: reconsiderSelection ? materials : normalized.value.selection.eligible, omitted: normalized.value.selection.omitted, snapshot: activeSession.snapshot }) }],
            maxTokens: OPENER_GENERATE_MAX_TOKENS,
            deadlineAtMs,
            allowModelFallback: false,
            purpose: "repair",
          });
          addUsage(correction);
          const stylesToReplace = [...new Set(hardBefore.map((flag) => flag.style).filter((s): s is string => typeof s === "string"))];
          const merged = mergeOpenerCorrection(parsedJson, parseJsonObjectFromText(correction.rawText), stylesToReplace, reconsiderSelection ? materials : undefined);
          const mergedNormalized = normalizeOpenerGenerateOutput(merged, materials, true);
          if (mergedNormalized.ok) {
            const mergedFlags = contentFlags(mergedNormalized.value);
            if (hardFlags(mergedFlags).length === 0) {
              parsedJson = merged;
              normalized = mergedNormalized;
              flags = mergedFlags;
              corrected = true;
            }
          }
        } catch (error) {
          if (error instanceof OpenerFlowDeadlineError || Date.now() >= deadlineAtMs) return await rejectDeadline("content_correction");
          logWarn("opener_generate_correction_error", { user, error: getErrorMessage(error) });
        }
      }
      const hardAfter = hardFlags(flags);
      if (hardAfter.length > 0) {
        logWarn("opener_generate_content_conflict", { user, flags: hardAfter.map((f) => `${f.code}:${f.style ?? ""}`), corrected, repaired, extraCallsRemaining });
        return await failNoCharge("OPENER_CONTENT_CONFLICT", "這次沒生成成功，可以重試；本次不會扣額度。", 502);
      }
      if (Date.now() >= deadlineAtMs) return await rejectDeadline("pre_projection");

      // 7. 權益投影：先篩可見卡，再從可見卡選推薦（先看原料證據，再看 rankedPicks）。
      const projected = projectOpenerGenerateResult({ normalized: normalized.value, materials, visibleTypes, servedTier, contractVersion });
      if (!projected) {
        return await failNoCharge("AI_RESPONSE_INVALID", "這次 AI 沒有產出目前方案可用的開場白，請再試一次。本次不會扣額度。", 502);
      }
      if (Date.now() >= deadlineAtMs) return await rejectDeadline("pre_settlement");

      return await settleAndRespond(projected, {
        softFlags: flags.filter((f) => f.severity === "soft").map((f) => f.code),
        hardFlagsBeforeCorrection: hardBefore.map((f) => f.code),
        corrected,
        repaired,
        servedTier,
        model: output.model,
        // 累加主呼叫＋修復／修正的 usage；usageComplete=false 代表有嘗試拿不到 usage，
        // 這個數字不得當本局完整模型成本。
        inputTokens: usageTotal.inputTokens,
        outputTokens: usageTotal.outputTokens,
        modelAttempts: usageTotal.attempts,
        usageComplete: usageTotal.complete,
      });
    },
  });
}

async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}
