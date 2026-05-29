// supabase/functions/analyze-chat/anchor_drift_test.ts
//
// Phase 2.2 — drift detector tests. Validates the four cases from plan
// §Task 2.2 plus three guard cases (degenerate inputs, elaboration, threshold).

import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

import { detectAnchorDrift, DRIFT_THRESHOLD } from "./anchor_drift.ts";

Deno.test("anchor_drift: identical reply → no drift", () => {
  const report = detectAnchorDrift(
    { recommendedReply: "週六一起去看電影？" },
    { finalRecommendation: { content: "週六一起去看電影？" } },
  );
  assertEquals(report.driftedFields, []);
  assertEquals(report.replyOverlapRatio, 1);
});

Deno.test("anchor_drift: light edit (whitespace + punctuation) → no drift", () => {
  const report = detectAnchorDrift(
    { recommendedReply: "週六一起去看電影？" },
    { finalRecommendation: { content: "  週六一起去看電影 ?  " } },
  );
  assertEquals(report.driftedFields, []);
  // Normalization should make these effectively identical.
  assert(
    report.replyOverlapRatio >= DRIFT_THRESHOLD,
    `expected ≥ ${DRIFT_THRESHOLD}, got ${report.replyOverlapRatio}`,
  );
});

Deno.test("anchor_drift: topic change → drifted", () => {
  const report = detectAnchorDrift(
    { recommendedReply: "週六一起去看電影？" },
    { finalRecommendation: { content: "明天要不要去打網球？" } },
  );
  assertEquals(report.driftedFields, ["recommendedReply"]);
  assert(report.replyOverlapRatio < DRIFT_THRESHOLD);
});

Deno.test("anchor_drift: empty full reply → drifted with ratio 0", () => {
  const report = detectAnchorDrift(
    { recommendedReply: "週六一起去看電影？" },
    { finalRecommendation: { content: "" } },
  );
  assertEquals(report.driftedFields, ["recommendedReply"]);
  assertEquals(report.replyOverlapRatio, 0);
});

Deno.test("anchor_drift: missing finalRecommendation entirely → drifted", () => {
  const report = detectAnchorDrift(
    { recommendedReply: "週六一起去看電影？" },
    {} as Record<string, unknown>,
  );
  assertEquals(report.driftedFields, ["recommendedReply"]);
  assertEquals(report.replyOverlapRatio, 0);
});

Deno.test("anchor_drift: missing quick anchor → no drift signal (degenerate)", () => {
  // No anchor → nothing to drift FROM. Avoid polluting telemetry with false
  // alarms when quick payload is malformed.
  const report = detectAnchorDrift(
    {} as Record<string, unknown>,
    { finalRecommendation: { content: "完全不一樣的回覆" } },
  );
  assertEquals(report.driftedFields, []);
  assertEquals(report.replyOverlapRatio, 1);
});

Deno.test("anchor_drift: faithful elaboration on same topic → no drift", () => {
  // The full prompt is allowed to ELABORATE on quick (I7: confirm/supplement/
  // light-polish). Containment metric must not penalize the longer string for
  // adding bigrams — only check that the quick anchor is preserved inside full.
  const report = detectAnchorDrift(
    { recommendedReply: "週六一起去看電影？" },
    {
      finalRecommendation: {
        content: "週六一起去看電影怎麼樣？我聽說最近有部新片很不錯。",
      },
    },
  );
  assertFalse(
    report.driftedFields.includes("recommendedReply"),
    `elaboration should not drift, got ratio ${report.replyOverlapRatio}`,
  );
  assert(report.replyOverlapRatio >= DRIFT_THRESHOLD);
});

Deno.test("anchor_drift: non-string content fields → drifted (empty)", () => {
  // Defensive: if Claude returns finalRecommendation.content as a non-string
  // (e.g. object/null), we treat it as empty rather than throw.
  const report = detectAnchorDrift(
    { recommendedReply: "週六一起去看電影？" },
    { finalRecommendation: { content: { foo: "bar" } as unknown as string } },
  );
  assertEquals(report.driftedFields, ["recommendedReply"]);
  assertEquals(report.replyOverlapRatio, 0);
});

Deno.test("anchor_drift: minor character swap stays above threshold", () => {
  // Swapping a single character should still preserve enough bigrams.
  const report = detectAnchorDrift(
    { recommendedReply: "週六一起去看電影怎樣？" },
    { finalRecommendation: { content: "週六一起去看電影怎麼樣？" } },
  );
  assertFalse(report.driftedFields.includes("recommendedReply"));
  assert(report.replyOverlapRatio >= DRIFT_THRESHOLD);
});
