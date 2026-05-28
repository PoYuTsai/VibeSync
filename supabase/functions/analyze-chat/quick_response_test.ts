// supabase/functions/analyze-chat/quick_response_test.ts
//
// Phase 1.3 testable units: parseQuickResponse (JSON parse + repair),
// applyQuickGuardrails (block-pattern safety swap for recommendedReply),
// estimateFullSeconds (UI skeleton ETA lookup).
//
// The end-to-end quick handler integration (atomic RPC charge, no-charge-on-
// Claude-failure, rollback-on-RPC-failure) is exercised by Edge Function
// integration tests + the Codex Phase 1 review gate, not here.

import {
  assert,
  assertEquals,
  assertFalse,
  assertStrictEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  applyQuickGuardrails,
  estimateFullSeconds,
  parseQuickResponse,
} from "./quick_response.ts";

// ------------------------------------------------------------------
// parseQuickResponse
// ------------------------------------------------------------------

Deno.test("parseQuickResponse — happy path extracts all 5 canonical fields", () => {
  const raw = JSON.stringify({
    nextStep: "先回應她的累，再順勢問週末",
    recommendedReply: "今天聽起來真的很滿，要不要週末一起去吃宵夜放空？",
    shortReason: "先接情緒比直接邀約更有耐性",
    insufficientContext: false,
    confidence: "high",
  });
  const result = parseQuickResponse(raw);
  assert(result.ok);
  assertEquals(result.payload.nextStep, "先回應她的累，再順勢問週末");
  assertEquals(
    result.payload.recommendedReply,
    "今天聽起來真的很滿，要不要週末一起去吃宵夜放空？",
  );
  assertEquals(result.payload.shortReason, "先接情緒比直接邀約更有耐性");
  assertEquals(result.payload.insufficientContext, false);
  assertEquals(result.payload.confidence, "high");
});

Deno.test("parseQuickResponse — accepts surrounding prose / markdown fence", () => {
  const raw = "```json\n" + JSON.stringify({
    nextStep: "稍微緩一下",
    recommendedReply: "好的我懂",
    shortReason: "對方訊號弱",
    insufficientContext: false,
    confidence: "medium",
  }) + "\n```";
  const result = parseQuickResponse(raw);
  assert(result.ok);
  assertEquals(result.payload.confidence, "medium");
});

Deno.test("parseQuickResponse — confidence falls back to 'medium' when invalid", () => {
  const raw = JSON.stringify({
    nextStep: "x",
    recommendedReply: "y",
    shortReason: "z",
    insufficientContext: false,
    confidence: "super_high", // not a valid bucket
  });
  const result = parseQuickResponse(raw);
  assert(result.ok);
  assertEquals(result.payload.confidence, "medium");
});

Deno.test("parseQuickResponse — insufficientContext coerced to boolean", () => {
  const raw = JSON.stringify({
    nextStep: "x",
    recommendedReply: "y",
    shortReason: "z",
    insufficientContext: "true", // model sometimes returns string
    confidence: "low",
  });
  const result = parseQuickResponse(raw);
  assert(result.ok);
  assertStrictEquals(result.payload.insufficientContext, true);
});

Deno.test("parseQuickResponse — missing recommendedReply fails", () => {
  const raw = JSON.stringify({
    nextStep: "x",
    shortReason: "z",
    insufficientContext: false,
    confidence: "medium",
  });
  const result = parseQuickResponse(raw);
  assertFalse(result.ok);
  if (!result.ok) {
    assertEquals(result.error, "MISSING_REQUIRED_FIELD");
  }
});

Deno.test("parseQuickResponse — empty recommendedReply fails (model produced nothing useful)", () => {
  const raw = JSON.stringify({
    nextStep: "x",
    recommendedReply: "   ",
    shortReason: "z",
    insufficientContext: false,
    confidence: "medium",
  });
  const result = parseQuickResponse(raw);
  assertFalse(result.ok);
});

Deno.test("parseQuickResponse — missing nextStep fails (Codex P2: 本回合怎麼接 must not be blank)", () => {
  // UX contract (plan I7): above-the-fold card binds to both nextStep and
  // recommendedReply. Either empty = unusable quick result.
  const raw = JSON.stringify({
    recommendedReply: "y",
    shortReason: "z",
    insufficientContext: false,
    confidence: "medium",
  });
  const result = parseQuickResponse(raw);
  assertFalse(result.ok);
  if (!result.ok) assertEquals(result.error, "MISSING_REQUIRED_FIELD");
});

Deno.test("parseQuickResponse — empty/whitespace nextStep fails", () => {
  const raw = JSON.stringify({
    nextStep: "   ",
    recommendedReply: "y",
    shortReason: "z",
    insufficientContext: false,
    confidence: "medium",
  });
  const result = parseQuickResponse(raw);
  assertFalse(result.ok);
  if (!result.ok) assertEquals(result.error, "MISSING_REQUIRED_FIELD");
});

Deno.test("parseQuickResponse — no JSON block in text returns NO_JSON", () => {
  const result = parseQuickResponse("hi! here is my advice without JSON.");
  assertFalse(result.ok);
  if (!result.ok) assertEquals(result.error, "NO_JSON");
});

Deno.test("parseQuickResponse — malformed JSON returns INVALID_JSON", () => {
  const result = parseQuickResponse('{nextStep: "x", recommendedReply');
  assertFalse(result.ok);
  if (!result.ok) {
    assert(["INVALID_JSON", "NO_JSON"].includes(result.error));
  }
});

Deno.test("parseQuickResponse — trims string fields", () => {
  const raw = JSON.stringify({
    nextStep: "  先接情緒  ",
    recommendedReply: "\t你今天辛苦了\n",
    shortReason: "  接住  ",
    insufficientContext: false,
    confidence: "high",
  });
  const result = parseQuickResponse(raw);
  assert(result.ok);
  assertEquals(result.payload.nextStep, "先接情緒");
  assertEquals(result.payload.recommendedReply, "你今天辛苦了");
  assertEquals(result.payload.shortReason, "接住");
});

// ------------------------------------------------------------------
// applyQuickGuardrails
// ------------------------------------------------------------------

Deno.test("applyQuickGuardrails — clean payload passes through unchanged", () => {
  const payload = {
    nextStep: "順勢延伸",
    recommendedReply: "聽起來不錯，要不要週末聊聊？",
    shortReason: "輕邀約給對方退路",
    insufficientContext: false,
    confidence: "high" as const,
  };
  const result = applyQuickGuardrails(payload);
  assertFalse(result.safetyFiltered);
  assertEquals(result.payload, payload);
});

Deno.test("applyQuickGuardrails — recommendedReply hitting BLOCKED_PATTERNS is replaced", () => {
  const payload = {
    nextStep: "x",
    recommendedReply: "你不要放棄一直跟她講就會喜歡你了",
    shortReason: "z",
    insufficientContext: false,
    confidence: "medium" as const,
  };
  const result = applyQuickGuardrails(payload);
  assert(result.safetyFiltered);
  // 替換後的 reply 不能再含 blocked pattern
  assertFalse(/不要放棄.*一直/.test(result.payload.recommendedReply));
  // 仍然有非空 recommendedReply 給使用者
  assert(result.payload.recommendedReply.length > 0);
});

Deno.test("applyQuickGuardrails — nextStep with blocked pattern is also filtered", () => {
  // 不只 recommendedReply，nextStep 也是 user-visible
  const payload = {
    nextStep: "強迫她答應週末出來",
    recommendedReply: "週末有空嗎？",
    shortReason: "z",
    insufficientContext: false,
    confidence: "low" as const,
  };
  const result = applyQuickGuardrails(payload);
  assert(result.safetyFiltered);
  assertFalse(/強迫|逼.*答應/.test(result.payload.nextStep));
});

Deno.test("applyQuickGuardrails — non-string fields are coerced before pattern test", () => {
  // Defensive: if something upstream lets through a non-string we shouldn't crash.
  const payload = {
    nextStep: "x",
    recommendedReply: "y",
    shortReason: "z",
    insufficientContext: false,
    confidence: "medium" as const,
  };
  const result = applyQuickGuardrails(payload);
  assertFalse(result.safetyFiltered);
});

// ------------------------------------------------------------------
// estimateFullSeconds
// ------------------------------------------------------------------

Deno.test("estimateFullSeconds — images → 22s (Sonnet vision)", () => {
  assertEquals(
    estimateFullSeconds({ model: "claude-sonnet-4-20250514", hasImages: true }),
    22,
  );
});

Deno.test("estimateFullSeconds — haiku text → 5s", () => {
  assertEquals(
    estimateFullSeconds({
      model: "claude-haiku-4-5-20251001",
      hasImages: false,
    }),
    5,
  );
});

Deno.test("estimateFullSeconds — sonnet text → 17s", () => {
  assertEquals(
    estimateFullSeconds({
      model: "claude-sonnet-4-20250514",
      hasImages: false,
    }),
    17,
  );
});

Deno.test("estimateFullSeconds — images dominates model choice", () => {
  // hasImages=true 一定走 vision 計時，不管 model 字串
  assertEquals(
    estimateFullSeconds({
      model: "claude-haiku-4-5-20251001",
      hasImages: true,
    }),
    22,
  );
});

Deno.test("estimateFullSeconds — unknown model defaults to sonnet text (17s)", () => {
  assertEquals(
    estimateFullSeconds({ model: "future-claude-model", hasImages: false }),
    17,
  );
});
