import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  callClaudeAPI,
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
  settleResult?: (args: {
    body: Record<string, unknown>;
    charge: boolean;
  }) => Promise<{ charged: boolean; body: Record<string, unknown> }>;
  onProgress?: (update: {
    stage: string;
    attempt?: number;
    maxAttempts?: number;
  }) => void;
  onWarn?: (event: string, data: Record<string, unknown>) => void;
  now?: () => number;
}) {
  const events: string[] = [];
  let deductCalls = 0;
  const settleCalls: Array<{ charge: boolean; bodyKeys: string[] }> = [];
  return {
    events,
    settleCalls,
    get deductCalls() {
      return deductCalls;
    },
    deps: {
      callClaude: opts.callClaude ?? (() => Promise.resolve(validClaudeCard())),
      deductCredit: async () => {
        deductCalls++;
        if (opts.deductCredit) await opts.deductCredit();
      },
      // 未注入 settleResult＝舊路徑；有注入才掛（Task 5 注入縫）。
      ...(opts.settleResult
        ? {
          settleResult: (args: {
            body: Record<string, unknown>;
            charge: boolean;
          }) => {
            settleCalls.push({
              charge: args.charge,
              bodyKeys: Object.keys(args.body).sort(),
            });
            return opts.settleResult!(args);
          },
        }
        : {}),
      logger: {
        info: (event: string) => events.push(event),
        warn: (event: string, data: Record<string, unknown> = {}) => {
          events.push(event);
          opts.onWarn?.(event, data);
        },
      },
      onProgress: opts.onProgress,
      now: opts.now ?? (() => 1_700_000_000_000),
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

Deno.test("runCoachChat routes paid and Free to Sonnet 5", async () => {
  const models: string[] = [];

  for (const tier of ["starter", "free"] as const) {
    const harness = deps({
      callClaude: (args) => {
        models.push(args.model);
        return Promise.resolve(validClaudeCard());
      },
    });
    const result = await runCoachChat(
      {
        userId: `u-${tier}`,
        request,
        tier,
        accountIsTest: true,
        apiKey: "key",
      },
      harness.deps,
    );
    assertEquals(result.status, 200);
  }

  assertEquals(models, [
    "claude-sonnet-5",
    "claude-sonnet-5",
  ]);
});

Deno.test("runCoachChat reports truthful retry stages without model content", async () => {
  const progress: Array<{
    stage: string;
    attempt?: number;
    maxAttempts?: number;
  }> = [];
  let calls = 0;
  const harness = deps({
    callClaude: () => {
      calls++;
      return Promise.resolve(
        calls === 1 ? malformedClaudeCard() : validClaudeCard(),
      );
    },
    onProgress: (update) => progress.push(update),
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
  assertEquals(harness.deductCalls, 1);
  assertEquals(progress, [
    { stage: "request" },
    { stage: "generating", attempt: 1, maxAttempts: 3 },
    { stage: "validating", attempt: 1, maxAttempts: 3 },
    { stage: "retrying", attempt: 1, maxAttempts: 3 },
    { stage: "generating", attempt: 2, maxAttempts: 3 },
    { stage: "validating", attempt: 2, maxAttempts: 3 },
    { stage: "finalizing" },
  ]);
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

function insistentClarificationCard() {
  return validClaudeCard({
    responseType: "clarifyingQuestion",
    mode: "clarifyIntent",
    headline: "我先問清楚一點",
    answer: "我還需要再確認你的意思。",
    userTruth: null,
    userState: "你還在釐清。",
    nextStep: "再補一點想法。",
    suggestedLine: null,
    rewriteDecision: null,
    rewriteReason: null,
    boundaryReminder: "正式建議才扣額度。",
    needsReflection: true,
    reflectionQuestion: "你現在最怕的是什麼？",
    costDeducted: 0,
  });
}

const threeClarificationTurns = [
  { role: "coach", kind: "clarification", content: "q1" },
  { role: "coach", kind: "clarification", content: "q2" },
  { role: "coach", kind: "clarification", content: "q3" },
] as const;

Deno.test("runCoachChat regenerates a real paid answer when limit-hit clarification is rejected", async () => {
  const prompts: string[] = [];
  let calls = 0;
  const harness = deps({
    callClaude: (args) => {
      prompts.push(args.prompt);
      calls++;
      return Promise.resolve(
        calls === 1 ? insistentClarificationCard() : validClaudeCard(),
      );
    },
  });
  const result = await runCoachChat(
    {
      userId: "u1",
      request: {
        ...request,
        activeSessionTurns: [...threeClarificationTurns],
      },
      tier: "free",
      accountIsTest: false,
      apiKey: "key",
    },
    harness.deps,
  );
  const card = result.body.card as Record<string, unknown>;
  assertEquals(result.status, 200);
  assertEquals(card.responseType, "coachAnswer");
  // 扣 1 則 ⇔ AI 真正生成的回覆：重生成功的真卡才扣費
  assertEquals(card.costDeducted, 1);
  assertEquals(harness.deductCalls, 1);
  assertEquals(card.headline, "承認一半再反問");
  assertEquals(calls, 2);
  assertEquals(prompts[1].includes("禁止再輸出 clarifyingQuestion"), true);
});

Deno.test("runCoachChat falls back without deducting when model insists on clarification past limit", async () => {
  let calls = 0;
  const harness = deps({
    callClaude: () => {
      calls++;
      return Promise.resolve(insistentClarificationCard());
    },
  });
  const result = await runCoachChat(
    {
      userId: "u1",
      request: {
        ...request,
        activeSessionTurns: [...threeClarificationTurns],
      },
      tier: "free",
      accountIsTest: false,
      apiKey: "key",
    },
    harness.deps,
  );
  const card = result.body.card as Record<string, unknown>;
  assertEquals(result.status, 200);
  assertEquals(card.responseType, "coachAnswer");
  // 重生 3 次全失敗 → 保守 fallback 不是 AI 真生成，不得扣費
  assertEquals(card.costDeducted, 0);
  assertEquals(harness.deductCalls, 0);
  assertEquals(calls, 3);
  assertEquals(harness.events.includes("coach_chat_fallback_used"), true);
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

Deno.test("runCoachChat retries an unsourced suggestedLine time range", async () => {
  let calls = 0;
  const prompts: string[] = [];
  const harness = deps({
    callClaude: (args) => {
      calls++;
      prompts.push(args.prompt);
      return Promise.resolve(validClaudeCard({
        suggestedLine: calls === 1
          ? "這陣子真的辛苦妳了，週末好好休息。"
          : "這週真的辛苦妳了，週末好好休息。",
      }));
    },
  });
  const result = await runCoachChat(
    {
      userId: "u1",
      request: {
        ...request,
        forceAnswer: true,
        recentMessages: [{
          sender: "partner",
          text: "這週一直加班，週末只想睡覺。",
        }],
      },
      tier: "starter",
      accountIsTest: false,
      apiKey: "key",
    },
    harness.deps,
  );

  assertEquals(result.status, 200);
  assertEquals(calls, 2);
  assertEquals(harness.deductCalls, 1);
  assertEquals(
    (result.body.card as Record<string, unknown>).suggestedLine,
    "這週真的辛苦妳了，週末好好休息。",
  );
  assertEquals(
    prompts[1].includes("上一次 suggestedLine 擴寫了來源沒有的時間範圍"),
    true,
  );
});

Deno.test("runCoachChat accepts a suggestedLine time range present in source", async () => {
  let calls = 0;
  const harness = deps({
    callClaude: () => {
      calls++;
      return Promise.resolve(validClaudeCard({
        suggestedLine: "這陣子真的辛苦妳了，先好好休息。",
      }));
    },
  });
  const result = await runCoachChat(
    {
      userId: "u1",
      request: {
        ...request,
        forceAnswer: true,
        recentMessages: [{
          sender: "partner",
          text: "這陣子一直加班，真的有點累。",
        }],
      },
      tier: "starter",
      accountIsTest: false,
      apiKey: "key",
    },
    harness.deps,
  );

  assertEquals(result.status, 200);
  assertEquals(calls, 1);
  assertEquals(harness.deductCalls, 1);
});

Deno.test("runCoachChat retries an unsourced negative motive label", async () => {
  let calls = 0;
  const prompts: string[] = [];
  const harness = deps({
    callClaude: (args) => {
      calls++;
      prompts.push(args.prompt);
      return Promise.resolve(validClaudeCard({
        suggestedLine: calls === 1
          ? "哈哈你這人真的很會裝欸。"
          : "哈哈是喔，那就好。",
      }));
    },
  });
  const result = await runCoachChat(
    {
      userId: "u1",
      request: {
        ...request,
        forceAnswer: true,
        recentMessages: [{ sender: "partner", text: "還好啦哈哈" }],
      },
      tier: "starter",
      accountIsTest: false,
      apiKey: "key",
    },
    harness.deps,
  );

  assertEquals(result.status, 200);
  assertEquals(calls, 2);
  assertEquals(harness.deductCalls, 1);
  assertEquals(
    (result.body.card as Record<string, unknown>).suggestedLine,
    "哈哈是喔，那就好。",
  );
  assertEquals(prompts[1].includes("來源沒有的負面動機標籤"), true);
});

Deno.test("runCoachChat honors an explicit no-question request", async () => {
  let calls = 0;
  const prompts: string[] = [];
  const harness = deps({
    callClaude: (args) => {
      calls++;
      prompts.push(args.prompt);
      return Promise.resolve(validClaudeCard({
        suggestedLine: calls === 1 ? "哈哈還好是多好？" : "哈哈是喔，那就好。",
      }));
    },
  });
  const result = await runCoachChat(
    {
      userId: "u1",
      request: {
        ...request,
        userQuestion: "直接給一句，輕一點，不要逼她解釋或安撫我。",
        forceAnswer: true,
        recentMessages: [{ sender: "partner", text: "還好啦哈哈" }],
      },
      tier: "starter",
      accountIsTest: false,
      apiKey: "key",
    },
    harness.deps,
  );

  assertEquals(result.status, 200);
  assertEquals(calls, 2);
  assertEquals(harness.deductCalls, 1);
  assertEquals(
    (result.body.card as Record<string, unknown>).suggestedLine,
    "哈哈是喔，那就好。",
  );
  assertEquals(prompts[1].includes("不要追問／不要逼對方解釋"), true);
});

Deno.test("runCoachChat does not deduct when grounding fails every attempt", async () => {
  let calls = 0;
  const harness = deps({
    callClaude: () => {
      calls++;
      return Promise.resolve(validClaudeCard({
        suggestedLine: "這陣子妳真的很會裝欸？",
      }));
    },
  });
  const result = await runCoachChat(
    {
      userId: "u1",
      request: {
        ...request,
        userQuestion: "直接給一句，不要逼她解釋。",
        forceAnswer: true,
        recentMessages: [{ sender: "partner", text: "還好啦哈哈" }],
      },
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
    (result.body.card as Record<string, unknown>).costDeducted,
    0,
  );
  assertEquals(harness.events.includes("coach_chat_fallback_used"), true);
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

Deno.test("runCoachChat shares one 75 second generation budget across retries", async () => {
  let nowMs = 1_700_000_000_000;
  const timeouts: number[] = [];
  const harness = deps({
    now: () => nowMs,
    callClaude: (args) => {
      timeouts.push(args.timeoutMs);
      nowMs += args.timeoutMs;
      return Promise.resolve(malformedClaudeCard());
    },
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
  assertEquals(timeouts, [60_000, 15_000]);
  assertEquals(harness.deductCalls, 0);
  assertEquals(
    (result.body.card as Record<string, unknown>).costDeducted,
    0,
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

Deno.test("runCoachChat does not treat resolved clarifications as no-charge answer fallback", async () => {
  const harness = deps({
    callClaude: () => Promise.resolve(malformedClaudeCard()),
  });
  const result = await runCoachChat(
    {
      userId: "u1",
      request: {
        ...request,
        userQuestion: "那我下一句要不要幽默一點？",
        forceAnswer: false,
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
            role: "coach",
            kind: "answer",
            content: "先降壓，用一句短訊息接住她的累，再留一個小球。",
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
  assertEquals(harness.deductCalls, 0);
});

Deno.test("runCoachChat clarification follow-up fallback remains a no-charge conservative answer", async () => {
  const harness = deps({
    callClaude: () => Promise.resolve(malformedClaudeCard()),
  });
  const result = await runCoachChat(
    {
      userId: "u1",
      request: {
        ...request,
        userQuestion: "我補充一下，我其實怕太急但又想推進。",
        forceAnswer: false,
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
  assertEquals(harness.deductCalls, 0);
});

Deno.test("runCoachChat clarification continuation fallback does not ask again", async () => {
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
  assertEquals(card.responseType, "coachAnswer");
  assertEquals(card.costDeducted, 0);
  assertEquals(card.needsReflection, false);
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

Deno.test("runCoachChat repairs forced empty-answer card into no-charge conservative answer", async () => {
  // D2 Codex P3 顯式覆蓋：釐清上限已到（forced coachAnswer）且模型吐出
  // answer 為空的 coachAnswer——repair 直接落保守 no-charge 答案，不再釐清、
  // 不重試、絕不扣費（扣 1 則 ⇔ AI 真生成）。
  let calls = 0;
  const harness = deps({
    callClaude: () => {
      calls++;
      return Promise.resolve(partialClaudeAnswer({ answer: "" }));
    },
  });
  const result = await runCoachChat(
    {
      userId: "u1",
      request: {
        ...request,
        activeSessionTurns: [...threeClarificationTurns],
      },
      tier: "free",
      accountIsTest: false,
      apiKey: "key",
    },
    harness.deps,
  );
  const card = result.body.card as Record<string, unknown>;
  assertEquals(result.status, 200);
  assertEquals(card.responseType, "coachAnswer");
  assertEquals(card.costDeducted, 0);
  assertEquals(harness.deductCalls, 0);
  assertEquals(calls, 1);
});

Deno.test("runCoachChat reads JSON from a visible text block after Sonnet 5 thinking", async () => {
  let calls = 0;
  const harness = deps({
    callClaude: () => {
      calls++;
      const visible = validClaudeCard() as {
        content: Array<{ text: string }>;
      };
      return Promise.resolve({
        stop_reason: "end_turn",
        content: [
          { type: "thinking", thinking: "hidden reasoning" },
          { type: "text", text: visible.content[0].text },
        ],
      });
    },
  });

  const result = await runCoachChat(
    {
      userId: "u1",
      request,
      tier: "essential",
      accountIsTest: false,
      apiKey: "key",
    },
    harness.deps,
  );

  assertEquals(result.status, 200);
  assertEquals(calls, 1);
  assertEquals(harness.deductCalls, 1);
  assertEquals(
    (result.body.card as Record<string, unknown>).responseType,
    "coachAnswer",
  );
});

Deno.test("runCoachChat accepts a complete valid card even when stop_reason=max_tokens", async () => {
  let calls = 0;
  const harness = deps({
    callClaude: () => {
      calls++;
      return Promise.resolve({
        ...validClaudeCard(),
        stop_reason: "max_tokens",
      });
    },
  });

  const result = await runCoachChat(
    {
      userId: "u1",
      request,
      tier: "essential",
      accountIsTest: false,
      apiKey: "key",
    },
    harness.deps,
  );

  assertEquals(result.status, 200);
  assertEquals(calls, 1);
  assertEquals(harness.deductCalls, 1);
  assertEquals(
    (result.body.card as Record<string, unknown>).costDeducted,
    1,
  );
});

Deno.test("runCoachChat rejects a truncated max_tokens response without deducting", async () => {
  let calls = 0;
  const harness = deps({
    callClaude: () => {
      calls++;
      return Promise.resolve({
        stop_reason: "max_tokens",
        content: [{ type: "text", text: '{"responseType":"coachAnswer"' }],
      });
    },
  });

  const result = await runCoachChat(
    {
      userId: "u1",
      request,
      tier: "essential",
      accountIsTest: false,
      apiKey: "key",
    },
    harness.deps,
  );

  assertEquals(result.status, 200);
  assertEquals(calls, 3);
  assertEquals(harness.deductCalls, 0);
  assertEquals(
    (result.body.card as Record<string, unknown>).costDeducted,
    0,
  );
});

Deno.test("runCoachChat rejects a schema-shaped refusal without returning a card or deducting", async () => {
  const warnings: Array<{
    event: string;
    data: Record<string, unknown>;
  }> = [];
  let calls = 0;
  const harness = deps({
    callClaude: () => {
      calls++;
      return Promise.resolve({
        ...validClaudeCard(),
        stop_reason: "refusal",
      });
    },
    onWarn: (event, data) => warnings.push({ event, data }),
  });

  const result = await runCoachChat(
    {
      userId: "u1",
      request,
      tier: "essential",
      accountIsTest: false,
      apiKey: "key",
    },
    harness.deps,
  );

  assertEquals(result.status, 500);
  assertEquals(result.body.error, "refusal");
  assertEquals("card" in result.body, false);
  assertEquals(calls, 1);
  assertEquals(harness.deductCalls, 0);
  const invalid = warnings.find((log) =>
    log.event === "coach_chat_card_invalid"
  );
  assertEquals(invalid?.data.errorClass, "refusal");
  const failed = warnings.find((log) => log.event === "coach_chat_failed");
  assertEquals(failed?.data.errorClass, "refusal");
});

Deno.test("runCoachChat rejects a context-window partial response without deducting", async () => {
  let calls = 0;
  const harness = deps({
    callClaude: () => {
      calls++;
      return Promise.resolve({
        ...validClaudeCard(),
        stop_reason: "model_context_window_exceeded",
      });
    },
  });

  const result = await runCoachChat(
    {
      userId: "u1",
      request,
      tier: "essential",
      accountIsTest: false,
      apiKey: "key",
    },
    harness.deps,
  );

  assertEquals(result.status, 500);
  assertEquals(result.body.error, "model_context_window_exceeded");
  assertEquals(calls, 1);
  assertEquals(harness.deductCalls, 0);
});

Deno.test("coach callClaudeAPI disables thinking only for Sonnet 5", async () => {
  const originalFetch = globalThis.fetch;
  const bodies: Array<Record<string, unknown>> = [];
  globalThis.fetch = ((_input: Request | URL | string, init?: RequestInit) => {
    bodies.push(JSON.parse(String(init?.body)) as Record<string, unknown>);
    return Promise.resolve(
      new Response(JSON.stringify({ content: [] }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );
  }) as typeof fetch;

  try {
    await callClaudeAPI({
      model: "claude-sonnet-5",
      prompt: "test",
      maxTokens: 1200,
      timeoutMs: 1000,
      apiKey: "key",
    });
    await callClaudeAPI({
      model: "claude-haiku-4-5-20251001",
      prompt: "test",
      maxTokens: 1200,
      timeoutMs: 1000,
      apiKey: "key",
    });
  } finally {
    globalThis.fetch = originalFetch;
  }

  assertEquals(bodies[0].thinking, { type: "disabled" });
  assertEquals("thinking" in bodies[1], false);
});

// ---- Phase C：settleResult 結算縫（未注入＝舊路徑） ----

const settleInput = {
  userId: "u1",
  request,
  tier: "starter" as const,
  accountIsTest: false,
  apiKey: "key",
};

Deno.test("runCoachChat settles instead of deducting when settleResult injected", async () => {
  const harness = deps({
    settleResult: (args) => Promise.resolve({ charged: true, body: args.body }),
  });
  const result = await runCoachChat(settleInput, harness.deps);
  assertEquals(result.status, 200);
  assertEquals(harness.settleCalls.length, 1);
  assertEquals(harness.settleCalls[0].charge, true);
  assertEquals(harness.settleCalls[0].bodyKeys, [
    "card",
    "generatedAt",
    "model",
    "provider",
    "sessionId",
  ]);
  assertEquals(harness.deductCalls, 0);
  assertEquals((result.body.card as Record<string, unknown>).costDeducted, 1);
});

Deno.test("runCoachChat returns ledger-authoritative body on settle replay", async () => {
  // F1：stale lease takeover 後晚到的 settle 拿到先入帳者的卡——
  // 回應必須逐 byte 等於 ledger result，本地生成丟棄。
  const ledgerBody = {
    card: {
      responseType: "coachAnswer",
      costDeducted: 1,
      headline: "先入帳者的卡",
    },
    sessionId: null,
    provider: "claude",
    model: "claude-sonnet-5",
    generatedAt: "2026-07-21T10:00:00.000Z",
  };
  const harness = deps({
    settleResult: () => Promise.resolve({ charged: false, body: ledgerBody }),
  });
  const result = await runCoachChat(settleInput, harness.deps);
  assertEquals(result.status, 200);
  assertEquals(harness.deductCalls, 0);
  assertEquals(result.body, ledgerBody);
});

Deno.test("runCoachChat settles clarifyingQuestion with charge=false", async () => {
  const harness = deps({
    callClaude: () =>
      Promise.resolve(validClaudeCard({
        responseType: "clarifyingQuestion",
        needsReflection: true,
        reflectionQuestion: "你想要的是安心感，還是想確認她的興趣？",
        rewriteDecision: null,
      })),
    settleResult: (args) =>
      Promise.resolve({ charged: false, body: args.body }),
  });
  const result = await runCoachChat(settleInput, harness.deps);
  assertEquals(result.status, 200);
  assertEquals(harness.settleCalls.length, 1);
  assertEquals(harness.settleCalls[0].charge, false);
  assertEquals(harness.deductCalls, 0);
  assertEquals((result.body.card as Record<string, unknown>).costDeducted, 0);
});

Deno.test("runCoachChat settles test account with charge=false", async () => {
  const harness = deps({
    settleResult: (args) =>
      Promise.resolve({ charged: false, body: args.body }),
  });
  const result = await runCoachChat(
    { ...settleInput, accountIsTest: true },
    harness.deps,
  );
  assertEquals(result.status, 200);
  assertEquals(harness.settleCalls.length, 1);
  assertEquals(harness.settleCalls[0].charge, false);
  assertEquals(harness.deductCalls, 0);
});

Deno.test("runCoachChat settles no-charge fallback card with charge=false", async () => {
  const harness = deps({
    callClaude: () => Promise.resolve(malformedClaudeCard()),
    settleResult: (args) =>
      Promise.resolve({ charged: false, body: args.body }),
  });
  const result = await runCoachChat(settleInput, harness.deps);
  assertEquals(result.status, 200);
  assertEquals(harness.settleCalls.length, 1);
  assertEquals(harness.settleCalls[0].charge, false);
  assertEquals(harness.deductCalls, 0);
  assertEquals((result.body.card as Record<string, unknown>).costDeducted, 0);
});

Deno.test("runCoachChat never settles nor deducts when Claude call fails", async () => {
  const harness = deps({
    callClaude: () => Promise.reject(new Error("upstream down")),
    settleResult: (args) => Promise.resolve({ charged: true, body: args.body }),
  });
  const result = await runCoachChat(settleInput, harness.deps);
  assertEquals(result.status, 500);
  assertEquals(harness.settleCalls.length, 0);
  assertEquals(harness.deductCalls, 0);
});

Deno.test("runCoachChat maps settle quota error to deduct-time 429 shape", async () => {
  const harness = deps({
    settleResult: () =>
      Promise.reject(
        new CoachChatQuotaExceededError("monthly_limit_exceeded", 200, 200),
      ),
  });
  const result = await runCoachChat(settleInput, harness.deps);
  assertEquals(result.status, 429);
  assertEquals(result.body, {
    error: "Monthly limit exceeded",
    message: "本月額度已用完，升級方案可取得更多分析與教練額度。",
    quotaNeeded: 1,
    used: 200,
    limit: 200,
  });
  assertEquals(harness.deductCalls, 0);
});

Deno.test("runCoachChat keeps legacy deduct path when settleResult absent", async () => {
  const harness = deps({});
  const result = await runCoachChat(settleInput, harness.deps);
  assertEquals(result.status, 200);
  assertEquals(harness.settleCalls.length, 0);
  assertEquals(harness.deductCalls, 1);
  assertEquals((result.body.card as Record<string, unknown>).costDeducted, 1);
});
