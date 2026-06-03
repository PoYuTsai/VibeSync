import {
  assert,
  assertEquals,
  assertFalse,
  assertStrictEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  normalizeRequestMode,
  shouldRejectFullMode,
} from "./request_mode.ts";

Deno.test("missing responseMode falls back to legacy (I10 backwards compat)", () => {
  const result = normalizeRequestMode({});
  assertEquals(result.responseMode, "legacy");
  assertStrictEquals(result.analysisRunId, null);
});

Deno.test("explicit responseMode='legacy' stays legacy", () => {
  const result = normalizeRequestMode({ responseMode: "legacy" });
  assertEquals(result.responseMode, "legacy");
});

Deno.test("responseMode='quick' is preserved", () => {
  const result = normalizeRequestMode({ responseMode: "quick" });
  assertEquals(result.responseMode, "quick");
});

Deno.test("responseMode='full' is preserved", () => {
  const result = normalizeRequestMode({ responseMode: "full" });
  assertEquals(result.responseMode, "full");
});

Deno.test("responseMode='stream' is preserved", () => {
  const result = normalizeRequestMode({ responseMode: "stream" });
  assertEquals(result.responseMode, "stream");
  assertStrictEquals(result.analysisRunId, null);
});

Deno.test("unknown responseMode strings degrade to legacy (defensive default)", () => {
  const result = normalizeRequestMode({ responseMode: "Quick" });
  assertEquals(result.responseMode, "legacy");

  const result2 = normalizeRequestMode({ responseMode: "fast" });
  assertEquals(result2.responseMode, "legacy");
});

Deno.test("non-string responseMode (number / object / null) degrades to legacy", () => {
  assertEquals(normalizeRequestMode({ responseMode: 1 }).responseMode, "legacy");
  assertEquals(
    normalizeRequestMode({ responseMode: { kind: "quick" } }).responseMode,
    "legacy",
  );
  assertEquals(
    normalizeRequestMode({ responseMode: null }).responseMode,
    "legacy",
  );
});

Deno.test("analysisRunId string is trimmed", () => {
  const result = normalizeRequestMode({
    responseMode: "full",
    analysisRunId: "  abc-123  ",
  });
  assertEquals(result.analysisRunId, "abc-123");
});

Deno.test("analysisRunId empty string normalizes to null", () => {
  const result = normalizeRequestMode({
    responseMode: "full",
    analysisRunId: "   ",
  });
  assertStrictEquals(result.analysisRunId, null);
});

Deno.test("non-string analysisRunId is dropped to null", () => {
  assertStrictEquals(
    normalizeRequestMode({ responseMode: "full", analysisRunId: 123 })
      .analysisRunId,
    null,
  );
  assertStrictEquals(
    normalizeRequestMode({ responseMode: "full", analysisRunId: { id: "x" } })
      .analysisRunId,
    null,
  );
  assertStrictEquals(
    normalizeRequestMode({ responseMode: "full", analysisRunId: null })
      .analysisRunId,
    null,
  );
});

Deno.test("quick mode with analysisRunId still surfaces the value", () => {
  const result = normalizeRequestMode({
    responseMode: "quick",
    analysisRunId: "run-1",
  });
  assertEquals(result.responseMode, "quick");
  assertEquals(result.analysisRunId, "run-1");
});

Deno.test("stream mode with analysisRunId still surfaces the value", () => {
  const result = normalizeRequestMode({
    responseMode: "stream",
    analysisRunId: "run-stream",
  });
  assertEquals(result.responseMode, "stream");
  assertEquals(result.analysisRunId, "run-stream");
});

Deno.test("output type is the canonical 4-value union", () => {
  const allModes: Array<"quick" | "full" | "legacy" | "stream"> = [
    normalizeRequestMode({ responseMode: "quick" }).responseMode,
    normalizeRequestMode({ responseMode: "full" }).responseMode,
    normalizeRequestMode({ responseMode: "stream" }).responseMode,
    normalizeRequestMode({}).responseMode,
  ];
  assertEquals(allModes.sort(), ["full", "legacy", "quick", "stream"]);
});

Deno.test("shouldRejectFullMode: legacy never rejected", () => {
  const r = shouldRejectFullMode({ responseMode: "legacy", analysisRunId: null });
  assertFalse(r.reject);
});

Deno.test("shouldRejectFullMode: legacy with stray runId still not rejected", () => {
  const r = shouldRejectFullMode({
    responseMode: "legacy",
    analysisRunId: "abc-123",
  });
  assertFalse(r.reject);
});

Deno.test("shouldRejectFullMode: quick never rejected", () => {
  const r = shouldRejectFullMode({ responseMode: "quick", analysisRunId: null });
  assertFalse(r.reject);
});

Deno.test("shouldRejectFullMode: stream never rejected", () => {
  const r = shouldRejectFullMode({ responseMode: "stream", analysisRunId: null });
  assertFalse(r.reject);
});

Deno.test("shouldRejectFullMode: full + missing runId returns 400 MISSING_RUN_ID", () => {
  const r = shouldRejectFullMode({ responseMode: "full", analysisRunId: null });
  assert(r.reject);
  if (r.reject) {
    assertEquals(r.status, 400);
    assertEquals(r.code, "MISSING_RUN_ID");
  }
});

Deno.test("shouldRejectFullMode: full + runId passes through to handler", () => {
  const r = shouldRejectFullMode({
    responseMode: "full",
    analysisRunId: "11111111-1111-1111-1111-111111111111",
  });
  assertFalse(r.reject);
});

Deno.test("shouldRejectFullMode: routing decision uses only mode and runId", () => {
  const noRunId = shouldRejectFullMode({
    responseMode: "full",
    analysisRunId: null,
  });
  const withRunId = shouldRejectFullMode({
    responseMode: "full",
    analysisRunId: "abc",
  });
  assert(noRunId.reject);
  if (noRunId.reject) assertEquals(noRunId.code, "MISSING_RUN_ID");
  assertFalse(withRunId.reject);
});
