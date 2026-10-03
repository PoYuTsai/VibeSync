import {
  assert,
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import * as learning from "./temperature.ts";
import { resolvePracticeProfile } from "./practice_persona.ts";

// deno-lint-ignore no-explicit-any
type DynamicFn = (...args: any[]) => any;

function requireFn<T extends DynamicFn>(name: string): T {
  const fn = (learning as Record<string, unknown>)[name];
  assertEquals(typeof fn, "function", `${name} should be exported`);
  return fn as T;
}

const safeCaught = {
  connection: "caught",
  impact: "medium",
  testHandling: "none",
  boundary: "safe",
  hintAlignment: "none",
};

Deno.test("relationshipStageFor maps familiarity and heat to user-facing labels", () => {
  const relationshipStageFor = requireFn("relationshipStageFor");

  assertEquals(relationshipStageFor(39, 90).label, "建立熟悉中");
  assertEquals(relationshipStageFor(40, 49).label, "可以聊個人");
  assertEquals(relationshipStageFor(40, 50).label, "可以輕推曖昧");
});

Deno.test("applyLearningClassification rewards catching her latest emotion in the familiarity-building stage", () => {
  const applyLearningClassification = requireFn("applyLearningClassification");

  const result = applyLearningClassification(
    { heatScore: 30, familiarityScore: 10 },
    safeCaught,
  );

  assertEquals(result.score, 34);
  assertEquals(result.delta, 4);
  assertEquals(result.familiarityScore, 15);
  assertEquals(result.familiarityDelta, 5);
  assertEquals(result.stageLabel, "建立熟悉中");
  assert(result.reason.includes("接住"));
});

// 新手獎勵閘門（PR 2 修 D2；PR #88 擴大）：閘門不適用的呼叫端（Game、熱度
// ≤40 的 easy）低壓 neutral 照舊 +1；套閘門後無正向證據夾到 0。
Deno.test("low-pressure neutral replies stay +1 ungated but the challenge gate zeroes them", () => {
  const applyLearningClassification = requireFn("applyLearningClassification");
  const applyChallengeRewardGate = requireFn("applyChallengeRewardGate");

  const neutralMinor = {
    connection: "neutral",
    impact: "minor",
    testHandling: "none",
    boundary: "safe",
    hintAlignment: "none",
  };
  const ungated = applyLearningClassification(
    { heatScore: 30, familiarityScore: 10 },
    neutralMinor,
  );

  assertEquals(ungated.score, 31);
  assertEquals(ungated.delta, 1);
  assertEquals(ungated.familiarityScore, 11);
  assertEquals(ungated.familiarityDelta, 1);

  const gated = applyChallengeRewardGate({
    judgement: ungated,
    currentHeat: 30,
    currentFamiliarity: 10,
    classification: neutralMinor,
  });

  assertEquals(gated.score, 30);
  assertEquals(gated.delta, 0);
  assertEquals(gated.familiarityScore, 10);
  assertEquals(gated.familiarityDelta, 0);
});

// PR #88 A（Eric 2026-10-03 決定 1）：閘門適用範圍。easy 看這一輪開始前的熱度，
// ≤40（frozen／cold 檔）不套；Game 與 standard 永遠不套（Game 有自己的閘門）。
Deno.test("beginnerRewardGateActive covers challenge, normal and easy above heat 40 only", () => {
  const beginnerRewardGateActive = requireFn("beginnerRewardGateActive");
  const cases: Array<
    [string | undefined, string | undefined, number, boolean]
  > = [
    ["beginner", "challenge", 0, true],
    ["beginner", "challenge", 100, true],
    ["beginner", "normal", 0, true],
    ["beginner", "normal", 100, true],
    ["beginner", "easy", 0, false],
    ["beginner", "easy", 40, false],
    ["beginner", "easy", 40.4, false],
    ["beginner", "easy", 41, true],
    ["beginner", "easy", 100, true],
    // 不認得的難度比照 normal（difficultyTuningFor 的預設）。
    ["beginner", undefined, 10, true],
    ["game", "easy", 60, false],
    ["game", "normal", 60, false],
    ["game", "challenge", 60, false],
    ["standard", "normal", 60, false],
    [undefined, "normal", 60, false],
  ];
  for (const [practiceMode, difficulty, currentHeat, expected] of cases) {
    assertEquals(
      beginnerRewardGateActive({ practiceMode, difficulty, currentHeat }),
      expected,
      `${practiceMode}/${difficulty}@${currentHeat}`,
    );
  }
});

Deno.test("challenge reward gate keeps negatives and evidence-backed positives only", () => {
  const applyLearningClassification = requireFn("applyLearningClassification");
  const applyChallengeRewardGate = requireFn("applyChallengeRewardGate");
  const challengeTuning = {
    positiveDeltaMultiplier: 0.7,
    negativeDeltaMultiplier: 1.3,
  };
  const state = { heatScore: 30, familiarityScore: 10 };
  const gate = (
    judgement: Record<string, unknown>,
    classification: Record<string, unknown>,
  ) =>
    applyChallengeRewardGate({
      judgement,
      currentHeat: 30,
      currentFamiliarity: 10,
      classification,
    });

  // caught → 正向證據，正分保留（已吃 ×0.7：+4/+5 → +3/+4）
  const caught = applyLearningClassification(
    state,
    safeCaught,
    challengeTuning,
  );
  assertEquals(caught.delta, 3);
  assertEquals(caught.familiarityDelta, 4);
  assertEquals(gate(caught, safeCaught), caught);

  // testHandling passed → 正向證據，正分保留
  const passedClassification = {
    connection: "neutral",
    impact: "medium",
    testHandling: "passed",
    boundary: "safe",
    hintAlignment: "none",
  };
  const passed = applyLearningClassification(
    state,
    passedClassification,
    challengeTuning,
  );
  // 硬編碼 ×0.7 後的值（Codex 審 P2）：(1+4)=5 → +4；(2+2)=4 → +3
  assertEquals(passed.delta, 4);
  assertEquals(passed.familiarityDelta, 3);
  assertEquals(gate(passed, passedClassification), passed);

  // missed → 小負分照常放行：-2/-1 先吃 minor ×0.6（roundNonZero／round
  // 取整成 -1/-1），再 ×1.3 = -1.3 四捨五入仍 -1/-1
  const missedClassification = {
    connection: "missed",
    impact: "minor",
    testHandling: "none",
    boundary: "safe",
    hintAlignment: "none",
  };
  const missed = applyLearningClassification(
    state,
    missedClassification,
    challengeTuning,
  );
  assertEquals(missed.delta, -1);
  assertEquals(missed.familiarityDelta, -1);
  assertEquals(gate(missed, missedClassification), missed);

  // missed／defensive → 負分照常放行（原 judgement 原樣返回）
  const defensiveClassification = {
    connection: "defensive",
    impact: "medium",
    testHandling: "failed",
    boundary: "safe",
    hintAlignment: "none",
  };
  const defensive = applyLearningClassification(
    state,
    defensiveClassification,
    challengeTuning,
  );
  assert(defensive.delta < 0);
  assertEquals(gate(defensive, defensiveClassification), defensive);

  // PR #88 B1：受保護的 Hint 不再豁免——對齊提示的 neutral 一樣夾到 0
  // （原封貼提示只保證不扣分，加分要有正向證據）。
  const neutralMinor = {
    connection: "neutral",
    impact: "minor",
    testHandling: "none",
    boundary: "safe",
    hintAlignment: "aligned",
  };
  const neutral = applyLearningClassification(
    state,
    neutralMinor,
    challengeTuning,
  );
  assert(neutral.delta > 0);
  const gatedNeutral = gate(neutral, neutralMinor);
  assertEquals(gatedNeutral.delta, 0);
  assertEquals(gatedNeutral.familiarityDelta, 0);
  assertEquals(gatedNeutral.score, 30);
  assertEquals(gatedNeutral.familiarityScore, 10);
});

// PR #88 H：倍率算出非有限數時熱度與熟悉度都回 0（熱度原本回 +1）。
Deno.test("applyLearningClassification treats non-finite tuning results as zero on both axes", () => {
  const applyLearningClassification = requireFn("applyLearningClassification");
  const nanTuning = {
    positiveDeltaMultiplier: Number.NaN,
    negativeDeltaMultiplier: Number.NaN,
  };
  for (
    const classification of [
      safeCaught,
      { ...safeCaught, connection: "missed" },
    ]
  ) {
    const result = applyLearningClassification(
      { heatScore: 40, familiarityScore: 20 },
      classification,
      nanTuning,
    );
    assertEquals(result.delta, 0, classification.connection);
    assertEquals(result.familiarityDelta, 0, classification.connection);
    assertEquals(result.score, 40, classification.connection);
    assertEquals(result.familiarityScore, 20, classification.connection);
  }
});

Deno.test("applyLearningClassification rewards passing a consistency test even before familiarity is ready", () => {
  const applyLearningClassification = requireFn("applyLearningClassification");

  const result = applyLearningClassification(
    { heatScore: 30, familiarityScore: 10 },
    {
      connection: "neutral",
      impact: "medium",
      testHandling: "passed",
      boundary: "safe",
      hintAlignment: "none",
    },
  );

  assertEquals(result.score, 35);
  assertEquals(result.delta, 5);
  assertEquals(result.familiarityScore, 14);
  assertEquals(result.familiarityDelta, 4);
  assert(result.reason.includes("小測試"));
});

Deno.test("applyLearningClassification penalizes defensive failed-test replies", () => {
  const applyLearningClassification = requireFn("applyLearningClassification");

  const result = applyLearningClassification(
    { heatScore: 30, familiarityScore: 10 },
    {
      connection: "defensive",
      impact: "medium",
      testHandling: "failed",
      boundary: "safe",
      hintAlignment: "none",
    },
  );

  assertEquals(result.score, 21);
  assertEquals(result.delta, -9);
  assertEquals(result.familiarityScore, 5);
  assertEquals(result.familiarityDelta, -5);
  assert(result.reason.includes("防禦"));
});

Deno.test("applyLearningClassification lets easy difficulty soften overstep familiarity damage", () => {
  const applyLearningClassification = requireFn("applyLearningClassification");
  const classification = {
    connection: "overstepped",
    impact: "medium",
    testHandling: "none",
    boundary: "overstep",
    hintAlignment: "none",
  };

  const normal = applyLearningClassification(
    { heatScore: 35, familiarityScore: 20 },
    classification,
  );
  const easy = applyLearningClassification(
    { heatScore: 35, familiarityScore: 20 },
    classification,
    { positiveDeltaMultiplier: 1.25, negativeDeltaMultiplier: 0.75 },
  );

  assertEquals(normal.delta, -12);
  assertEquals(normal.familiarityDelta, -12);
  assertEquals(easy.delta, -9);
  assertEquals(easy.familiarityDelta, -9);
  assert(easy.reason.includes("越界"));
});

Deno.test("applyLearningClassification applies positive difficulty tuning to outcome deltas", () => {
  const applyLearningClassification = requireFn("applyLearningClassification");

  const withoutTuning = applyLearningClassification(
    { heatScore: 30, familiarityScore: 10 },
    safeCaught,
  );
  const withTuning = applyLearningClassification(
    { heatScore: 30, familiarityScore: 10 },
    safeCaught,
    { positiveDeltaMultiplier: 1.25, negativeDeltaMultiplier: 0.75 },
  );

  assertEquals(withoutTuning.delta, 4);
  assertEquals(withTuning.delta, 5);
  assertEquals(withoutTuning.familiarityDelta, 5);
  assertEquals(withTuning.familiarityDelta, 6);
});

Deno.test("applyLearningClassification keeps neutral tuning byte-for-byte identical", () => {
  const applyLearningClassification = requireFn("applyLearningClassification");

  const state = { heatScore: 30, familiarityScore: 10 };
  const classification = {
    connection: "missed",
    impact: "medium",
    testHandling: "none",
    boundary: "safe",
    hintAlignment: "none",
  };

  const omitted = applyLearningClassification(state, classification);
  const explicitNeutral = applyLearningClassification(state, classification, {
    positiveDeltaMultiplier: 1,
    negativeDeltaMultiplier: 1,
  });

  assertEquals(omitted, explicitNeutral);
});

Deno.test("parseTurnClassification accepts v2 classifier JSON and defaults optional hint alignment", () => {
  const parseTurnClassification = requireFn("parseTurnClassification");

  assertEquals(
    parseTurnClassification(
      '```json\n{"connection":"caught","impact":"medium","testHandling":"passed","boundary":"safe"}\n```',
    ),
    {
      connection: "caught",
      impact: "medium",
      testHandling: "passed",
      boundary: "safe",
      hintAlignment: "none",
      partnerMood: "neutral",
      moodConfidence: 0,
      innerThought: "",
    },
  );
});

Deno.test("parseTurnClassification accepts hint alignment when present", () => {
  const parseTurnClassification = requireFn("parseTurnClassification");

  assertEquals(
    parseTurnClassification(
      '{"connection":"neutral","impact":"minor","testHandling":"none","boundary":"safe","hintAlignment":"aligned"}',
    ),
    {
      connection: "neutral",
      impact: "minor",
      testHandling: "none",
      boundary: "safe",
      hintAlignment: "aligned",
      partnerMood: "neutral",
      moodConfidence: 0,
      innerThought: "",
    },
  );
});

Deno.test("parseTurnClassification accepts partner state tracker fields", () => {
  const parseTurnClassification = requireFn("parseTurnClassification");

  assertEquals(
    parseTurnClassification(
      '{"connection":"caught","impact":"medium","testHandling":"passed","boundary":"safe","hintAlignment":"none","partnerMood":"amused","moodConfidence":0.82,"innerThought":"他有接住我的玩笑，可以多聊一點。"}',
    ),
    {
      connection: "caught",
      impact: "medium",
      testHandling: "passed",
      boundary: "safe",
      hintAlignment: "none",
      partnerMood: "amused",
      moodConfidence: 0.82,
      innerThought: "他有接住我的玩笑，可以多聊一點。",
    },
  );
});

Deno.test("applyPartnerStateUpdate keeps prior mood when confidence is low", () => {
  const applyPartnerStateUpdate = requireFn("applyPartnerStateUpdate");

  assertEquals(
    applyPartnerStateUpdate(
      { mood: "guarded", innerThought: "先保持距離。" },
      {
        connection: "neutral",
        impact: "minor",
        testHandling: "none",
        boundary: "safe",
        hintAlignment: "none",
        partnerMood: "curious",
        moodConfidence: 0.4,
        innerThought: "也許他只是慢熱。",
      },
    ),
    { mood: "guarded", innerThought: "也許他只是慢熱。" },
  );
});

Deno.test("applyPartnerStateUpdate lets overstep override low confidence", () => {
  const applyPartnerStateUpdate = requireFn("applyPartnerStateUpdate");

  assertEquals(
    applyPartnerStateUpdate(
      { mood: "comfortable", innerThought: "剛剛聊得還可以。" },
      {
        connection: "overstepped",
        impact: "strong",
        testHandling: "none",
        boundary: "overstep",
        hintAlignment: "none",
        partnerMood: "neutral",
        moodConfidence: 0.2,
        innerThought: "這個邀約太快了，我會想退後一點。",
      },
    ),
    {
      mood: "guarded",
      innerThought: "這個邀約太快了，我會想退後一點。",
    },
  );
});

Deno.test("parseTurnClassification rejects legacy category classifiers", () => {
  const parseTurnClassification = requireFn("parseTurnClassification");

  assertThrows(
    () =>
      parseTurnClassification(
        '{"category":"personal","quality":"good","overstep":false}',
      ),
    Error,
    "extra fields",
  );
});

Deno.test("parseTurnClassification requires v2 connection, testHandling, and boundary", () => {
  const parseTurnClassification = requireFn("parseTurnClassification");

  assertThrows(
    () =>
      parseTurnClassification(
        '{"impact":"medium","testHandling":"none","boundary":"safe"}',
      ),
    Error,
    "connection",
  );
  assertThrows(
    () =>
      parseTurnClassification(
        '{"connection":"caught","impact":"medium","boundary":"safe"}',
      ),
    Error,
    "testHandling",
  );
  assertThrows(
    () =>
      parseTurnClassification(
        '{"connection":"caught","impact":"medium","testHandling":"none"}',
      ),
    Error,
    "boundary",
  );
});

Deno.test("buildTurnClassifierMessages asks for outcome schema instead of event/personal/flirt", () => {
  const buildTurnClassifierMessages = requireFn("buildTurnClassifierMessages");

  const messages = buildTurnClassifierMessages({
    turns: [
      { role: "user", text: "今天主要是在整理下週簡報" },
      { role: "ai", text: "你感覺壓力滿大的耶" },
      { role: "user", text: "對啊，差點被簡報追著跑" },
    ],
    profile: resolvePracticeProfile({ profileId: "practice_girl_004" }),
    heatScore: 30,
    familiarityScore: 10,
    assistantReply: "哈哈那你現在是簡報倖存者嗎",
  });
  const text = (messages as Array<{ content: string }>)
    .map((message) => message.content)
    .join("\n");

  assert(text.includes("只分類最後一句 user 訊息"));
  assert(text.includes("互動結果"));
  assert(text.includes("connection"));
  assert(text.includes("testHandling"));
  assert(text.includes("boundary"));
  assert(text.includes("partnerMood"));
  assert(text.includes("moodConfidence"));
  assert(text.includes("innerThought"));
  assert(text.includes("assistantReplyAfterUser"));
  assert(text.includes("對啊，差點被簡報追著跑"));
  assert(text.includes("哈哈那你現在是簡報倖存者嗎"));
  assertEquals(text.includes("事件 / 個人 / 曖昧"), false);
  assertEquals(text.includes('"category":"event"'), false);
  assertEquals(text.includes('"quality":"ordinary"'), false);
  assert(text.includes("recentContext"));
  assert(text.includes("untrusted data"));
  assert(text.includes("latestUserText"));
  assertEquals(text.includes("S__42795075.jpg"), false);
});

Deno.test("buildTurnClassifierMessages scrubs raw image filenames from hint and latest text", () => {
  const buildTurnClassifierMessages = requireFn("buildTurnClassifierMessages");

  const messages = buildTurnClassifierMessages({
    turns: [{ role: "user", text: "S__42795075.jpg" }],
    profile: resolvePracticeProfile({ profileId: "practice_girl_004" }),
    heatScore: 30,
    familiarityScore: 10,
    appliedHintType: "steady",
    appliedHintText: "S__42795075.jpg",
  });
  const text = (messages as Array<{ content: string }>)
    .map((message) => message.content)
    .join("\n");

  assertEquals(text.includes("S__42795075.jpg"), false);
  assert(text.includes("[image concept omitted]"));
  assert(text.includes("originalHint"));
});

Deno.test("buildTurnClassifierMessages includes recent context to judge whether hi answers the previous turn", () => {
  const buildTurnClassifierMessages = requireFn("buildTurnClassifierMessages");

  const messages = buildTurnClassifierMessages({
    turns: [
      { role: "ai", text: "You said you were tired. Was work heavy today?" },
      { role: "user", text: "hi" },
    ],
    profile: resolvePracticeProfile({ profileId: "practice_girl_004" }),
    heatScore: 30,
    familiarityScore: 10,
  });
  const text = (messages as Array<{ content: string }>)
    .map((message) => message.content)
    .join("\n");

  assert(text.includes("recentContext"));
  assert(text.includes("untrusted data"));
  assert(text.includes("You said you were tired. Was work heavy today?"));
  assert(text.includes("latestUserText"));
  assert(text.includes("hi"));
  assertEquals(text.includes("user: hi"), false);
  assert(text.includes("classify only latestUserText"));
  assert(text.includes("short greeting"));
});
