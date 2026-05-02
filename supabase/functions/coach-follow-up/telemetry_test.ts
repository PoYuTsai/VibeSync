// supabase/functions/coach-follow-up/telemetry_test.ts
//
// T8 — telemetry contract + privacy assertions.
//
// Verifies the three server events from design §7 fire with the right field
// shape AND that NO sensitive content leaks into logs:
//   - free-text answers (q1 / q2 / q3 user input)
//   - prompt content (system prompt verbatim, banned-token list)
//   - Claude raw response (card text fields, raw envelope)
//
// Pure-helper testability: same DI harness as generation_test.ts. We capture
// each {event, data} payload into an in-memory list and stringify all of it
// to grep for forbidden tokens — if any sensitive value lands ANYWHERE in
// the captured log payload, the assertion fails.

import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  runCoachFollowUp,
  type GenerationDeps,
  type GenerationInput,
} from "./generation.ts";

// ---------------------------------------------------------------------------
// Harness (mirror of generation_test.ts; duplicated rather than imported to
// keep the privacy contract test self-contained).
// ---------------------------------------------------------------------------

interface CapturedLog {
  level: "info" | "warn";
  event: string;
  data: Record<string, unknown>;
}

function makeHarness(claudeBehavior: () => Promise<unknown>) {
  const logs: CapturedLog[] = [];
  const deductCalls: Array<{ userId: string }> = [];

  const deps: GenerationDeps = {
    callClaude: async () => await claudeBehavior(),
    deductCredit: async ({ userId }) => {
      deductCalls.push({ userId });
    },
    logger: {
      info: (event, data = {}) => logs.push({ level: "info", event, data }),
      warn: (event, data = {}) => logs.push({ level: "warn", event, data }),
    },
    now: () => 1700000000000,
  };

  return { deps, logs, deductCalls };
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
// Event-shape assertions
// ---------------------------------------------------------------------------

Deno.test("T8 invoked: phase + tier + hasOptionalText only", async () => {
  const h = makeHarness(async () => claudeWrapped(VALID_CARD));
  await runCoachFollowUp(BASE_INPUT, h.deps);

  const invoked = h.logs.find((l) => l.event === "coach_follow_up_invoked");
  assertEquals(invoked?.level, "info");
  assertEquals(invoked?.data.phase, "postDateReflection");
  assertEquals(invoked?.data.tier, "starter");
  assertEquals(invoked?.data.hasOptionalText, false);
  // No extra fields beyond contract
  assertEquals(Object.keys(invoked!.data).sort(), [
    "hasOptionalText",
    "phase",
    "tier",
  ]);
});

Deno.test("T8 invoked: hasOptionalText=true when q3 has content", async () => {
  const h = makeHarness(async () => claudeWrapped(VALID_CARD));
  await runCoachFollowUp(
    { ...BASE_INPUT, answers: { q1: "卡卡的", q2: null, q3: "她最近回得慢" } },
    h.deps,
  );

  const invoked = h.logs.find((l) => l.event === "coach_follow_up_invoked");
  assertEquals(invoked?.data.hasOptionalText, true);
});

Deno.test("T8 invoked: hasOptionalText=false when q3 is empty string", async () => {
  const h = makeHarness(async () => claudeWrapped(VALID_CARD));
  await runCoachFollowUp(
    { ...BASE_INPUT, answers: { q1: "卡卡的", q2: null, q3: "" } },
    h.deps,
  );

  const invoked = h.logs.find((l) => l.event === "coach_follow_up_invoked");
  assertEquals(invoked?.data.hasOptionalText, false);
});

Deno.test("T8 succeeded: phase + tier + model + latencyMs + costDeducted only", async () => {
  const h = makeHarness(async () => claudeWrapped(VALID_CARD));
  await runCoachFollowUp(BASE_INPUT, h.deps);

  const succeeded = h.logs.find((l) => l.event === "coach_follow_up_succeeded");
  assertEquals(succeeded?.level, "info");
  assertEquals(succeeded?.data.phase, "postDateReflection");
  assertEquals(succeeded?.data.tier, "starter");
  assertEquals(succeeded?.data.model, "claude-sonnet-4-20250514");
  assertEquals(typeof succeeded?.data.latencyMs, "number");
  assertEquals(succeeded?.data.costDeducted, 1);
  assertEquals(Object.keys(succeeded!.data).sort(), [
    "costDeducted",
    "latencyMs",
    "model",
    "phase",
    "tier",
  ]);
});

Deno.test("T8 succeeded: costDeducted=0 for test account", async () => {
  const h = makeHarness(async () => claudeWrapped(VALID_CARD));
  await runCoachFollowUp({ ...BASE_INPUT, accountIsTest: true }, h.deps);

  const succeeded = h.logs.find((l) => l.event === "coach_follow_up_succeeded");
  assertEquals(succeeded?.data.costDeducted, 0);
});

Deno.test("T8 failed: schema_invalid carries phase + tier + errorClass only", async () => {
  const h = makeHarness(async () =>
    claudeWrapped({ ...VALID_CARD, boundaryReminder: null })
  );
  await runCoachFollowUp(BASE_INPUT, h.deps);

  const failed = h.logs.find((l) => l.event === "coach_follow_up_failed");
  assertEquals(failed?.level, "warn");
  assertEquals(failed?.data.phase, "postDateReflection");
  assertEquals(failed?.data.tier, "starter");
  assertEquals(failed?.data.errorClass, "schema_invalid");
  assertEquals(Object.keys(failed!.data).sort(), [
    "errorClass",
    "phase",
    "tier",
  ]);
});

Deno.test("T8 failed: banned_token errorClass", async () => {
  const h = makeHarness(async () =>
    claudeWrapped({
      ...VALID_CARD,
      boundaryReminder: "別用 PUA 話術",
    })
  );
  await runCoachFollowUp(BASE_INPUT, h.deps);

  const failed = h.logs.find((l) => l.event === "coach_follow_up_failed");
  assertEquals(failed?.data.errorClass, "banned_token");
});

Deno.test("T8 failed: claude_timeout errorClass when Claude throws timeout", async () => {
  const h = makeHarness(async () => {
    throw new Error("timeout: claude api after 60000ms");
  });
  await runCoachFollowUp(BASE_INPUT, h.deps);

  const failed = h.logs.find((l) => l.event === "coach_follow_up_failed");
  assertEquals(failed?.data.errorClass, "claude_timeout");
});

// ---------------------------------------------------------------------------
// Privacy assertions: NO free-text / NO prompt / NO Claude raw in any log
// ---------------------------------------------------------------------------

Deno.test("T8 privacy: free-text answers (q1/q2/q3) NEVER appear in any log", async () => {
  const SECRET_Q1 = "SECRET_TOKEN_Q1_xyz";
  const SECRET_Q2 = "SECRET_TOKEN_Q2_xyz";
  const SECRET_Q3 = "SECRET_TOKEN_Q3_xyz";

  const h = makeHarness(async () => claudeWrapped(VALID_CARD));
  await runCoachFollowUp(
    {
      ...BASE_INPUT,
      answers: { q1: SECRET_Q1, q2: SECRET_Q2, q3: SECRET_Q3 },
    },
    h.deps,
  );

  const allLogJson = JSON.stringify(h.logs);
  assertEquals(allLogJson.includes(SECRET_Q1), false, "q1 leaked");
  assertEquals(allLogJson.includes(SECRET_Q2), false, "q2 leaked");
  assertEquals(allLogJson.includes(SECRET_Q3), false, "q3 leaked");
});

Deno.test("T8 privacy: partnerHint.name NEVER appears in any log", async () => {
  const SECRET_NAME = "SECRET_PARTNER_NAME_xyz";
  const h = makeHarness(async () => claudeWrapped(VALID_CARD));
  await runCoachFollowUp(
    { ...BASE_INPUT, partnerHint: { name: SECRET_NAME } },
    h.deps,
  );

  const allLogJson = JSON.stringify(h.logs);
  assertEquals(allLogJson.includes(SECRET_NAME), false, "partner name leaked");
});

Deno.test("T8 privacy: prompt content (system rules + phase blocks) NEVER appears", async () => {
  // Tokens unique to prompts.ts SYSTEM_PROMPT_BASE / PHASE_INSTRUCTIONS
  const PROMPT_TOKENS = [
    "教練跟進",
    "硬規則",
    "輸出格式",
    "boundaryReminder 是 REQUIRED",
    "破冰",
  ];

  const h = makeHarness(async () => claudeWrapped(VALID_CARD));
  await runCoachFollowUp(BASE_INPUT, h.deps);
  await runCoachFollowUp({ ...BASE_INPUT, phase: "prepareInvite" }, h.deps);
  await runCoachFollowUp({ ...BASE_INPUT, phase: "preDateReminder" }, h.deps);

  const allLogJson = JSON.stringify(h.logs);
  for (const tok of PROMPT_TOKENS) {
    assertEquals(allLogJson.includes(tok), false, `prompt token leaked: ${tok}`);
  }
});

Deno.test("T8 privacy: Claude raw response card fields NEVER appear in success logs", async () => {
  const h = makeHarness(async () => claudeWrapped(VALID_CARD));
  await runCoachFollowUp(BASE_INPUT, h.deps);

  const allLogJson = JSON.stringify(h.logs);
  assertEquals(
    allLogJson.includes(VALID_CARD.headline),
    false,
    "headline leaked",
  );
  assertEquals(
    allLogJson.includes(VALID_CARD.observation),
    false,
    "observation leaked",
  );
  assertEquals(allLogJson.includes(VALID_CARD.task), false, "task leaked");
  assertEquals(
    allLogJson.includes(VALID_CARD.boundaryReminder),
    false,
    "boundaryReminder leaked",
  );
});

Deno.test("T8 privacy: Claude error message detail NEVER appears in failed log", async () => {
  const h = makeHarness(async () => {
    throw new Error("timeout: leaked-internal-detail-xyz");
  });
  await runCoachFollowUp(BASE_INPUT, h.deps);

  // Failed log should only have errorClass — the raw error message goes into
  // the response body (user-visible) but not into telemetry.
  const failedLog = h.logs.find((l) => l.event === "coach_follow_up_failed");
  const failedJson = JSON.stringify(failedLog);
  assertEquals(
    failedJson.includes("leaked-internal-detail-xyz"),
    false,
    "Claude error detail leaked into telemetry",
  );
});

Deno.test("T8 privacy: deduct failure uses stable bucket, NOT raw Supabase error", async () => {
  // Codex P1 follow-up: when index.ts's deductCredit closure throws because
  // Supabase update returned {error}, the underlying Supabase message MUST
  // NOT enter the failed log. errorClass must be the stable string
  // "credit_deduct_failed" so dashboards can alert on it without coupling to
  // Supabase's error format.
  const RAW_SUPABASE_LEAK = "supabase-raw-detail-row-not-found-xyz";
  const h = makeHarness(async () => claudeWrapped(VALID_CARD));
  h.deps.deductCredit = async () => {
    throw new Error(RAW_SUPABASE_LEAK);
  };
  await runCoachFollowUp(BASE_INPUT, h.deps);

  const allLogJson = JSON.stringify(h.logs);
  assertEquals(
    allLogJson.includes(RAW_SUPABASE_LEAK),
    false,
    "raw Supabase error message leaked into telemetry",
  );

  const failed = h.logs.find((l) => l.event === "coach_follow_up_failed");
  assertEquals(failed?.data.errorClass, "credit_deduct_failed");
  // Field shape: only stable trio
  assertEquals(Object.keys(failed!.data).sort(), [
    "errorClass",
    "phase",
    "tier",
  ]);
});

Deno.test("T8 privacy: schema-invalid path does NOT leak Claude raw card text", async () => {
  // When validation rejects a card, the bad card's text fields must not
  // appear in the failed log either.
  const BAD_CARD_TEXT = "raw-claude-bad-card-text-xyz";
  const h = makeHarness(async () =>
    claudeWrapped({
      headline: BAD_CARD_TEXT,
      observation: "obs",
      task: "task",
      boundaryReminder: null,
    })
  );
  await runCoachFollowUp(BASE_INPUT, h.deps);

  const allLogJson = JSON.stringify(h.logs);
  assertEquals(
    allLogJson.includes(BAD_CARD_TEXT),
    false,
    "raw bad-card text leaked into failed log",
  );
});
