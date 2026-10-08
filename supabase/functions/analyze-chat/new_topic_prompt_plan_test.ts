// 新話題提示詞路由（ADR #53 結構刀）：handler 與評測工具共用的 planNewTopicPrompt。
import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { allowsNewTopicSharedFrame } from "./new_topic_payload.ts";
import { planNewTopicPrompt } from "./new_topic_prompt_plan.ts";
import { hasNewTopicSlotsPromptLeak } from "./prompt_leak.ts";
import {
  buildNewTopicSlotsUserPrompt,
  NEW_TOPIC_SLOTS_SYSTEM_PROMPT,
  newTopicSlotsRecommendationReason,
  planNewTopicSlots,
} from "./new_topic_slots.ts";
import {
  NEW_TOPIC_PROMPT_VERSION,
  NEW_TOPIC_RED_CLOSE_REASON,
  newTopicTodayLabel,
  sanitizeNewTopicTopicContext,
} from "./new_topic_two_stage.ts";

const REQUEST_ID = "123e4567-e89b-42d3-a456-426614174000";
const PARTNER = "[對象作戰板：Miya]\n- 興趣：咖啡、爬山";
// 台灣時間 2026-10-05（週一）12:00。
const NOW_MS = Date.UTC(2026, 9, 5, 4, 0);

Deno.test("plan：基本模式（沒帶 topicContext）走結構刀、帶今天、沒有素材豁免；推薦固定第一題", () => {
  const plan = planNewTopicPrompt({
    partnerSummary: PARTNER,
    effectiveStyleContext: null,
    situation: "after_date",
    topicContext: null,
    requestId: REQUEST_ID,
    nowMs: NOW_MS,
  });
  assertEquals(plan.system, NEW_TOPIC_SLOTS_SYSTEM_PROMPT);
  const slots = planNewTopicSlots({
    situation: "after_date",
    topicContext: null,
    interests: ["咖啡", "爬山"],
    requestId: REQUEST_ID,
  });
  assertEquals(plan.slots, slots);
  assertEquals(
    plan.user,
    buildNewTopicSlotsUserPrompt({
      partnerSummary: PARTNER,
      effectiveStyleContext: null,
      situation: "after_date",
      topicContext: null,
      slots,
      today: "2026 年 10 月 5 日（週一）",
    }),
  );
  assert(
    plan.user.includes("### 今天（台灣時間）\n2026 年 10 月 5 日（週一）。"),
  );
  assertEquals(plan.hasPromptLeak, hasNewTopicSlotsPromptLeak);
  assertEquals(plan.grounding, {
    allowSharedFrame: allowsNewTopicSharedFrame({
      partnerSummary: PARTNER,
      situation: "after_date",
      topicContext: null,
    }),
    userMaterialText: null,
  });
  assertFalse(plan.appliesRedClose);
  assertEquals(
    plan.recommendationReason,
    newTopicSlotsRecommendationReason(slots[0], null),
  );
  assertEquals(plan.promptVariant, "basic");
  assertEquals(plan.promptVersion, NEW_TOPIC_PROMPT_VERSION);
  assertEquals(plan.promptVersion, "new-topic-slots-v1");
});

Deno.test("plan：進階模式帶素材 → 素材原文進提示詞與 grounding 豁免；紅燈時第一題是收尾、理由用固定句", () => {
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
  assertEquals(plan.system, NEW_TOPIC_SLOTS_SYSTEM_PROMPT);
  assertEquals(
    plan.user,
    buildNewTopicSlotsUserPrompt({
      partnerSummary: PARTNER,
      effectiveStyleContext: null,
      situation: "warm_up",
      topicContext,
      slots: plan.slots,
      today: newTopicTodayLabel(NOW_MS),
    }),
  );
  assert(plan.user.includes("- 原文：「這週被拉去跑接力賽」"));
  assertEquals(plan.grounding.userMaterialText, "這週被拉去跑接力賽");
  assert(plan.appliesRedClose);
  assertEquals(plan.slots.map((s) => s.kind), [
    "red_close",
    "share_material",
    "share_material_ask",
    "material_light",
    "ask_interest",
  ]);
  assertEquals(plan.recommendationReason, NEW_TOPIC_RED_CLOSE_REASON);
  assertEquals(plan.promptVariant, "advanced");
});

Deno.test("plan：同一個 requestId 排出同一組任務（重放一致），換 requestId 才換興趣順序", () => {
  const plan = (requestId: string) =>
    planNewTopicPrompt({
      partnerSummary: "[對象作戰板：小雯]\n- 興趣：甜點、爬山、韓劇",
      effectiveStyleContext: null,
      situation: null,
      topicContext: null,
      requestId,
      nowMs: NOW_MS,
    });
  assertEquals(plan(REQUEST_ID).user, plan(REQUEST_ID).user);
  const firstFoci = new Set<string | null>();
  for (let i = 0; i < 30; i++) firstFoci.add(plan(`req-${i}`).slots[0].focus);
  assertEquals(firstFoci, new Set(["甜點", "爬山", "韓劇"]));
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
