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

import {
  calibrateEnthusiasmScore,
  enforceReplySegmentSourceContract,
  extractPartnerBallList,
  postProcessAnalysisResult,
  sanitizeReplies,
  sanitizeReplySegments,
  stripForeignScriptChars,
} from "./post_process.ts";

Deno.test("calibrateEnthusiasmScore applies 0.9 and rounds fractions up", () => {
  assertEquals(calibrateEnthusiasmScore(82), 74);
  assertEquals(calibrateEnthusiasmScore(65), 59);
  assertEquals(calibrateEnthusiasmScore(1), 1);
  assertEquals(calibrateEnthusiasmScore(0), 0);
  assertEquals(calibrateEnthusiasmScore(100), 90);
  assertEquals(calibrateEnthusiasmScore(120), 90);
  assertEquals(calibrateEnthusiasmScore(-10), 0);
  assertEquals(calibrateEnthusiasmScore(null), null);
  assertEquals(calibrateEnthusiasmScore(""), null);
});

Deno.test("postProcess returns the calibrated enthusiasm score", () => {
  const input = buildBaseResult();
  input.enthusiasm = { score: 82, level: "very_hot" };

  const result = postProcessAnalysisResult({
    result: input,
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: ESSENTIAL_FEATURES,
  });

  assertEquals(
    (result.enthusiasm as Record<string, unknown>).score,
    74,
  );
});

Deno.test("targetProfile：貼圖／emoji 不能被包裝成寵物興趣", () => {
  const input = buildBaseResult();
  input.targetProfile = {
    interests: [{
      value: "寵物互動玩笑",
      evidence: ["🐶", "狗狗貼圖"],
    }],
    traits: [],
    notes: [],
  };

  const result = postProcessAnalysisResult({
    result: input,
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: ESSENTIAL_FEATURES,
    requestMessages: [
      { isFromMe: false, content: "🐶" },
      { isFromMe: false, content: "狗狗貼圖" },
      { isFromMe: true, content: "哈哈" },
    ],
  });

  assertEquals(result.targetProfile, {
    provenanceVersion: 1,
    interests: [],
    traits: [],
    notes: [],
    evidence: { interests: [], traits: [], notes: [] },
  });
});

Deno.test("targetProfile：一餐與本輪連發都不是穩定興趣／人格", () => {
  const input = buildBaseResult();
  input.targetProfile = {
    interests: [{
      value: "茄汁牛肉飯",
      evidence: ["今天終於吃到想吃的茄汁牛肉飯"],
    }],
    traits: [{
      value: "幽默自信",
      evidence: ["肯定是看我有禮貌又可愛", "今天終於吃到了嗎"],
    }],
    notes: [],
  };

  const result = postProcessAnalysisResult({
    result: input,
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: ESSENTIAL_FEATURES,
    requestMessages: [
      { isFromMe: false, content: "肯定是看我有禮貌又可愛" },
      { isFromMe: false, content: "今天終於吃到了嗎" },
      { isFromMe: false, content: "今天終於吃到想吃的茄汁牛肉飯" },
    ],
  });

  const profile = result.targetProfile as Record<string, unknown>;
  assertEquals(profile.interests, []);
  assertEquals(profile.traits, []);
});

Deno.test("targetProfile：不能拿我方訊息當她的證據", () => {
  const input = buildBaseResult();
  input.targetProfile = {
    interests: [{ value: "養狗", evidence: ["我每週都會帶狗散步"] }],
    traits: [],
    notes: [],
  };
  const result = postProcessAnalysisResult({
    result: input,
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: ESSENTIAL_FEATURES,
    requestMessages: [{
      isFromMe: true,
      content: "我每週都會帶狗散步",
    }],
  });

  assertEquals(
    (result.targetProfile as Record<string, unknown>).interests,
    [],
  );
});

Deno.test("targetProfile：只保留能對回她文字原句的穩定資料與出處", () => {
  const input = buildBaseResult();
  input.targetProfile = {
    interests: [{
      value: "爬山",
      evidence: ["我每個週末都會去爬山"],
    }],
    traits: [{
      value: "慢熱",
      evidence: ["我其實很慢熱"],
    }],
    notes: [{
      value: "不喜歡聊工作",
      evidence: ["我不喜歡一直聊工作"],
    }],
  };

  const result = postProcessAnalysisResult({
    result: input,
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: ESSENTIAL_FEATURES,
    requestMessages: [
      { isFromMe: false, content: "我每個週末都會去爬山" },
      { isFromMe: true, content: "感覺很健康" },
      { isFromMe: false, content: "我其實很慢熱" },
      { isFromMe: true, content: "慢慢來就好" },
      { isFromMe: false, content: "我不喜歡一直聊工作" },
    ],
  });

  const profile = result.targetProfile as Record<string, unknown>;
  assertEquals(profile.provenanceVersion, 1);
  assertEquals(profile.interests, ["爬山"]);
  assertEquals(profile.traits, ["慢熱"]);
  assertEquals(profile.notes, ["不喜歡聊工作"]);
  assertEquals(profile.evidence, {
    interests: [{
      value: "爬山",
      sourceMessages: ["我每個週末都會去爬山"],
    }],
    traits: [{
      value: "慢熱",
      sourceMessages: ["我其實很慢熱"],
    }],
    notes: [{
      value: "不喜歡聊工作",
      sourceMessages: ["我不喜歡一直聊工作"],
    }],
  });
});

Deno.test("targetProfile：提到喜歡某種人格，不等於她本人有該人格", () => {
  const input = buildBaseResult();
  input.targetProfile = {
    interests: [],
    traits: [{
      value: "幽默",
      evidence: ["我喜歡幽默的人"],
    }],
    notes: [],
  };

  const result = postProcessAnalysisResult({
    result: input,
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: ESSENTIAL_FEATURES,
    requestMessages: [{ isFromMe: false, content: "我喜歡幽默的人" }],
  });

  assertEquals(
    (result.targetProfile as Record<string, unknown>).traits,
    [],
  );
});

Deno.test("targetProfile：跨回合兩句無關原文也不能升格成推測人格", () => {
  const input = buildBaseResult();
  input.targetProfile = {
    interests: [],
    traits: [{
      value: "幽默自信",
      evidence: ["今天天氣不錯", "我待會要去吃飯"],
    }],
    notes: [],
  };

  const result = postProcessAnalysisResult({
    result: input,
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: ESSENTIAL_FEATURES,
    requestMessages: [
      { isFromMe: false, content: "今天天氣不錯" },
      { isFromMe: true, content: "真的，終於放晴了" },
      { isFromMe: false, content: "我待會要去吃飯" },
    ],
  });

  assertEquals(
    (result.targetProfile as Record<string, unknown>).traits,
    [],
  );
});

Deno.test("targetProfile：超愛／最愛是明確興趣自述", () => {
  for (
    const [value, message] of [
      ["潛水", "我超愛潛水"],
      ["爬山", "我最愛爬山"],
    ]
  ) {
    const input = buildBaseResult();
    input.targetProfile = {
      interests: [{ value, evidence: [message] }],
      traits: [],
      notes: [],
    };

    const result = postProcessAnalysisResult({
      result: input,
      recognizeOnly: false,
      isMyMessageMode: false,
      allowedFeatures: ESSENTIAL_FEATURES,
      requestMessages: [{ isFromMe: false, content: message }],
    });

    assertEquals(
      (result.targetProfile as Record<string, unknown>).interests,
      [value],
    );
  }
});

Deno.test("targetProfile：同句否定爬山不應誤刪明講喜歡的潛水", () => {
  const input = buildBaseResult();
  const message = "我不喜歡爬山，我喜歡潛水";
  input.targetProfile = {
    interests: [{ value: "潛水", evidence: [message] }],
    traits: [],
    notes: [],
  };

  const result = postProcessAnalysisResult({
    result: input,
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: ESSENTIAL_FEATURES,
    requestMessages: [{ isFromMe: false, content: message }],
  });

  assertEquals(
    (result.targetProfile as Record<string, unknown>).interests,
    ["潛水"],
  );
});

Deno.test("targetProfile：值後面的否定不能被反向當成興趣自述", () => {
  const input = buildBaseResult();
  const message = "潛水我不喜歡";
  input.targetProfile = {
    interests: [{ value: "潛水", evidence: [message] }],
    traits: [],
    notes: [],
  };

  const result = postProcessAnalysisResult({
    result: input,
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: ESSENTIAL_FEATURES,
    requestMessages: [{ isFromMe: false, content: message }],
  });

  assertEquals(
    (result.targetProfile as Record<string, unknown>).interests,
    [],
  );
});

Deno.test("targetProfile：別句的喜歡不能替無關主題提供興趣證據", () => {
  const input = buildBaseResult();
  const message = "我喜歡爬山，但潛水很危險";
  input.targetProfile = {
    interests: [{ value: "潛水", evidence: [message] }],
    traits: [],
    notes: [],
  };

  const result = postProcessAnalysisResult({
    result: input,
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: ESSENTIAL_FEATURES,
    requestMessages: [{ isFromMe: false, content: message }],
  });

  assertEquals(
    (result.targetProfile as Record<string, unknown>).interests,
    [],
  );
});

Deno.test("targetProfile：明講不喜歡的主題只能是邊界，不能變成興趣", () => {
  const input = buildBaseResult();
  input.targetProfile = {
    interests: [{
      value: "工作",
      evidence: ["我不喜歡一直聊工作"],
    }],
    traits: [],
    notes: [{
      value: "不喜歡聊工作",
      evidence: ["我不喜歡一直聊工作"],
    }],
  };

  const result = postProcessAnalysisResult({
    result: input,
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: ESSENTIAL_FEATURES,
    requestMessages: [{ isFromMe: false, content: "我不喜歡一直聊工作" }],
  });

  const profile = result.targetProfile as Record<string, unknown>;
  assertEquals(profile.interests, []);
  assertEquals(profile.notes, ["不喜歡聊工作"]);
});

Deno.test("targetProfile：舊式字串陣列沒有出處，一律不升格成可信記憶", () => {
  const input = buildBaseResult();
  input.targetProfile = {
    interests: ["寵物互動玩笑"],
    traits: ["幽默自信"],
    notes: ["她喜歡狗"],
  };

  const result = postProcessAnalysisResult({
    result: input,
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: ESSENTIAL_FEATURES,
    requestMessages: [{ isFromMe: false, content: "🐶" }],
  });

  const profile = result.targetProfile as Record<string, unknown>;
  assertEquals(profile.interests, []);
  assertEquals(profile.traits, []);
  assertEquals(profile.notes, []);
});

// Mirror of TIER_FEATURES from index.ts. If the tier definition there
// changes, update this fixture too.
const FREE_FEATURES = ["extend", "tease"];
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

Deno.test("postProcess: replies are filtered to allowedFeatures (Free → extend + tease)", () => {
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
    ["extend", "tease"],
    "Free tier replies must contain only 'extend' and 'tease'",
  );
  assertFalse("resonate" in replies, "Paid 'resonate' reply must not leak");
  assert("tease" in replies, "Free 'tease' reply must be preserved");
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

Deno.test("postProcess: stretchLevels filtered to allowedFeatures like replies (Free → extend + tease)", () => {
  const raw = buildBaseResult();
  raw.stretchLevels = {
    extend: "within",
    resonate: "stretch",
    tease: "far",
    humor: "stretch",
    coldRead: "within",
  };

  const result = postProcessAnalysisResult({
    result: raw,
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: FREE_FEATURES,
  });

  const stretchLevels = result.stretchLevels as Record<string, string>;
  assertEquals(Object.keys(stretchLevels).sort(), ["extend", "tease"]);
  assertEquals(stretchLevels.extend, "within");
  assertEquals(stretchLevels.tease, "far");
  assertFalse("resonate" in stretchLevels, "Paid stretchLevel must not leak");
  assertFalse("humor" in stretchLevels, "Paid stretchLevel must not leak");
});

Deno.test("postProcess: stretchLevels missing entirely or holding illegal values fallback to within (single-source normalizeStretchLevels, not a third parallel impl)", () => {
  // Case A: AI omitted stretchLevels entirely — must not just leave the
  // field absent; every allowed style falls back to "within".
  const missing = postProcessAnalysisResult({
    result: buildBaseResult(),
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: ESSENTIAL_FEATURES,
  });
  const missingLevels = missing.stretchLevels as Record<string, string>;
  assertEquals(missingLevels, {
    extend: "within",
    resonate: "within",
    tease: "within",
    humor: "within",
    coldRead: "within",
  });

  // Case B: AI gave illegal values for some keys — those fall back to
  // "within" rather than leaking a garbage string or dropping the key.
  const raw = buildBaseResult();
  raw.stretchLevels = {
    extend: "stretch",
    resonate: "way-too-far",
    tease: 42,
  };
  const result = postProcessAnalysisResult({
    result: raw,
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: ESSENTIAL_FEATURES,
  });
  const levels = result.stretchLevels as Record<string, string>;
  assertEquals(levels.extend, "stretch");
  assertEquals(levels.resonate, "within");
  assertEquals(levels.tease, "within");
  assertEquals(levels.humor, "within");
  assertEquals(levels.coldRead, "within");
});

// ---------------------------------------------------------------------------
// Parity test 3 — finalRecommendation normalize / fallback
// ---------------------------------------------------------------------------

Deno.test("postProcess: finalRecommendation falls back to extend when AI pick is not allowed", () => {
  // Model picked 'resonate', but Free tier only has extend + tease. Helper must
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

// ---------------------------------------------------------------------------
// #12 一球一回 — extractPartnerBallList + enforceReplySegmentSourceContract
//
// 球清單 = 對方這一輪連發（trailing partner run），1-based。
// 三層缺 source 規則：回查修復 → drop 該段 → 全 drop 回退單段 content。
// ---------------------------------------------------------------------------

Deno.test("extractPartnerBallList takes trailing partner run from request messages", () => {
  const balls = extractPartnerBallList({
    requestMessages: [
      { isFromMe: true, content: "我先說一句" },
      { isFromMe: false, content: "紅牛跟賓士差點打起來XD" },
      { isFromMe: false, content: "剛來吃晚餐" },
      { isFromMe: false, content: "等等要去樂華夜市" },
    ],
  });
  assertEquals(balls, [
    "紅牛跟賓士差點打起來XD",
    "剛來吃晚餐",
    "等等要去樂華夜市",
  ]);
});

Deno.test("extractPartnerBallList prefers recognizedConversation over request messages", () => {
  const balls = extractPartnerBallList({
    result: {
      recognizedConversation: {
        messages: [
          { isFromMe: false, content: "OCR 球一" },
          { isFromMe: false, content: "OCR 球二" },
        ],
      },
    },
    requestMessages: [{ isFromMe: false, content: "request 球" }],
  });
  assertEquals(balls, ["OCR 球一", "OCR 球二"]);
});

Deno.test("extractPartnerBallList falls back to last partner messages when trailing run is mine", () => {
  const balls = extractPartnerBallList({
    requestMessages: [
      { isFromMe: false, content: "她的舊球" },
      { isFromMe: true, content: "我剛回了一句" },
    ],
  });
  assertEquals(balls, ["她的舊球"]);
});

Deno.test("source contract layer 1: invalid sourceIndex repaired by text lookup", () => {
  const repaired = enforceReplySegmentSourceContract(
    [{
      sourceIndex: 99,
      label: "",
      sourceMessage: "剛來吃晚餐",
      reply: "回吃飯球",
      reason: "",
    }],
    ["紅牛跟賓士差點打起來XD", "剛來吃晚餐"],
  );
  assertEquals(repaired.length, 1);
  assertEquals(repaired[0].sourceIndex, 2);
});

Deno.test("source contract layer 1b: valid sourceIndex backfills empty sourceMessage", () => {
  const repaired = enforceReplySegmentSourceContract(
    [{
      sourceIndex: 1,
      label: "",
      sourceMessage: "",
      reply: "回 F1 球",
      reason: "",
    }],
    ["紅牛跟賓士差點打起來XD"],
  );
  assertEquals(repaired.length, 1);
  assertEquals(repaired[0].sourceMessage, "紅牛跟賓士差點打起來XD");
});

Deno.test("source contract layer 2: unrepairable segment is dropped", () => {
  const repaired = enforceReplySegmentSourceContract(
    [
      { label: "", sourceMessage: "", reply: "沒 source 的段", reason: "" },
      {
        sourceIndex: 1,
        label: "",
        sourceMessage: "球一",
        reply: "好段",
        reason: "",
      },
    ],
    ["球一"],
  );
  assertEquals(repaired.length, 1);
  assertEquals(repaired[0].reply, "好段");
});

Deno.test("source contract: empty ball list keeps well-formed segments, drops empty-source ones", () => {
  const repaired = enforceReplySegmentSourceContract(
    [
      {
        sourceIndex: 2,
        label: "",
        sourceMessage: "她的原句",
        reply: "保留",
        reason: "",
      },
      { label: "", sourceMessage: "", reply: "丟棄", reason: "" },
    ],
    [],
  );
  assertEquals(repaired.length, 1);
  assertEquals(repaired[0].reply, "保留");
});

Deno.test("postProcess repairs finalRecommendation segment sources against ball list", () => {
  const result = postProcessAnalysisResult({
    result: {
      replies: { extend: "合併版" },
      finalRecommendation: {
        pick: "extend",
        content: "合併版",
        reason: "r",
        psychology: "p",
        replySegments: [
          { sourceMessage: "剛來吃晚餐", reply: "回吃飯球", reason: "" },
          {
            sourceIndex: 3,
            sourceMessage: "等等要去樂華夜市",
            reply: "回夜市球",
            reason: "",
          },
        ],
      },
    },
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: ["extend"],
    requestMessages: [
      { isFromMe: false, content: "紅牛跟賓士差點打起來XD" },
      { isFromMe: false, content: "剛來吃晚餐" },
      { isFromMe: false, content: "等等要去樂華夜市" },
    ],
  });
  const rec = result.finalRecommendation as Record<string, unknown>;
  const segments = rec.replySegments as Array<Record<string, unknown>>;
  assertEquals(segments.length, 2);
  assertEquals(segments[0].sourceIndex, 2); // 文字回查修復
  assertEquals(segments[1].sourceIndex, 3); // 原本就合法
});

Deno.test("postProcess layer 3: all segments dropped falls back to merged content, never empty-source segments", () => {
  const result = postProcessAnalysisResult({
    result: {
      replies: {},
      finalRecommendation: {
        pick: "extend",
        content: "",
        reason: "r",
        psychology: "p",
        replySegments: [
          { sourceMessage: "", reply: "第一段", reason: "" },
          { sourceMessage: "", reply: "第二段", reason: "" },
        ],
      },
    },
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: ["extend"],
    requestMessages: [{ isFromMe: false, content: "她的球" }],
  });
  const rec = result.finalRecommendation as Record<string, unknown>;
  // 第三層不變量：空 source 段絕不流出 server。
  assertEquals((rec.replySegments as unknown[]).length, 0);
  // 現狀單段行為：content 仍非空可用（replies 空時走 safe-reply 回填，
  // 為既有 precedence——replies[pick] 優先於 segment 合併版）。
  assert((rec.content as string).trim().length > 0);
});

Deno.test("postProcess keeps newline-joined segment content when replies lack the pick (規格 #4 換行 join)", () => {
  const result = postProcessAnalysisResult({
    result: {
      replies: { extend: "" },
      replyOptions: {},
      finalRecommendation: {
        pick: "extend",
        content: "",
        reason: "r",
        psychology: "p",
        replySegments: [
          {
            sourceIndex: 1,
            sourceMessage: "球一",
            reply: "第一段",
            reason: "",
          },
          {
            sourceIndex: 2,
            sourceMessage: "球二",
            reply: "第二段",
            reason: "",
          },
        ],
      },
    },
    recognizeOnly: true, // 跳過 ensureNonEmpty 的 safe-reply 回填，直驗 Step 3 join
    isMyMessageMode: false,
    allowedFeatures: ["extend"],
  });
  const rec = result.finalRecommendation as Record<string, unknown>;
  // 規格 #4：合併版用換行 join，不用逗點。
  assertEquals(rec.content, "第一段\n第二段");
});

// ---------------------------------------------------------------------------
// #12 Codex 實作雙審 r1 — 兩 P2 修訂
// ---------------------------------------------------------------------------

Deno.test("r1-P2a: multi-segment content prefers newline join over comma-joined replies[pick]", () => {
  const result = postProcessAnalysisResult({
    result: {
      replies: { extend: "回F1球，回夜市球，全部擠成一句" },
      finalRecommendation: {
        pick: "extend",
        content: "",
        reason: "r",
        psychology: "p",
        replySegments: [
          {
            sourceIndex: 1,
            sourceMessage: "紅牛跟賓士差點打起來XD",
            reply: "回F1球",
            reason: "",
          },
          {
            sourceIndex: 2,
            sourceMessage: "等等要去樂華夜市",
            reply: "回夜市球",
            reason: "",
          },
        ],
      },
    },
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: ["extend"],
    requestMessages: [
      { isFromMe: false, content: "紅牛跟賓士差點打起來XD" },
      { isFromMe: false, content: "等等要去樂華夜市" },
    ],
  });
  const rec = result.finalRecommendation as Record<string, unknown>;
  // 規格 #4：多球時舊 client 合併版必須是段落換行 join，不是逗點 replies。
  assertEquals(rec.content, "回F1球\n回夜市球");
});

Deno.test("r1-P2a guard: single segment keeps existing replies[pick] precedence (N=1 現狀)", () => {
  const result = postProcessAnalysisResult({
    result: {
      replies: { extend: "replies 的單球版本" },
      finalRecommendation: {
        pick: "extend",
        content: "",
        reason: "r",
        psychology: "p",
        replySegments: [
          {
            sourceIndex: 1,
            sourceMessage: "她的球",
            reply: "segment 的單球版本",
            reason: "",
          },
        ],
      },
    },
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: ["extend"],
    requestMessages: [{ isFromMe: false, content: "她的球" }],
  });
  const rec = result.finalRecommendation as Record<string, unknown>;
  assertEquals(rec.content, "replies 的單球版本");
});

Deno.test("r1-P2b: mismatched sourceMessage pointing at another ball corrects sourceIndex", () => {
  const repaired = enforceReplySegmentSourceContract(
    [{
      sourceIndex: 1,
      label: "",
      sourceMessage: "等等要去樂華夜市",
      reply: "回夜市球",
      reason: "",
    }],
    ["紅牛跟賓士差點打起來XD", "等等要去樂華夜市"],
  );
  assertEquals(repaired.length, 1);
  // message 是 UI 引用主鍵 → 信 message、修 index。
  assertEquals(repaired[0].sourceIndex, 2);
});

Deno.test("r1-P2b: hallucinated sourceMessage canonicalized from indexed ball", () => {
  const repaired = enforceReplySegmentSourceContract(
    [{
      sourceIndex: 1,
      label: "",
      sourceMessage: "模型幻覺出來的引用",
      reply: "回球",
      reason: "",
    }],
    ["紅牛跟賓士差點打起來XD"],
  );
  assertEquals(repaired.length, 1);
  // 匹配不到任何球 → 以 index 球回填真實原句，絕不流出幻覺引用。
  assertEquals(repaired[0].sourceMessage, "紅牛跟賓士差點打起來XD");
});

// ---------------------------------------------------------------------------
// 方案二件5 contract 堵漏 — 併球 sourceMessage 唯一性
//
// #12 調查實測：模型把兩顆球串成「球A / 球B」當 sourceMessage，
// containment 對每顆球都成立 → 舊 matchBallIndex 取第一個匹配放行。
// 新規則：containment 同時匹配 ≥2 顆不同的球 = 併球指紋 → 不放行；
// 有合法 sourceIndex 則回填該球正典原文，否則丟段。
// ---------------------------------------------------------------------------

Deno.test("件1: sanitizeReplySegments keeps up to 5 segments (cap 3→5)", () => {
  const result = postProcessAnalysisResult({
    result: {
      replies: { extend: "五段合併版" },
      finalRecommendation: {
        pick: "extend",
        content: "五段合併版",
        reason: "r",
        psychology: "p",
        replySegments: [1, 2, 3, 4, 5].map((n) => ({
          sourceIndex: n,
          sourceMessage: `球${n}`,
          reply: `回球${n}`,
          reason: "",
        })),
      },
    },
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: ["extend"],
    requestMessages: [1, 2, 3, 4, 5].map((n) => ({
      isFromMe: false,
      content: `球${n}`,
    })),
  });
  const rec = result.finalRecommendation as Record<string, unknown>;
  assertEquals((rec.replySegments as unknown[]).length, 5);
});

Deno.test("件5: merged-ball sourceMessage with invalid index is dropped, not repaired", () => {
  const repaired = enforceReplySegmentSourceContract(
    [{
      label: "",
      sourceMessage: "剛來吃晚餐 / 等等要去樂華夜市",
      reply: "晚餐有吃飽嗎？等等夜市幫我吃份地瓜球",
      reason: "",
    }],
    ["紅牛跟賓士差點打起來XD", "剛來吃晚餐", "等等要去樂華夜市"],
  );
  // 併球指紋匹配到 2 顆球 → ambiguous，不得修出任一 sourceIndex 放行。
  assertEquals(repaired.length, 0);
});

Deno.test("件5: merged-ball sourceMessage with valid index backfills canonical ball text", () => {
  const repaired = enforceReplySegmentSourceContract(
    [{
      sourceIndex: 2,
      label: "",
      sourceMessage: "剛來吃晚餐 / 等等要去樂華夜市",
      reply: "晚餐有吃飽嗎",
      reason: "",
    }],
    ["紅牛跟賓士差點打起來XD", "剛來吃晚餐", "等等要去樂華夜市"],
  );
  // index 合法但 message 是併球指紋 → 信 index、回填正典單球原文。
  assertEquals(repaired.length, 1);
  assertEquals(repaired[0].sourceIndex, 2);
  assertEquals(repaired[0].sourceMessage, "剛來吃晚餐");
});

Deno.test("件5 guard: exact-equal sourceMessage wins over containment overlap", () => {
  // 球二是球一的子字串（OCR 重疊球會出現）：整句引用球一不該被判 ambiguous。
  const repaired = enforceReplySegmentSourceContract(
    [{
      sourceIndex: 99,
      label: "",
      sourceMessage: "剛到家了好累",
      reply: "回球",
      reason: "",
    }],
    ["剛到家了好累", "到家了"],
  );
  assertEquals(repaired.length, 1);
  assertEquals(repaired[0].sourceIndex, 1);
});

Deno.test("r1-P2b guard: fragment sourceMessage matching its own ball passes unchanged", () => {
  const repaired = enforceReplySegmentSourceContract(
    [{
      sourceIndex: 1,
      label: "",
      sourceMessage: "紅牛跟賓士",
      reply: "回球",
      reason: "",
    }],
    ["紅牛跟賓士差點打起來XD"],
  );
  assertEquals(repaired.length, 1);
  assertEquals(repaired[0].sourceIndex, 1);
  assertEquals(repaired[0].sourceMessage, "紅牛跟賓士");
});

Deno.test("stripForeignScriptChars 清外語洩漏、保中英 emoji 與の", () => {
  // 2026-08-17 Eric 實測：冷讀卡混出俄文「простее」。含外語的整個子句
  // 要丟掉，不是只摳詞——摳詞會留缺謂語的殘句。
  assertEquals(
    stripForeignScriptChars(
      "妳下課後直接來找我，應該比妳自己糾結怎麼約простее",
    ),
    "妳下課後直接來找我",
  );
  // 整段只剩外語子句時退回摳字，寧可短也不要空。
  assertEquals(
    stripForeignScriptChars("應該比妳自己糾結怎麼約простее"),
    "應該比妳自己糾結怎麼約",
  );
  assertEquals(stripForeignScriptChars("안녕 妳好 สวัสดี"), "妳好");
  // 白名單全保留：中文、英文、數字、emoji、假名（台灣常見の）、換行。
  assertEquals(
    stripForeignScriptChars("週五 7 點的 F1 派對🔥 妳の行程\nOK?"),
    "週五 7 點的 F1 派對🔥 妳の行程\nOK?",
  );
});

Deno.test("外語清洗只套生成欄位：reply 清、sourceMessage 引用原文不清", () => {
  const segments = sanitizeReplySegments([
    {
      sourceIndex: 1,
      label: "接她的行程простое",
      sourceMessage: "오늘 뭐해?（她原文就是韓文）",
      reply: "妳下課後直接來找我простее",
      reason: "降低她的糾結",
    },
  ]);
  assertEquals(segments.length, 1);
  assertEquals(segments[0].reply, "妳下課後直接來找我");
  assertEquals(segments[0].label, "接她的行程");
  // 引用對方原文的欄位原樣保留。
  assert(segments[0].sourceMessage.includes("오늘 뭐해?"));

  const replies = sanitizeReplies(
    { extend: "我們要怎麼約～妳來找我простее" },
    ["extend"],
  );
  assertEquals(replies.extend, "我們要怎麼約～妳來找我");
});

// ---------------------------------------------------------------------------
// Step 3b — 風格卡則數對齊最終建議（2026-08-17）
// ---------------------------------------------------------------------------

Deno.test("Step 3b: style card messages trimmed to final replySegments count", () => {
  const twoSegments = [1, 2].map((n) => ({
    sourceIndex: n,
    sourceMessage: `球${n}`,
    reply: `回球${n}`,
    reason: "",
  }));
  const result = postProcessAnalysisResult({
    result: {
      replies: { extend: "回球1\n回球2", coldRead: "冷1, 冷2, 冷3" },
      replyOptions: {
        extend: { approach: "接法", messages: twoSegments },
        coldRead: {
          approach: "冷讀接法",
          messages: [1, 2, 3].map((n) => ({
            sourceIndex: Math.min(n, 2),
            sourceMessage: `球${Math.min(n, 2)}`,
            reply: `冷${n}`,
            reason: "",
          })),
        },
      },
      finalRecommendation: {
        pick: "extend",
        content: "回球1\n回球2",
        reason: "r",
        psychology: "p",
        replySegments: twoSegments,
      },
    },
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: ["extend", "coldRead"],
    requestMessages: [1, 2].map((n) => ({
      isFromMe: false,
      content: `球${n}`,
    })),
  });
  const rec = result.finalRecommendation as Record<string, unknown>;
  assertEquals((rec.replySegments as unknown[]).length, 2);
  const options = result.replyOptions as Record<
    string,
    { messages: { reply: string }[] }
  >;
  // 多噴的第 3 則被裁掉，與最終建議同段數
  assertEquals(options.coldRead.messages.length, 2);
  assertEquals(options.extend.messages.length, 2);
  // 舊 client 合併版同步重建
  const replies = result.replies as Record<string, string>;
  assertEquals(replies.coldRead, "冷1\n冷2");
});

Deno.test("Step 3b: style card with fewer messages than final count is left as-is", () => {
  const twoSegments = [1, 2].map((n) => ({
    sourceIndex: n,
    sourceMessage: `球${n}`,
    reply: `回球${n}`,
    reason: "",
  }));
  const result = postProcessAnalysisResult({
    result: {
      replies: { extend: "回球1\n回球2", humor: "只有一句" },
      replyOptions: {
        extend: { approach: "接法", messages: twoSegments },
        humor: {
          approach: "幽默接法",
          messages: [{
            sourceIndex: 1,
            sourceMessage: "球1",
            reply: "只有一句",
            reason: "",
          }],
        },
      },
      finalRecommendation: {
        pick: "extend",
        content: "回球1\n回球2",
        reason: "r",
        psychology: "p",
        replySegments: twoSegments,
      },
    },
    recognizeOnly: false,
    isMyMessageMode: false,
    allowedFeatures: ["extend", "humor"],
    requestMessages: [1, 2].map((n) => ({
      isFromMe: false,
      content: `球${n}`,
    })),
  });
  const options = result.replyOptions as Record<
    string,
    { messages: { reply: string }[] }
  >;
  // 無法無中生有補段：少的維持原樣
  assertEquals(options.humor.messages.length, 1);
  const replies = result.replies as Record<string, string>;
  assertEquals(replies.humor, "只有一句");
});
