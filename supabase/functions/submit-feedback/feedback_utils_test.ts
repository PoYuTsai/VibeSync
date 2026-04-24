import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildDiscordNotificationContent,
  maskEmailForNotification,
  sanitizeFeedbackAiResponse,
} from "./feedback_utils.ts";

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
        modelUsed: "claude-sonnet-4-20250514",
      },
      {
        timestamp: "2026-04-24T12:00:00.000Z",
      },
    ),
    [
      "Negative feedback received",
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
      "Model: claude-sonnet-4-20250514",
      "Time: 2026-04-24T12:00:00.000Z",
    ].join("\n"),
  );
});
