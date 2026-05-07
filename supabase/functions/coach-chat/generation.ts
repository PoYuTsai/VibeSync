import { buildCoachChatPrompt } from "./prompts.ts";
import type { CoachChatRequest, CoachChatResponseCard } from "./schemas.ts";
import {
  assertCardSafe,
  truncateCard,
  validateResponseCard,
} from "./validate.ts";

export interface GenerationLogger {
  info: (event: string, data?: Record<string, unknown>) => void;
  warn: (event: string, data?: Record<string, unknown>) => void;
}

export interface ClaudeCallArgs {
  model: string;
  prompt: string;
  maxTokens: number;
  timeoutMs: number;
  apiKey: string;
}

export interface GenerationDeps {
  callClaude: (args: ClaudeCallArgs) => Promise<unknown>;
  deductCredit: (input: { userId: string }) => Promise<void>;
  logger: GenerationLogger;
  now?: () => number;
}

export class CoachChatQuotaExceededError extends Error {
  constructor(
    readonly reason: "monthly_limit_exceeded" | "daily_limit_exceeded",
    readonly used: number,
    readonly limit: number,
  ) {
    super(reason);
    this.name = "CoachChatQuotaExceededError";
  }
}

export interface GenerationInput {
  userId: string;
  request: CoachChatRequest;
  tier: "free" | "starter" | "essential";
  accountIsTest: boolean;
  apiKey: string;
}

export interface GenerationResult {
  status: number;
  body: Record<string, unknown>;
}

const MAX_CARD_GENERATION_ATTEMPTS = 3;

export async function runCoachChat(
  input: GenerationInput,
  deps: GenerationDeps,
): Promise<GenerationResult> {
  const now = deps.now ?? (() => Date.now());
  const startedAt = now();
  const model = input.tier === "free"
    ? "claude-haiku-4-5-20251001"
    : "claude-sonnet-4-20250514";

  deps.logger.info("coach_chat_invoked", {
    tier: input.tier,
    hasSummary: !!input.request.conversationSummary,
    hasStyleContext: !!input.request.effectiveStyleContext,
    hasSessionTurns: input.request.activeSessionTurns.length > 0,
    forceAnswer: input.request.forceAnswer,
    dataQualityFlagged: input.request.dataQualityFlagged,
  });

  let card: CoachChatResponseCard | null = null;
  const basePrompt = buildCoachChatPrompt(input.request);
  let lastValidationError = "schema_invalid";

  for (let attempt = 1; attempt <= MAX_CARD_GENERATION_ATTEMPTS; attempt++) {
    let claudeData: unknown;
    try {
      claudeData = await deps.callClaude({
        model,
        prompt: buildAttemptPrompt(basePrompt, attempt, lastValidationError),
        maxTokens: 1200,
        timeoutMs: 60000,
        apiKey: input.apiKey,
      });
    } catch (e) {
      deps.logger.warn("coach_chat_failed", {
        tier: input.tier,
        errorClass: classifyClaudeError(e),
        attempt,
      });
      return { status: 500, body: { error: "AI 生成失敗" } };
    }

    try {
      card = parseAndValidateCard(claudeData);
      if (attempt > 1) {
        deps.logger.info("coach_chat_retry_succeeded", {
          tier: input.tier,
          attempt,
        });
      }
      break;
    } catch (e) {
      const message = getErrorMessage(e);
      lastValidationError = message.startsWith("banned_token")
        ? "banned_token"
        : "schema_invalid";
      deps.logger.warn("coach_chat_card_invalid", {
        tier: input.tier,
        errorClass: lastValidationError,
        attempt,
      });
      if (attempt === MAX_CARD_GENERATION_ATTEMPTS) {
        deps.logger.warn("coach_chat_fallback_used", {
          tier: input.tier,
          errorClass: lastValidationError,
          attempts: attempt,
        });
        card = buildFallbackClarificationCard(input.request);
        break;
      }
    }
  }

  if (!card) {
    return { status: 500, body: { error: lastValidationError } };
  }

  const shouldDeduct = card.responseType === "coachAnswer";

  if (shouldDeduct && !input.accountIsTest) {
    try {
      await deps.deductCredit({ userId: input.userId });
    } catch (e) {
      if (e instanceof CoachChatQuotaExceededError) {
        deps.logger.warn("coach_chat_failed", {
          tier: input.tier,
          errorClass: e.reason,
          used: e.used,
          limit: e.limit,
        });
        return {
          status: 429,
          body: {
            error: e.reason === "monthly_limit_exceeded"
              ? "Monthly limit exceeded"
              : "Daily limit exceeded",
            quotaNeeded: 1,
            used: e.used,
            limit: e.limit,
          },
        };
      }
      deps.logger.warn("coach_chat_failed", {
        tier: input.tier,
        errorClass: "credit_deduct_failed",
      });
      return { status: 500, body: { error: "credit_deduct_failed" } };
    }
  }

  deps.logger.info("coach_chat_succeeded", {
    tier: input.tier,
    mode: card.mode,
    responseType: card.responseType,
    model,
    provider: "claude",
    latencyMs: now() - startedAt,
    costDeducted: shouldDeduct && !input.accountIsTest ? 1 : 0,
  });

  return {
    status: 200,
    body: {
      card: {
        ...card,
        costDeducted: shouldDeduct && !input.accountIsTest ? 1 : 0,
      },
      sessionId: input.request.sessionId ?? null,
      provider: "claude",
      model,
      generatedAt: new Date(now()).toISOString(),
    },
  };
}

function buildAttemptPrompt(
  basePrompt: string,
  attempt: number,
  lastValidationError: string,
): string {
  if (attempt === 1) return basePrompt;
  return `${basePrompt}

上一次輸出未通過後端驗證：${lastValidationError}
請重新輸出一個完整且合法的 JSON 物件：
- 只輸出 JSON，不要 markdown，不要前後解釋。
- 所有 schema 欄位都要存在；不確定可用 null，但必填欄位不可省略。
- responseType="clarifyingQuestion" 時：rewriteDecision、rewriteReason、suggestedLine 用 null，needsReflection=true，reflectionQuestion 必填。
- responseType="coachAnswer" 時：rewriteDecision 必填。
- 避免輸出被禁止的可見詞彙。`;
}

function parseAndValidateCard(claudeData: unknown): CoachChatResponseCard {
  const parsed = parseClaudeJSON(claudeData);
  const truncated = truncateCard(parsed);
  const card = validateResponseCard(truncated);
  assertCardSafe(card);
  return card;
}

function buildFallbackClarificationCard(
  request: CoachChatRequest,
): CoachChatResponseCard {
  const question = request.userQuestion.toLowerCase();
  const isMoveForward = /推進|約|邀|升溫|收尾|關門|轉場/.test(question);
  const card = validateResponseCard({
    responseType: "clarifyingQuestion",
    mode: isMoveForward ? "moveForward" : "clarifyIntent",
    headline: isMoveForward ? "先把推進目標說清楚" : "先問清楚你的真實想法",
    answer: isMoveForward
      ? "我先接住你：這題不是不能判斷，而是目前需要先知道你想推進到哪一步。先把目的說清楚，下一步才不會太硬或太急。"
      : "我先接住你：這題可以判斷，但還缺你當下的第一反應。先把真實想法補上，教練才不會替你亂補劇本。",
    userTruth: null,
    userState: isMoveForward
      ? "你可能想往前，但還沒把目的、節奏和可承擔成本講清楚。"
      : "你可能急著找答案，但還沒說出自己真正卡住的點。",
    frictionType: isMoveForward ? "hesitatesToMoveForward" : "unclearIntent",
    nextStep: isMoveForward
      ? "先補一句你真正想達成的下一步。"
      : "先補一句你心裡第一個反應。",
    suggestedLine: null,
    rewriteDecision: null,
    rewriteReason: null,
    boundaryReminder: "釐清不扣額度；正式建議才扣 1 則。",
    needsReflection: true,
    reflectionQuestion: isMoveForward
      ? "你說推進，是想邀約、升溫，還是確認她意願？"
      : "你聽到她這句話後，心裡第一個反應是什麼？",
  });
  assertCardSafe(card);
  return card;
}

function getErrorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (typeof error === "string") return error;
  return "unknown_error";
}

function classifyClaudeError(error: unknown): string {
  const msg = getErrorMessage(error).toLowerCase();
  if (msg.includes("timeout") || msg.includes("aborted")) {
    return "claude_timeout";
  }
  if (msg.includes("rate") && msg.includes("limit")) return "claude_rate_limit";
  if (msg.includes("network") || msg.includes("fetch failed")) {
    return "claude_network";
  }
  return "claude_unknown";
}

function parseClaudeJSON(
  claudeData: unknown,
): Record<string, string | number | boolean | null | undefined> {
  if (!claudeData || typeof claudeData !== "object") {
    throw new Error("schema_invalid: claude returned non-object");
  }
  const data = claudeData as { content?: Array<{ text?: string }> };
  const rawText = data.content?.[0]?.text ?? "";
  const jsonMatch = rawText.match(/\{[\s\S]*\}/);
  if (!jsonMatch) {
    throw new Error("schema_invalid: no JSON found in claude response");
  }
  try {
    const parsed = JSON.parse(jsonMatch[0]);
    if (!parsed || typeof parsed !== "object") {
      throw new Error("schema_invalid: claude JSON is not an object");
    }
    return parsed;
  } catch (e) {
    if (e instanceof Error && e.message.startsWith("schema_invalid")) throw e;
    throw new Error("schema_invalid: malformed JSON in claude response");
  }
}

export async function callClaudeAPI(args: ClaudeCallArgs): Promise<unknown> {
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
