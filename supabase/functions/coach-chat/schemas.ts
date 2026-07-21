import { z } from "https://deno.land/x/zod@v3.22.4/mod.ts";

export const CoachChatModeEnum = z.enum([
  "clarifyIntent",
  "stateCalibration",
  "boundaryRisk",
  "moveForward",
  "replyCraft",
  "stopSignal",
]);

export const LifecyclePhaseEnum = z.enum([
  "chatStalled",
  "prepareInvite",
  "postDate",
]);
export type LifecyclePhase = z.infer<typeof LifecyclePhaseEnum>;

// 教練統一案 Phase B：Phase C 帳本 scopeKey 前置的判別式 scope（選填）。
export const CoachScopeSchema = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("conversation"),
    conversationId: z.string().min(1).max(100),
  }).strict(),
  z.object({
    type: z.literal("partner"),
    partnerId: z.string().min(1).max(100),
  }).strict(),
]);
export type CoachScope = z.infer<typeof CoachScopeSchema>;

export const MessageSenderEnum = z.enum(["me", "partner"]);
export const SessionTurnRoleEnum = z.enum(["user", "coach"]);
export const SessionTurnKindEnum = z.enum([
  "question",
  "clarification",
  "supplement",
  "answer",
]);
export const ResponseTypeEnum = z.enum([
  "clarifyingQuestion",
  "coachAnswer",
]);
export const RewriteDecisionEnum = z.enum([
  "keep_original",
  "light_edit",
  "rewrite",
  "do_not_send",
]);
export const FrictionTypeEnum = z.enum([
  "fearOfMistake",
  "overPolishing",
  "hesitatesToMoveForward",
  "emotionalOverreach",
  "boundaryRisk",
  "stopLoss",
  "unclearIntent",
  "none",
]);

export const RequestMessageSchema = z.object({
  sender: MessageSenderEnum,
  text: z.string().min(1).max(500),
  createdAt: z.string().max(40).nullable().optional(),
});

export const SessionTurnSchema = z.object({
  role: SessionTurnRoleEnum,
  kind: SessionTurnKindEnum,
  content: z.string().min(1).max(500),
  createdAt: z.string().max(40).nullable().optional(),
}).strict();

export const AnalysisSnapshotSchema = z.object({
  heatScore: z.number().int().min(0).max(100).nullable().optional(),
  stage: z.string().max(40).nullable().optional(),
  summary: z.string().max(220).nullable().optional(),
  nextStep: z.string().max(220).nullable().optional(),
  coachActionType: z.string().max(80).nullable().optional(),
  keySignals: z.array(z.string().max(80)).max(8).optional(),
}).strict();

export const PartnerHintSchema = z.object({
  name: z.string().max(80).nullable().optional(),
  traits: z.array(z.string().max(40)).max(5).optional(),
}).strict();

export const RequestSchema = z.object({
  conversationId: z.string().min(1).max(100),
  partnerId: z.string().max(100).nullable().optional(),
  sessionId: z.string().max(120).nullable().optional(),
  userQuestion: z.string().min(1).max(240),
  rawReplyDraft: z.string().max(240).nullable().optional(),
  activeSessionTurns: z.array(SessionTurnSchema).max(12).default([]),
  forceAnswer: z.boolean().default(false),
  recentMessages: z.array(RequestMessageSchema).max(30).default([]),
  conversationSummary: z.string().max(500).nullable().optional(),
  analysisSnapshot: AnalysisSnapshotSchema.nullable().optional(),
  effectiveStyleContext: z.string().max(500).nullable().optional(),
  partnerHint: PartnerHintSchema.nullable().optional(),
  // 教練有記憶：近期建議結果的去識別化洞察句（client digest.statisticalInsightLines）。
  // 選填，缺席＝現行為（不注入 prompt）。只含統計句，不含對象回覆原文/筆記。
  outcomeInsightLines: z.array(z.string().max(120)).max(6).optional(),
  dataQualityFlagged: z.boolean().default(false),
  // 教練統一案 Phase B：三情境 framing（選填）。缺席＝現行為。
  lifecyclePhase: LifecyclePhaseEnum.nullable().optional(),
  // 教練統一案 Phase B：Phase C exactly-once 帳本前置欄位（選填）。
  // 本 Phase 只驗 UUID 格式（對齊 ADR #22 keyboard 範本）、不消費。
  // Phase C：帳本 key 前先 lowercase normalize（zod .uuid() 收大小寫混寫）。
  requestId: z.string().uuid().nullable().optional().transform((value) =>
    value == null ? value : value.toLowerCase()
  ),
  // 教練統一案 Phase B：Phase C scopeKey 前置（選填）。缺席＝現行為。
  scope: CoachScopeSchema.nullable().optional(),
}).strict().superRefine((payload, ctx) => {
  if (
    payload.dataQualityFlagged &&
    payload.partnerHint?.traits != null &&
    payload.partnerHint.traits.length > 0
  ) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["partnerHint", "traits"],
      message: "partnerHint.traits must be omitted when dataQualityFlagged",
    });
  }
  if (
    payload.scope?.type === "conversation" &&
    payload.scope.conversationId !== payload.conversationId
  ) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["scope", "conversationId"],
      message: "scope_conversation_id_mismatch",
    });
  }
  if (
    payload.scope?.type === "partner" &&
    payload.partnerId != null &&
    payload.scope.partnerId !== payload.partnerId
  ) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["scope", "partnerId"],
      message: "scope_partner_id_mismatch",
    });
  }
});

export const ResponseCardSchema = z.object({
  responseType: ResponseTypeEnum.default("coachAnswer"),
  mode: CoachChatModeEnum,
  headline: z.string().min(1).max(32),
  answer: z.string().min(1).max(360),
  userTruth: z.string().max(120).nullable().optional(),
  userState: z.string().min(1).max(100),
  frictionType: FrictionTypeEnum.default("unclearIntent"),
  nextStep: z.string().min(1).max(100),
  suggestedLine: z.string().max(160).nullable().optional(),
  rewriteDecision: RewriteDecisionEnum.nullable().optional(),
  rewriteReason: z.string().max(100).nullable().optional(),
  boundaryReminder: z.string().min(1).max(100),
  needsReflection: z.boolean(),
  reflectionQuestion: z.string().max(90).nullable().optional(),
  costDeducted: z.number().int().min(0).max(1).nullable().optional(),
}).strict().superRefine((card, ctx) => {
  if (
    card.needsReflection &&
    (card.reflectionQuestion == null || card.reflectionQuestion.trim() === "")
  ) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["reflectionQuestion"],
      message: "reflectionQuestion required when needsReflection=true",
    });
  }
  if (card.responseType === "clarifyingQuestion") {
    if (!card.needsReflection) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["needsReflection"],
        message: "clarifyingQuestion must set needsReflection=true",
      });
    }
  }
  if (card.responseType === "coachAnswer") {
    if (card.rewriteDecision == null) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["rewriteDecision"],
        message: "rewriteDecision required for coachAnswer",
      });
    }
  }
}).transform((card) => ({
  ...card,
  costDeducted: card.responseType === "clarifyingQuestion" ? 0 : 1,
}));

export const ResponseSchema = z.object({
  card: ResponseCardSchema,
  provider: z.literal("claude"),
  model: z.string().min(1),
  generatedAt: z.string().min(1),
});

export type CoachChatRequest = z.infer<typeof RequestSchema>;
export type CoachChatResponseCard = z.infer<typeof ResponseCardSchema>;
export type CoachChatResponse = z.infer<typeof ResponseSchema>;
