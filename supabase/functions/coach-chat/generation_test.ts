import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { type ClaudeCallArgs, runCoachChat } from "./generation.ts";
import type { CoachChatRequest } from "./schemas.ts";

const request: CoachChatRequest = {
  conversationId: "c1",
  userQuestion: "她這句話是真的有興趣嗎？",
  activeSessionTurns: [],
  forceAnswer: false,
  recentMessages: [{ sender: "partner", text: "你感覺是個很有故事的人" }],
  dataQualityFlagged: false,
};

function validClaudeCard(overrides: Record<string, unknown> = {}) {
  return {
    content: [{
      text: JSON.stringify({
        mode: "replyCraft",
        responseType: "coachAnswer",
        headline: "承認一半再反問",
        answer:
          "她是在丟一個觀察，不一定是要你證明自己。接住一半，再補一個有畫面的反問就好。",
        userTruth: "你想接住她的好奇，但不想裝深沉。",
        userState: "你可能想抓住她的興趣，但不用急著解釋自己。",
        nextStep: "用一句輕鬆反問把球丟回去。",
        suggestedLine: "被妳發現了，我會在飲料櫃前思考人生。妳也是亂逛派嗎？",
        rewriteDecision: "light_edit",
        rewriteReason: "保留你的輕鬆感，只補一個畫面和反問。",
        boundaryReminder: "不要把一句觀察放大成承諾或壓力。",
        needsReflection: false,
        reflectionQuestion: null,
        costDeducted: 1,
        ...overrides,
      }),
    }],
  };
}

function deps(opts: {
  callClaude?: (args: ClaudeCallArgs) => Promise<unknown>;
  deductCredit?: () => Promise<void>;
}) {
  const events: string[] = [];
  let deductCalls = 0;
  return {
    events,
    get deductCalls() {
      return deductCalls;
    },
    deps: {
      callClaude: opts.callClaude ?? (() => Promise.resolve(validClaudeCard())),
      deductCredit: async () => {
        deductCalls++;
        if (opts.deductCredit) await opts.deductCredit();
      },
      logger: {
        info: (event: string) => events.push(event),
        warn: (event: string) => events.push(event),
      },
      now: () => 1_700_000_000_000,
    },
  };
}

Deno.test("runCoachChat returns card and deducts one credit on success", async () => {
  const harness = deps({});
  const result = await runCoachChat(
    {
      userId: "u1",
      request,
      tier: "starter",
      accountIsTest: false,
      apiKey: "key",
    },
    harness.deps,
  );
  assertEquals(result.status, 200);
  assertEquals(harness.deductCalls, 1);
  assertEquals(
    (result.body.card as Record<string, unknown>).mode,
    "replyCraft",
  );
  assertEquals(harness.events.includes("coach_chat_succeeded"), true);
});

Deno.test("runCoachChat returns clarification without deducting credit", async () => {
  const harness = deps({
    callClaude: () =>
      Promise.resolve(validClaudeCard({
        responseType: "clarifyingQuestion",
        mode: "clarifyIntent",
        headline: "先問清楚你的真實想法",
        answer: "我先接住你：你不是沒有答案，而是怕一回就失去分寸。",
        userTruth: null,
        userState: "你可能想推進，但還沒說清楚自己真實想回什麼。",
        nextStep: "先補一句你心裡原本想怎麼回。",
        suggestedLine: null,
        rewriteDecision: null,
        rewriteReason: null,
        boundaryReminder: "補充釐清不扣額度；正式建議才扣 1 則。",
        needsReflection: true,
        reflectionQuestion: "你聽到她這句話後，心裡第一個想回的是什麼？",
        costDeducted: 0,
      })),
  });
  const result = await runCoachChat(
    {
      userId: "u1",
      request,
      tier: "starter",
      accountIsTest: false,
      apiKey: "key",
    },
    harness.deps,
  );
  assertEquals(result.status, 200);
  assertEquals(harness.deductCalls, 0);
  assertEquals(
    (result.body.card as Record<string, unknown>).responseType,
    "clarifyingQuestion",
  );
  assertEquals((result.body.card as Record<string, unknown>).costDeducted, 0);
});

Deno.test("runCoachChat skips deduction for test account", async () => {
  const harness = deps({});
  const result = await runCoachChat(
    {
      userId: "u1",
      request,
      tier: "essential",
      accountIsTest: true,
      apiKey: "key",
    },
    harness.deps,
  );
  assertEquals(result.status, 200);
  assertEquals(harness.deductCalls, 0);
});

Deno.test("runCoachChat does not deduct on banned token", async () => {
  const harness = deps({
    callClaude: () => Promise.resolve(validClaudeCard({ headline: "PUA" })),
  });
  const result = await runCoachChat(
    {
      userId: "u1",
      request,
      tier: "starter",
      accountIsTest: false,
      apiKey: "key",
    },
    harness.deps,
  );
  assertEquals(result.status, 500);
  assertEquals(result.body.error, "banned_token");
  assertEquals(harness.deductCalls, 0);
});

Deno.test("runCoachChat does not return card when deduction fails", async () => {
  const harness = deps({
    deductCredit: () => Promise.reject(new Error("db")),
  });
  const result = await runCoachChat(
    {
      userId: "u1",
      request,
      tier: "starter",
      accountIsTest: false,
      apiKey: "key",
    },
    harness.deps,
  );
  assertEquals(result.status, 500);
  assertEquals(result.body.error, "credit_deduct_failed");
  assertEquals(harness.deductCalls, 1);
});

Deno.test("runCoachChat does not deduct on Claude failure", async () => {
  const harness = deps({
    callClaude: () => Promise.reject(new Error("timeout")),
  });
  const result = await runCoachChat(
    {
      userId: "u1",
      request,
      tier: "starter",
      accountIsTest: false,
      apiKey: "key",
    },
    harness.deps,
  );
  assertEquals(result.status, 500);
  assertEquals(harness.deductCalls, 0);
});
