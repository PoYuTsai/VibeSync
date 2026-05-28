// supabase/functions/analyze-chat/post_process_test.ts
//
// Parity tests for the shared post-processing helper.
//
// Codex Phase 2 P1 — full mode previously bypassed legacy post-processing,
// causing entitlement leaks (Free users receiving healthCheck) and missing
// normalization. These tests pin the contract so any future divergence
// between modes will fail loudly.
//
// The helper itself is mode-agnostic; legacy and full branches both call it
// with the same args, so unit-testing the helper IS the parity test. The
// fixtures mirror the TIER_FEATURES table in index.ts.

import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

import { postProcessAnalysisResult } from "./post_process.ts";

// Mirror of TIER_FEATURES from index.ts. If the tier definition there
// changes, update this fixture too.
const FREE_FEATURES = ["extend"];
const ESSENTIAL_FEATURES = [
  "extend",
  "resonate",
  "tease",
  "humor",
  "coldRead",
  "needy_warning",
  "topic_depth",
  "health_check",
];

// Realistic-ish raw Claude payload for analysis.
function buildBaseResult(): Record<string, unknown> {
  return {
    enthusiasm: { score: 65 },
    replies: {
      extend: "那聽起來蠻有畫面的，後來有去成嗎？",
      resonate: "工作真的會累到不想動，先休息一下沒關係。",
      tease: "你這樣講我懷疑你只是想偷懶 XD",
      humor: "聽起來像是需要被人騙出去吃宵夜。",
      coldRead: "感覺你最近真的把自己排得太滿。",
    },
    replyOptions: {
      extend: {
        approach: "順著她剛說的點再帶一步",
        messages: [
          {
            label: "建議訊息",
            sourceMessage: "我今天好累",
            reply: "那聽起來蠻有畫面的，後來有去成嗎？",
            reason: "保持低壓延展",
          },
        ],
      },
    },
    finalRecommendation: {
      pick: "resonate",
      content: "工作真的會累到不想動，先休息一下沒關係。",
      reason: "她明顯在發洩疲憊，先接住情緒。",
      psychology: "被理解的感覺比建議重要。",
      replySegments: [],
    },
    coachActionHint: {
      catchablePoint: "她吐露今天好累",
      read: "情緒在低點，需要被接住而不是被建議。",
      microMove: "回一句承接，再丟一個低壓提問。",
      avoid: "不要急著給建議或約見面。",
      actionType: "emotionalResonance",
      confidence: "high",
    },
    healthCheck: {
      issues: ["回話偏長"],
      suggestions: ["試著縮短一句話"],
    },
  };
}

// ---------------------------------------------------------------------------
// Parity test 1 — healthCheck entitlement gate (Free strips it)
// ---------------------------------------------------------------------------

Deno.test("postProcess: Free tier strips healthCheck (entitlement gate)", () => {
  const result = postProcessAnalysisResult({
    result: buildBaseResult(),
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: FREE_FEATURES,
  });

  assertFalse(
    "healthCheck" in result,
    "Free tier MUST NOT receive healthCheck (entitlement leak)",
  );
});

Deno.test("postProcess: Essential tier preserves healthCheck", () => {
  const result = postProcessAnalysisResult({
    result: buildBaseResult(),
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: ESSENTIAL_FEATURES,
  });

  assert("healthCheck" in result, "Essential tier should keep healthCheck");
});

// ---------------------------------------------------------------------------
// Parity test 2 — replies filtered to allowedFeatures
// ---------------------------------------------------------------------------

Deno.test("postProcess: replies are filtered to allowedFeatures (Free → extend only)", () => {
  const result = postProcessAnalysisResult({
    result: buildBaseResult(),
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: FREE_FEATURES,
  });

  const replies = result.replies as Record<string, string>;
  const keys = Object.keys(replies);

  assertEquals(
    keys.sort(),
    ["extend"],
    "Free tier replies must contain only 'extend'",
  );
  assertFalse("resonate" in replies, "Paid 'resonate' reply must not leak");
  assertFalse("tease" in replies, "Paid 'tease' reply must not leak");
  assertFalse("humor" in replies, "Paid 'humor' reply must not leak");
  assertFalse("coldRead" in replies, "Paid 'coldRead' reply must not leak");
});

Deno.test("postProcess: Essential tier preserves all reply keys present in payload", () => {
  const result = postProcessAnalysisResult({
    result: buildBaseResult(),
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: ESSENTIAL_FEATURES,
  });

  const replies = result.replies as Record<string, string>;
  assert("extend" in replies);
  assert("resonate" in replies);
  assert("tease" in replies);
  assert("humor" in replies);
  assert("coldRead" in replies);
});

// ---------------------------------------------------------------------------
// Parity test 3 — finalRecommendation normalize / fallback
// ---------------------------------------------------------------------------

Deno.test("postProcess: finalRecommendation falls back to extend when AI pick is not allowed", () => {
  // Model picked 'resonate', but Free tier only has 'extend'. Helper must
  // remap pick to a feature that actually exists in the filtered replies.
  const result = postProcessAnalysisResult({
    result: buildBaseResult(),
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: FREE_FEATURES,
  });

  const finalRec = result.finalRecommendation as Record<string, string>;
  assertEquals(
    finalRec.pick,
    "extend",
    "When original pick is filtered out, pick must remap to an allowed feature",
  );
  // content should come from the remaining 'extend' reply, not the dropped
  // 'resonate' one.
  assertEquals(
    finalRec.content,
    "那聽起來蠻有畫面的，後來有去成嗎？",
    "Content must come from an allowed reply, not the stripped one",
  );
  assert(
    finalRec.reason.length > 0,
    "Reason must be non-empty (fallback text fills it)",
  );
  assert(
    finalRec.psychology.length > 0,
    "Psychology must be non-empty (fallback text fills it)",
  );
});

Deno.test("postProcess: finalRecommendation backfills reason/psychology when AI returns empty strings", () => {
  const base = buildBaseResult();
  (base.finalRecommendation as Record<string, unknown>).reason = "";
  (base.finalRecommendation as Record<string, unknown>).psychology = "";

  const result = postProcessAnalysisResult({
    result: base,
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: ESSENTIAL_FEATURES,
  });

  const finalRec = result.finalRecommendation as Record<string, string>;
  assert(
    finalRec.reason.length > 0,
    "Empty AI reason must be replaced by fallback text",
  );
  assert(
    finalRec.psychology.length > 0,
    "Empty AI psychology must be replaced by fallback text",
  );
});

// ---------------------------------------------------------------------------
// Parity test 4 — coachActionHint sanitize / remove
// ---------------------------------------------------------------------------

Deno.test("postProcess: valid coachActionHint is kept and normalized", () => {
  const result = postProcessAnalysisResult({
    result: buildBaseResult(),
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: ESSENTIAL_FEATURES,
  });

  const hint = result.coachActionHint as Record<string, string>;
  assertEquals(hint.actionType, "emotionalResonance");
  assertEquals(hint.confidence, "high");
  assert(hint.catchablePoint.length > 0);
  assert(hint.microMove.length > 0);
});

Deno.test("postProcess: coachActionHint with missing required field is removed entirely", () => {
  const base = buildBaseResult();
  // Missing microMove makes the hint invalid.
  (base.coachActionHint as Record<string, unknown>).microMove = "";

  const result = postProcessAnalysisResult({
    result: base,
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: ESSENTIAL_FEATURES,
  });

  assertFalse(
    "coachActionHint" in result,
    "Invalid coachActionHint must be removed, not partially kept",
  );
});

Deno.test("postProcess: coachActionHint with unknown actionType is rewritten to default", () => {
  const base = buildBaseResult();
  (base.coachActionHint as Record<string, unknown>).actionType = "notARealType";

  const result = postProcessAnalysisResult({
    result: base,
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: ESSENTIAL_FEATURES,
  });

  const hint = result.coachActionHint as Record<string, string>;
  assertEquals(
    hint.actionType,
    "extendTopicStoryFrame",
    "Unknown actionType must be normalized to the safe default",
  );
});

// ---------------------------------------------------------------------------
// Bonus — recognizeOnly / isMyMessageMode short-circuit
// ---------------------------------------------------------------------------

Deno.test("postProcess: recognizeOnly skips ensureNonEmpty but still gates healthCheck", () => {
  // recognizeOnly used to mean "OCR only, no analysis" — backfill is skipped
  // but the entitlement gate must still apply (otherwise Free could leak
  // healthCheck via this path too).
  const result = postProcessAnalysisResult({
    result: buildBaseResult(),
    recognizeOnly: true,
    isMyMessageMode: false,
    allowedFeatures: FREE_FEATURES,
  });

  assertFalse(
    "healthCheck" in result,
    "healthCheck must be stripped even in recognizeOnly mode for Free tier",
  );
});
