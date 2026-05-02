// supabase/functions/coach-follow-up/privacy_test.ts
//
// THE consolidated Spec 5 privacy contract spec (Phase B T16, narrow scope).
//
// Spec 5 makes six privacy promises. This file owns one focused test per
// promise so "what is Spec 5 not allowed to leak?" has a single pointer.
// Some assertions intentionally overlap with telemetry_test.ts — those tests
// own the broader telemetry-shape contract; this file owns the privacy
// contract. Both are correct sources of truth; the redundancy is defensive.
//
// SIX CONTRACTS
//
//   C1 — Supabase write surface
//        The only Supabase write the success path makes is the credit
//        deduction (counters update). Its DI signature is
//        `deductCredit({userId}) => Promise<void>`. q1 / q2 / q3 free-text,
//        partnerHint.name, and Claude card content are STRUCTURALLY
//        unreachable from inside that closure — even a buggy refactor can't
//        leak them without changing the type, which the test catches.
//
//   C2 — partnerHint.name handling
//        Sent to Claude as wire context. NEVER logged. NEVER persisted to
//        Supabase. (Local persistence: see C5.)
//
//   C3 — Prompt content
//        System rules, banned-token list, and phase-instruction blocks are
//        sent to Claude but NEVER logged.
//
//   C4 — Claude raw response
//        Card text fields (headline / observation / task / boundaryReminder
//        / suggestedLine) are returned to the client and persisted locally,
//        but NEVER logged. Includes the schema-invalid path: even bad-card
//        text from a rejected response must not enter the failed log.
//
//   C5 — Local persistence (Flutter-side, NOT testable from Deno)
//        Locked at the Hive box type signature `Box<CoachFollowUpResult>`
//        in lib/core/services/storage_service.dart (B14). The box only
//        accepts the validated result entity — q1/q2/q3 raw text,
//        partnerHint.name, and Claude raw response cannot be persisted
//        because they are not fields of the entity. Round-trip coverage in
//        test/unit/features/coach_follow_up/data/repositories/
//        coach_follow_up_repository_impl_test.dart (B13).
//
//   C6 — Telemetry whitelist
//        invoked   → { phase, tier, hasOptionalText }
//        succeeded → { phase, tier, model, latencyMs, costDeducted }
//        failed    → { phase, tier, errorClass }
//        No other fields. errorClass is always a stable bucket name, never
//        raw Claude / Supabase / network error text.

import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  type GenerationDeps,
  type GenerationInput,
  runCoachFollowUp,
} from "./generation.ts";

// ---------------------------------------------------------------------------
// Self-contained harness — same pattern as telemetry_test.ts. Duplicated
// (not imported) so each privacy assertion is hermetic and can't be silently
// broken by a refactor of telemetry_test's harness.
// ---------------------------------------------------------------------------

interface CapturedLog {
  level: "info" | "warn";
  event: string;
  data: Record<string, unknown>;
}

interface DeductCall {
  payload: Record<string, unknown>;
}

function makeHarness(claudeBehavior: () => Promise<unknown>) {
  const logs: CapturedLog[] = [];
  const deductCalls: DeductCall[] = [];
  const deps: GenerationDeps = {
    callClaude: async () => await claudeBehavior(),
    deductCredit: async (input) => {
      // Capture verbatim payload — proves shape AND content.
      deductCalls.push({ payload: { ...input } });
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
// C1 — Supabase write surface
// ---------------------------------------------------------------------------

Deno.test(
  "Spec 5 privacy C1: deductCredit payload is exactly {userId} — q1/q2/q3/partnerHint.name/card never reach Supabase",
  async () => {
    const SECRET_Q1 = "C1_SECRET_Q1_xyz";
    const SECRET_Q2 = "C1_SECRET_Q2_xyz";
    const SECRET_Q3 = "C1_SECRET_Q3_xyz";
    const SECRET_NAME = "C1_SECRET_PARTNER_NAME_xyz";

    const h = makeHarness(async () => claudeWrapped(VALID_CARD));
    await runCoachFollowUp(
      {
        ...BASE_INPUT,
        answers: { q1: SECRET_Q1, q2: SECRET_Q2, q3: SECRET_Q3 },
        partnerHint: { name: SECRET_NAME },
      },
      h.deps,
    );

    // Shape lock: the only Supabase-bound payload key is userId.
    assertEquals(h.deductCalls.length, 1, "exactly one deduction in success path");
    assertEquals(
      Object.keys(h.deductCalls[0].payload).sort(),
      ["userId"],
      "deductCredit payload shape locked",
    );

    // Defensive grep: even if someone added a field named harmlessly that
    // happened to carry user content, the sentinels would surface here.
    const captured = JSON.stringify(h.deductCalls);
    assertEquals(captured.includes(SECRET_Q1), false, "q1 in deduct payload");
    assertEquals(captured.includes(SECRET_Q2), false, "q2 in deduct payload");
    assertEquals(captured.includes(SECRET_Q3), false, "q3 in deduct payload");
    assertEquals(captured.includes(SECRET_NAME), false, "partner name in deduct payload");
    assertEquals(
      captured.includes(VALID_CARD.headline),
      false,
      "card headline in deduct payload",
    );
    assertEquals(
      captured.includes(VALID_CARD.observation),
      false,
      "card observation in deduct payload",
    );
  },
);

// ---------------------------------------------------------------------------
// C2 — partnerHint.name never logged
// ---------------------------------------------------------------------------

Deno.test(
  "Spec 5 privacy C2: partnerHint.name never appears in any log event",
  async () => {
    const SECRET_NAME = "C2_PARTNER_NAME_SENTINEL_xyz";
    const h = makeHarness(async () => claudeWrapped(VALID_CARD));
    await runCoachFollowUp(
      { ...BASE_INPUT, partnerHint: { name: SECRET_NAME } },
      h.deps,
    );

    const allLogJson = JSON.stringify(h.logs);
    assertEquals(
      allLogJson.includes(SECRET_NAME),
      false,
      "partner name leaked into log",
    );
  },
);

// ---------------------------------------------------------------------------
// C3 — Prompt content never logged
// ---------------------------------------------------------------------------

Deno.test(
  "Spec 5 privacy C3: prompt content (system rules / banned-token list / phase blocks) never logged",
  async () => {
    // Tokens unique to prompts.ts SYSTEM_PROMPT_BASE / PHASE_INSTRUCTIONS.
    // If any reaches the log, the prompt verbatim is leaking.
    const PROMPT_TOKENS = [
      "教練跟進",
      "硬規則",
      "輸出格式",
      "boundaryReminder 是 REQUIRED",
      "破冰",
    ];

    const h = makeHarness(async () => claudeWrapped(VALID_CARD));
    // Cover every phase — phase blocks differ, all must be silent.
    await runCoachFollowUp(BASE_INPUT, h.deps);
    await runCoachFollowUp({ ...BASE_INPUT, phase: "prepareInvite" }, h.deps);
    await runCoachFollowUp({ ...BASE_INPUT, phase: "preDateReminder" }, h.deps);

    const allLogJson = JSON.stringify(h.logs);
    for (const tok of PROMPT_TOKENS) {
      assertEquals(
        allLogJson.includes(tok),
        false,
        `prompt token leaked: ${tok}`,
      );
    }
  },
);

// ---------------------------------------------------------------------------
// C4 — Claude raw response never logged (success + schema-invalid paths)
// ---------------------------------------------------------------------------

Deno.test(
  "Spec 5 privacy C4: Claude raw card fields never appear in any log (success path)",
  async () => {
    const h = makeHarness(async () => claudeWrapped(VALID_CARD));
    await runCoachFollowUp(BASE_INPUT, h.deps);

    const allLogJson = JSON.stringify(h.logs);
    assertEquals(allLogJson.includes(VALID_CARD.headline), false, "headline leaked");
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
  },
);

Deno.test(
  "Spec 5 privacy C4: schema-invalid bad-card text never appears in failed log",
  async () => {
    const BAD_HEADLINE = "C4_BAD_CARD_HEADLINE_SENTINEL_xyz";
    const h = makeHarness(async () =>
      claudeWrapped({
        headline: BAD_HEADLINE,
        observation: "obs",
        task: "task",
        boundaryReminder: null, // schema_invalid trigger (REQUIRED missing)
      })
    );
    await runCoachFollowUp(BASE_INPUT, h.deps);

    const allLogJson = JSON.stringify(h.logs);
    assertEquals(
      allLogJson.includes(BAD_HEADLINE),
      false,
      "bad-card headline leaked into failed log",
    );
  },
);

// ---------------------------------------------------------------------------
// C5 — Local persistence: see header docstring. Not testable from Deno.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// C6 — Telemetry whitelist
// ---------------------------------------------------------------------------

Deno.test(
  "Spec 5 privacy C6: invoked event keys are exactly {phase, tier, hasOptionalText}",
  async () => {
    const h = makeHarness(async () => claudeWrapped(VALID_CARD));
    await runCoachFollowUp(BASE_INPUT, h.deps);

    const invoked = h.logs.find((l) => l.event === "coach_follow_up_invoked");
    assertEquals(Object.keys(invoked!.data).sort(), [
      "hasOptionalText",
      "phase",
      "tier",
    ]);
  },
);

Deno.test(
  "Spec 5 privacy C6: succeeded event keys are exactly {phase, tier, model, latencyMs, costDeducted}",
  async () => {
    const h = makeHarness(async () => claudeWrapped(VALID_CARD));
    await runCoachFollowUp(BASE_INPUT, h.deps);

    const succeeded = h.logs.find((l) => l.event === "coach_follow_up_succeeded");
    assertEquals(Object.keys(succeeded!.data).sort(), [
      "costDeducted",
      "latencyMs",
      "model",
      "phase",
      "tier",
    ]);
  },
);

Deno.test(
  "Spec 5 privacy C6: failed event keys are exactly {phase, tier, errorClass} — never raw Claude error text",
  async () => {
    const RAW_CLAUDE_LEAK = "timeout: C6_CLAUDE_RAW_DETAIL_xyz";
    const h = makeHarness(async () => {
      // Prefix "timeout:" maps to the stable claude_timeout bucket; the rest
      // of the message is the raw detail that MUST NOT enter telemetry.
      throw new Error(RAW_CLAUDE_LEAK);
    });
    await runCoachFollowUp(BASE_INPUT, h.deps);

    const failed = h.logs.find((l) => l.event === "coach_follow_up_failed");
    assertEquals(Object.keys(failed!.data).sort(), [
      "errorClass",
      "phase",
      "tier",
    ]);
    assertEquals(failed!.data.errorClass, "claude_timeout");

    const failedJson = JSON.stringify(failed);
    assertEquals(
      failedJson.includes("C6_CLAUDE_RAW_DETAIL_xyz"),
      false,
      "raw Claude error detail leaked into failed log",
    );
  },
);

Deno.test(
  "Spec 5 privacy C6: deduct failure errorClass is the stable bucket — never raw Supabase error",
  async () => {
    const RAW_SUPABASE_LEAK = "C6_SUPABASE_RAW_ERROR_DETAIL_xyz";
    const h = makeHarness(async () => claudeWrapped(VALID_CARD));
    h.deps.deductCredit = async () => {
      throw new Error(RAW_SUPABASE_LEAK);
    };
    await runCoachFollowUp(BASE_INPUT, h.deps);

    const failed = h.logs.find((l) => l.event === "coach_follow_up_failed");
    assertEquals(failed!.data.errorClass, "credit_deduct_failed");

    const allLogJson = JSON.stringify(h.logs);
    assertEquals(
      allLogJson.includes(RAW_SUPABASE_LEAK),
      false,
      "raw Supabase error detail leaked into telemetry",
    );
  },
);
