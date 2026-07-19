import {
  assertEquals,
  assertObjectMatch,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildHintPrefetchTelemetry,
  decideHintPrefetchReplay,
  HINT_QUALITY_SCHEMA_VERSION,
  HINT_REVIEW_SCHEMA_VERSION,
  hintPrefetchAck,
  hintRecordPolicy,
  isExplicitModelHintResult,
  isHintPrefetchEnabled,
  isReplayableModelHintResult,
} from "./hint_prefetch.ts";

const result = {
  replies: [
    { type: "warm_up", label: "暖場", text: "嗨" },
    { type: "steady", label: "穩健", text: "哈囉" },
  ],
  coaching: "接住她的語氣",
  generationSource: "model",
  fallbackUsed: false,
  qualitySchemaVersion: HINT_QUALITY_SCHEMA_VERSION,
  hintReviewSchemaVersion: HINT_REVIEW_SCHEMA_VERSION,
};

Deno.test("prefetch kill switch is exact true and defaults off", () => {
  assertEquals(isHintPrefetchEnabled("true"), true);
  for (const value of [undefined, "", "false", "TRUE", "1"]) {
    assertEquals(isHintPrefetchEnabled(value), false);
  }
});

Deno.test("replay decision keeps generating distinct from consumable prefetch", () => {
  assertEquals(
    decideHintPrefetchReplay({ requestPrefetch: false, row: null }),
    { kind: "miss" },
  );
  assertEquals(
    decideHintPrefetchReplay({
      requestPrefetch: false,
      row: {
        state: "generating",
        charged: false,
        result: null,
        legacyReplacementPending: false,
      },
    }),
    { kind: "continueToClaim" },
  );
  assertEquals(
    decideHintPrefetchReplay({
      requestPrefetch: true,
      row: {
        state: "generating",
        charged: false,
        result: null,
        legacyReplacementPending: false,
      },
    }),
    { kind: "continueToClaim" },
  );
});

Deno.test("settled request is formal replay but prefetch remains opaque", () => {
  assertEquals(
    decideHintPrefetchReplay({
      requestPrefetch: false,
      row: {
        state: "settled",
        charged: true,
        result,
        isPrefetch: false,
      },
    }),
    { kind: "settledReplay", result },
  );
  assertEquals(
    decideHintPrefetchReplay({
      requestPrefetch: true,
      row: {
        state: "settled",
        charged: true,
        result,
        isPrefetch: false,
      },
    }),
    { kind: "opaqueAck" },
  );
});

Deno.test("prefetched request is formal consume but retry remains opaque", () => {
  assertEquals(
    decideHintPrefetchReplay({
      requestPrefetch: false,
      row: { state: "prefetched", charged: false, result, isPrefetch: true },
    }),
    { kind: "prefetchedConsume", result },
  );
  assertEquals(
    decideHintPrefetchReplay({
      requestPrefetch: true,
      row: { state: "prefetched", charged: false, result, isPrefetch: true },
    }),
    { kind: "opaqueAck" },
  );
});

Deno.test("record policy keeps quota and formal consumption as separate axes", () => {
  assertEquals(
    hintRecordPolicy({
      isPrefetch: false,
      isTestAccount: false,
    }),
    { chargeQuota: true, charged: true },
  );
  assertEquals(
    hintRecordPolicy({
      isPrefetch: false,
      isTestAccount: true,
    }),
    { chargeQuota: false, charged: true },
  );
  assertEquals(
    hintRecordPolicy({
      isPrefetch: true,
      isTestAccount: false,
    }),
    { chargeQuota: false, charged: false },
  );
  assertEquals(
    hintRecordPolicy({
      isPrefetch: false,
      isTestAccount: false,
      quotaAlreadyPaid: true,
    }),
    { chargeQuota: false, charged: true },
  );
});

Deno.test("replay accepts only explicit model snapshots", () => {
  assertEquals(isReplayableModelHintResult(result), true);
  assertEquals(isExplicitModelHintResult(result), true);
  assertEquals(
    isReplayableModelHintResult({ costDeducted: 1, replies: [] }),
    false,
  );
  assertEquals(
    isReplayableModelHintResult({ costDeducted: 0, replies: [] }),
    false,
  );
  assertEquals(
    isReplayableModelHintResult({
      generationSource: "model",
      fallbackUsed: false,
    }),
    false,
  );
  assertEquals(
    isReplayableModelHintResult({
      generationSource: "fallback",
      fallbackUsed: true,
      costDeducted: 0,
    }),
    false,
  );
});

Deno.test("semantic-quality-v2 snapshots without review certification are replaced", () => {
  const uncertified = {
    replies: result.replies,
    coaching: result.coaching,
    generationSource: "model",
    fallbackUsed: false,
    qualitySchemaVersion: HINT_QUALITY_SCHEMA_VERSION,
  };

  assertEquals(isExplicitModelHintResult(uncertified), false);
  assertEquals(isReplayableModelHintResult(uncertified), false);
  assertEquals(
    decideHintPrefetchReplay({
      requestPrefetch: false,
      row: {
        state: "settled",
        charged: true,
        result: uncertified,
        isPrefetch: false,
      },
    }),
    { kind: "legacyReplacementClaim" },
  );
  assertEquals(
    decideHintPrefetchReplay({
      requestPrefetch: false,
      row: {
        state: "prefetched",
        charged: false,
        result: uncertified,
        isPrefetch: true,
      },
    }),
    { kind: "legacyPrefetchDiscard" },
  );
});

Deno.test("unmarked prefetch snapshots never settle or replay as model output", () => {
  const legacy = { costDeducted: 0, replies: [], coaching: "legacy" };
  assertEquals(
    decideHintPrefetchReplay({
      requestPrefetch: false,
      row: {
        state: "prefetched",
        charged: false,
        result: legacy,
        isPrefetch: true,
      },
    }),
    { kind: "legacyPrefetchDiscard" },
  );
  assertEquals(
    decideHintPrefetchReplay({
      requestPrefetch: false,
      row: {
        state: "settled",
        charged: true,
        result: { ...legacy, costDeducted: 1 },
        isPrefetch: true,
      },
    }),
    { kind: "legacyReplacementClaim" },
  );
});

Deno.test("prefetch telemetry emits only allowlisted scalar fields", () => {
  assertEquals(
    buildHintPrefetchTelemetry({
      outcome: "hit",
      reason: "pending",
      practiceMode: "game",
    }),
    { outcome: "hit", reason: "pending", practiceMode: "game" },
  );
  assertEquals(
    buildHintPrefetchTelemetry({
      outcome: "not-allowed",
      reason: "raw provider said something private",
      practiceMode: "beginner",
    }),
    { outcome: "failed", reason: "unknown", practiceMode: "beginner" },
  );
  assertEquals(
    buildHintPrefetchTelemetry({
      outcome: "failed",
      reason: "semantic_rejected",
      practiceMode: "beginner",
    }),
    {
      outcome: "failed",
      reason: "semantic_rejected",
      practiceMode: "beginner",
    },
  );
});

Deno.test("prefetch ack has no content-bearing fields", () => {
  const ack = hintPrefetchAck();
  assertEquals(ack, { prefetched: true });
  assertEquals(Object.keys(ack), ["prefetched"]);
  assertObjectMatch(ack, { prefetched: true });
});
