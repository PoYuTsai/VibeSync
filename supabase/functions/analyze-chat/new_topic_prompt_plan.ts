// 新話題提示詞路由（ADR #51）：handler 與評測工具共用同一個函式，評測送出的
// 提示詞、外洩守門、grounding 判準與紅燈收尾規則就是 production 的那一份。
// 純函式：不碰 DB、不連網、不記 log。

import {
  allowsNewTopicSharedFrame,
  type NewTopicGroundingPolicy,
  type NewTopicSituation,
} from "./new_topic_payload.ts";
import { hasNewTopicTwoStagePromptLeak } from "./prompt_leak.ts";
import {
  buildNewTopicTwoStageUserPrompt,
  NEW_TOPIC_TWO_STAGE_PROMPT,
  NEW_TOPIC_TWO_STAGE_PROMPT_VERSION,
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
  /** 紅燈收尾的伺服器保證只在帶 topicContext 的進階路徑套。 */
  appliesRedClose: boolean;
  promptVariant: "basic" | "advanced";
  promptVersion: string;
};

export function planNewTopicPrompt(input: {
  partnerSummary: string | null;
  effectiveStyleContext: string | null;
  situation: NewTopicSituation | null;
  topicContext: NewTopicTopicContext | null;
  requestId: string;
  /** 「今天」以台灣時間算：handler 傳請求開始時間，評測傳固定時間。 */
  nowMs: number;
}): NewTopicPromptPlan {
  return {
    system: NEW_TOPIC_TWO_STAGE_PROMPT,
    user: buildNewTopicTwoStageUserPrompt({
      partnerSummary: input.partnerSummary,
      effectiveStyleContext: input.effectiveStyleContext,
      situation: input.situation,
      topicContext: input.topicContext,
      // 切入角度由 requestId 決定：同次 replay 一致、不同次生成才換。
      requestId: input.requestId,
      // 不進重放指紋：同一筆跨日重試照常回放已落帳的結果。
      today: newTopicTodayLabel(input.nowMs),
    }),
    hasPromptLeak: hasNewTopicTwoStagePromptLeak,
    grounding: {
      allowSharedFrame: allowsNewTopicSharedFrame({
        partnerSummary: input.partnerSummary,
        situation: input.situation,
        topicContext: input.topicContext,
      }),
      // 只有進階路徑會有；用戶自己寫的字撞到內部術語時不算外洩。
      userMaterialText: input.topicContext?.materialText ?? null,
    },
    appliesRedClose: input.topicContext !== null,
    promptVariant: newTopicPromptVariant(input.topicContext),
    promptVersion: NEW_TOPIC_TWO_STAGE_PROMPT_VERSION,
  };
}
