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
// 批 A（2026-08-01）：加 global（全域教練，不綁對象；無 id 欄——一人一串）。
export const CoachScopeSchema = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("conversation"),
    conversationId: z.string().min(1).max(100),
  }).strict(),
  z.object({
    type: z.literal("partner"),
    partnerId: z.string().min(1).max(100),
  }).strict(),
  z.object({
    type: z.literal("global"),
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
// Batch B2（CoachAnswerV2）：「這一輪要不要傳訊息」的正式三態。伺服器端
// deterministic 推導（見 deriveMessageDecision），模型契約不含此欄——
// 模型不擲骰、不會漂移，UI 不再從 suggestedLine null 態反推。
export const MessageDecisionEnum = z.enum([
  "send",
  "hold_off",
  "no_message_needed",
]);
// Batch B2：本卡背後的個案證據量。同樣伺服器端 deterministic（依 request
// context 推導，見 generation.ts deriveEvidenceQuality），非模型自評。
export const EvidenceQualityEnum = z.enum([
  "none",
  "stale_or_partial",
  "fresh",
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
  // 2026-08-19：使用者在「對象設定」填的長期備註（客端 customNote，
  // 上限 300）。選填、缺席＝現行為；dataQualityFlagged 時必須缺席（同 traits）。
  note: z.string().max(300).nullable().optional(),
}).strict();

// Batch B1（2026-08-31）：partner scope 補送「最近一段有效對話」時的來源
// 標記（client 本地 conversation id＋最後訊息時間）。選填、缺席＝現行為；
// 只有 partner scope 可帶（superRefine 強制）——conversation scope 的來源
// 就是對話本身，global 不綁對象。不入 computeCoachInputHash（context 欄位
// 不入 hash 的既有先例）。
export const ContextProvenanceSchema = z.object({
  sourceConversationId: z.string().min(1).max(100),
  lastMessageAt: z.string().max(40).nullable().optional(),
}).strict();

// Batch B3：近期「已送出的建議與對方反應」（client 的結構化 outcome 事件，
// 由舊到新）。邀約分類刻意留在 server（LINE_INVITE_RE 同源，不跨語言複製
// 詞群）；summary 是教練自家產出文字（nextStep/suggestedLine），絕不含
// 對方原文或使用者筆記。選填、缺席＝現行為；不入 computeCoachInputHash。
export const SentAdviceOutcomeSchema = z.object({
  summary: z.string().min(1).max(160),
  outcome: z.enum([
    "engaged",
    "cold",
    "noReply",
    "negative",
    "pending",
    "unknown",
  ]),
  createdAt: z.string().max(40).nullable().optional(),
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
  effectiveStyleContext: z.string().max(900).nullable().optional(),
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
  // Batch B1：partner scope 來源對話標記（見 ContextProvenanceSchema 註解）。
  contextProvenance: ContextProvenanceSchema.nullable().optional(),
  // Batch B3：邀約歷史來源資料（見 SentAdviceOutcomeSchema 註解）。
  inviteHistory: z.array(SentAdviceOutcomeSchema).max(10).optional(),
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
    payload.dataQualityFlagged &&
    payload.partnerHint?.note != null &&
    payload.partnerHint.note.length > 0
  ) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["partnerHint", "note"],
      message: "partnerHint.note must be omitted when dataQualityFlagged",
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
  // 批 A：global scope 的合成 conversationId 固定 'global:me'，且不綁對象——
  // 頂層 partnerId 與所有對象綁定欄位（partnerHint/conversationSummary/
  // analysisSnapshot）都必須缺席，否則對象隱私會混進「不綁對象」串、prompt
  // 也會同時出現全域框架與對象上下文（review Grok Imp-3／GLM P2-1）。
  // 形狀不符一律拒收，不得靜默當 partner。
  // Batch B1：contextProvenance 只有 partner scope 可帶。legacy 無 scope、
  // conversation、global 一律拒收——形狀不符不靜默吞。
  if (payload.contextProvenance != null && payload.scope?.type !== "partner") {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["contextProvenance"],
      message: "context_provenance_scope_mismatch",
    });
  }
  // B3：inviteHistory 綁定單一對象的邀約歷史；global 的 unbound 事件混
  // 不同真實對象，「兩次未承接」語意不成立，一律拒收。
  if (
    payload.scope?.type === "global" &&
    (payload.conversationId !== "global:me" ||
      payload.partnerId != null ||
      payload.partnerHint != null ||
      payload.conversationSummary != null ||
      payload.analysisSnapshot != null ||
      (payload.inviteHistory != null && payload.inviteHistory.length > 0))
  ) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["scope"],
      message: "scope_global_shape_mismatch",
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
  // Batch B2：兩欄輸入端選填（24h 內舊 replay rows 沒有這兩鍵，重放驗證
  // 不得炸）；messageDecision 由 transform 一律覆寫成 deterministic 值。
  messageDecision: MessageDecisionEnum.nullable().optional(),
  evidenceQuality: EvidenceQualityEnum.nullable().optional(),
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
  messageDecision: deriveMessageDecision(card),
}));

/// Batch B2：messageDecision 的唯一真相源（costDeducted 同款 transform
/// 覆寫模式）。釐清卡 null；有句＝send；無句且 do_not_send＝hold_off
/// （這輪先別傳）；無句其餘＝no_message_needed（本來就不是傳訊息的題）。
/// generation.ts 的剝句路徑繞過 schema 重建卡，必須同用此函式。
export function deriveMessageDecision(card: {
  responseType?: string | null;
  suggestedLine?: string | null;
  rewriteDecision?: string | null;
}): z.infer<typeof MessageDecisionEnum> | null {
  if (card.responseType === "clarifyingQuestion") return null;
  if (card.suggestedLine != null && card.suggestedLine.trim() !== "") {
    return "send";
  }
  if (card.rewriteDecision === "do_not_send") return "hold_off";
  return "no_message_needed";
}

export const ResponseSchema = z.object({
  card: ResponseCardSchema,
  provider: z.literal("claude"),
  model: z.string().min(1),
  generatedAt: z.string().min(1),
});

export type CoachChatRequest = z.infer<typeof RequestSchema>;
export type CoachChatResponseCard = z.infer<typeof ResponseCardSchema>;
export type CoachChatResponse = z.infer<typeof ResponseSchema>;
