import {
  assertEquals,
  assertRejects,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  assertCardSafe,
  truncateCard,
  validateRequest,
  validateResponseCard,
} from "./validate.ts";

const baseRequest = {
  conversationId: "c1",
  userQuestion: "她這句話是真的有興趣嗎？",
  recentMessages: [{ sender: "partner", text: "你感覺是個很有故事的人" }],
  dataQualityFlagged: false,
};

Deno.test("validateRequest accepts minimal coach chat payload", () => {
  const parsed = validateRequest(baseRequest);
  assertEquals(parsed.conversationId, "c1");
  assertEquals(parsed.recentMessages.length, 1);
});

Deno.test("validateRequest rejects images for coach-chat v1", () => {
  assertThrows(
    () => validateRequest({ ...baseRequest, images: ["base64"] }),
    Error,
    "images not accepted",
  );
});

Deno.test("validateRequest rejects partner traits when data quality is flagged", () => {
  assertThrows(
    () =>
      validateRequest({
        ...baseRequest,
        dataQualityFlagged: true,
        partnerHint: { name: "Candy", traits: ["慢熱"] },
      }),
    Error,
    "partnerHint.traits must be omitted",
  );
});

Deno.test("validateResponseCard requires reflection question when flagged", () => {
  assertThrows(
    () =>
      validateResponseCard({
        mode: "clarifyIntent",
        headline: "先問清楚自己",
        answer: "你現在資訊還不夠。",
        userState: "你可能急著找答案。",
        nextStep: "先釐清你真正想要什麼。",
        boundaryReminder: "不要用焦慮替對方補劇本。",
        needsReflection: true,
        reflectionQuestion: null,
      }),
    Error,
    "reflectionQuestion required",
  );
});

Deno.test("truncateCard caps long visible fields before validation", () => {
  const card = truncateCard({
    mode: "moveForward",
    headline: "這是一個非常非常非常非常非常長的標題",
    answer: "a".repeat(260),
    userState: "b".repeat(120),
    nextStep: "c".repeat(120),
    suggestedLine: "d".repeat(140),
    boundaryReminder: "e".repeat(100),
    needsReflection: false,
    reflectionQuestion: null,
  });
  const parsed = validateResponseCard(card);
  assertEquals(parsed.headline.length <= 32, true);
  assertEquals(parsed.answer.length <= 220, true);
  assertEquals(parsed.boundaryReminder.length <= 80, true);
});

Deno.test("assertCardSafe rejects shared banned tokens", () => {
  assertThrows(
    () =>
      assertCardSafe({
        mode: "replyCraft",
        headline: "不要走 PUA 框架",
        answer: "正常",
        userState: "正常",
        nextStep: "正常",
        boundaryReminder: "正常",
        needsReflection: false,
      }),
    Error,
    "banned_token: PUA",
  );
});
