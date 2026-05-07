import { z } from "https://deno.land/x/zod@v3.22.4/mod.ts";

export const CoachChatModeEnum = z.enum([
  "clarifyIntent",
  "stateCalibration",
  "boundaryRisk",
  "moveForward",
  "replyCraft",
  "stopSignal",
]);

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
  dataQualityFlagged: z.boolean().default(false),
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
  costDeducted: z.number().int().min(0).max(1).default(1),
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
    if (card.costDeducted !== 0) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["costDeducted"],
        message: "clarifyingQuestion must not deduct credit",
      });
    }
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
});

export const ResponseSchema = z.object({
  card: ResponseCardSchema,
  provider: z.literal("claude"),
  model: z.string().min(1),
  generatedAt: z.string().min(1),
});

export type CoachChatRequest = z.infer<typeof RequestSchema>;
export type CoachChatResponseCard = z.infer<typeof ResponseCardSchema>;
export type CoachChatResponse = z.infer<typeof ResponseSchema>;
