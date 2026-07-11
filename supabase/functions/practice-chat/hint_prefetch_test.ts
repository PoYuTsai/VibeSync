import {
  assertEquals,
  assertObjectMatch,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildHintPrefetchTelemetry,
  decideHintPrefetchReplay,
  hintPrefetchAck,
  hintRecordPolicy,
  isHintPrefetchEnabled,
} from "./hint_prefetch.ts";

const result = {
  replies: [
    { type: "warm_up", label: "暖場", text: "嗨" },
    { type: "steady", label: "穩健", text: "哈囉" },
  ],
  coaching: "接住她的語氣",
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
      row: { state: "generating", charged: false, result: null },
    }),
    { kind: "continueToClaim" },
  );
  assertEquals(
    decideHintPrefetchReplay({
      requestPrefetch: true,
      row: { state: "generating", charged: false, result: null },
    }),
    { kind: "continueToClaim" },
  );
});

Deno.test("settled request is formal replay but prefetch remains opaque", () => {
  assertEquals(
    decideHintPrefetchReplay({
      requestPrefetch: false,
      row: { state: "settled", charged: true, result },
    }),
    { kind: "settledReplay", result },
  );
  assertEquals(
    decideHintPrefetchReplay({
      requestPrefetch: true,
      row: { state: "settled", charged: true, result },
    }),
    { kind: "opaqueAck" },
  );
});

Deno.test("prefetched request is formal consume but retry remains opaque", () => {
  assertEquals(
    decideHintPrefetchReplay({
      requestPrefetch: false,
      row: { state: "prefetched", charged: false, result },
    }),
    { kind: "prefetchedConsume", result },
  );
  assertEquals(
    decideHintPrefetchReplay({
      requestPrefetch: true,
      row: { state: "prefetched", charged: false, result },
    }),
    { kind: "opaqueAck" },
  );
});

Deno.test("record policy keeps quota and formal consumption as separate axes", () => {
  assertEquals(
    hintRecordPolicy({
      isPrefetch: false,
      isTestAccount: false,
      isFallback: false,
    }),
    { chargeQuota: true, charged: true },
  );
  assertEquals(
    hintRecordPolicy({
      isPrefetch: false,
      isTestAccount: true,
      isFallback: false,
    }),
    { chargeQuota: false, charged: true },
  );
  assertEquals(
    hintRecordPolicy({
      isPrefetch: false,
      isTestAccount: false,
      isFallback: true,
    }),
    { chargeQuota: false, charged: true },
  );
  assertEquals(
    hintRecordPolicy({
      isPrefetch: true,
      isTestAccount: false,
      isFallback: false,
    }),
    { chargeQuota: false, charged: false },
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
});

Deno.test("prefetch ack has no content-bearing fields", () => {
  const ack = hintPrefetchAck();
  assertEquals(ack, { prefetched: true });
  assertEquals(Object.keys(ack), ["prefetched"]);
  assertObjectMatch(ack, { prefetched: true });
});
