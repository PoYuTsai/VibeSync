// 新話題提示詞路由：handler 與評測工具共用同一個函式，評測送出的提示詞、外洩
// 守門、grounding 判準與推薦規則就是 production 的那一份。2026-10-09 起改走結構刀
// （ADR #53，new_topic_slots.ts）：伺服器排好五題任務，AI 只寫句子，推薦固定第一題。
// 純函式：不碰 DB、不連網、不記 log。

import {
  allowsNewTopicSharedFrame,
  type NewTopicGroundingPolicy,
  type NewTopicSituation,
} from "./new_topic_payload.ts";
import { hasNewTopicSlotsPromptLeak } from "./prompt_leak.ts";
import {
  buildNewTopicSlotsUserPrompt,
  NEW_TOPIC_SLOTS_SYSTEM_PROMPT,
  type NewTopicSlot,
  newTopicSlotsRecommendationReason,
  parseNewTopicInterests,
  planNewTopicSlots,
} from "./new_topic_slots.ts";
import {
  isNewTopicRedClose,
  NEW_TOPIC_PROMPT_VERSION,
  newTopicPromptVariant,
  newTopicTodayLabel,
  type NewTopicTopicContext,
} from "./new_topic_two_stage.ts";

export type NewTopicPromptPlan = {
  system: string;
  user: string;
  /** 整包外洩檢查：模型輸出命中就不交付、不扣。 */
  hasPromptLeak: (text: string | null | undefined) => boolean;
  grounding: NewTopicGroundingPolicy;
  /** 這筆是紅燈收尾（第一題是收尾句）；只用於 telemetry，推薦一律固定第一題。 */
  appliesRedClose: boolean;
  /** 五題的任務（順序就是 topics 的順序）。 */
  slots: NewTopicSlot[];
  /** 用戶看到的推薦理由（固定句，依第一題的任務）；推薦一律是第一題。 */
  recommendationReason: string;
  promptVariant: "basic" | "advanced";
  promptVersion: string;
};

/**
 * 用戶給我們、也進了提示詞的原文：對象作戰板摘要、素材原文。「關於我」只給
 * Coach 1:1（2026-08-04），不進新話題的提示詞，這裡也不收。
 */
function newTopicUserProvidedText(input: {
  partnerSummary: string | null;
  topicContext: NewTopicTopicContext | null;
}): string | null {
  const parts = [
    input.partnerSummary,
    input.topicContext?.materialText ?? null,
  ].filter((part): part is string => part !== null && part.trim() !== "");
  return parts.length === 0 ? null : parts.join("\n");
}

export function planNewTopicPrompt(input: {
  partnerSummary: string | null;
  situation: NewTopicSituation | null;
  topicContext: NewTopicTopicContext | null;
  requestId: string;
  /** 「今天」以台灣時間算：handler 傳請求開始時間，評測傳固定時間。 */
  nowMs: number;
}): NewTopicPromptPlan {
  const slots = planNewTopicSlots({
    situation: input.situation,
    topicContext: input.topicContext,
    interests: parseNewTopicInterests(input.partnerSummary),
    // 任務由 requestId 決定：同次 replay 一致、不同次生成才換興趣與問法。
    requestId: input.requestId,
  });
  const materialKind = input.topicContext?.materialText
    ? input.topicContext.materialKind
    : null;
  return {
    system: NEW_TOPIC_SLOTS_SYSTEM_PROMPT,
    user: buildNewTopicSlotsUserPrompt({
      partnerSummary: input.partnerSummary,
      situation: input.situation,
      topicContext: input.topicContext,
      slots,
      // 不進重放指紋：同一筆跨日重試照常回放已落帳的結果。
      today: newTopicTodayLabel(input.nowMs),
    }),
    hasPromptLeak: hasNewTopicSlotsPromptLeak,
    grounding: {
      allowSharedFrame: allowsNewTopicSharedFrame({
        partnerSummary: input.partnerSummary,
        situation: input.situation,
        topicContext: input.topicContext,
      }),
      // 用戶給的字撞到內部術語不算外洩：她的興趣是 One Direction、在讀人間失格時，
      // 說明欄提到它很正常，修格式也救不回（2026-10-12 唯讀評估 P2）。
      userProvidedText: newTopicUserProvidedText(input),
    },
    appliesRedClose: isNewTopicRedClose(input.situation, input.topicContext),
    slots,
    recommendationReason: newTopicSlotsRecommendationReason(
      slots[0],
      materialKind,
    ),
    promptVariant: newTopicPromptVariant(input.topicContext),
    promptVersion: NEW_TOPIC_PROMPT_VERSION,
  };
}
