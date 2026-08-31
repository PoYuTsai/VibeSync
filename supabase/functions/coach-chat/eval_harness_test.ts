import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import type { SocialKnowledgeSignal } from "../_shared/social/knowledge_registry.ts";
import { COACH_EVAL_CASES, runCoachEvalHarness } from "./eval_harness.ts";

Deno.test("Batch E eval corpus is exactly 72 unique cases across 12 families", () => {
  assertEquals(COACH_EVAL_CASES.length, 72);
  assertEquals(new Set(COACH_EVAL_CASES.map((item) => item.id)).size, 72);
  const familyCounts = new Map<string, number>();
  for (const item of COACH_EVAL_CASES) {
    familyCounts.set(item.family, (familyCounts.get(item.family) ?? 0) + 1);
  }
  assertEquals(familyCounts.size, 12);
  assert([...familyCounts.values()].every((count) => count === 6));
});

Deno.test("all 72 cases route required knowledge and assemble bounded prompts", () => {
  const results = runCoachEvalHarness();
  const failures = results.filter((result) => !result.passed);
  assertEquals(
    failures,
    [],
    JSON.stringify(failures, null, 2),
  );
  for (const result of results) {
    assert(result.selectedAtomIds.length <= 12);
    assert(result.selectedAtomIds.length < 62);
    assert(result.promptChars > 0);
  }
});

Deno.test("72-case corpus covers behavior, safety, style, and evidence signals", () => {
  const signals = new Set(
    COACH_EVAL_CASES.flatMap((item) => item.expectedSignals),
  );
  const requiredSignals: readonly SocialKnowledgeSignal[] = [
    "interpretation",
    "reply",
    "invite",
    "repeated_non_uptake",
    "stalled",
    "clear_no",
    "intimacy",
    "health",
    "impaired",
    "minor",
    "anxiety",
    "repair",
    "compatibility",
    "humor",
    "partnered",
    "low_investment",
  ];
  for (const required of requiredSignals) {
    assert(signals.has(required));
  }
});
