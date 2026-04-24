import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
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
