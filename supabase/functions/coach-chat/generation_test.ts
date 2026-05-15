import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  type ClaudeCallArgs,
  CoachChatQuotaExceededError,
  runCoachChat,
} from "./generation.ts";
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
        frictionType: "overPolishing",
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

function malformedClaudeCard() {
  return {
    content: [{
      text: "這不是 JSON",
    }],
  };
}

function partialClaudeAnswer(overrides: Record<string, unknown> = {}) {
  return {
    content: [{
      text: JSON.stringify({
        responseType: "coachAnswer",
        mode: "moveForward",
        headline: "先小幅推進",
        answer:
          "這題可以推，但不要一次推太滿。先用低壓方式確認她願不願意給時間。",
        nextStep: "先丟一個低壓邀約。",
        boundaryReminder: "邀約是給選擇，不是給壓力。",
        extraField: "Claude 偶爾會多吐欄位",
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
  assertEquals(
    (result.body.card as Record<string, unknown>).frictionType,
    "overPolishing",
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

Deno.test("runCoachChat accepts clarification when Claude omits cost", async () => {
  const harness = deps({
    callClaude: () =>
      Promise.resolve(validClaudeCard({
        responseType: "clarifyingQuestion",
        mode: "clarifyIntent",
        headline: "先問清楚你的推進目標",
        answer: "我先接住你：你不是不能推，而是還沒說清楚想推到哪一步。",
        userTruth: null,
        userState: "你可能想往前，但還沒釐清目的與成本。",
        nextStep: "先補一句你心裡真正想推進到哪裡。",
        suggestedLine: null,
        rewriteDecision: null,
        rewriteReason: null,
        boundaryReminder: "釐清不扣額度；正式建議才扣 1 則。",
        needsReflection: true,
        reflectionQuestion: "你說推進，是想邀約、升溫，還是確認她意願？",
        costDeducted: undefined,
      })),
  });
  const result = await runCoachChat(
    {
      userId: "u1",
      request: { ...request, userQuestion: "我該推進嗎？" },
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

Deno.test("runCoachChat repairs common coach answer schema drift", async () => {
  const harness = deps({
    callClaude: () => Promise.resolve(partialClaudeAnswer()),
  });
  const result = await runCoachChat(
    {
      userId: "u1",
      request: { ...request, userQuestion: "我該推進嗎？" },
      tier: "starter",
      accountIsTest: false,
      apiKey: "key",
    },
    harness.deps,
  );
  const card = result.body.card as Record<string, unknown>;
  assertEquals(result.status, 200);
  assertEquals(card.responseType, "coachAnswer");
  assertEquals(card.rewriteDecision, "light_edit");
  assertEquals(card.userState, "你正在找一個穩而不過度的下一步。");
  assertEquals("extraField" in card, false);
  assertEquals(harness.deductCalls, 1);
});

Deno.test("runCoachChat downgrades answer without answer text to a free clarification", async () => {
  const harness = deps({
    callClaude: () =>
      Promise.resolve(partialClaudeAnswer({
        answer: undefined,
      })),
  });
  const result = await runCoachChat(
    {
      userId: "u1",
      request: { ...request, userQuestion: "我該推進嗎？" },
      tier: "starter",
      accountIsTest: false,
      apiKey: "key",
    },
    harness.deps,
  );
  const card = result.body.card as Record<string, unknown>;
  assertEquals(result.status, 200);
  assertEquals(card.responseType, "clarifyingQuestion");
  assertEquals(card.costDeducted, 0);
  assertEquals(harness.deductCalls, 0);
});

Deno.test("runCoachChat retries malformed cards before surfacing failure", async () => {
  let calls = 0;
  const harness = deps({
    callClaude: () => {
      calls++;
      return Promise.resolve(
        calls < 3 ? malformedClaudeCard() : validClaudeCard(),
      );
    },
  });
  const result = await runCoachChat(
    {
      userId: "u1",
      request: { ...request, userQuestion: "我該推進嗎？" },
      tier: "starter",
      accountIsTest: false,
      apiKey: "key",
    },
    harness.deps,
  );
  assertEquals(result.status, 200);
  assertEquals(calls, 3);
  assertEquals(harness.deductCalls, 1);
  assertEquals(harness.events.includes("coach_chat_retry_succeeded"), true);
});

Deno.test("runCoachChat falls back to a free clarification when all card attempts are malformed", async () => {
  let calls = 0;
  const harness = deps({
    callClaude: () => {
      calls++;
      return Promise.resolve(malformedClaudeCard());
    },
  });
  const result = await runCoachChat(
    {
      userId: "u1",
      request: { ...request, userQuestion: "我該推進嗎？" },
      tier: "starter",
      accountIsTest: false,
      apiKey: "key",
    },
    harness.deps,
  );
  assertEquals(result.status, 200);
  assertEquals(calls, 3);
  assertEquals(harness.deductCalls, 0);
  assertEquals(
    (result.body.card as Record<string, unknown>).responseType,
    "clarifyingQuestion",
  );
  assertEquals((result.body.card as Record<string, unknown>).costDeducted, 0);
  assertEquals(
    (result.body.card as Record<string, unknown>).reflectionQuestion,
    "你說推進，是想邀約、升溫，還是確認她意願？",
  );
  assertEquals(harness.events.includes("coach_chat_fallback_used"), true);
});

Deno.test("runCoachChat forceAnswer fallback returns no-charge conservative answer", async () => {
  const harness = deps({
    callClaude: () => Promise.resolve(malformedClaudeCard()),
  });
  const result = await runCoachChat(
    {
      userId: "u1",
      request: {
        ...request,
        userQuestion: "她最近很累，我要不要直接約？",
        forceAnswer: true,
        activeSessionTurns: [
          {
            role: "user",
            kind: "question",
            content: "她最近很累，我要不要直接約？",
          },
          {
            role: "coach",
            kind: "clarification",
            content: "你聽到她這句話後，心裡第一個反應是什麼？",
          },
          {
            role: "user",
            kind: "supplement",
            content: "我覺得她在暗示我太黏，但我還是想知道方向。",
          },
        ],
      },
      tier: "starter",
      accountIsTest: false,
      apiKey: "key",
    },
    harness.deps,
  );
  const card = result.body.card as Record<string, unknown>;
  assertEquals(result.status, 200);
  assertEquals(card.responseType, "coachAnswer");
  assertEquals(card.costDeducted, 0);
  assertEquals(card.needsReflection, false);
  assertEquals(harness.deductCalls, 0);
});

Deno.test("runCoachChat repeated clarification fallback rotates the reflection question", async () => {
  const harness = deps({
    callClaude: () => Promise.resolve(malformedClaudeCard()),
  });
  const result = await runCoachChat(
    {
      userId: "u1",
      request: {
        ...request,
        userQuestion: "她剛剛說最近很累，我是不是太急？",
        activeSessionTurns: [
          {
            role: "user",
            kind: "question",
            content: "她剛剛說最近很累，我是不是太急？",
          },
          {
            role: "coach",
            kind: "clarification",
            content: "你聽到她這句話後，心裡第一個反應是什麼？",
          },
        ],
      },
      tier: "starter",
      accountIsTest: false,
      apiKey: "key",
    },
    harness.deps,
  );
  const card = result.body.card as Record<string, unknown>;
  assertEquals(result.status, 200);
  assertEquals(card.responseType, "clarifyingQuestion");
  assertEquals(card.costDeducted, 0);
  assertEquals(
    card.reflectionQuestion,
    "先補一句你心裡其實想怎麼回，不用修飾。",
  );
  assertEquals(harness.deductCalls, 0);
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

Deno.test("runCoachChat falls back without deducting on repeated banned tokens", async () => {
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
  assertEquals(result.status, 200);
  assertEquals(
    (result.body.card as Record<string, unknown>).responseType,
    "clarifyingQuestion",
  );
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

Deno.test("runCoachChat returns quota error when formal answer cannot deduct", async () => {
  const harness = deps({
    deductCredit: () =>
      Promise.reject(
        new CoachChatQuotaExceededError("daily_limit_exceeded", 15, 15),
      ),
  });
  const result = await runCoachChat(
    {
      userId: "u1",
      request,
      tier: "free",
      accountIsTest: false,
      apiKey: "key",
    },
    harness.deps,
  );
  assertEquals(result.status, 429);
  assertEquals(result.body.error, "Daily limit exceeded");
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
