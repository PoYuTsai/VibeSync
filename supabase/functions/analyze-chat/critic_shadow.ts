// supabase/functions/analyze-chat/critic_shadow.ts
//
// Phase 3d：Analyze 的第二層語意審核器，先以「影子」方式跑（規格 §15.3：
// 絕不整條 fail-closed）。只審最終選中的那一張卡，跑在 analysis.done 之後的
// 背景（EdgeRuntime.waitUntil），永遠不改結果、不擋、不 throw；只出
// `stream_semantic_critic` telemetry 與 ai_logs 成本紀錄。
// 觸發條件與模型是產品／成本決定（ANALYZE_CRITIC_SHADOW），預設關閉。

import {
  ANALYZE_CRITIC_VIOLATIONS,
  type AnalyzeCriticCandidate,
  type AnalyzeCriticEvidence,
  buildAnalyzeCriticPrompt,
  parseSemanticCriticUsage,
  parseSemanticCriticVerdict,
  SEMANTIC_CRITIC_MAX_TOKENS,
  type SemanticCriticCallArgs,
} from "../_shared/social/semantic_critic.ts";
import { isPlainObject } from "../_shared/quota.ts";
import { parseDivergencePlanV1 } from "./divergence_contract.ts";
import {
  deliveredReplyText,
  replySegmentsForStyle,
  selectedDeliveredStyle,
} from "./phase0_observability.ts";

export interface AnalyzeCriticShadowConfig {
  readonly enabled: boolean;
  readonly model: string;
  readonly timeoutMs: number;
  /// always＝每個 send 的選中卡都審；risk＝只在守門違規、beta flags 或四張同開頭時審。
  readonly trigger: "always" | "risk";
}

/// 模型＝Sonnet 5（Eric 2026-09-03 定案）；觸發條件與成本上限定案前預設關閉，
/// 開關是一行 commit。
export const ANALYZE_CRITIC_SHADOW: AnalyzeCriticShadowConfig = {
  enabled: false,
  model: "claude-sonnet-5",
  timeoutMs: 12_000,
  trigger: "risk",
};

export const ANALYZE_CRITIC_REQUEST_TYPE = "analyze_semantic_critic";
const RECENT_MESSAGES = 12;
const SAME_OPENING_TRIGGER_AT = 4;
const NO_SEND = new Set([
  "do_not_send",
  "acknowledge_and_stop",
  "need_context",
]);
const DISPOSITIONS = new Set(["接", "併", "略"]);

type Message = { readonly isFromMe: boolean; readonly content: string };

function record(value: unknown): Record<string, unknown> | null {
  return isPlainObject(value) && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function text(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() !== "" ? value : undefined;
}

function stringList(value: unknown): string[] | undefined {
  return Array.isArray(value) &&
      value.every((item) => typeof item === "string" && item.trim() !== "")
    ? value as string[]
    : undefined;
}

function positiveInt(value: unknown): number | undefined {
  return typeof value === "number" && Number.isInteger(value) && value > 0
    ? value
    : undefined;
}

function decisionV2(
  finalResult: Record<string, unknown>,
): Record<string, unknown> | null {
  const decision = record(finalResult.analysisDecisionV2);
  return decision?.schemaVersion === 2 ? decision : null;
}

/// 選中卡＝client 真正看到的那張（finalRecommendation 優先，讀法同 phase0）。
function selectedCard(finalResult: Record<string, unknown>): {
  style: string;
  segments: Record<string, unknown>[];
  text: string;
} | null {
  const linkage = record(finalResult.analysisEvidenceLinkage) ?? {};
  const style = selectedDeliveredStyle(finalResult, linkage);
  if (!style) return null;
  const segments = replySegmentsForStyle(finalResult, style, style) ?? [];
  const delivered = deliveredReplyText(finalResult, style, style, segments);
  return delivered ? { style, segments, text: delivered } : null;
}

/// 回 null＝不跑；否則回觸發理由（進 telemetry，方便之後對成本）。
export function analyzeCriticTrigger(
  finalResult: Record<string, unknown>,
  phase0: Record<string, unknown> | null,
  mode: AnalyzeCriticShadowConfig["trigger"],
): string[] | null {
  const decision = decisionV2(finalResult);
  if (decision && NO_SEND.has(String(decision.messageDecision))) return null;
  if (!selectedCard(finalResult)) return null;
  if (mode === "always") return ["always"];

  const reasons: string[] = [];
  const violations = record(phase0?.candidateGuard)?.violations;
  if (Array.isArray(violations)) {
    for (const code of new Set(violations.map((v) => record(v)?.code))) {
      if (typeof code === "string") reasons.push(`guard:${code}`);
    }
  }
  for (const flag of new Set(stringList(decision?.betaRiskFlags) ?? [])) {
    reasons.push(`beta:${flag}`);
  }
  const sameOpening = record(phase0?.divergencePlan)?.sameOpeningCount;
  if (
    typeof sameOpening === "number" && sameOpening >= SAME_OPENING_TRIGGER_AT
  ) {
    reasons.push("same_opening");
  }
  return reasons.length > 0 ? reasons : null;
}

/// 把 client 真正拿到的結果組成 critic 的證據與候選；只帶選中卡與它用到的枝。
export function buildAnalyzeCriticInput(
  finalResult: Record<string, unknown>,
  messages: readonly Message[],
  guardViolations: readonly string[],
):
  | { evidence: AnalyzeCriticEvidence; candidate: AnalyzeCriticCandidate }
  | null {
  const card = selectedCard(finalResult);
  if (!card) return null;
  const decision = decisionV2(finalResult);
  const variant = record(
    record(record(finalResult.analysisEvidenceLinkage)?.variants)?.[card.style],
  );
  const plan = parseDivergencePlanV1(finalResult.analysisDivergencePlan);
  const usedBranchIds = stringList(variant?.selectedBranchIds) ?? [];

  const balls = record(finalResult.analysisInventory)?.balls;
  const inventory = Array.isArray(balls)
    ? balls.flatMap((ball) => {
      const item = record(ball);
      const sourceIndex = positiveInt(item?.sourceIndex);
      const disposition = item?.disposition;
      return sourceIndex && typeof disposition === "string" &&
          DISPOSITIONS.has(disposition)
        ? [{
          sourceIndex,
          disposition,
          text: text(item?.sourceMessage) ?? null,
        }]
        : [];
    })
    : [];

  const evidence: AnalyzeCriticEvidence = {
    messages: messages.slice(-RECENT_MESSAGES).map((message) => ({
      from: message.isFromMe ? "me" : "her",
      text: message.content,
    })),
    inventory: inventory.length > 0 ? inventory : null,
    decision: decision
      ? {
        ...(text(decision.messageDecision)
          ? { messageDecision: decision.messageDecision as string }
          : {}),
        ...(text(decision.action) ? { action: decision.action as string } : {}),
        ...(stringList(decision.selectedBallIds)
          ? { selectedBallIds: decision.selectedBallIds as string[] }
          : {}),
        ...(stringList(decision.betaRiskFlags)
          ? { betaRiskFlags: decision.betaRiskFlags as string[] }
          : {}),
        ...(text(decision.strategyIntent)
          ? { strategyIntent: decision.strategyIntent as string }
          : {}),
        ...(typeof decision.solutionModeAllowed === "boolean"
          ? { solutionModeAllowed: decision.solutionModeAllowed }
          : {}),
      }
      : null,
    plan: plan
      ? {
        threadFrame: plan.threadFrame,
        anchorSourceIndex: plan.anchorSourceIndex,
        supportSourceIndices: plan.supportSourceIndices,
        mergeContextSourceIndices: plan.mergeContextSourceIndices,
        semanticDistanceCap: plan.semanticDistanceCap,
        newTopicBudget: plan.newTopicBudget,
        questionBudget: plan.questionBudget,
        usedBranches: plan.branchPool
          .filter((branch) => usedBranchIds.includes(branch.id))
          .map((branch) => ({
            id: branch.id,
            method: branch.method,
            idea: branch.idea,
            associationPath: branch.associationPath,
            semanticDistance: branch.semanticDistance,
          })),
      }
      : null,
    guardViolations: [...guardViolations],
  };

  const candidate: AnalyzeCriticCandidate = {
    style: card.style,
    ...(text(variant?.rhetoricalMove)
      ? { rhetoricalMove: variant!.rhetoricalMove as string }
      : {}),
    ...(typeof variant?.styleIntensity === "number"
      ? { styleIntensity: variant.styleIntensity }
      : {}),
    segments: card.segments.map((segment) => ({
      ...(positiveInt(segment.sourceIndex)
        ? { sourceIndex: segment.sourceIndex as number }
        : {}),
      ...(text(segment.sourceMessage)
        ? { sourceMessage: segment.sourceMessage as string }
        : {}),
      reply: text(segment.reply ?? segment.content ?? segment.text) ?? "",
    })),
    questionCount: card.text.match(/[?？]/g)?.length ?? 0,
  };
  return { evidence, candidate };
}

export interface AnalyzeCriticAiCall {
  readonly model: string;
  readonly requestType: typeof ANALYZE_CRITIC_REQUEST_TYPE;
  readonly inputTokens: number;
  readonly outputTokens: number;
  readonly latencyMs: number;
  readonly status: "success" | "failed";
  readonly errorCode?: string;
  readonly requestBody?: unknown;
  readonly responseBody?: unknown;
}

export interface AnalyzeCriticShadowArgs {
  readonly finalResult: Record<string, unknown>;
  readonly messages: readonly Message[];
  readonly guardViolations: readonly string[];
  readonly trigger: readonly string[];
  readonly config: AnalyzeCriticShadowConfig;
  readonly apiKey: string;
  readonly callCritic: (args: SemanticCriticCallArgs) => Promise<unknown>;
  /// 純數字／enum 的 telemetry（呼叫端補 user／analysisRunId）。
  readonly emit: (event: string, metadata: Record<string, unknown>) => void;
  /// ai_logs 成本紀錄（呼叫端補 userId）。
  readonly recordAiCall?: (entry: AnalyzeCriticAiCall) => Promise<void>;
}

/// 影子執行：永不 throw、永不改 finalResult。
export async function runAnalyzeCriticShadow(
  args: AnalyzeCriticShadowArgs,
): Promise<void> {
  const emit = (metadata: Record<string, unknown>) => {
    try {
      args.emit("stream_semantic_critic", {
        model: args.config.model,
        trigger: [...args.trigger],
        ...metadata,
      });
    } catch {
      // telemetry 失敗不得影響任何事。
    }
  };
  const recordAiCall = async (
    entry: Omit<AnalyzeCriticAiCall, "model" | "requestType">,
  ) => {
    try {
      await args.recordAiCall?.({
        model: args.config.model,
        requestType: ANALYZE_CRITIC_REQUEST_TYPE,
        ...entry,
      });
    } catch {
      // 成本紀錄失敗只影響帳，不影響使用者。
    }
  };

  try {
    const input = buildAnalyzeCriticInput(
      args.finalResult,
      args.messages,
      args.guardViolations,
    );
    if (!input) {
      emit({ status: "skipped", reason: "no_candidate" });
      return;
    }
    const prompt = buildAnalyzeCriticPrompt(input.evidence, input.candidate);
    const requestBody = {
      trigger: [...args.trigger],
      candidateStyle: input.candidate.style,
    };
    const started = Date.now();
    let raw: unknown;
    try {
      raw = await args.callCritic({
        model: args.config.model,
        prompt,
        maxTokens: SEMANTIC_CRITIC_MAX_TOKENS,
        timeoutMs: args.config.timeoutMs,
        apiKey: args.apiKey,
      });
    } catch (error) {
      const latencyMs = Date.now() - started;
      const errorClass =
        (error instanceof Error ? error.message : String(error))
          .slice(0, 80);
      emit({ status: "failed", errorClass, latencyMs });
      await recordAiCall({
        inputTokens: 0,
        outputTokens: 0,
        latencyMs,
        status: "failed",
        errorCode: "semantic_critic_failed",
        requestBody,
      });
      return;
    }
    const latencyMs = Date.now() - started;
    const usage = parseSemanticCriticUsage(raw) ??
      { inputTokens: 0, outputTokens: 0 };
    let verdict: ReturnType<typeof parseSemanticCriticVerdict> | null = null;
    try {
      verdict = parseSemanticCriticVerdict(raw, ANALYZE_CRITIC_VIOLATIONS);
    } catch {
      verdict = null;
    }
    if (!verdict) {
      emit({ status: "invalid", ...usage, latencyMs });
      await recordAiCall({
        ...usage,
        latencyMs,
        status: "failed",
        errorCode: "semantic_critic_invalid",
        requestBody,
      });
      return;
    }
    emit({
      status: "ok",
      verdict: verdict.verdict,
      violations: [...verdict.violations],
      ...usage,
      latencyMs,
    });
    await recordAiCall({
      ...usage,
      latencyMs,
      status: "success",
      requestBody,
      responseBody: {
        verdict: verdict.verdict,
        violations: [...verdict.violations],
      },
    });
  } catch {
    // 影子永不影響已完成的分析。
  }
}

/// 把影子 task 掛上 EdgeRuntime.waitUntil（範式同 practice-chat moments_handler）。
export function scheduleAnalyzeCriticShadow(
  waitUntil: ((task: Promise<void>) => void) | undefined,
  task: Promise<void>,
): void {
  try {
    if (waitUntil) {
      waitUntil(task);
      return;
    }
    const edgeRuntime = (globalThis as unknown as {
      EdgeRuntime?: { waitUntil(task: Promise<void>): void };
    }).EdgeRuntime;
    if (edgeRuntime?.waitUntil) {
      edgeRuntime.waitUntil(task);
      return;
    }
  } catch {
    // 排程器失敗不得影響回應。
  }
  // 本機測試沒有 EdgeRuntime：task 自吞錯誤，detach 不會 unhandled rejection。
  void task.catch(() => {});
}

/// 預設 transport：非串流 messages 呼叫（與 coach-chat callClaudeAPI 同款；
/// analyze-chat 目前只有串流客戶端）。
export async function callClaudeJson(
  args: SemanticCriticCallArgs,
): Promise<unknown> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), args.timeoutMs);
  try {
    const res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": args.apiKey,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: args.model,
        max_tokens: args.maxTokens,
        messages: [{ role: "user", content: args.prompt }],
        ...(args.model === "claude-sonnet-5"
          ? { thinking: { type: "disabled" } }
          : {}),
      }),
      signal: controller.signal,
    });
    if (!res.ok) {
      const body = await res.text().catch(() => "");
      throw new Error(`claude_http_${res.status}: ${body.slice(0, 200)}`);
    }
    return await res.json();
  } finally {
    clearTimeout(timeout);
  }
}
