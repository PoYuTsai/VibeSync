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

Deno.test("validateRequest accepts dialogue session fields", () => {
  const parsed = validateRequest({
    ...baseRequest,
    sessionId: "s1",
    forceAnswer: true,
    rawReplyDraft: "哈哈哪有",
    activeSessionTurns: [
      {
        role: "user",
        kind: "question",
        content: "她說我很有故事是什麼意思？",
      },
      {
        role: "coach",
        kind: "clarification",
        content: "你聽到她這句話後，第一個反應是什麼？",
      },
    ],
  });
  assertEquals(parsed.sessionId, "s1");
  assertEquals(parsed.forceAnswer, true);
  assertEquals(parsed.activeSessionTurns.length, 2);
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
        responseType: "coachAnswer",
        headline: "先問清楚自己",
        answer: "你現在資訊還不夠。",
        userState: "你可能急著找答案。",
        nextStep: "先釐清你真正想要什麼。",
        rewriteDecision: "light_edit",
        rewriteReason: "先讓語氣更穩。",
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
    responseType: "coachAnswer",
    headline: "這是一個非常非常非常非常非常長的標題",
    answer: "a".repeat(420),
    userTruth: "x".repeat(160),
    userState: "b".repeat(140),
    nextStep: "c".repeat(140),
    suggestedLine: "d".repeat(140),
    rewriteDecision: "rewrite",
    rewriteReason: "f".repeat(140),
    boundaryReminder: "e".repeat(140),
    needsReflection: false,
    reflectionQuestion: null,
    costDeducted: 1,
  });
  const parsed = validateResponseCard(card);
  assertEquals(parsed.headline.length <= 32, true);
  assertEquals(parsed.answer.length <= 360, true);
  assertEquals((parsed.userTruth ?? "").length <= 120, true);
  assertEquals(parsed.boundaryReminder.length <= 100, true);
});

Deno.test("validateResponseCard accepts clarification when it does not deduct", () => {
  const parsed = validateResponseCard({
    responseType: "clarifyingQuestion",
    mode: "clarifyIntent",
    headline: "先問清楚你的真實想法",
    answer: "我先接住你：你其實有感覺，只是還沒說清楚。",
    userTruth: null,
    userState: "你可能還沒確定自己想推進還是想觀察。",
    nextStep: "先補一句你心裡原本想怎麼回。",
    suggestedLine: null,
    rewriteDecision: null,
    rewriteReason: null,
    boundaryReminder: "補充釐清不扣額度；正式建議才扣 1 則。",
    needsReflection: true,
    reflectionQuestion: "你聽到她這句話後，心裡第一個反應是什麼？",
    costDeducted: 0,
  });
  assertEquals(parsed.responseType, "clarifyingQuestion");
  assertEquals(parsed.costDeducted, 0);
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
