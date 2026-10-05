// 新話題提示詞路由（ADR #51）：handler 與評測工具共用的 planNewTopicPrompt。
import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { allowsNewTopicSharedFrame } from "./new_topic_payload.ts";
import { planNewTopicPrompt } from "./new_topic_prompt_plan.ts";
import { hasNewTopicTwoStagePromptLeak } from "./prompt_leak.ts";
import {
  buildNewTopicTwoStageUserPrompt,
  NEW_TOPIC_TWO_STAGE_PROMPT,
  NEW_TOPIC_TWO_STAGE_PROMPT_VERSION,
  newTopicTodayLabel,
  sanitizeNewTopicTopicContext,
} from "./new_topic_two_stage.ts";

const REQUEST_ID = "123e4567-e89b-42d3-a456-426614174000";
const PARTNER = "[對象作戰板：Miya]\n- 興趣：咖啡、爬山";
// 台灣時間 2026-10-05（週一）12:00。
const NOW_MS = Date.UTC(2026, 9, 5, 4, 0);

Deno.test("plan：基本模式（沒帶 topicContext）走 v2.3、帶今天、不套紅燈收尾、沒有素材豁免", () => {
  const plan = planNewTopicPrompt({
    partnerSummary: PARTNER,
    effectiveStyleContext: null,
    situation: "after_date",
    topicContext: null,
    requestId: REQUEST_ID,
    nowMs: NOW_MS,
  });
  assertEquals(plan.system, NEW_TOPIC_TWO_STAGE_PROMPT);
  assertEquals(
    plan.user,
    buildNewTopicTwoStageUserPrompt({
      partnerSummary: PARTNER,
      effectiveStyleContext: null,
      situation: "after_date",
      topicContext: null,
      requestId: REQUEST_ID,
      today: "2026 年 10 月 5 日（週一）",
    }),
  );
  assert(
    plan.user.includes("## 今天（台灣時間）\n2026 年 10 月 5 日（週一）。"),
  );
  assertEquals(plan.hasPromptLeak, hasNewTopicTwoStagePromptLeak);
  assertEquals(plan.grounding, {
    allowSharedFrame: allowsNewTopicSharedFrame({
      partnerSummary: PARTNER,
      situation: "after_date",
      topicContext: null,
    }),
    userMaterialText: null,
  });
  assertFalse(plan.appliesRedClose);
  assertEquals(plan.promptVariant, "basic");
  assertEquals(plan.promptVersion, NEW_TOPIC_TWO_STAGE_PROMPT_VERSION);
});

Deno.test("plan：進階模式帶素材 → 素材原文進使用者提示詞與 grounding 豁免、套紅燈收尾規則", () => {
  const sanitized = sanitizeNewTopicTopicContext(
    {
      engagement: "red",
      materialKind: "my_story",
      materialText: "這週被拉去跑接力賽",
    },
    "warm_up",
  );
  assert(sanitized.ok && sanitized.topicContext !== null);
  const topicContext = sanitized.topicContext;
  const plan = planNewTopicPrompt({
    partnerSummary: PARTNER,
    effectiveStyleContext: null,
    situation: "warm_up",
    topicContext,
    requestId: REQUEST_ID,
    nowMs: NOW_MS,
  });
  assertEquals(plan.system, NEW_TOPIC_TWO_STAGE_PROMPT);
  assertEquals(
    plan.user,
    buildNewTopicTwoStageUserPrompt({
      partnerSummary: PARTNER,
      effectiveStyleContext: null,
      situation: "warm_up",
      topicContext,
      requestId: REQUEST_ID,
      today: newTopicTodayLabel(NOW_MS),
    }),
  );
  assert(plan.user.includes("- 原文：「這週被拉去跑接力賽」"));
  assertEquals(plan.grounding.userMaterialText, "這週被拉去跑接力賽");
  assert(plan.appliesRedClose);
  assertEquals(plan.promptVariant, "advanced");
});

Deno.test("plan：今天由 nowMs 照台灣時間決定（跨午夜換日）", () => {
  const at = (nowMs: number) =>
    planNewTopicPrompt({
      partnerSummary: PARTNER,
      effectiveStyleContext: null,
      situation: null,
      topicContext: null,
      requestId: REQUEST_ID,
      nowMs,
    }).user;
  assert(
    at(Date.UTC(2026, 9, 4, 15, 59)).includes("2026 年 10 月 4 日（週日）"),
  );
  assert(
    at(Date.UTC(2026, 9, 4, 16, 0)).includes("2026 年 10 月 5 日（週一）"),
  );
});
