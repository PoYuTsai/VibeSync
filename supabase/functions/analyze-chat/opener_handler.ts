// Opener handler：開場救星（flat cost 3、idempotency ledger、五風格投影）。
// 固定順序：contract/profile 驗證→style sanitize→HMAC preflight→rate limit→
// quota gate→charge（exactly-once ledger）→generate→(wrong surface 422)→
// format repair→tier 投影→回應。stream 為 transport-only，扣費只在
// completeOpenerRequest 共用管線內。

import { enforceModelRateLimit } from "../_shared/model_rate_limit.ts";
import {
  buildQuotaExceededPayload,
  isPlainObject,
} from "../_shared/quota.ts";
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
  OPENER_STREAM_STAGES,
} from "./opener_stream.ts";
import {
  buildOpenerAccess,
  buildWrongSurfaceErrorBody,
  detectOpenerWrongSurface,
  filterOpenerPayloadForAllowedFeatures,
  missingOpenerTypes,
  normalizeOpenerPayload,
  OPENER_FREE_V1_TYPES,
  OPENER_FREE_V2_TYPES,
  OPENER_TYPES,
  parseOpenerContractVersion,
} from "./opener_payload.ts";
import {
  chargeOpenerQuota,
  classifyOpenerReplayPreflight,
  computeOpenerInputHash,
  isValidOpenerRequestId,
  OPENER_REPLAY_LIMIT,
} from "./opener_charge.ts";
import {
  hasOpenerProfileSubstance,
  normalizeOpenerProfileInfo,
} from "./opener_profile.ts";
import { validateOpenerImages } from "./opener_image_validation.ts";
import {
  buildOpenerRepairPrompt,
  OPENER_DEADLINE_MS,
  OPENER_MAX_TOKENS,
  OPENER_PROMPT,
  OPENER_REPAIR_PROMPT,
} from "./opener_prompt.ts";
import {
  type ImageData,
  sanitizeEffectiveStyleContext,
} from "./analysis_input_compiler.ts";
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
import { type TierSyncRefreshStatus } from "./tier_sync_contract.ts";

export interface OpenerQuotaView {
  // deno-lint-ignore no-explicit-any
  sub: any;
  monthlyLimit: number;
  dailyLimit: number;
  effectiveTier: string;
  allowedFeatures: string[];
}

export interface OpenerHandlerDeps {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  userId: string;
  images: unknown;
  rawProfileInfo: unknown;
  rawRequestId: unknown;
  rawKnownContactName: unknown;
  rawEffectiveStyleContext: unknown;
  rawOpenerContractVersion: unknown;
  responseMode: "legacy" | "stream";
  requestStartedAtMs: number;
  accountIsTest: boolean;
  claudeApiKey: string;
  refreshTierFromRevenueCat: (
    reason: string,
  ) => Promise<TierSyncRefreshStatus>;
  /// 額度視圖 getter：refresh 會改寫 handler 端狀態，讀取必取當下值。
  quota: () => OpenerQuotaView;
}

async function repairMalformedOpenerPayload({
  rawText,
  apiKey,
  absoluteDeadlineAtMs,
}: {
  rawText: string;
  apiKey: string;
  absoluteDeadlineAtMs: number;
}): Promise<{
  parsed: Record<string, unknown> | null;
  rawText: string;
  model?: string;
  fallbackUsed?: boolean;
  inputTokens?: number;
  outputTokens?: number;
}> {
  const repairResult = await callClaudeWithFallback(
    {
      model: "claude-sonnet-5",
      max_tokens: OPENER_MAX_TOKENS,
      system: OPENER_REPAIR_PROMPT,
      messages: [
        {
          role: "user",
          content: buildOpenerRepairPrompt(rawText),
        },
      ],
    },
    apiKey,
    {
      timeout: 20000,
      maxRetries: 1,
      allowModelFallback: false,
      absoluteDeadlineAtMs,
    },
  );
  const repairData = repairResult.data as {
    content?: Array<{ text?: string }>;
    usage?: { input_tokens?: number; output_tokens?: number };
  };
  const repairedText = extractClaudeText(repairData);

  return {
    parsed: normalizeOpenerPayload(parseJsonObjectFromText(repairedText)),
    rawText: repairedText,
    model: repairResult.model,
    fallbackUsed: repairResult.fallbackUsed,
    inputTokens: repairData.usage?.input_tokens,
    outputTokens: repairData.usage?.output_tokens,
  };
}

export async function handleOpenerRequest(
  deps: OpenerHandlerDeps,
): Promise<Response> {
  const quota = deps.quota;
  const openerDeadlineAtMs = deps.requestStartedAtMs + OPENER_DEADLINE_MS;
  const openerDeadlineReached = () => Date.now() >= openerDeadlineAtMs;
  const rejectOpenerDeadline = (stage: string) => {
    logWarn("opener_deadline_exceeded", {
      user: summarizeUser(deps.userId),
      stage,
      deadlineMs: OPENER_DEADLINE_MS,
    });
    return jsonResponse({
      error: "OPENER_DEADLINE_EXCEEDED",
      code: "OPENER_DEADLINE_EXCEEDED",
      message: "這次開場白生成逾時，請重新生成；這次不會新增扣額度。",
      shouldChargeQuota: false,
    }, 504);
  };

  // Opener contract v2（Free 3 卡）：只在 opener mode 解析；非法型別在
  // rate limit、模型與扣費前 400。缺席／1＝v1（舊 App Free 維持單卡）。
  const openerContractParse = parseOpenerContractVersion(
    deps.rawOpenerContractVersion,
  );
  if (!openerContractParse.ok) {
    logWarn("opener_contract_version_invalid", {
      user: summarizeUser(deps.userId),
      rawType: typeof deps.rawOpenerContractVersion,
    });
    return jsonResponse({
      error: "OPENER_CONTRACT_VERSION_INVALID",
      code: "OPENER_CONTRACT_VERSION_INVALID",
      message: "App 版本資訊異常，請更新 App 後再試。本次不會扣額度。",
      shouldChargeQuota: false,
    }, 400);
  }
  const openerContractVersion = openerContractParse.version;

  const openerImageValidation = validateOpenerImages(deps.images);
  if (openerImageValidation.error) {
    logWarn("opener_image_validation_failed", {
      user: summarizeUser(deps.userId),
      error: openerImageValidation.error,
      imageCount: Array.isArray(deps.images) ? deps.images.length : null,
    });
    return jsonResponse(
      { error: openerImageValidation.error },
      openerImageValidation.status ?? 400,
    );
  }

  // F3-1：用戶（發訊者）風格設定。無效形狀 400 必須在 rate-limit gate
  // 與任何扣費之前（gate 鐵則：不打模型的拒絕路徑先行）；空字串視同未帶。
  const openerStyleValidation = sanitizeEffectiveStyleContext(
    deps.rawEffectiveStyleContext,
  );
  if (openerStyleValidation.error) {
    return jsonResponse({ error: openerStyleValidation.error }, 400);
  }
  const openerStyleContext = openerStyleValidation.effectiveStyleContext ??
    null;

  const imageCount = Array.isArray(deps.images) ? deps.images.length : 0;
  // Flat cost regardless of image count: image processing cost is
  // absorbed by the platform; users perceive opener as predictable
  // (3 quota per request) and multi-image bills no longer feel
  // punitive for low-value gains.
  const openerCost = 3;

  // Server-side eligibility for no-charge: when input is objectively
  // too thin (no image + no bio/interests/meetingContext content),
  // the server independently decides not to bill. This is the
  // authoritative billing decision — the model's
  // profileAnalysis.insufficientInfo is logged for observability
  // but cannot grant free use on its own. Required to keep
  // prompt-injection in user-controlled profileInfo fields from
  // creating an unbilled opener path.
  //
  // normalizeOpenerProfileInfo() is the single chokepoint that maps
  // raw payload → string-only fields. Both the substance check below
  // and the prompt builder further down read from this normalized
  // object, so a non-string value (e.g. `interests: ["咖啡"]`) cannot
  // simultaneously slip into the prompt while being treated as "no
  // substance" for billing.
  const normalizedProfile = normalizeOpenerProfileInfo(deps.rawProfileInfo);
  const hasProfileSubstance = hasOpenerProfileSubstance(normalizedProfile);
  const serverEligibleForNoCharge = imageCount === 0 &&
    !hasProfileSubstance;
  // Use 0 as the gate cost so a user at the quota cap can still
  // reach the model when the server already plans to bill nothing.
  const upfrontGateCost = serverEligibleForNoCharge ? 0 : openerCost;

  // Batch 4#2 idempotency：requestId＋payload hash 在 quota gate 之前算。
  // Codex R2 P2b：replay 護欄前移——mismatch / 同 payload 刷超過上限
  // 在燒 Claude 成本之前就 400。此讀 fail-open、非原子；最終權威仍在
  // 扣費 RPC 的同款檢查。
  // Codex R3 P2-1：已知同 payload 預算內 dedup（已扣過費的重試）必須
  // 跳過 upfront quota gate——用戶額度剛好扣到頂時，回應丟失的重試
  // 才拿得到 dedup 200，不會被 429 卡死（dedup 不會再扣，跳過安全）。
  const openerRequestId = isValidOpenerRequestId(deps.rawRequestId)
    ? deps.rawRequestId
    : null;
  const openerInputHash = openerRequestId === null
    ? null
    : await computeOpenerInputHash({
      images: deps.images,
      profileInfo: deps.rawProfileInfo,
      effectiveStyleContext: openerStyleContext,
    });
  let openerKnownDedupReplay = false;
  if (openerRequestId !== null && openerInputHash !== null) {
    const { data: replayRow, error: replayReadError } = await deps.supabase
      .from("opener_request_charges")
      .select("input_hash, replay_count")
      .eq("user_id", deps.userId)
      .eq("request_id", openerRequestId)
      .maybeSingle();
    if (replayReadError) {
      logWarn("opener_replay_preflight_read_failed", {
        user: summarizeUser(deps.userId),
        error: replayReadError.message,
      });
    } else {
      const verdict = classifyOpenerReplayPreflight({
        row: replayRow,
        inputHash: openerInputHash,
        replayLimit: OPENER_REPLAY_LIMIT,
      });
      if (verdict !== "proceed") {
        logWarn("opener_charge_replay_blocked_preflight", {
          user: summarizeUser(deps.userId),
          requestId: openerRequestId,
          verdict,
        });
        return jsonResponse({
          error: verdict === "mismatch"
            ? "OPENER_REQUEST_REPLAY_MISMATCH"
            : "OPENER_REQUEST_REPLAY_EXHAUSTED",
          message: verdict === "mismatch"
            ? "這次的輸入和先前的重試不一致，請重新生成一次。本次不會扣額度。"
            : "這個請求已重試太多次，請重新生成一次。本次不會扣額度。",
        }, 400);
      }
      openerKnownDedupReplay = replayRow !== null;
    }
  }

  // 模型呼叫限流（docs/plans/2026-07-03-model-rate-limit-design.md）：
  // opener 3/分、30/日。放在 replay preflight 後（mismatch/exhausted 400
  // 不佔名額）、quota gate 前——並發 storm 在燒 Claude 成本前就封頂
  // （P2-2 成本上界）。已知 dedup replay 不打模型、不計限流，cap 邊緣
  // 重試才不會被 429 卡死。
  if (!openerKnownDedupReplay) {
    const openerRateVerdict = await enforceModelRateLimit({
      supabase: deps.supabase,
      userId: deps.userId,
      scope: "opener",
      isTestAccount: deps.accountIsTest,
    });
    if (openerRateVerdict.kind === "limited") {
      logWarn("model_rate_limited", {
        user: summarizeUser(deps.userId),
        scope: "opener",
        reason: openerRateVerdict.reason,
      });
      return jsonResponse(openerRateVerdict.payload, 429);
    }
    if (openerRateVerdict.kind === "failOpen") {
      // fail-open：infra 錯誤（非超限 RAISE）不擋核心流程，必留 telemetry。
      logError("model_rate_limit_check_failed", {
        user: summarizeUser(deps.userId),
        scope: "opener",
        error: openerRateVerdict.errorMessage,
      });
    }
  }

  // Quota check for opener（已知 dedup 重試不進 gate——那次已扣過費）
  if (!deps.accountIsTest && !openerKnownDedupReplay) {
    const openerExceedsQuota = () =>
      quota().sub.monthly_messages_used + upfrontGateCost > quota().monthlyLimit ||
      quota().sub.daily_messages_used + upfrontGateCost > quota().dailyLimit;

    if (openerExceedsQuota()) {
      await deps.refreshTierFromRevenueCat(
        "opener_quota_exceeded",
      );
      // refresh applied 時 applyRefreshedSub 已重算上限；quota() 即新值。
    }

    if (openerExceedsQuota()) {
      const monthlyRemaining = Math.max(
        0,
        quota().monthlyLimit - quota().sub.monthly_messages_used,
      );
      const dailyRemaining = Math.max(
        0,
        quota().dailyLimit - quota().sub.daily_messages_used,
      );
      const message = monthlyRemaining < upfrontGateCost
        ? "本月額度不足，升級方案可取得更多開場與分析額度。"
        : "今日額度不足，每天早上 8 點恢復；也可以升級取得更多額度。";
      return jsonResponse({
        error: "額度不足",
        message,
        quotaNeeded: upfrontGateCost,
        monthlyRemaining,
        dailyRemaining,
        monthlyLimit: quota().monthlyLimit,
        dailyLimit: quota().dailyLimit,
        monthlyUsed: quota().sub.monthly_messages_used,
        dailyUsed: quota().sub.daily_messages_used,
      }, 429);
    }
  }

  // Build user prompt
  const userContent: string[] = [];

  {
    // Prompt builder reads from the same normalized object as the
    // billing decision above, so a non-string profileInfo field can
    // never leak into the prompt while bypassing the substance check.
    const { name, bio, interests, meetingContext } = normalizedProfile;
    const parts: string[] = [];
    if (name) parts.push(`對方名字：${name}`);
    if (bio) parts.push(`自我介紹：${bio}`);
    if (interests) parts.push(`興趣：${interests}`);
    if (meetingContext) parts.push(`認識場景：${meetingContext}`);
    if (parts.length > 0) {
      userContent.push("用戶提供的對方資訊：\n" + parts.join("\n"));
    }
  }

  if (!userContent.length && !imageCount) {
    userContent.push(
      "用戶沒有提供對方資料。請明確標示可見線索不足，生成低風險、自然、不油、不假裝洞察的開場白。",
    );
  } else if (userContent.length > 0) {
    userContent.push(
      "\n請根據以上可見資訊生成 5 種風格的開場白；只使用明確線索，不要補不存在的人格或共同點。",
    );
  }

  if (imageCount > 0) {
    userContent.push(
      "用戶上傳了對方的交友軟體自介截圖。請先讀取自介文字、明確禁忌、可接線索與照片中的具體場景，再生成開場白；不要只分析照片風格或外貌。",
    );
  }

  // F3-1：風格設定必須在「對方資訊有無」分流之後注入，否則
  // 沒填對方資料時它會被當成「可見資訊」觸發對方線索指令。
  if (openerStyleContext) {
    userContent.push(
      "用戶（發訊者本人）的風格設定：\n" + openerStyleContext +
        "\n這些不是對方的資料；只用來調整開場白語氣，絕不當成對方的興趣或共同點。",
    );
  }

  // All production Opener tiers use Sonnet 5. Older models are reserved
  // for the bounded outage fallback chain in fallback.ts.
  const openerModel = "claude-sonnet-5";

  // Build messages for Claude API
  let claudeMessages;
  if (imageCount > 0 && Array.isArray(deps.images)) {
    const imageContents = deps.images.map((img: ImageData | string) => {
      // Support both ImageData objects and plain base64 strings
      const data = typeof img === "string" ? img : (img as ImageData).data;
      const mediaType = typeof img === "string"
        ? "image/jpeg"
        : ((img as ImageData).mediaType || "image/jpeg");
      return {
        type: "image",
        source: {
          type: "base64",
          media_type: mediaType,
          data,
        },
      };
    });
    claudeMessages = [{
      role: "user",
      content: [
        ...imageContents,
        { type: "text", text: userContent.join("\n") },
      ],
    }];
  } else {
    claudeMessages = [{
      role: "user",
      content: userContent.join("\n"),
    }];
  }

  // Call Claude API using shared fallback helper
  const apiKey = deps.claudeApiKey;

  // ── 2026-08-18 opener 串流（transport-only）────────────────────────
  // 模型輸出契約不變（單一 JSON）。stream 模式只改兩件事：Claude 逐塊
  // 接收＋誠實進度事件。解析／repair／completeness／tier 投影／扣費
  // 與 legacy 共用下面同一個 completeOpenerRequest（內部邏輯零改動，
  // 只把模型輸出以同名 shim 變數餵進去），扣費語義 byte-identical：
  // 驗證全過才扣、失敗一律不扣，done 之前不外流任何生成內容。
  const completeOpenerRequest = async (modelOutput: {
    rawText: string;
    model: string;
    stopReason?: string;
    fallbackUsed: boolean;
    inputTokens?: number;
    outputTokens?: number;
  }): Promise<Response> => {
    const rawText = modelOutput.rawText;
    const apiResult = {
      model: modelOutput.model,
      fallbackUsed: modelOutput.fallbackUsed,
    };
    const apiData = {
      usage: {
        input_tokens: modelOutput.inputTokens,
        output_tokens: modelOutput.outputTokens,
      },
      stop_reason: modelOutput.stopReason,
    };

    // 反 prompt 外洩（2026-08-19）：輸出含系統指示片段＝整包擋下，
    // 不解析、不 repair、不扣費（挑戰式注入的產物不值得修復）。
    // R2 主審 MAJOR-1 澄清：opener 與 new_topic 不同，**沒有**任何
    // claim/lease 機制可釋放（opener_charge.ts 全檔無 claim；本分支
    // 模型呼叫前只有唯讀 preflight、rate-limit 計數與唯讀 quota gate，
    // 與既有 502 路徑同語義），故此處無 release 對稱物是正確的。
    if (hasAnalyzeChatPromptLeak(rawText)) {
      logWarn("prompt_leak_blocked", {
        user: summarizeUser(deps.userId),
        surface: "opener",
        textLength: rawText.length,
      });
      return jsonResponse({
        error: "OPENER_RESPONSE_BLOCKED",
        message: "這次 AI 回傳格式異常，請重新生成一次；本次不會扣額度。",
        shouldChargeQuota: false,
      }, 502);
    }

  // Parse and validate JSON from response. Never surface raw model output
  // as an opener; malformed output gets one format-only repair pass before
  // failing cleanly without charging quota.
  const openerPrimaryParsed = parseJsonObjectFromText(rawText);

  // 錯圖旗標（2026-08-19 Eric 拍板治本）：聊天對話截圖被硬分析後，模型
  // 把拒答說明寫進 opener 卡欄位（活坑「說明塞進資料欄，要用旗標宣告
  // 失敗」真機實錄）——照常扣費、渲染五張廢卡。模型宣告 wrongSurface →
  // 不扣費、不回任何分析內容、結構化 422 引導改用分析功能。免費安全性
  // 與 insufficientInfo 不同：這條路**零內容產出**，注入騙免費也薅不到
  // 東西，模型成本另有 3/分 30/日限流封頂。只認 primary parse 的白名單
  // 值；放在 repair 之前——宣告錯圖時 openers 是空的，晚攔會多燒一次
  // format repair。
  // 判定與 422 body 抽純函式（R1 主審 P1：source-scan 測不到邏輯被刪，
  // 行為測試在 opener_payload_test.ts）。扣費順位證據：opener 限流在模型
  // 呼叫前（enforceModelRateLimit scope "opener" 3/分 30/日），扣費在本
  // return 之後的 chargeOpenerQuota——upfrontGateCost 只做上限比較不預扣，
  // 走到這裡 return 即零落帳。
  const wrongSurface = detectOpenerWrongSurface(
    openerPrimaryParsed,
    imageCount,
  );
  if (wrongSurface) {
    logWarn("opener_wrong_surface", {
      user: summarizeUser(deps.userId),
      surface: wrongSurface,
      imageCount,
      model: apiResult.model,
    });
    return jsonResponse(buildWrongSurfaceErrorBody(wrongSurface), 422);
  }

  let parsed = normalizeOpenerPayload(openerPrimaryParsed);
  let repairMetadata:
    | Awaited<
      ReturnType<typeof repairMalformedOpenerPayload>
    >
    | null = null;
  if (!parsed) {
    try {
      repairMetadata = await repairMalformedOpenerPayload({
        rawText,
        apiKey,
        absoluteDeadlineAtMs: openerDeadlineAtMs,
      });
      parsed = repairMetadata.parsed;
      if (parsed) {
        logInfo("opener_response_repaired", {
          user: summarizeUser(deps.userId),
          model: apiResult.model,
          stopReason: apiData.stop_reason,
          repairModel: repairMetadata.model,
          imageCount,
          originalTextLength: rawText.length,
          repairedTextLength: repairMetadata.rawText.length,
          repairInputTokens: repairMetadata.inputTokens,
          repairOutputTokens: repairMetadata.outputTokens,
        });
      } else {
        logWarn("opener_repair_failed", {
          user: summarizeUser(deps.userId),
          model: apiResult.model,
          stopReason: apiData.stop_reason,
          repairModel: repairMetadata.model,
          imageCount,
          originalTextLength: rawText.length,
          repairedTextLength: repairMetadata.rawText.length,
        });
      }
    } catch (repairError) {
      if (
        (repairError instanceof AiServiceError &&
          repairError.code === "DEADLINE_EXCEEDED") ||
        openerDeadlineReached()
      ) {
        return rejectOpenerDeadline("repair");
      }
      logWarn("opener_repair_error", {
        user: summarizeUser(deps.userId),
        model: apiResult.model,
        imageCount,
        error: getErrorMessage(repairError),
      });
    }
  }
  if (openerDeadlineReached()) {
    return rejectOpenerDeadline("post_parse");
  }
  if (!parsed) {
    logWarn("opener_response_invalid", {
      user: summarizeUser(deps.userId),
      model: apiResult.model,
      stopReason: apiData.stop_reason,
      imageCount,
      textLength: rawText.length,
      startsWithCodeFence: rawText.trim().startsWith("```"),
      containsProfileAnalysis: rawText.includes('"profileAnalysis"'),
      containsOpeners: rawText.includes('"openers"'),
    });
    return jsonResponse({
      error: "開場產生格式異常",
      message: "這次 AI 回傳格式異常，請重新生成一次；本次不會扣額度。",
      shouldChargeQuota: false,
    }, 502);
  }

  // Completeness gate（contract v2 前置）：tier filter 前先確認模型五種
  // 都完整。partial 且尚未 repair 過→ 進一次既有 format repair；repair
  // 後仍不足五種→ 502 不扣（不得偷偷丟掉壞題只投影剩下的）。
  let openerMissingTypes = missingOpenerTypes(parsed);
  if (openerMissingTypes.length > 0 && repairMetadata === null) {
    try {
      repairMetadata = await repairMalformedOpenerPayload({
        rawText,
        apiKey,
        absoluteDeadlineAtMs: openerDeadlineAtMs,
      });
      const repaired = repairMetadata.parsed;
      if (repaired && missingOpenerTypes(repaired).length === 0) {
        parsed = repaired;
        logInfo("opener_response_repaired", {
          user: summarizeUser(deps.userId),
          model: apiResult.model,
          stopReason: apiData.stop_reason,
          repairModel: repairMetadata.model,
          imageCount,
          reason: "incomplete_openers",
          missingTypes: openerMissingTypes,
          originalTextLength: rawText.length,
          repairedTextLength: repairMetadata.rawText.length,
          repairInputTokens: repairMetadata.inputTokens,
          repairOutputTokens: repairMetadata.outputTokens,
        });
      }
    } catch (repairError) {
      if (
        (repairError instanceof AiServiceError &&
          repairError.code === "DEADLINE_EXCEEDED") ||
        openerDeadlineReached()
      ) {
        return rejectOpenerDeadline("completeness_repair");
      }
      logWarn("opener_repair_error", {
        user: summarizeUser(deps.userId),
        model: apiResult.model,
        imageCount,
        error: getErrorMessage(repairError),
      });
    }
    openerMissingTypes = missingOpenerTypes(parsed);
  }
  if (openerDeadlineReached()) {
    return rejectOpenerDeadline("post_completeness");
  }
  if (openerMissingTypes.length > 0) {
    logWarn("opener_response_incomplete", {
      user: summarizeUser(deps.userId),
      model: apiResult.model,
      stopReason: apiData.stop_reason,
      imageCount,
      missingTypes: openerMissingTypes,
      repaired: !!repairMetadata,
    });
    return jsonResponse({
      error: "OPENER_RESPONSE_INCOMPLETE",
      message: "這次 AI 沒有產出完整的五種開場白，請重新生成一次；本次不會扣額度。",
      shouldChargeQuota: false,
    }, 502);
  }

  // Free 權益投影：v1（舊 App）維持 legacy extend 單卡；v2 恰好三種
  // extend/humor/tease。Paid 不因 contract version 改變五卡權益。
  // fallbackOrder＝該 tier 的展示序，推薦被鎖時 fallback 用它取首個完整卡。
  const openerVisibleTypes = quota().effectiveTier === "free"
    ? (openerContractVersion >= 2
      ? OPENER_FREE_V2_TYPES
      : OPENER_FREE_V1_TYPES)
    : OPENER_TYPES;
  const openerAllowedFeatures = quota().effectiveTier === "free"
    ? [...openerVisibleTypes]
    : quota().allowedFeatures;
  const filteredOpenerPayload = filterOpenerPayloadForAllowedFeatures(
    parsed,
    openerAllowedFeatures,
    { fallbackOrder: openerVisibleTypes },
  );
  if (openerDeadlineReached()) {
    return rejectOpenerDeadline("post_filter");
  }
  if (!filteredOpenerPayload) {
    logWarn("opener_response_no_allowed_styles", {
      user: summarizeUser(deps.userId),
      tier: quota().effectiveTier,
      allowedFeatures: openerAllowedFeatures,
      openerKeys: Object.keys(
        isPlainObject(parsed.openers) ? parsed.openers : {},
      ),
    });
    return jsonResponse({
      error: "AI_RESPONSE_INVALID",
      message:
        "這次 AI 沒有產出目前方案可用的開場白，請再試一次。本次不會扣額度。",
      shouldChargeQuota: false,
    }, 502);
  }
  parsed = filteredOpenerPayload;

  // Billing decision: driven by server-side eligibility computed
  // before the model call (no image + no profile substance). The
  // model's profileAnalysis.insufficientInfo is captured for
  // telemetry but cannot grant free use on its own — keeps the
  // quota path safe from prompt-injection in user-controlled
  // profileInfo fields.
  const profileAnalysisObj = isPlainObject(parsed.profileAnalysis)
    ? (parsed.profileAnalysis as Record<string, unknown>)
    : null;
  const aiInsufficientFlag = profileAnalysisObj?.insufficientInfo === true;
  const effectiveOpenerCost = serverEligibleForNoCharge ? 0 : openerCost;

  // The model, fallback chain, and optional repair all share one wall-clock
  // budget. Re-check immediately before settlement so a response that
  // finished at the deadline can never create an orphaned quota charge.
  if (openerDeadlineReached()) {
    return rejectOpenerDeadline("pre_charge");
  }

  // Deduct quota。Batch C#2：帶 tier 上限讓 increment_usage 鎖內複檢，
  // 兜住 preflight 與扣費之間的並發競態；超限 RAISE 映射 429。
  // Batch 4#2：client 帶合法 requestId → increment_usage_idempotent
  // 去重扣費（傳輸層重試不雙扣）；舊 client 走舊路，行為不變。
  if (!deps.accountIsTest && effectiveOpenerCost > 0) {
    // requestId／payload hash 已在模型呼叫前算好（preflight 區塊）。
    // Codex P2：requestId 綁 payload hash——同 id 換輸入會被 RPC 擋，
    // 防改造 client 付一次後無限免費重生成。
    const chargeOutcome = await chargeOpenerQuota({
      rpc: async (fn, params) => await deps.supabase.rpc(fn, params),
      userId: deps.userId,
      cost: effectiveOpenerCost,
      monthlyLimit: quota().monthlyLimit,
      dailyLimit: quota().dailyLimit,
      requestId: openerRequestId,
      inputHash: openerInputHash,
    });

    if (chargeOutcome.kind === "quota_exceeded") {
      logWarn("opener_credit_deduct_quota_exceeded", {
        user: summarizeUser(deps.userId),
        reason: chargeOutcome.reason,
      });
      return jsonResponse(
        buildQuotaExceededPayload({
          sub: quota().sub,
          cost: effectiveOpenerCost,
          reason: chargeOutcome.reason,
          monthlyLimit: quota().monthlyLimit,
          dailyLimit: quota().dailyLimit,
        }),
        429,
      );
    }
    if (
      chargeOutcome.kind === "replay_mismatch" ||
      chargeOutcome.kind === "replay_exhausted"
    ) {
      // 同 requestId 換 payload／同 payload 刷超過上限：正常 client 不會
      // 走到（requestId 隨輸入指紋 rotate、傳輸層重試不會連環三次），
      // 只有改造 client 蹭生成會踩，直接擋（RPC 原子權威，preflight 漏
      // 網的並發也會在這裡被抓）。
      logWarn("opener_charge_replay_blocked", {
        user: summarizeUser(deps.userId),
        requestId: openerRequestId,
        kind: chargeOutcome.kind,
      });
      return jsonResponse({
        error: chargeOutcome.kind === "replay_mismatch"
          ? "OPENER_REQUEST_REPLAY_MISMATCH"
          : "OPENER_REQUEST_REPLAY_EXHAUSTED",
        message: chargeOutcome.kind === "replay_mismatch"
          ? "這次的輸入和先前的重試不一致，請重新生成一次。本次不會扣額度。"
          : "這個請求已重試太多次，請重新生成一次。本次不會扣額度。",
      }, 400);
    }
    if (chargeOutcome.kind === "failed") {
      logError("opener_credit_deduct_failed", {
        user: summarizeUser(deps.userId),
        error: chargeOutcome.message,
      });
      return jsonResponse({
        error: "credit_deduct_failed",
        message: "額度扣除失敗，請稍後再試。本次不會扣額度。",
      }, 500);
    }
    if (chargeOutcome.kind === "dedup") {
      // 同 requestId 已扣過（前次回應在傳輸層丟失後的重試）：
      // 不再扣，照常回 200 完整結果。
      logInfo("opener_charge_dedup_hit", {
        user: summarizeUser(deps.userId),
        requestId: openerRequestId,
        cost: effectiveOpenerCost,
      });
    }
  }

  // Log
  logInfo("opener_success", {
    user: summarizeUser(deps.userId),
    model: apiResult.model,
    imageCount,
    cost: effectiveOpenerCost,
    serverEligibleForNoCharge,
    aiInsufficientFlag,
    inputTokens: apiData.usage?.input_tokens,
    outputTokens: apiData.usage?.output_tokens,
    fallbackUsed: apiResult.fallbackUsed,
    repaired: !!repairMetadata?.parsed,
  });

  return jsonResponse({
    ...parsed,
    // Server 權威 access：client 不可只靠「有幾張卡」猜 tier。
    access: buildOpenerAccess({
      contractVersion: openerContractVersion,
      servedTier: quota().effectiveTier,
      visibleTypes: openerVisibleTypes,
    }),
    usage: {
      model: apiResult.model,
      inputTokens: apiData.usage?.input_tokens,
      outputTokens: apiData.usage?.output_tokens,
      cost: effectiveOpenerCost,
      serverEligibleForNoCharge,
      aiInsufficientFlag,
      repaired: !!repairMetadata?.parsed,
      repairModel: repairMetadata?.parsed
        ? repairMetadata.model
        : undefined,
    },
  });
  };

  // Opener 尚保留自己的 stream flag 相容行為；AnalyzeChat 本身已改為
  // streaming-only 並在不可用時 fail closed，兩者不可混用。
  const openerStreamRequested = deps.responseMode === "stream" &&
    Deno.env.get("OPENER_STREAM_ENABLED") === "true";
  if (deps.responseMode === "stream" && !openerStreamRequested) {
    logInfo("opener_stream_fell_back_to_legacy", {
      user: summarizeUser(deps.userId),
    });
  }
  if (openerStreamRequested) {
    logInfo("opener_stream_started", {
      user: summarizeUser(deps.userId),
      model: openerModel,
      imageCount,
    });
    return ndjsonStreamResponse(async (emit, close) => {
      emit({
        type: "opener.started",
        etaSeconds: 20,
        label: "開始生成開場白",
      });
      const tracker = createStreamStageTracker({
        stages: OPENER_STREAM_STAGES,
        eventType: "opener.progress",
        emit,
      });
      const heartbeat = setInterval(() => {
        emit({
          type: "opener.progress",
          phase: "heartbeat",
          label: "生成仍在進行",
          detail: "正在等待模型完成，請保持連線。",
        });
      }, 15000);
      // R2 主審 round-2 修正：try 只包 provider 呼叫與文字累積，
      // completeOpenerRequest 在 catch 外——complete 內部（含扣費後）
      // 的非預期例外走 ndjson fail（=連線中斷），與 legacy 的全域 500
      // 同語義，不會被誤映成 provider 錯誤。
      try {
        // deadline 先擋：剩餘預算 ≤0 不得再起 provider 呼叫（與 legacy
        // absoluteDeadlineAtMs 拒絕語義一致；不設 1 秒地板）。
        // 已知 transport 差異（記錄為 flag-on 營運風險）：
        // callClaudeStreaming 走自己的 pre-content 模型 fallback 鏈，
        // 無 maxRetries、無絕對 deadline 參數；扣費前仍有 complete 內
        // 的 pre_charge deadline 複檢把關。
        let modelOutput:
          | Parameters<typeof completeOpenerRequest>[0]
          | null = null;
        let failureResponse: Response | null = null;
        const remainingBudgetMs = openerDeadlineAtMs - Date.now();
        if (remainingBudgetMs <= 0) {
          failureResponse = rejectOpenerDeadline("primary_or_fallback");
        } else {
          try {
            const claude = await callClaudeStreaming(
              {
                model: openerModel,
                max_tokens: OPENER_MAX_TOKENS,
                system: OPENER_PROMPT,
                messages: claudeMessages,
              },
              apiKey,
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
              // SSE 串流不外露 stop_reason；complete 內它只進 telemetry
              // log、無任何計費/驗證決策（R2 主審 round-2 已核）。
              fallbackUsed: claude.model !== openerModel,
              inputTokens: claude.usage.inputTokens,
              outputTokens: claude.usage.outputTokens,
            };
          } catch (streamError) {
            // 與 legacy catch 同語義：deadline → 504 body；其他 → 500。
            // 此時必然尚未扣費（complete 還沒跑）。
            if (
              (streamError instanceof AiStreamingServiceError &&
                streamError.code === "TIMEOUT") ||
              openerDeadlineReached()
            ) {
              failureResponse = rejectOpenerDeadline(
                "primary_or_fallback",
              );
            } else {
              logWarn("opener_api_error", {
                error: getErrorMessage(streamError),
                code: streamError instanceof AiStreamingServiceError
                  ? streamError.code
                  : "UNKNOWN",
                model: openerModel,
                imageCount,
                responseMode: "stream",
              });
              failureResponse = jsonResponse({
                error: `AI 生成失敗：${getErrorMessage(streamError)}`,
                shouldChargeQuota: false,
              }, 500);
            }
          }
        }

        if (failureResponse !== null) {
          await emitJsonResponseAsStreamOutcome(
            failureResponse,
            emit,
            "opener",
          );
        } else if (modelOutput !== null) {
          emit({
            type: "opener.progress",
            phase: "finalizing",
            label: "整理與驗證結果",
          });
          const response = await completeOpenerRequest(modelOutput);
          await emitJsonResponseAsStreamOutcome(response, emit, "opener");
        }
      } finally {
        clearInterval(heartbeat);
        close();
      }
    }, corsHeaders);
  }

  let apiResult: FallbackResult;
  try {
    apiResult = await callClaudeWithFallback(
      {
        model: openerModel,
        max_tokens: OPENER_MAX_TOKENS,
        system: OPENER_PROMPT,
        messages: claudeMessages,
      },
      apiKey,
      {
        timeout: 60000,
        maxRetries: 1,
        allowModelFallback: true,
        absoluteDeadlineAtMs: openerDeadlineAtMs,
      },
    );
  } catch (apiError) {
    if (
      (apiError instanceof AiServiceError &&
        apiError.code === "DEADLINE_EXCEEDED") ||
      openerDeadlineReached()
    ) {
      return rejectOpenerDeadline("primary_or_fallback");
    }
    const errMsg = getErrorMessage(apiError);
    const errCode = apiError instanceof AiServiceError
      ? apiError.code
      : "UNKNOWN";
    const errMeta = apiError instanceof AiServiceError
      ? apiError.metadata
      : {};
    logWarn("opener_api_error", {
      error: errMsg,
      code: errCode,
      metadata: errMeta,
      model: openerModel,
      imageCount,
      userContentLength: userContent.join("\n").length,
    });
    return jsonResponse({ error: `AI 生成失敗：${errMsg}` }, 500);
  }

  const legacyApiData = apiResult.data as {
    content?: Array<{ text?: string }>;
    usage?: { input_tokens?: number; output_tokens?: number };
    stop_reason?: string;
  };
  return await completeOpenerRequest({
    rawText: extractClaudeText(legacyApiData),
    model: apiResult.model,
    stopReason: legacyApiData.stop_reason,
    fallbackUsed: apiResult.fallbackUsed,
    inputTokens: legacyApiData.usage?.input_tokens,
    outputTokens: legacyApiData.usage?.output_tokens,
  });
}
