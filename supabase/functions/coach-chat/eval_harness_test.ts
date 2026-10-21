import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import type { SocialKnowledgeSignal } from "../_shared/social/knowledge_registry.ts";
import { COACH_EVAL_CASES, runCoachEvalHarness } from "./eval_harness.ts";

// Batch E 的 12 組＋規格 PR-4a 的「填了關於我、但問題無關」1 組，每組 6 題。
Deno.test("Batch E eval corpus is exactly 78 unique cases across 13 families", () => {
  assertEquals(COACH_EVAL_CASES.length, 78);
  assertEquals(new Set(COACH_EVAL_CASES.map((item) => item.id)).size, 78);
  const familyCounts = new Map<string, number>();
  for (const item of COACH_EVAL_CASES) {
    familyCounts.set(item.family, (familyCounts.get(item.family) ?? 0) + 1);
  }
  assertEquals(familyCounts.size, 13);
  assert([...familyCounts.values()].every((count) => count === 6));
});

Deno.test("about_me_unrelated cases carry About Me and forbid its heading-word signals", () => {
  const cases = COACH_EVAL_CASES.filter((item) =>
    item.family === "about_me_unrelated"
  );
  assertEquals(cases.length, 6);
  for (const item of cases) {
    assert((item.request.effectiveStyleContext ?? "").length > 0, item.id);
    assert((item.forbiddenSignals ?? []).length > 0, item.id);
  }
  const results = runCoachEvalHarness(cases);
  assertEquals(results.flatMap((result) => result.unexpectedSignals), []);
});

Deno.test("all 78 cases route required knowledge and assemble bounded prompts", () => {
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
