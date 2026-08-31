import { buildCoachChatPrompt } from "./prompts.ts";
import { deriveMessageDecision } from "./schemas.ts";
import type { CoachChatRequest, CoachChatResponseCard } from "./schemas.ts";
import {
  assertCardSafe,
  truncateCard,
  validateResponseCard,
  VISIBLE_FIELDS,
} from "./validate.ts";
import {
  mustClarifyFirstRound,
  shouldForceCoachAnswerAfterClarifications,
} from "./clarification_policy.ts";
import { LINE_INVITE_RE, shouldSuppressInviteLine } from "./invite_policy.ts";
import { quotaExceededMessage } from "../_shared/quota.ts";
import {
  findUnsupportedLatinTokens,
  isExplicitEnglishRequest,
} from "../_shared/zh_tw_visible_text_guard.ts";
import {
  runSemanticCritic,
  type SemanticCriticCallArgs,
} from "./semantic_critic.ts";

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
  callSemanticCritic: (args: SemanticCriticCallArgs) => Promise<unknown>;
  deductCredit: (input: { userId: string }) => Promise<void>;
  // Phase C 帳本結算縫：注入時取代 deductCredit（settle 交易內扣費＋存卡）。
  // 未注入＝舊路徑零改動。回傳的 body 是 DB ledger 權威結果——stale lease
  // takeover 後晚到的 settle 會拿到對方已入帳的卡，必須回它而非本地生成。
  // quota 超額拋 CoachChatQuotaExceededError；其它失敗拋 index 定義的
  // typed error，由 index 映射 503/500。
  settleResult?: (args: {
    body: Record<string, unknown>;
    charge: boolean;
  }) => Promise<{ charged: boolean; body: Record<string, unknown> }>;
  logger: GenerationLogger;
  onProgress?: (update: CoachChatProgressUpdate) => void;
  now?: () => number;
}

export type CoachChatProgressStage =
  | "request"
  | "generating"
  | "validating"
  | "retrying"
  | "finalizing";

export interface CoachChatProgressUpdate {
  stage: CoachChatProgressStage;
  attempt?: number;
  maxAttempts?: number;
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
const FALLBACK_NO_CHARGE = 0;
const COACH_GENERATION_BUDGET_MS = 75_000;
const COACH_CLAUDE_ATTEMPT_TIMEOUT_MS = 60_000;
const COACH_SEMANTIC_CRITIC_TIMEOUT_MS = 12_000;
const UNSOURCED_TIME_RANGE_TERMS = [
  "這陣子",
  "最近這陣子",
  "前陣子",
  "這幾天",
  "最近幾天",
  "這幾週",
  "最近幾週",
  "好幾週",
  "這幾個月",
  "最近幾個月",
  "好幾個月",
  "隔天",
  "第一天",
] as const;
const UNSOURCED_NEGATIVE_MOTIVE_TERMS = [
  "會裝",
  "敷衍",
  "冷淡",
  "吊胃口",
  "不想理我",
] as const;
// Batch A（2026-08-31）：建議句模板佔位符硬擋。`（店名）`/`OO`/`___` 曾
// 直接外洩到可複製句（golden G-04/G-05）。全形〇/Ｏ、方括號、角括號一併擋。
const SUGGESTED_LINE_PLACEHOLDER_RE =
  /[_＿]{2,}|(?<![A-Za-z])[OＯ〇]{2,}(?![A-Za-z])|[（(][^（）()]{0,6}(?:店名|地點|時間|活動|名字)[^（）()]{0,6}[）)]|\[[^\]]{1,20}\]|<[^>]{1,20}>/u;
// Batch A：自貶求接住／無限配合（Beta 模式）詞群。只有「來源沒出現」才擋
// ——對方或使用者自己講過的詞不受影響（同 temporal_drift 的來源支持制）。
const UNSOURCED_BETA_TERMS = [
  "可憐",
  "都可以",
  "我都行",
  "都行",
  "配合你",
  "配合妳",
  "看你方便",
  "看妳方便",
  "隨時都可以",
  "隨時有空",
] as const;
// Batch A：建議句與邊界提醒同卡矛盾（邊界說先別約、句子仍在邀）。
// 邊界提醒裡「如果/若/要是」開頭的條件句不算當下指令，先剝掉再比對。
const BOUNDARY_ANTI_INVITE_RE =
  /(?:先別|不要|別再|先收|不再|先停)[^。；;，,]{0,8}(?:邀|約)|先收手/;
// B3：邀約句型 regex 移到 invite_policy.ts（prompts 也要用，單一真相源）。
// 最終回合守門仍不過時：這些錯誤類別只剝掉建議句、保留模型答案，
// 不退罐頭 fallback（守門是否決那一句，不是否決整張卡）。
const SUGGESTED_LINE_STRIP_ERRORS = new Set([
  "placeholder_leak",
  "beta_pattern",
  "invite_contradiction",
  "multi_question",
  "temporal_drift",
  "motive_drift",
  "explicit_no_question",
  // B3：兩次未承接禁再邀——同樣是對句子的否決，不是對整卡的否決。
  "invite_suppressed",
]);

export async function runCoachChat(
  input: GenerationInput,
  deps: GenerationDeps,
): Promise<GenerationResult> {
  const now = deps.now ?? (() => Date.now());
  const startedAt = now();
  const request = shouldForceCoachAnswerAfterClarifications(input.request)
    ? { ...input.request, forceAnswer: true }
    : input.request;
  const model = "claude-sonnet-5";

  deps.logger.info("coach_chat_invoked", {
    tier: input.tier,
    hasSummary: !!request.conversationSummary,
    hasStyleContext: !!request.effectiveStyleContext,
    hasSessionTurns: request.activeSessionTurns.length > 0,
    forceAnswer: request.forceAnswer,
    dataQualityFlagged: request.dataQualityFlagged,
    lifecyclePhase: request.lifecyclePhase ?? null,
    hasRequestId: request.requestId != null,
    hasScope: request.scope != null,
  });
  emitProgress(deps, { stage: "request" });

  let card: CoachChatResponseCard | null = null;
  const basePrompt = buildCoachChatPrompt(request);
  let lastValidationError = "schema_invalid";
  const generationDeadlineAt = startedAt + COACH_GENERATION_BUDGET_MS;

  for (let attempt = 1; attempt <= MAX_CARD_GENERATION_ATTEMPTS; attempt++) {
    const remainingGenerationMs = generationDeadlineAt - now();
    if (remainingGenerationMs <= 0) {
      deps.logger.warn("coach_chat_fallback_used", {
        tier: input.tier,
        errorClass: "generation_deadline",
        attempts: attempt - 1,
      });
      card = buildFallbackCard(request);
      break;
    }

    let claudeData: unknown;
    emitProgress(deps, {
      stage: "generating",
      attempt,
      maxAttempts: MAX_CARD_GENERATION_ATTEMPTS,
    });
    try {
      claudeData = await deps.callClaude({
        model,
        prompt: buildAttemptPrompt(basePrompt, attempt, lastValidationError),
        maxTokens: 1200,
        timeoutMs: Math.max(
          1,
          Math.min(
            COACH_CLAUDE_ATTEMPT_TIMEOUT_MS,
            remainingGenerationMs,
          ),
        ),
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

    emitProgress(deps, {
      stage: "validating",
      attempt,
      maxAttempts: MAX_CARD_GENERATION_ATTEMPTS,
    });
    let candidate: CoachChatResponseCard | null = null;
    try {
      candidate = parseAndValidateCard(claudeData, request);
      assertSuggestedLineGrounded(candidate, request);
      assertSuggestedLineDeliverable(candidate, request);
      assertExplicitNoQuestionConstraint(candidate, request);
      assertInviteSuppressionRespected(candidate, request);
      assertVisibleTextLanguage(candidate, request);
      assertClarificationRequired(candidate, request);
      candidate = assertClarificationAllowed(candidate, request);
      if (
        candidate.responseType === "coachAnswer" &&
        candidate.costDeducted !== FALLBACK_NO_CHARGE
      ) {
        const remainingCriticMs = generationDeadlineAt - now();
        if (remainingCriticMs <= 0) {
          throw new Error("semantic_critic_unavailable");
        }
        let critic;
        try {
          critic = await runSemanticCritic({
            request,
            card: candidate,
            model,
            apiKey: input.apiKey,
            timeoutMs: Math.max(
              1,
              Math.min(COACH_SEMANTIC_CRITIC_TIMEOUT_MS, remainingCriticMs),
            ),
            callCritic: deps.callSemanticCritic,
          });
        } catch (error) {
          deps.logger.warn("coach_chat_semantic_critic_failed", {
            tier: input.tier,
            errorClass: getErrorMessage(error).slice(0, 80),
            attempt,
          });
          throw new Error("semantic_critic_unavailable");
        }
        if (critic.verdict === "rewrite") {
          deps.logger.warn("coach_chat_semantic_critic_rejected", {
            tier: input.tier,
            violations: critic.violations.join(","),
            attempt,
          });
          throw new Error(`semantic_critic:${critic.violations.join(",")}`);
        }
        deps.logger.info("coach_chat_semantic_critic_passed", {
          tier: input.tier,
          attempt,
        });
      }
      card = candidate;
      if (attempt > 1) {
        deps.logger.info("coach_chat_retry_succeeded", {
          tier: input.tier,
          attempt,
        });
      }
      break;
    } catch (e) {
      const message = getErrorMessage(e);
      lastValidationError = message.startsWith("semantic_critic:")
        ? message.slice(0, 200)
        : message === "semantic_critic_unavailable"
        ? "semantic_critic_unavailable"
        : message.startsWith("banned_token")
        ? "banned_token"
        : message === "temporal_drift"
        ? "temporal_drift"
        : message === "motive_drift"
        ? "motive_drift"
        : message === "explicit_no_question"
        ? "explicit_no_question"
        : message === "language_drift"
        ? "language_drift"
        : message === "clarification_forbidden"
        ? "clarification_forbidden"
        : message === "clarification_required"
        ? "clarification_required"
        : message === "placeholder_leak"
        ? "placeholder_leak"
        : message === "beta_pattern"
        ? "beta_pattern"
        : message === "invite_contradiction"
        ? "invite_contradiction"
        : message === "invite_suppressed"
        ? "invite_suppressed"
        : message === "multi_question"
        ? "multi_question"
        : message === "max_tokens"
        ? "max_tokens"
        : message === "refusal"
        ? "refusal"
        : message === "model_context_window_exceeded"
        ? "model_context_window_exceeded"
        : "schema_invalid";
      deps.logger.warn("coach_chat_card_invalid", {
        tier: input.tier,
        errorClass: lastValidationError,
        detail: summarizeValidationError(e),
        attempt,
      });
      if (
        lastValidationError === "refusal" ||
        lastValidationError === "model_context_window_exceeded"
      ) {
        deps.logger.warn("coach_chat_failed", {
          tier: input.tier,
          errorClass: lastValidationError,
          attempt,
        });
        return { status: 500, body: { error: lastValidationError } };
      }
      if (attempt === MAX_CARD_GENERATION_ATTEMPTS) {
        // Batch A：建議句層級的守門在最終回合仍不過時，只剝掉那一句、
        // 保留模型的判斷與策略（守門降級成對句子的否決，不是對整卡的
        // 否決）；其餘錯誤照舊退保守 fallback。
        if (
          candidate != null &&
          SUGGESTED_LINE_STRIP_ERRORS.has(lastValidationError)
        ) {
          deps.logger.warn("coach_chat_line_stripped", {
            tier: input.tier,
            errorClass: lastValidationError,
            attempts: attempt,
          });
          card = {
            ...candidate,
            suggestedLine: null,
            rewriteDecision: candidate.responseType === "coachAnswer"
              ? "do_not_send"
              : candidate.rewriteDecision,
            rewriteReason: candidate.responseType === "coachAnswer"
              ? "建議句沒通過安全檢查，這輪先不給可貼句。"
              : candidate.rewriteReason,
            // 剝句卡不扣費：扣 1 ⇔ AI 真生成完整過驗卡（同 fallback/repair
            // 的既有計費不變量）。
            costDeducted: FALLBACK_NO_CHARGE,
          };
          // 剝句繞過 schema transform 重建卡：messageDecision 必須重推，
          // 否則會殘留剝句前的 "send"（B2）。
          card = { ...card, messageDecision: deriveMessageDecision(card) };
          break;
        }
        deps.logger.warn("coach_chat_fallback_used", {
          tier: input.tier,
          errorClass: lastValidationError,
          attempts: attempt,
        });
        card = buildFallbackCard(request);
        break;
      }
      emitProgress(deps, {
        stage: "retrying",
        attempt,
        maxAttempts: MAX_CARD_GENERATION_ATTEMPTS,
      });
    }
  }

  if (!card) {
    return { status: 500, body: { error: lastValidationError } };
  }

  // B2：本卡證據量由 request context deterministic 推導（非模型自評），
  // 在唯一收斂點蓋上——settle 與非帳本兩條回應路徑都從這裡展開 card。
  card = { ...card, evidenceQuality: deriveEvidenceQuality(request, now()) };

  const shouldDeduct = card.responseType === "coachAnswer" &&
    card.costDeducted !== FALLBACK_NO_CHARGE;
  const shouldCharge = shouldDeduct && !input.accountIsTest;

  emitProgress(deps, { stage: "finalizing" });

  if (deps.settleResult) {
    // 帳本路徑：先組完整 200 body（costDeducted 以 shouldCharge 預填），
    // settle 交易內同時扣費＋存卡；回傳 charged 才是最終扣費真相。
    const body = {
      card: { ...card, costDeducted: shouldCharge ? 1 : 0 },
      sessionId: request.sessionId ?? null,
      provider: "claude",
      model,
      generatedAt: new Date(now()).toISOString(),
    };
    let settled: { charged: boolean; body: Record<string, unknown> };
    try {
      settled = await deps.settleResult({ body, charge: shouldCharge });
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
            message: quotaExceededMessage(e.reason),
            quotaNeeded: 1,
            used: e.used,
            limit: e.limit,
          },
        };
      }
      deps.logger.warn("coach_chat_failed", {
        tier: input.tier,
        errorClass: "settlement_failed",
      });
      throw e;
    }
    deps.logger.info("coach_chat_succeeded", {
      tier: input.tier,
      mode: card.mode,
      responseType: card.responseType,
      model,
      provider: "claude",
      latencyMs: now() - startedAt,
      costDeducted: settled.charged ? 1 : 0,
    });
    // 回 ledger 權威 body：fresh settle＝剛存的本地 body；state='done'
    // replay＝先入帳者的卡（本地生成丟棄，絕不回未入帳結果）。
    return { status: 200, body: settled.body };
  }

  if (shouldCharge) {
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
            message: quotaExceededMessage(e.reason),
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
    costDeducted: shouldCharge ? 1 : 0,
  });

  return {
    status: 200,
    body: {
      card: {
        ...card,
        costDeducted: shouldCharge ? 1 : 0,
      },
      sessionId: request.sessionId ?? null,
      provider: "claude",
      model,
      generatedAt: new Date(now()).toISOString(),
    },
  };
}

// B2：evidenceQuality 的唯一真相源。只認「對方證據」——recentMessages 逐字
// 訊息與 summary/snapshot 二手材料；activeSessionTurns 是教練室對話，刻意
// 不算證據（使用者轉述≠對方原話）。partner scope 的逐字訊息是 B1 從來源
// 對話補的，新鮮度看 contextProvenance.lastMessageAt（7 天窗；缺時間戳
// 保守判 stale）。
const EVIDENCE_FRESH_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;

export function deriveEvidenceQuality(
  request: CoachChatRequest,
  nowMs: number,
): "none" | "stale_or_partial" | "fresh" {
  const hasMessages = request.recentMessages.length > 0;
  const hasSecondary = request.conversationSummary != null ||
    request.analysisSnapshot != null;
  if (!hasMessages) return hasSecondary ? "stale_or_partial" : "none";
  if (request.scope?.type === "partner") {
    const raw = request.contextProvenance?.lastMessageAt;
    const at = raw == null ? NaN : Date.parse(raw);
    if (!Number.isFinite(at) || nowMs - at > EVIDENCE_FRESH_WINDOW_MS) {
      return "stale_or_partial";
    }
  }
  return "fresh";
}

function emitProgress(
  deps: GenerationDeps,
  update: CoachChatProgressUpdate,
): void {
  try {
    deps.onProgress?.(update);
  } catch {
    // Progress is best-effort UI telemetry. It must never affect generation,
    // validation, clarification, or quota behavior.
  }
}

function assertClarificationAllowed(
  card: CoachChatResponseCard,
  request: CoachChatRequest,
): CoachChatResponseCard {
  if (
    card.responseType === "clarifyingQuestion" &&
    shouldForceCoachAnswerAfterClarifications(request)
  ) {
    throw new Error("clarification_forbidden");
  }
  return card;
}

// assertClarificationAllowed 的鏡像（2026-08-31 決策分岔案）：全域首輪
// 缺脈絡時模型不得直接給 coachAnswer——首輪決策與扣費都變成確定的。
function assertClarificationRequired(
  card: CoachChatResponseCard,
  request: CoachChatRequest,
): void {
  if (card.responseType === "coachAnswer" && mustClarifyFirstRound(request)) {
    throw new Error("clarification_required");
  }
}

function buildAttemptPrompt(
  basePrompt: string,
  attempt: number,
  lastValidationError: string,
): string {
  if (attempt === 1) return basePrompt;
  if (lastValidationError.startsWith("semantic_critic:")) {
    const violations = lastValidationError.slice("semantic_critic:".length);
    return `${basePrompt}

上一次內容通過 schema 與安全守門，但第二層語意審核要求重寫：${violations}
請重新輸出完整 JSON，只修正這些 rubric 病灶：
- 直接回答使用者本題；所有事實只能來自上下文。
- suggestedLine 必須接住現有內容，不可用空泛鉤子或查戶口補材料。
- 遵守使用者風格設定裡的主／副風格、句長與問句密度。
- 投入對等、策略與界線一致，並收斂成一個可立刻執行的最小下一步。
- 只輸出 JSON，不要用 Markdown 格式，不要前後解釋。`;
  }
  if (lastValidationError === "semantic_critic_unavailable") {
    return `${basePrompt}

上一次第二層語意審核未能完成。本輪仍須輸出一份全新完整 JSON，並自行逐項核對：
直接回答本題、不得新增來源外事實、不得用空泛鉤子、遵守風格與問句密度、投入對等、界線一致、只有一個最小下一步。`;
  }
  if (lastValidationError === "clarification_forbidden") {
    return `${basePrompt}

上一次輸出違反釐清上限：免費釐清已達上限，本輪禁止再輸出 clarifyingQuestion。
請重新輸出 responseType="coachAnswer" 的正式建議 JSON：
- 只輸出 JSON，不要用 Markdown 格式，不要前後解釋。
- 所有 schema 欄位都要存在；rewriteDecision 必填。
- 資訊不足可以低信心，但仍要給一個最小安全下一步。
- 避免輸出被禁止的可見詞彙。`;
  }
  if (lastValidationError === "temporal_drift") {
    return `${basePrompt}

上一次 suggestedLine 擴寫了來源沒有的時間範圍，未通過事實校對。
請重新輸出完整 JSON，並逐字核對 suggestedLine：
- 時間詞只能照來源原詞保留或直接省略。
- 不得把「這週」改成「這陣子／這幾週」，也不得新增來源沒有的時間經歷。
- 只輸出 JSON，不要用 Markdown 格式，不要前後解釋。`;
  }
  if (lastValidationError === "motive_drift") {
    return `${basePrompt}

上一次 suggestedLine 替對方貼了來源沒有的負面動機標籤，未通過事實校對。
請重新輸出完整 JSON：
- 資訊不足時輕接或留白，不得腦補對方在裝、敷衍、冷淡或故意吊胃口。
- 不要逼對方解釋或安撫使用者。
- 只輸出 JSON，不要用 Markdown 格式，不要前後解釋。`;
  }
  if (lastValidationError === "clarification_required") {
    return `${basePrompt}

上一次輸出違反首輪規則：本回合完全沒有任何個案對話脈絡，必須先免費釐清，不可直接給 coachAnswer。
請重新輸出 responseType="clarifyingQuestion" 的 JSON：
- 只問一個問題。全域模式方向固定三選一：全新對象／聊到一半斷掉想重新接上／正在聊但沒話題。對象模式引導三選一：切到與她的對話視窗再問／貼上她最近三到五則原話／先聽通用原則。
- costDeducted 必須是 0；suggestedLine、rewriteDecision、rewriteReason 用 null；needsReflection=true，reflectionQuestion 必填。
- 只輸出 JSON，不要用 Markdown 格式，不要前後解釋。`;
  }
  if (lastValidationError === "placeholder_leak") {
    return `${basePrompt}

上一次 suggestedLine 含有模板佔位符（例如 OO、＿＿、（店名）、[地點]），這不是可以直接傳出去的句子。
請重新輸出完整 JSON：
- 只能用上下文裡真實出現過的店名、地點、活動；沒有就不要編，把句子改寫成不需要那個細節，或 suggestedLine 用 null。
- 絕不可輸出任何佔位符或要使用者自行填空的句型。
- 只輸出 JSON，不要用 Markdown 格式，不要前後解釋。`;
  }
  if (lastValidationError === "beta_pattern") {
    return `${basePrompt}

上一次 suggestedLine 出現自貶求接住或無限配合的句型（例如「我自己去會很可憐」「時間我都可以配合你」），會讓使用者掉價。
請重新輸出完整 JSON：
- 邀約要有自己的時間與選擇，給對方清楚可拒絕的空間，但不乞求、不自貶、不把節奏全讓出去。
- 不確定怎麼寫就把 suggestedLine 用 null，把策略講清楚即可。
- 只輸出 JSON，不要用 Markdown 格式，不要前後解釋。`;
  }
  if (lastValidationError === "invite_contradiction") {
    return `${basePrompt}

上一次輸出自相矛盾：boundaryReminder 說先別邀約，suggestedLine 卻還在邀。
請重新輸出完整 JSON，二選一收斂：
- 若判斷值得邀：邊界提醒改成邀約後的守則，不要寫「先別約」。
- 若判斷該收手：suggestedLine 用 null 或改成不帶邀約的低壓句，rewriteDecision 用 do_not_send。
- 只輸出 JSON，不要用 Markdown 格式，不要前後解釋。`;
  }
  if (lastValidationError === "invite_suppressed") {
    return `${basePrompt}

上一次 suggestedLine 又提出邀約，但邀約歷史顯示對方最近兩次邀約都沒有承接：本輪禁止再邀。
請重新輸出完整 JSON：
- suggestedLine 改成不帶邀約的低壓句（接話、留白、給價值），或用 null＋rewriteDecision="do_not_send"。
- 策略面向「等對方主動帶新材料或給窗口」，不要教使用者換句話再約。
- 只輸出 JSON，不要用 Markdown 格式，不要前後解釋。`;
  }
  if (lastValidationError === "multi_question") {
    return `${basePrompt}

上一次 suggestedLine 有超過一個問句，像在盤問。
請重新輸出完整 JSON：
- suggestedLine 最多一個問號；先給內容或立場，再留一個自然回口。
- 只輸出 JSON，不要用 Markdown 格式，不要前後解釋。`;
  }
  if (lastValidationError === "language_drift") {
    return `${basePrompt}

上一次輸出的可見欄位混入了沒有來源支持的英文詞，未通過語言檢查。
請保持原意重新輸出完整 JSON，可見文字改成自然台灣繁體中文：
- 除非英文詞已出現在使用者或對方的原文、或是常見品牌服務名（LINE、IG、Netflix），否則一律改用自然中文說法（例如 today 要寫成「今天」）。
- JSON 的欄位名（key）維持英文不變。
- 只輸出 JSON，不要用 Markdown 格式，不要前後解釋。`;
  }
  if (lastValidationError === "explicit_no_question") {
    return `${basePrompt}

上一次 suggestedLine 違反使用者明確要求的「不要追問／不要逼對方解釋」。
請重新輸出完整 JSON：
- suggestedLine 不得出現問句或問號；輕接後收住即可。
- 不要換句話繼續索取解釋或安撫。
- 只輸出 JSON，不要用 Markdown 格式，不要前後解釋。`;
  }
  return `${basePrompt}

上一次輸出未通過後端驗證：${lastValidationError}
請重新輸出一個完整且合法的 JSON 物件：
- 只輸出 JSON，不要用 Markdown 格式，不要前後解釋。
- 所有 schema 欄位都要存在；不確定可用 null，但必填欄位不可省略。
- responseType="clarifyingQuestion" 時：rewriteDecision、rewriteReason、suggestedLine 用 null，needsReflection=true，reflectionQuestion 必填。
- responseType="coachAnswer" 時：rewriteDecision 必填。
- 避免輸出被禁止的可見詞彙。`;
}

function assertSuggestedLineGrounded(
  card: CoachChatResponseCard,
  request: CoachChatRequest,
): void {
  const suggestedLine = card.suggestedLine?.trim();
  if (!suggestedLine) return;

  const source = [
    request.userQuestion,
    request.rawReplyDraft,
    ...request.recentMessages.map((message) => message.text),
    ...request.activeSessionTurns.map((turn) => turn.content),
    request.conversationSummary,
    request.analysisSnapshot?.summary,
    request.analysisSnapshot?.nextStep,
    ...(request.analysisSnapshot?.keySignals ?? []),
    request.effectiveStyleContext,
  ].filter((value): value is string => typeof value === "string").join("\n");

  for (const term of UNSOURCED_TIME_RANGE_TERMS) {
    if (suggestedLine.includes(term) && !source.includes(term)) {
      throw new Error("temporal_drift");
    }
  }
  for (const term of UNSOURCED_NEGATIVE_MOTIVE_TERMS) {
    if (suggestedLine.includes(term) && !source.includes(term)) {
      throw new Error("motive_drift");
    }
  }
}

// Batch A 建議句可交付守門（2026-08-31）：擋 placeholder 外洩、無來源的
// 自貶／全面配合詞、同卡「邊界說先別約、句子仍在邀」矛盾、問號超過一個。
// 詞群類走來源支持制（同 temporal_drift）：對方或使用者講過的詞不擋。
function assertSuggestedLineDeliverable(
  card: CoachChatResponseCard,
  request: CoachChatRequest,
): void {
  const suggestedLine = card.suggestedLine?.trim();
  if (!suggestedLine) return;

  if (SUGGESTED_LINE_PLACEHOLDER_RE.test(suggestedLine)) {
    throw new Error("placeholder_leak");
  }

  if (((suggestedLine.match(/[?？]/g) ?? []).length) > 1) {
    throw new Error("multi_question");
  }

  const source = [
    request.userQuestion,
    request.rawReplyDraft,
    ...request.recentMessages.map((message) => message.text),
    ...request.activeSessionTurns
      .filter((turn) => turn.role === "user")
      .map((turn) => turn.content),
  ].filter((value): value is string => typeof value === "string").join("\n");
  for (const term of UNSOURCED_BETA_TERMS) {
    if (suggestedLine.includes(term) && !source.includes(term)) {
      throw new Error("beta_pattern");
    }
  }

  // 邊界提醒的條件句（如果/若/要是…）是「事後怎麼辦」，不算當下指令；
  // 只拿第一個條件詞之前的文字比對反邀約指令。
  const boundary = card.boundaryReminder ?? "";
  const unconditional = boundary.split(/如果|若|要是|萬一/)[0];
  if (
    BOUNDARY_ANTI_INVITE_RE.test(unconditional) &&
    LINE_INVITE_RE.test(suggestedLine)
  ) {
    throw new Error("invite_contradiction");
  }
}

// B3：兩次未承接 deterministic 禁再邀。gate 由 invite_policy 判（client 送
// 的 inviteHistory 由舊到新，最近兩筆邀約都未承接即啟動）；prompt 第一回合
// 已注入「邀約守門」段，這裡是硬保底——retry-first、耗盡剝句不砍卡。
function assertInviteSuppressionRespected(
  card: CoachChatResponseCard,
  request: CoachChatRequest,
): void {
  if (card.responseType !== "coachAnswer") return;
  const suggestedLine = card.suggestedLine?.trim() ?? "";
  if (suggestedLine === "") return;
  if (!shouldSuppressInviteLine(request.inviteHistory)) return;
  if (LINE_INVITE_RE.test(suggestedLine)) {
    throw new Error("invite_suppressed");
  }
}

// 語言守門（2026-08-31）：可見欄位裡的英文詞必須有「使用者親手寫的來源」
// 或在小白名單，否則 language_drift → 扣費前重試。來源刻意不含教練舊輸出、
// 跨天摘要、分析快照、風格設定與對象特質標籤（traits 來自 AI 分析快照）——
// AI 自己產出的英文不能替下一次背書。使用者明確要英文時只放行建議句，
// 解釋欄位仍守繁中（R1 審查 P1-3：建議句不得替解釋欄位背書）。
function assertVisibleTextLanguage(
  card: CoachChatResponseCard,
  request: CoachChatRequest,
): void {
  const source = [
    request.userQuestion,
    request.rawReplyDraft,
    ...request.recentMessages.map((message) => message.text),
    ...request.activeSessionTurns
      .filter((turn) => turn.role === "user")
      .map((turn) => turn.content),
    request.partnerHint?.name,
    request.partnerHint?.note,
  ].filter((value): value is string => typeof value === "string").join("\n");

  // 英文要求看整輪：首輪要求被釐清閘門攔下後，補充回合的 userQuestion
  // 只剩「全新對象」之類，原始要求在 user turns 裡（R2 審查：要求遺失）。
  const englishRequested = [
    request.userQuestion,
    ...request.activeSessionTurns
      .filter((turn) => turn.role === "user")
      .map((turn) => turn.content),
  ].some(isExplicitEnglishRequest);

  for (const field of VISIBLE_FIELDS) {
    const value = card[field];
    if (typeof value !== "string") continue;
    if (englishRequested && field === "suggestedLine") continue;
    if (findUnsupportedLatinTokens(value, source).length > 0) {
      throw new Error("language_drift");
    }
  }
}

function assertExplicitNoQuestionConstraint(
  card: CoachChatResponseCard,
  request: CoachChatRequest,
): void {
  const suggestedLine = card.suggestedLine?.trim();
  if (!suggestedLine) return;

  const explicitlyAvoidsQuestions =
    /(?:不要|別)(?:再|一直|硬)?(?:追問|問)|(?:不要|別)[^。！？]{0,12}逼[^。！？]{0,12}解釋/
      .test(
        request.userQuestion,
      );
  if (explicitlyAvoidsQuestions && /[?？]/.test(suggestedLine)) {
    throw new Error("explicit_no_question");
  }
}

function parseAndValidateCard(
  claudeData: unknown,
  request: CoachChatRequest,
): CoachChatResponseCard {
  const parsed = parseClaudeJSON(claudeData);
  const repaired = repairCardShape(parsed, request);
  const truncated = truncateCard(repaired);
  const card = validateResponseCard(truncated);
  assertCardSafe(card);
  // repair 落保守 no-charge fallback（如 forced 模式下空 answer）時，
  // validateResponseCard 會把 coachAnswer 的 costDeducted 正規化回 1——
  // 必須重掛 0（扣 1 則 ⇔ AI 真生成）。repaired.costDeducted 全由 server
  // 端 repair 函式設定，不受模型原始輸出影響。buildFallbackCard 已有同款
  // 重掛（見上方 FALLBACK_NO_CHARGE spread）。
  if (
    repaired.costDeducted === FALLBACK_NO_CHARGE &&
    card.responseType === "coachAnswer"
  ) {
    return { ...card, costDeducted: FALLBACK_NO_CHARGE };
  }
  return card;
}

function buildFallbackCard(
  request: CoachChatRequest,
): CoachChatResponseCard {
  if (shouldUseNoChargeAnswerFallback(request)) {
    const card = validateResponseCard(buildFallbackCoachAnswerShape(request));
    assertCardSafe(card);
    return { ...card, costDeducted: FALLBACK_NO_CHARGE };
  }

  return buildFallbackClarificationCard(request);
}

function buildFallbackClarificationCard(
  request: CoachChatRequest,
): CoachChatResponseCard {
  const card = validateResponseCard(buildFallbackClarificationShape(request));
  assertCardSafe(card);
  return card;
}

function shouldUseNoChargeAnswerFallback(request: CoachChatRequest): boolean {
  if (request.forceAnswer) return true;
  return isAnsweringLatestClarification(request.activeSessionTurns);
}

function isAnsweringLatestClarification(
  turns: CoachChatRequest["activeSessionTurns"],
): boolean {
  const lastTurn = turns[turns.length - 1];
  return lastTurn?.role === "coach" && lastTurn.kind === "clarification";
}

function buildFallbackCoachAnswerShape(
  request: CoachChatRequest,
): Record<string, string | number | boolean | null | undefined> {
  const hasPriorAnswer = request.activeSessionTurns.some((turn) =>
    turn.role === "coach" && turn.kind === "answer"
  );
  const hasPriorClarification = request.activeSessionTurns.some((turn) =>
    turn.role === "coach" && turn.kind === "clarification"
  );
  // Batch A：fallback 不再產罐頭救場句（「丟一個好回答的小問題」正是
  // conversation-rescue 病灶）。使用者自己的草稿可以保留；沒有就不給句。
  // R2 主審 P1-1：草稿也要過建議句守門（placeholder／多問句）——fallback
  // 路徑不跑 assert 群，這裡是它進複製卡前的最後一道。Beta 詞群免查：
  // 草稿本身就是來源。
  const baseLine = request.rawReplyDraft?.trim();
  const keepDraft = baseLine != null && baseLine.length > 0 &&
    baseLine.length <= 80 &&
    !SUGGESTED_LINE_PLACEHOLDER_RE.test(baseLine) &&
    ((baseLine.match(/[?？]/g) ?? []).length) <= 1;
  return {
    responseType: "coachAnswer",
    mode: inferFallbackAnswerMode(request),
    headline: "先給你保守版",
    answer: hasPriorAnswer
      ? "我先沿用前一輪判斷補一個保守方向：不要重複解釋，也不要急著推進。這輪值不值得回、由誰先投入，比句子本身重要；她沒有給新東西時，不回也是一個正確選項。這版是系統保守建議，本次不扣額度。"
      : hasPriorClarification
      ? "你已經補充了，我先不再追問同一題。保守做法是先回得短一點、不要自證太多，把重點放在接住她的情緒或狀態；她投入少你就跟著少，不用替對話續命。本次保守版不扣額度。"
      : "我先給你保守方向：不要把訊息寫得太滿，也不要急著證明自己。先看她這輪實際給了什麼——有接球才值得延伸，沒接球就降低投入等下一輪。本次保守版不扣額度。",
    userTruth: null,
    userState: "你現在需要先拿到可執行方向，而不是再被追問同一題。",
    frictionType: "unclearIntent",
    nextStep: keepDraft
      ? "先用你自己的原句送出短版；她有接再延伸。"
      : "先判斷這輪值不值得回；要回就短而低壓，不確定就等她的下一則。",
    suggestedLine: keepDraft ? baseLine : null,
    rewriteDecision: keepDraft ? "light_edit" : "do_not_send",
    rewriteReason: keepDraft
      ? "這是低信心保守版：你的原句已可用，先不多加工。"
      : "系統這輪生不出夠可靠的句子，先不給可貼句，避免給你錯的話術。",
    boundaryReminder: "如果她明顯冷或累，先降壓，不要追問或逼她立刻表態。",
    needsReflection: false,
    reflectionQuestion: null,
    costDeducted: FALLBACK_NO_CHARGE,
  };
}

function inferFallbackAnswerMode(request: CoachChatRequest): string {
  const question = request.userQuestion.toLowerCase();
  if (/推進|約|邀|升溫|收尾|關門|轉場/.test(question)) {
    return "moveForward";
  }
  if (/界線|男友|女友|伴侶|不舒服|拒絕|停止|不要/.test(question)) {
    return "boundaryRisk";
  }
  return "replyCraft";
}

function buildFallbackClarificationShape(
  request: CoachChatRequest,
): Record<string, string | number | boolean | null | undefined> {
  // 首輪閘門下的 fallback 不能問「你聽到她這句話後…」——根本還沒有
  // 對話。global 問三分法處境題；partner（Batch A）引導補個案證據。
  if (mustClarifyFirstRound(request)) {
    const isPartnerScope = request.scope?.type === "partner";
    return {
      responseType: "clarifyingQuestion",
      mode: "clarifyIntent",
      headline: isPartnerScope ? "先讓我看到你們的對話" : "先弄清楚你的處境",
      answer: isPartnerScope
        ? "這題我可以判斷，但我現在看不到你和她的實際對話，硬給建議只會是空話。先幫我補上實際內容。"
        : "這題可以給方向，但我需要先知道你現在的局面，建議才不會空泛。先幫我選一個最接近的狀況。",
      userTruth: null,
      userState: isPartnerScope
        ? "你想要個案建議，但教練還沒看到任何實際對話。"
        : "你想要可執行的方向，但還沒說目前是哪種局面。",
      frictionType: "unclearIntent",
      nextStep: isPartnerScope
        ? "切到與她的對話視窗再問，或把她最近幾則原話貼進來。"
        : "先選一個最接近的狀況。",
      suggestedLine: null,
      rewriteDecision: null,
      rewriteReason: null,
      boundaryReminder: "免費釐清最多 3 次；正式建議才扣 1 則。",
      needsReflection: true,
      reflectionQuestion: isPartnerScope
        ? "你要切到與她的對話視窗再問、貼上她最近三到五則原話，還是先聽不綁個案的通用原則？"
        : "這是全新對象、聊到一半斷掉想重新接上，還是正在聊但沒話題？",
    };
  }
  const question = request.userQuestion.toLowerCase();
  const isMoveForward = /推進|約|邀|升溫|收尾|關門|轉場/.test(question);
  const primaryReflection = isMoveForward
    ? "你說推進，是想邀約、升溫，還是確認她意願？"
    : "你聽到她這句話後，心裡第一個反應是什麼？";
  const alternateReflection = isMoveForward
    ? "先補一句你真正想達成的下一步：見面、升溫，還是先確認她願不願意聊下去？"
    : "先補一句你心裡其實想怎麼回，不用修飾。";
  const usedPrimaryReflection = request.activeSessionTurns.some((turn) =>
    turn.role === "coach" &&
    turn.kind === "clarification" &&
    turn.content.trim() === primaryReflection
  );
  return {
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
    boundaryReminder: "免費釐清最多 3 次；正式建議才扣 1 則。",
    needsReflection: true,
    reflectionQuestion: usedPrimaryReflection
      ? alternateReflection
      : primaryReflection,
  };
}

const VALID_RESPONSE_TYPES = new Set(["clarifyingQuestion", "coachAnswer"]);
const VALID_MODES = new Set([
  "clarifyIntent",
  "stateCalibration",
  "boundaryRisk",
  "moveForward",
  "replyCraft",
  "stopSignal",
]);
const VALID_FRICTION_TYPES = new Set([
  "fearOfMistake",
  "overPolishing",
  "hesitatesToMoveForward",
  "emotionalOverreach",
  "boundaryRisk",
  "stopLoss",
  "unclearIntent",
  "none",
]);
const VALID_REWRITE_DECISIONS = new Set([
  "keep_original",
  "light_edit",
  "rewrite",
  "do_not_send",
]);

function repairCardShape(
  raw: Record<string, string | number | boolean | null | undefined>,
  request: CoachChatRequest,
): Record<string, string | number | boolean | null | undefined> {
  const rawResponseType = typeof raw.responseType === "string"
    ? raw.responseType
    : "";
  const responseType = VALID_RESPONSE_TYPES.has(rawResponseType)
    ? rawResponseType
    : inferResponseType(raw);

  if (responseType === "clarifyingQuestion") {
    return repairClarificationCard(raw, request);
  }
  return repairCoachAnswerCard(raw, request);
}

function repairClarificationCard(
  raw: Record<string, string | number | boolean | null | undefined>,
  request: CoachChatRequest,
): Record<string, string | number | boolean | null | undefined> {
  const fallback = buildFallbackClarificationShape(request);
  return {
    responseType: "clarifyingQuestion",
    mode: validString(raw.mode, VALID_MODES) ?? fallback.mode,
    headline: nonEmptyString(raw.headline) ?? fallback.headline,
    answer: nonEmptyString(raw.answer) ?? fallback.answer,
    userTruth: nullableString(raw.userTruth),
    userState: nonEmptyString(raw.userState) ?? fallback.userState,
    frictionType: validString(raw.frictionType, VALID_FRICTION_TYPES) ??
      fallback.frictionType,
    nextStep: nonEmptyString(raw.nextStep) ?? fallback.nextStep,
    suggestedLine: null,
    rewriteDecision: null,
    rewriteReason: null,
    boundaryReminder: nonEmptyString(raw.boundaryReminder) ??
      fallback.boundaryReminder,
    needsReflection: true,
    reflectionQuestion: nonEmptyString(raw.reflectionQuestion) ??
      fallback.reflectionQuestion,
    costDeducted: 0,
  };
}

function repairCoachAnswerCard(
  raw: Record<string, string | number | boolean | null | undefined>,
  request: CoachChatRequest,
): Record<string, string | number | boolean | null | undefined> {
  const answer = nonEmptyString(raw.answer);
  if (answer == null) {
    return shouldUseNoChargeAnswerFallback(request)
      ? buildFallbackCoachAnswerShape(request)
      : buildFallbackClarificationShape(request);
  }
  const isMoveForward = /推進|約|邀|升溫|收尾|關門|轉場/.test(
    request.userQuestion.toLowerCase(),
  );
  const needsReflection = typeof raw.needsReflection === "boolean"
    ? raw.needsReflection
    : false;

  return {
    responseType: "coachAnswer",
    mode: validString(raw.mode, VALID_MODES) ??
      (isMoveForward ? "moveForward" : "replyCraft"),
    headline: nonEmptyString(raw.headline) ?? "先收斂成一小步",
    answer,
    userTruth: nullableString(raw.userTruth),
    userState: nonEmptyString(raw.userState) ??
      "你正在找一個穩而不過度的下一步。",
    frictionType: validString(raw.frictionType, VALID_FRICTION_TYPES) ??
      (isMoveForward ? "hesitatesToMoveForward" : "unclearIntent"),
    nextStep: nonEmptyString(raw.nextStep) ??
      "先做一個低壓、小幅度的試探。",
    suggestedLine: nullableString(raw.suggestedLine),
    rewriteDecision:
      validString(raw.rewriteDecision, VALID_REWRITE_DECISIONS) ??
        "light_edit",
    rewriteReason: nullableString(raw.rewriteReason) ??
      "保留方向，只把語氣收穩。",
    boundaryReminder: nonEmptyString(raw.boundaryReminder) ??
      "把選擇權留給對方，不要用焦慮推進。",
    needsReflection,
    reflectionQuestion: needsReflection
      ? (nonEmptyString(raw.reflectionQuestion) ?? "你真正想達成的是什麼？")
      : nullableString(raw.reflectionQuestion),
    costDeducted: 1,
  };
}

function inferResponseType(
  raw: Record<string, string | number | boolean | null | undefined>,
): string {
  if (raw.needsReflection === true && raw.rewriteDecision == null) {
    return "clarifyingQuestion";
  }
  return "coachAnswer";
}

function nonEmptyString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length ? trimmed : null;
}

function nullableString(value: unknown): string | null {
  return nonEmptyString(value);
}

function validString(value: unknown, allowed: Set<string>): string | null {
  const text = nonEmptyString(value);
  return text != null && allowed.has(text) ? text : null;
}

function summarizeValidationError(error: unknown): string {
  const maybeIssues = (error as { issues?: unknown } | null)?.issues;
  if (Array.isArray(maybeIssues)) {
    return maybeIssues.slice(0, 4).map((issue) => {
      const item = issue as { path?: unknown; message?: unknown };
      const path = Array.isArray(item.path) && item.path.length
        ? item.path.join(".")
        : "_";
      return `${path}:${String(item.message ?? "invalid")}`;
    }).join("|").slice(0, 260);
  }
  return getErrorMessage(error).slice(0, 260);
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
  const data = claudeData as {
    content?: Array<{ type?: string; text?: string }>;
    stop_reason?: string;
  };
  if (data.stop_reason === "refusal") {
    throw new Error("refusal");
  }
  if (data.stop_reason === "model_context_window_exceeded") {
    throw new Error("model_context_window_exceeded");
  }
  const rawText = (data.content ?? [])
    .filter((block) => block.type == null || block.type === "text")
    .map((block) => block.text ?? "")
    .join("");
  const jsonMatch = rawText.match(/\{[\s\S]*\}/);
  if (!jsonMatch) {
    if (data.stop_reason === "max_tokens") {
      throw new Error("max_tokens");
    }
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
    if (data.stop_reason === "max_tokens") {
      throw new Error("max_tokens");
    }
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
