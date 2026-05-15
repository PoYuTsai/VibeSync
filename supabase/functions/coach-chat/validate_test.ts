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

Deno.test("validateRequest accepts bounded outcome digest context", () => {
  const parsed = validateRequest({
    ...baseRequest,
    outcomeDigestContext:
      "本地結果摘要：最近 3 次教練建議回報，對方有接 2、冷回 1。",
  });
  assertEquals(
    parsed.outcomeDigestContext,
    "本地結果摘要：最近 3 次教練建議回報，對方有接 2、冷回 1。",
  );
});

Deno.test("validateRequest rejects oversized outcome digest context", () => {
  assertThrows(
    () =>
      validateRequest({
        ...baseRequest,
        outcomeDigestContext: "x".repeat(501),
      }),
    Error,
    "String must contain at most 500",
  );
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
    suggestedLine: "d".repeat(190),
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
  assertEquals((parsed.suggestedLine ?? "").length <= 160, true);
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

Deno.test("validateResponseCard normalizes omitted clarification cost to zero", () => {
  const parsed = validateResponseCard({
    responseType: "clarifyingQuestion",
    mode: "clarifyIntent",
    headline: "先問清楚你的真實想法",
    answer: "你不是不能推進，而是還沒說清楚自己想推到哪一步。",
    userTruth: null,
    userState: "你可能想往前，但還沒釐清目的與可承擔成本。",
    nextStep: "先補一句你心裡真正想推進到哪裡。",
    suggestedLine: null,
    rewriteDecision: null,
    rewriteReason: null,
    boundaryReminder: "釐清不扣額度；正式建議才扣 1 則。",
    needsReflection: true,
    reflectionQuestion: "你說推進，是想邀約、升溫，還是確認對方意願？",
  });
  assertEquals(parsed.responseType, "clarifyingQuestion");
  assertEquals(parsed.costDeducted, 0);
});

Deno.test("validateResponseCard normalizes omitted coach answer cost to one", () => {
  const parsed = validateResponseCard({
    responseType: "coachAnswer",
    mode: "moveForward",
    headline: "先做一個小推進",
    answer: "這題可以推，但不要一次推太滿。先用低壓邀約測她願不願意給時間。",
    userTruth: "你想往前，但怕被拒絕。",
    userState: "你把推進想成一次成敗考試。",
    frictionType: "hesitatesToMoveForward",
    nextStep: "今天只丟一個可退可進的輕邀約。",
    suggestedLine: "那下次你想放空時，我帶你去一間安靜的甜點店。",
    rewriteDecision: "rewrite",
    rewriteReason: "把目的感改成低壓邀約。",
    boundaryReminder: "邀約是給選擇，不是給壓力。",
    needsReflection: false,
    reflectionQuestion: null,
  });
  assertEquals(parsed.responseType, "coachAnswer");
  assertEquals(parsed.costDeducted, 1);
});

Deno.test("validateResponseCard defaults frictionType for backwards compatibility", () => {
  const parsed = validateResponseCard({
    responseType: "coachAnswer",
    mode: "moveForward",
    headline: "先做一個小推進",
    answer: "你現在不是缺話術，而是怕一推就尷尬。先用一個低壓邀約測窗口。",
    userTruth: "你其實想約，只是怕被拒絕。",
    userState: "你把邀約想成一次成敗考試。",
    nextStep: "今天只丟一個可退可進的輕邀約。",
    suggestedLine: "那下次你想放空時，我帶你去一間安靜的甜點店。",
    rewriteDecision: "rewrite",
    rewriteReason: "把焦慮解釋改成低壓邀約。",
    boundaryReminder: "邀約是給選擇，不是給壓力。",
    needsReflection: false,
    reflectionQuestion: null,
    costDeducted: 1,
  });

  assertEquals(parsed.frictionType, "unclearIntent");
});

Deno.test("validateResponseCard rejects unknown frictionType", () => {
  assertThrows(
    () =>
      validateResponseCard({
        responseType: "coachAnswer",
        mode: "moveForward",
        headline: "先做一個小推進",
        answer: "你現在不是缺話術，而是怕一推就尷尬。先用一個低壓邀約測窗口。",
        userTruth: "你其實想約，只是怕被拒絕。",
        userState: "你把邀約想成一次成敗考試。",
        frictionType: "random",
        nextStep: "今天只丟一個可退可進的輕邀約。",
        suggestedLine: "那下次你想放空時，我帶你去一間安靜的甜點店。",
        rewriteDecision: "rewrite",
        rewriteReason: "把焦慮解釋改成低壓邀約。",
        boundaryReminder: "邀約是給選擇，不是給壓力。",
        needsReflection: false,
        reflectionQuestion: null,
        costDeducted: 1,
      }),
    Error,
  );
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

Deno.test("assertCardSafe rejects raw JSON/code-fence payloads", () => {
  assertThrows(
    () =>
      assertCardSafe({
        answer: '```json\n{"responseType":"coachAnswer","answer":"hi"}\n```',
      }),
    Error,
    "raw_model_payload: answer",
  );

  assertThrows(
    () =>
      assertCardSafe({
        suggestedLine: '{"responseType":"coachAnswer","card":{"answer":"hi"}}',
      }),
    Error,
    "raw_model_payload: suggestedLine",
  );
});
