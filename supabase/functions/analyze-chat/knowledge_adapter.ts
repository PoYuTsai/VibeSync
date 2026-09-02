// Phase 2：Analyze 端的 social-knowledge adapter（規格 §11）。
//
// Analyze 沒有 userQuestion，也沒有 Coach 的 lifecyclePhase；它有的是對話
// 訊息、上次階段與使用者風格設定。這裡把 AnalyzeMessage 轉成 selector 吃的
// 形狀，並補上 Analyze 固定成立的 typed signals，讓 shared selector 以
// 6–10 條、每 domain 有上限的預算挑 atoms。只用在 v2 prompt；v1 byte-lock 不動。

import type { AnalyzeMessage } from "./analysis_input_compiler.ts";
import { normalizeStagePrior } from "./stream_prompt.ts";
import type {
  SocialKnowledgeAtom,
  SocialKnowledgeSignal,
} from "../_shared/social/knowledge_registry.ts";
import {
  detectSocialKnowledgeSignals,
  domainCap,
  idPrefixCap,
  selectSocialKnowledge,
  type SocialKnowledgeSelectionInput,
  type SocialKnowledgeSelectionOptions,
} from "../_shared/social/knowledge_selector.ts";

export interface AnalyzeKnowledgeInput {
  readonly messages: readonly AnalyzeMessage[];
  readonly previousStage?: string;
  readonly userDraft?: string;
  readonly conversationSummary?: string;
  readonly effectiveStyleContext?: string;
}

/// §11.2：core 2–3、evidence 2–3、action 1–2、voice 1–2、safety 依情境，
/// 合計 6–10；硬上限沿用 selector 的 1,400 字元。core 六條全是 always，
/// 不設上限會吃掉大半預算，情境規則反而進不來。
export const ANALYZE_KNOWLEDGE_BUDGET: SocialKnowledgeSelectionOptions = {
  maxAtoms: 10,
  maxChars: 1_400,
  caps: [
    idPrefixCap("core.", 3),
    domainCap("decision", 3),
    domainCap("evidence", 3),
    domainCap("action", 2),
    domainCap("voice", 2),
  ],
};

/// selector 的投入訊號只看最後 8 則；多給幾則讓 regex 也看得到前文。
const RECENT_MESSAGE_WINDOW = 12;

export function buildAnalyzeSocialKnowledgeInput(
  input: AnalyzeKnowledgeInput,
): SocialKnowledgeSelectionInput {
  const recentMessages = input.messages
    .slice(-RECENT_MESSAGE_WINDOW)
    .map((message) => ({
      sender: message.isFromMe ? "me" as const : "partner" as const,
      text: message.content,
    }));
  // 只補 selector 自己偵測不到的情境訊號。Analyze 永遠在「解讀」，但把
  // interpretation 當固定訊號會讓泛用 evidence／reply 規則靠多訊號加分
  // 擠掉精準的邀約／拒絕規則（實測），所以不給；reply 由訊息存在自動成立。
  const typedSignals: SocialKnowledgeSignal[] = [];
  if (normalizeStagePrior(input.previousStage) === "close") {
    typedSignals.push("invite");
  }
  return {
    userQuestion: "",
    rawReplyDraft: input.userDraft ?? null,
    recentMessages,
    conversationSummary: input.conversationSummary ?? null,
    effectiveStyleContext: input.effectiveStyleContext ?? null,
    typedSignals,
  };
}

export function selectAnalyzeSocialKnowledge(
  input: AnalyzeKnowledgeInput,
): readonly SocialKnowledgeAtom[] {
  return selectSocialKnowledge(
    buildAnalyzeSocialKnowledgeInput(input),
    ANALYZE_KNOWLEDGE_BUDGET,
  );
}

/// telemetry 用：這次命中的訊號（排序後），配 atom ids 一起記。
export function detectAnalyzeSocialKnowledgeSignals(
  input: AnalyzeKnowledgeInput,
): readonly SocialKnowledgeSignal[] {
  return [
    ...detectSocialKnowledgeSignals(buildAnalyzeSocialKnowledgeInput(input)),
  ]
    .sort();
}
