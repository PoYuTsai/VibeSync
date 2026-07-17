// supabase/functions/coach-follow-up/generation_test.ts
//
// T7 — full generation pipeline edge-case matrix.
// Pure helper pattern (T5/T6 precedent, Codex-ACK'd): runCoachFollowUp takes
// pre-validated context (gate already passed in index.ts) and DI'd
// {callClaude, deductCredit, logger}. No Supabase mock surface here — the
// orchestrator does the row update.
//
// Critical invariant under test:
//   parseClaudeJSON → truncateCard → validateResponseCard → assertCardSafe →
//   deduct → respond
// If ANY step before deduct throws, deductCredit MUST NOT fire.

import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  type ClaudeCallArgs,
  CoachFollowUpQuotaExceededError,
  type GenerationDeps,
  type GenerationInput,
  runCoachFollowUp,
} from "./generation.ts";

// ---------------------------------------------------------------------------
// Test harness
// ---------------------------------------------------------------------------

interface CapturedLog {
  level: "info" | "warn";
  event: string;
  data: Record<string, unknown>;
}

interface Harness {
  deps: GenerationDeps;
  logs: CapturedLog[];
  deductCalls: Array<{ userId: string }>;
  claudeCalls: ClaudeCallArgs[];
}

function makeHarness(claudeBehavior: () => Promise<unknown>): Harness {
  const logs: CapturedLog[] = [];
  const deductCalls: Array<{ userId: string }> = [];
  const claudeCalls: ClaudeCallArgs[] = [];

  const deps: GenerationDeps = {
    callClaude: async (args) => {
      claudeCalls.push(args);
      return await claudeBehavior();
    },
    deductCredit: async ({ userId }) => {
      deductCalls.push({ userId });
    },
    logger: {
      info: (event, data = {}) => logs.push({ level: "info", event, data }),
      warn: (event, data = {}) => logs.push({ level: "warn", event, data }),
    },
    now: () => 1700000000000, // deterministic
  };

  return { deps, logs, deductCalls, claudeCalls };
}

function claudeWrapped(card: Record<string, unknown>): unknown {
  return { content: [{ text: JSON.stringify(card) }] };
}

const VALID_CARD = {
  headline: "今晚先別發訊息",
  observation: "她回得慢一定是你太急——其實是你在想結果",
  task: "今晚不傳訊息，去吃個飯",
  suggestedLine: null,
  boundaryReminder: "她的節奏跟你的不安是兩件事",
};

const BASE_INPUT: GenerationInput = {
  userId: "user-abc-123",
  phase: "postDateReflection",
  answers: { q1: "卡卡的", q2: null, q3: null },
  partnerHint: { name: "Mia" },
  tier: "starter",
  accountIsTest: false,
  apiKey: "sk-test-key",
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

Deno.test("T7: successful generation deducts 1 credit and returns 200", async () => {
  const h = makeHarness(async () => claudeWrapped(VALID_CARD));
  const result = await runCoachFollowUp(BASE_INPUT, h.deps);

  assertEquals(result.status, 200);
  assertEquals(h.deductCalls.length, 1);
  assertEquals(h.deductCalls[0].userId, "user-abc-123");
  assertEquals(
    (result.body as Record<string, unknown>).phase,
    "postDateReflection",
  );
});

Deno.test("T7: styleContext is passed into the Claude prompt", async () => {
  const h = makeHarness(async () => claudeWrapped(VALID_CARD));
  const result = await runCoachFollowUp(
    {
      ...BASE_INPUT,
      styleContext: "- Preferred voice: 幽默；回覆要輕鬆、有留白",
    },
    h.deps,
  );

  assertEquals(result.status, 200);
  assertStringIncludes(
    h.claudeCalls[0].prompt,
    "User voice & coaching preferences",
  );
  assertStringIncludes(h.claudeCalls[0].prompt, "Preferred voice: 幽默");
});

Deno.test("T7: tier=starter selects Sonnet 5 in response", async () => {
  const h = makeHarness(async () => claudeWrapped(VALID_CARD));
  const result = await runCoachFollowUp(BASE_INPUT, h.deps);

  assertEquals(
    (result.body as Record<string, unknown>).model,
    "claude-sonnet-5",
  );
});

Deno.test("T7: tier=free selects haiku model", async () => {
  const h = makeHarness(async () => claudeWrapped(VALID_CARD));
  const result = await runCoachFollowUp(
    { ...BASE_INPUT, tier: "free" },
    h.deps,
  );

  assertEquals(
    (result.body as Record<string, unknown>).model,
    "claude-haiku-4-5-20251001",
  );
});

Deno.test("T7: null boundaryReminder → 5xx, credit NOT deducted", async () => {
  const h = makeHarness(async () =>
    claudeWrapped({ ...VALID_CARD, boundaryReminder: null })
  );
  const result = await runCoachFollowUp(BASE_INPUT, h.deps);

  assertEquals(result.status, 500);
  assertEquals(
    (result.body as Record<string, unknown>).error,
    "schema_invalid",
  );
  assertEquals(h.deductCalls.length, 0);
});

Deno.test("T7: missing boundaryReminder → 5xx, credit NOT deducted", async () => {
  const h = makeHarness(async () => {
    const { boundaryReminder: _, ...rest } = VALID_CARD;
    return claudeWrapped(rest);
  });
  const result = await runCoachFollowUp(BASE_INPUT, h.deps);

  assertEquals(result.status, 500);
  assertEquals(
    (result.body as Record<string, unknown>).error,
    "schema_invalid",
  );
  assertEquals(h.deductCalls.length, 0);
});

Deno.test("T7: banned token 'PUA' → 5xx errorClass=banned_token, credit NOT deducted", async () => {
  const h = makeHarness(async () =>
    claudeWrapped({
      ...VALID_CARD,
      boundaryReminder: "別用 PUA 話術——對方有自己節奏",
    })
  );
  const result = await runCoachFollowUp(BASE_INPUT, h.deps);

  assertEquals(result.status, 500);
  assertEquals((result.body as Record<string, unknown>).error, "banned_token");
  assertEquals(h.deductCalls.length, 0);

  const failed = h.logs.find((l) => l.event === "coach_follow_up_failed");
  assertEquals(failed?.data.errorClass, "banned_token");
});

Deno.test("T7: banned token '收割' in task → 5xx, credit NOT deducted", async () => {
  const h = makeHarness(async () =>
    claudeWrapped({ ...VALID_CARD, task: "練習收割節奏" })
  );
  const result = await runCoachFollowUp(BASE_INPUT, h.deps);

  assertEquals(result.status, 500);
  assertEquals((result.body as Record<string, unknown>).error, "banned_token");
  assertEquals(h.deductCalls.length, 0);
});

Deno.test("T7: Claude API timeout → 5xx, credit NOT deducted", async () => {
  const h = makeHarness(async () => {
    throw new Error("timeout: claude api after 60000ms");
  });
  const result = await runCoachFollowUp(BASE_INPUT, h.deps);

  assertEquals(result.status, 500);
  // 上游錯誤細節絕不外洩到 response：通用碼 only，細節進 telemetry。
  assertEquals(
    (result.body as Record<string, unknown>).error,
    "generation_failed",
  );
  assertEquals(h.deductCalls.length, 0);

  const failed = h.logs.find((l) => l.event === "coach_follow_up_failed");
  assertEquals(failed?.data.errorClass, "claude_timeout");
  // privacy C6：failed log 也不得帶上游原文，分類即全部細節。
  assertEquals("error" in (failed?.data ?? {}), false);
});

Deno.test("T7: over-cap headline (50 chars) → truncated to 30, credit deducted", async () => {
  const longHeadline = "今晚先別發訊息因為你還在想結果而不是想她".padEnd(
    50,
    "X",
  );
  const h = makeHarness(async () =>
    claudeWrapped({ ...VALID_CARD, headline: longHeadline })
  );
  const result = await runCoachFollowUp(BASE_INPUT, h.deps);

  assertEquals(result.status, 200);
  const body = result.body as Record<string, unknown>;
  const card = body.card as Record<string, string>;
  assertEquals(card.headline.length, 30);
  assertEquals(h.deductCalls.length, 1);
});

Deno.test("T7: test account success → 200 but credit NOT deducted (cap bypass)", async () => {
  const h = makeHarness(async () => claudeWrapped(VALID_CARD));
  const result = await runCoachFollowUp(
    { ...BASE_INPUT, accountIsTest: true },
    h.deps,
  );

  assertEquals(result.status, 200);
  assertEquals(h.deductCalls.length, 0);

  const succeeded = h.logs.find((l) => l.event === "coach_follow_up_succeeded");
  assertEquals(succeeded?.data.costDeducted, 0);
});

Deno.test("T7: deductCredit failure → 5xx credit_deduct_failed, NO succeeded log", async () => {
  // Codex P1: Supabase update returning {error} doesn't throw — index.ts
  // wrapper now checks {error} and throws "credit_deduct_failed". generation.ts
  // catches and emits stable bucket. Without this, a deduct miss would silently
  // give the user a free card.
  const h = makeHarness(async () => claudeWrapped(VALID_CARD));
  h.deps.deductCredit = async () => {
    throw new Error("credit_deduct_failed");
  };
  const result = await runCoachFollowUp(BASE_INPUT, h.deps);

  assertEquals(result.status, 500);
  assertEquals(
    (result.body as Record<string, unknown>).error,
    "credit_deduct_failed",
  );

  // No succeeded event — generation never reached the success log
  const succeeded = h.logs.find((l) => l.event === "coach_follow_up_succeeded");
  assertEquals(succeeded, undefined);

  // Failed event with stable bucket (NOT raw error message)
  const failed = h.logs.find((l) => l.event === "coach_follow_up_failed");
  assertEquals(failed?.data.errorClass, "credit_deduct_failed");
});

Deno.test("T7: test account skips deductCredit even when it would fail", async () => {
  // Sanity: test-account bypass MUST short-circuit before deductCredit is
  // called, so a broken deduct path can't accidentally lock out test accounts.
  let deductCalled = false;
  const h = makeHarness(async () => claudeWrapped(VALID_CARD));
  h.deps.deductCredit = async () => {
    deductCalled = true;
    throw new Error("credit_deduct_failed");
  };
  const result = await runCoachFollowUp(
    { ...BASE_INPUT, accountIsTest: true },
    h.deps,
  );

  assertEquals(result.status, 200);
  assertEquals(deductCalled, false);
});

Deno.test("T7: deduct order — validate + safety pass BEFORE deductCredit fires", async () => {
  // Sequence guard: if deductCredit threw, success log path would still fire.
  // We assert the order by checking deductCredit is invoked BEFORE the
  // succeeded telemetry event lands in the log capture.
  const events: string[] = [];
  const h = makeHarness(async () => claudeWrapped(VALID_CARD));
  h.deps.deductCredit = async () => {
    events.push("deduct");
  };
  h.deps.logger = {
    info: (event) => events.push(`info:${event}`),
    warn: (event) => events.push(`warn:${event}`),
  };
  await runCoachFollowUp(BASE_INPUT, h.deps);

  // Order: invoked → deduct → succeeded
  assertEquals(events, [
    "info:coach_follow_up_invoked",
    "deduct",
    "info:coach_follow_up_succeeded",
  ]);
});

Deno.test("T7: deductCredit quota error → 429 with quota payload, NO succeeded log", async () => {
  // Batch C#2：deductCredit 重查發現額度已被並發請求吃掉（或 increment_usage
  // 鎖內 RAISE）→ 必須回 429 quota 語義，不是 500 credit_deduct_failed。
  const h = makeHarness(async () => claudeWrapped(VALID_CARD));
  h.deps.deductCredit = () =>
    Promise.reject(
      new CoachFollowUpQuotaExceededError("daily_limit_exceeded", 50, 50),
    );

  const result = await runCoachFollowUp(BASE_INPUT, h.deps);

  assertEquals(result.status, 429);
  assertEquals(result.body.error, "Daily limit exceeded");
  assertEquals(result.body.quotaNeeded, 1);
  assertEquals(result.body.used, 50);
  assertEquals(result.body.limit, 50);
  assertEquals(typeof result.body.message, "string");

  const failed = h.logs.filter((l) => l.event === "coach_follow_up_failed");
  assertEquals(failed.length, 1);
  assertEquals(failed[0].data.errorClass, "daily_limit_exceeded");
  assertEquals(
    h.logs.some((l) => l.event === "coach_follow_up_succeeded"),
    false,
  );
});

Deno.test("T7: deductCredit monthly quota error → 429 monthly wording", async () => {
  const h = makeHarness(async () => claudeWrapped(VALID_CARD));
  h.deps.deductCredit = () =>
    Promise.reject(
      new CoachFollowUpQuotaExceededError("monthly_limit_exceeded", 300, 300),
    );

  const result = await runCoachFollowUp(BASE_INPUT, h.deps);

  assertEquals(result.status, 429);
  assertEquals(result.body.error, "Monthly limit exceeded");
});
