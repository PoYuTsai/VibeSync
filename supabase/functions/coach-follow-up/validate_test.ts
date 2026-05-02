// supabase/functions/coach-follow-up/validate_test.ts
//
// T2: request validator tests. All assertRejects calls are awaited inside async
// bodies AND each lambda is async so a synchronous throw inside validateRequest
// surfaces as a Promise rejection (Codex Plan-Review P1 #4 — without async
// wrapping the throw escapes assertRejects entirely with the misleading
// "Function throws when expected to reject" error).

import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { validateRequest } from "./validate.ts";

Deno.test("validateRequest rejects missing phase", async () => {
  await assertRejects(
    async () => validateRequest({ answers: { q1: "x" } }),
    Error,
    "phase",
  );
});

Deno.test("validateRequest rejects unknown phase", async () => {
  await assertRejects(
    async () =>
      validateRequest({ phase: "invalid", answers: { q1: "x" } }),
    Error,
    "phase",
  );
});

Deno.test("validateRequest rejects images field (v1 prohibited)", async () => {
  await assertRejects(
    async () =>
      validateRequest({
        phase: "prepareInvite",
        answers: { q1: "fuzzy" },
        images: [],
      }),
    Error,
    "invalid_input_for_mode",
  );
});

Deno.test("validateRequest rejects q3 over 80 chars", async () => {
  await assertRejects(
    async () =>
      validateRequest({
        phase: "prepareInvite",
        answers: { q1: "fuzzy", q3: "a".repeat(81) },
      }),
    Error,
    "q3",
  );
});

Deno.test("validateRequest rejects partnerHint.lastConversationSummary over 200 chars", async () => {
  await assertRejects(
    async () =>
      validateRequest({
        phase: "prepareInvite",
        answers: { q1: "fuzzy" },
        partnerHint: {
          name: "Candy",
          lastConversationSummary: "a".repeat(201),
        },
      }),
    Error,
    "lastConversationSummary",
  );
});

Deno.test("validateRequest accepts minimal valid payload", () => {
  const r = validateRequest({
    phase: "prepareInvite",
    answers: { q1: "fuzzy" },
  });
  assertEquals(r.phase, "prepareInvite");
  assertEquals(r.answers.q1, "fuzzy");
});

Deno.test("validateRequest accepts all three phases", () => {
  for (const phase of ["prepareInvite", "preDateReminder", "postDateReflection"]) {
    const r = validateRequest({ phase, answers: { q1: "x" } });
    assertEquals(r.phase, phase);
  }
});

Deno.test("validateRequest accepts full partnerHint", () => {
  const r = validateRequest({
    phase: "preDateReminder",
    answers: { q1: "明天", q2: "吃飯", q3: "緊張" },
    partnerHint: {
      name: "Candy",
      heatScore: 70,
      gameStage: "close",
      lastConversationSummary: "對話氣氛輕鬆，最近聊到週末有空",
    },
  });
  assertEquals(r.partnerHint?.name, "Candy");
  assertEquals(r.partnerHint?.heatScore, 70);
});

Deno.test("validateRequest rejects heatScore out of range", async () => {
  await assertRejects(
    async () =>
      validateRequest({
        phase: "prepareInvite",
        answers: { q1: "x" },
        partnerHint: { name: "C", heatScore: 150 },
      }),
    Error,
  );
});
