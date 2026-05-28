// supabase/functions/analyze-chat/request_mode_test.ts
//
// Phase 1.2: 兩階段 analyze 的 responseMode + analysisRunId normalization。
// 這層的責任只是 parse + normalize，不負責驗證 runId 是否存在於 DB 或屬於哪個 user。
// 後續驗證在 Phase 2.1 (full mode) 的 store.validateRunForFull 完成。

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

Deno.test("unknown responseMode strings degrade to legacy (defensive default)", () => {
  // 防止未來 client 送錯字串時 server 走未知分支：fall back to legacy 是最安全的。
  const result = normalizeRequestMode({ responseMode: "Quick" }); // case-sensitive
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
  assertEquals(normalizeRequestMode({ responseMode: null }).responseMode, "legacy");
});

Deno.test("analysisRunId string is trimmed", () => {
  const result = normalizeRequestMode({
    responseMode: "full",
    analysisRunId: "  abc-123  ",
  });
  assertEquals(result.analysisRunId, "abc-123");
});

Deno.test("analysisRunId empty string normalizes to null", () => {
  // 空字串對 caller 沒語意，統一變 null 讓 full mode handler 用單一 falsy 判斷拒絕。
  const result = normalizeRequestMode({
    responseMode: "full",
    analysisRunId: "   ",
  });
  assertStrictEquals(result.analysisRunId, null);
});

Deno.test("non-string analysisRunId is dropped to null", () => {
  // UUID 一定是 string；任何非 string 都當作沒帶。
  assertStrictEquals(
    normalizeRequestMode({ responseMode: "full", analysisRunId: 123 }).analysisRunId,
    null,
  );
  assertStrictEquals(
    normalizeRequestMode({ responseMode: "full", analysisRunId: { id: "x" } })
      .analysisRunId,
    null,
  );
  assertStrictEquals(
    normalizeRequestMode({ responseMode: "full", analysisRunId: null }).analysisRunId,
    null,
  );
});

Deno.test("quick mode with analysisRunId still surfaces the value (handler decides what to do)", () => {
  // 這層不拒絕；只 normalize。handler 才知道「quick 帶 runId 是不是該拒絕」。
  const result = normalizeRequestMode({
    responseMode: "quick",
    analysisRunId: "run-1",
  });
  assertEquals(result.responseMode, "quick");
  assertEquals(result.analysisRunId, "run-1");
});

Deno.test("output type is the canonical 3-value union (negative assertion)", () => {
  // 守住「除了 quick/full/legacy 沒有其他值」這條 invariant。
  const allModes: Array<"quick" | "full" | "legacy"> = [
    normalizeRequestMode({ responseMode: "quick" }).responseMode,
    normalizeRequestMode({ responseMode: "full" }).responseMode,
    normalizeRequestMode({}).responseMode,
  ];
  assertEquals(allModes.sort(), ["full", "legacy", "quick"]);
});

// ----------------------------------------------------------------------
// shouldRejectFullMode — Phase 1 stub guard. Must fire BEFORE quota
// preflight / Claude call so a quota-exhausted user gets MISSING_RUN_ID
// or FULL_MODE_NOT_READY instead of an out-of-band 429. Codex round-2
// review regression coverage.
// ----------------------------------------------------------------------

Deno.test("shouldRejectFullMode — legacy never rejected", () => {
  const r = shouldRejectFullMode({ responseMode: "legacy", analysisRunId: null });
  assertFalse(r.reject);
});

Deno.test("shouldRejectFullMode — legacy with stray runId still not rejected", () => {
  // Defensive: even if a client mistakenly sends runId on legacy, this helper
  // only routes full. Quota/auth gates elsewhere handle legacy.
  const r = shouldRejectFullMode({
    responseMode: "legacy",
    analysisRunId: "abc-123",
  });
  assertFalse(r.reject);
});

Deno.test("shouldRejectFullMode — quick never rejected", () => {
  const r = shouldRejectFullMode({ responseMode: "quick", analysisRunId: null });
  assertFalse(r.reject);
});

Deno.test("shouldRejectFullMode — full + missing runId → 400 MISSING_RUN_ID", () => {
  const r = shouldRejectFullMode({ responseMode: "full", analysisRunId: null });
  assert(r.reject);
  if (r.reject) {
    assertEquals(r.status, 400);
    assertEquals(r.code, "MISSING_RUN_ID");
  }
});

Deno.test("shouldRejectFullMode — full + runId present → 503 FULL_MODE_NOT_READY (Phase 2 stub)", () => {
  // Phase 2.1 will replace this with the real anchor handler; until then,
  // a valid-looking runId still gets rejected (no Claude call, no quota touch).
  const r = shouldRejectFullMode({
    responseMode: "full",
    analysisRunId: "11111111-1111-1111-1111-111111111111",
  });
  assert(r.reject);
  if (r.reject) {
    assertEquals(r.status, 503);
    assertEquals(r.code, "FULL_MODE_NOT_READY");
  }
});

Deno.test("shouldRejectFullMode — precedence: full routing decision is independent of quota state", () => {
  // The helper is pure — it does not know about quota. The handler MUST call
  // it before quota preflight so a quota-exhausted user still gets the
  // routing-level rejection (400/503), not 429. This test pins the contract:
  // the helper only looks at responseMode + analysisRunId.
  //
  // Codex round-2 regression: input shape minimal; no quota / no claude call
  // anywhere in this code path.
  const noRunId = shouldRejectFullMode({
    responseMode: "full",
    analysisRunId: null,
  });
  const withRunId = shouldRejectFullMode({
    responseMode: "full",
    analysisRunId: "abc",
  });
  assert(noRunId.reject);
  assert(withRunId.reject);
  if (noRunId.reject) assertEquals(noRunId.code, "MISSING_RUN_ID");
  if (withRunId.reject) assertEquals(withRunId.code, "FULL_MODE_NOT_READY");
});
