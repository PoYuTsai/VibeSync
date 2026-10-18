import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { GUIDE_V3_VERSION } from "../analyze-chat/guide_v3/guide_text.ts";
import type { GuideV3Decision } from "../analyze-chat/guide_v3/plan.ts";
import { LIGHTS } from "../analyze-chat/guide_v3/read_tags.ts";
import { TASK_CODE } from "../analyze-chat/guide_v3/wire.ts";
import { V3_CARD_TASK_CODES } from "../analyze-chat/stream_run_store.ts";
import {
  buildDiscordMessageBody,
  buildDiscordNotificationContent,
  GUIDE_V3_FEEDBACK_CARD_TASKS,
  GUIDE_V3_FEEDBACK_DECISIONS,
  GUIDE_V3_FEEDBACK_LIGHTS,
  GUIDE_V3_FEEDBACK_VERSIONS,
  maskEmailForNotification,
  resolveDiscordNotificationTarget,
  sanitizeFeedbackAiResponse,
  truncateOptionalStringToMax,
  VALID_FEEDBACK_CATEGORIES,
} from "./feedback_utils.ts";

const RUN_ID = "6f0c2c1e-4d5b-4d2f-9a8e-1b2c3d4e5f60";

Deno.test("feedback category whitelist includes Batch E coach failure modes", () => {
  for (
    const category of [
      "too_beta",
      "should_not_send",
      "too_generic",
      "invented_detail",
      "wrong_judgment",
      "too_many_questions",
      "missed_context",
    ]
  ) {
    assertEquals(VALID_FEEDBACK_CATEGORIES.has(category), true);
  }
  assertEquals(VALID_FEEDBACK_CATEGORIES.has("arbitrary"), false);
});

Deno.test("maskEmailForNotification masks normal emails", () => {
  assertEquals(
    maskEmailForNotification("vibesync.test@gmail.com"),
    "vi***@gmail.com",
  );
});

Deno.test("maskEmailForNotification masks short local parts", () => {
  assertEquals(maskEmailForNotification("a@b.com"), "a***@b.com");
});

Deno.test("maskEmailForNotification hides malformed emails", () => {
  assertEquals(maskEmailForNotification("unknown"), "hidden");
});

Deno.test("truncateOptionalStringToMax trims and clamps oversized input", () => {
  assertEquals(
    truncateOptionalStringToMax("  1234567890  ", 8),
    "12345...",
  );
});

Deno.test("truncateOptionalStringToMax keeps short input unchanged", () => {
  assertEquals(
    truncateOptionalStringToMax("  short  ", 10),
    "short",
  );
});

Deno.test("sanitizeFeedbackAiResponse keeps only whitelisted fields", () => {
  assertEquals(
    sanitizeFeedbackAiResponse({
      finalRecommendation: {
        pick: "extend",
        content: "先接住她的情緒，再順勢接話題。",
        reason: "這樣比較自然",
        psychology: "should be dropped",
      },
      strategy: "先共鳴，再延展",
      enthusiasmScore: 87,
      gameStage: "opening",
      gameStageStatus: "normal",
      topicDepth: "event",
      tierUsed: "starter",
      arbitrary: "drop me",
    }),
    {
      schemaVersion: 1,
      finalRecommendation: {
        pick: "extend",
        content: "先接住她的情緒，再順勢接話題。",
        reason: "這樣比較自然",
      },
      strategy: "先共鳴，再延展",
      enthusiasmScore: 87,
      gameStage: "opening",
      gameStageStatus: "normal",
      topicDepth: "event",
      tierUsed: "starter",
    },
  );
});

Deno.test("sanitizeFeedbackAiResponse clamps long text fields within max length", () => {
  const longText = "a".repeat(700);
  assertEquals(
    sanitizeFeedbackAiResponse({
      strategy: longText,
      finalRecommendation: {
        content: longText,
      },
    }),
    {
      schemaVersion: 1,
      strategy: `${"a".repeat(597)}...`,
      finalRecommendation: {
        content: `${"a".repeat(297)}...`,
      },
    },
  );
});

Deno.test("sanitizeFeedbackAiResponse clamps numeric score", () => {
  assertEquals(
    sanitizeFeedbackAiResponse({
      enthusiasmScore: 120.7,
    }),
    {
      schemaVersion: 1,
      enthusiasmScore: 100,
    },
  );
});

Deno.test("resolveDiscordNotificationTarget prefers webhook delivery", () => {
  assertEquals(
    resolveDiscordNotificationTarget({
      webhookUrl: "https://discord.com/api/webhooks/test",
      botToken: "bot-token",
      channelId: "123",
    }),
    "webhook",
  );
});

Deno.test("resolveDiscordNotificationTarget uses bot fallback when webhook is absent", () => {
  assertEquals(
    resolveDiscordNotificationTarget({
      botToken: "bot-token",
      channelId: "123",
    }),
    "bot",
  );
});

Deno.test("resolveDiscordNotificationTarget returns undefined for incomplete config", () => {
  assertEquals(
    resolveDiscordNotificationTarget({
      botToken: "bot-token",
    }),
    undefined,
  );
});

Deno.test("buildDiscordNotificationContent formats Discord webhook text", () => {
  assertEquals(
    buildDiscordNotificationContent(
      {
        userEmail: "vibesync.test@gmail.com",
        userTier: "starter",
        rating: "negative",
        category: "wrong_style",
        comment: "這次太像模板，不像我平常說話。",
        conversationSnippet: "她: 哈哈\n我: 真的假的",
        aiResponse: {
          finalRecommendation: {
            pick: "extend",
            content: "真的假的，你每次都這麼會接球喔？",
          },
        },
        modelUsed: "claude-sonnet-4-6",
      },
      {
        timestamp: "2026-04-24T12:00:00.000Z",
      },
    ),
    [
      "👎 沒幫助回饋 — 分析頁",
      "",
      "User: vi***@gmail.com (starter)",
      "Category: Wrong style",
      'Comment: "這次太像模板，不像我平常說話。"',
      "",
      "Conversation snippet:",
      "她: 哈哈",
      "我: 真的假的",
      "",
      "AI recommendation:",
      'extend: "真的假的，你每次都這麼會接球喔？"',
      "",
      "Model: claude-sonnet-4-6",
      "Time: 2026-04-24T12:00:00.000Z",
    ].join("\n"),
  );
});

Deno.test("buildDiscordNotificationContent formats positive coach feedback", () => {
  // 正評（2026-08-16 起也通知）：不放 Category，開頭標來源「問教練」。
  assertEquals(
    buildDiscordNotificationContent(
      {
        userEmail: "vibesync.test@gmail.com",
        userTier: "essential",
        rating: "positive",
        aiResponse: {
          finalRecommendation: {
            pick: "coach_chat",
            content: "先接住她的話，再丟一個輕鬆的開放題。",
          },
        },
        modelUsed: "claude-sonnet-5",
      },
      {
        timestamp: "2026-08-16T08:00:00.000Z",
      },
    ),
    [
      "👍 有幫助回饋 — 問教練",
      "",
      "User: vi***@gmail.com (essential)",
      "",
      "AI recommendation:",
      'coach_chat: "先接住她的話，再丟一個輕鬆的開放題。"',
      "",
      "Model: claude-sonnet-5",
      "Time: 2026-08-16T08:00:00.000Z",
    ].join("\n"),
  );
});

Deno.test("buildDiscordNotificationContent labels Batch E coach category", () => {
  const content = buildDiscordNotificationContent(
    {
      userEmail: "vibesync.test@gmail.com",
      userTier: "starter",
      rating: "negative",
      category: "should_not_send",
      aiResponse: {
        finalRecommendation: {
          pick: "coach_chat",
          content: "再問她一次週末有沒有空。",
        },
      },
      modelUsed: "claude-sonnet-5",
    },
    { timestamp: "2026-09-01T00:00:00.000Z" },
  );
  assertEquals(content.includes("Category: Should not send"), true);
  assertEquals(content.startsWith("👎 沒幫助回饋 — 問教練"), true);
});

Deno.test("sanitizeFeedbackAiResponse 保留對話分析 v3 的短欄位與 runId（Eric 2026-10-18）", () => {
  assertEquals(
    sanitizeFeedbackAiResponse({
      schemaVersion: 1,
      guideV3: {
        guideVersion: GUIDE_V3_VERSION,
        decision: "send",
        light: "green",
        cardTasks: ["accept", "push", "accept", "tension", "close"],
        runId: RUN_ID,
        feedbackCategory: "testing_her",
        cards: [{ messages: ["不該存"] }],
      },
    }),
    {
      schemaVersion: 1,
      guideV3: {
        guideVersion: GUIDE_V3_VERSION,
        decision: "send",
        light: "green",
        runId: RUN_ID,
        cardTasks: ["accept", "push", "accept", "tension", "close"],
        feedbackCategory: "testing_her",
      },
    },
  );
});

Deno.test("sanitizeFeedbackAiResponse 丟掉不認得的 v3 分類（含原型上的名字）", () => {
  for (const feedbackCategory of ["arbitrary", "constructor", "toString", 7]) {
    assertEquals(
      sanitizeFeedbackAiResponse({
        guideV3: { decision: "hold", feedbackCategory },
      }),
      { schemaVersion: 1, guideV3: { decision: "hold" } },
    );
  }
  assertEquals(
    sanitizeFeedbackAiResponse({ guideV3: "not an object" }),
    undefined,
  );
});

Deno.test("v3 回饋的合法值跟 analyze-chat 送給 App 的值一致（主審 r1 P2）", () => {
  assertEquals(GUIDE_V3_FEEDBACK_CARD_TASKS, new Set(V3_CARD_TASK_CODES));
  assertEquals(GUIDE_V3_FEEDBACK_CARD_TASKS, new Set(Object.values(TASK_CODE)));
  assertEquals(GUIDE_V3_FEEDBACK_LIGHTS, new Set(LIGHTS));
  assertEquals(GUIDE_V3_FEEDBACK_VERSIONS.has(GUIDE_V3_VERSION), true);
  // 型別上列滿每一種決定：plan.ts 加一種，這裡就編譯不過。
  const decisions: Record<GuideV3Decision, true> = {
    send: true,
    close: true,
    hold: true,
    stop: true,
    care: true,
  };
  assertEquals(GUIDE_V3_FEEDBACK_DECISIONS, new Set(Object.keys(decisions)));
});

Deno.test("v3 回饋欄位不合法就只丟那個欄位，回饋照收（主審 r1 P2）", () => {
  assertEquals(
    sanitizeFeedbackAiResponse({
      strategy: "先共鳴",
      guideV3: {
        guideVersion: "v9.9",
        decision: "maybe",
        light: "blue",
        cardTasks: ["accept", "hack"],
        runId: RUN_ID,
      },
    }),
    { schemaVersion: 1, strategy: "先共鳴", guideV3: { runId: RUN_ID } },
  );
  // 卡最多 5 張：多了就整個任務清單不收（位置對不回卡片）。
  assertEquals(
    sanitizeFeedbackAiResponse({
      guideV3: {
        decision: "send",
        cardTasks: ["accept", "push", "accept", "tension", "push", "accept"],
      },
    }),
    { schemaVersion: 1, guideV3: { decision: "send" } },
  );
  // 大小寫、前後空白也不算合法值。
  assertEquals(
    sanitizeFeedbackAiResponse({
      guideV3: { decision: " send", light: "GREEN", runId: RUN_ID },
    }),
    { schemaVersion: 1, guideV3: { runId: RUN_ID } },
  );
});

Deno.test("runId 只收 UUID（主審 r1 P2）", () => {
  for (
    const runId of [
      "run-123",
      "對話原文",
      `${RUN_ID}\n偽造通知`,
      RUN_ID.slice(0, -1),
      `${RUN_ID}0`,
      "6f0c2c1e4d5b4d2f9a8e1b2c3d4e5f60",
    ]
  ) {
    assertEquals(
      sanitizeFeedbackAiResponse({ guideV3: { decision: "send", runId } }),
      { schemaVersion: 1, guideV3: { decision: "send" } },
      runId,
    );
  }
});

Deno.test("v3 欄位塞 mention 或換行：清洗後不留、Discord 通知也不出現（主審 r1 P2）", () => {
  const injected = {
    guideVersion: "@everyone\n偽造通知",
    decision: "@everyone\n偽造通知",
    light: "<@&123456>",
    runId: "@here 對話原文",
    cardTasks: ["@everyone"],
    feedbackCategory: "@everyone",
  };
  assertEquals(sanitizeFeedbackAiResponse({ guideV3: injected }), undefined);
  // 就算有人直接拿沒清洗過的內容組通知，v3 那幾行也只用合法值。
  const content = buildDiscordNotificationContent(
    {
      userEmail: "vibesync.test@gmail.com",
      userTier: "free",
      rating: "negative",
      category: "other",
      aiResponse: { guideV3: injected },
    },
    { timestamp: "2026-10-18T00:00:00.000Z" },
  );
  assertEquals(content.includes("@everyone"), false);
  assertEquals(content.includes("偽造通知"), false);
  assertEquals(content.includes("@here"), false);
  assertEquals(content.includes("<@&"), false);
  assertEquals(content.includes("Category: Other"), true);
});

Deno.test("Discord 訊息一律不解析 mentions（主審 r1 P2）", () => {
  assertEquals(buildDiscordMessageBody("內容", "VibeSync Feedback"), {
    content: "內容",
    username: "VibeSync Feedback",
    allowed_mentions: { parse: [] },
  });
  assertEquals(buildDiscordMessageBody("內容"), {
    content: "內容",
    allowed_mentions: { parse: [] },
  });
});

Deno.test("buildDiscordNotificationContent 標出 v3 的分類、判讀與 runId", () => {
  const negative = buildDiscordNotificationContent(
    {
      userEmail: "vibesync.test@gmail.com",
      userTier: "free",
      rating: "negative",
      category: "other",
      aiResponse: {
        guideV3: {
          decision: "send",
          light: "yellow",
          runId: RUN_ID,
          feedbackCategory: "testing_her",
        },
      },
      modelUsed: "claude-sonnet-5-5",
    },
    { timestamp: "2026-10-18T00:00:00.000Z" },
  );
  assertEquals(negative.includes("Category: Testing / scoring her"), true);
  assertEquals(negative.includes("Category: Other"), false);
  assertEquals(negative.includes(`v3: send / yellow run ${RUN_ID}`), true);
  assertEquals(negative.startsWith("👎 沒幫助回饋 — 分析頁"), true);

  const positive = buildDiscordNotificationContent(
    {
      userEmail: "vibesync.test@gmail.com",
      userTier: "free",
      rating: "positive",
      aiResponse: { guideV3: { decision: "hold", light: "red" } },
    },
    { timestamp: "2026-10-18T00:00:00.000Z" },
  );
  assertEquals(positive.includes("Category:"), false);
  assertEquals(positive.includes("v3: hold / red\n"), true);
});
