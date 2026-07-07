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

Deno.test("applyLearningClassification no longer zeroes low-pressure neutral replies", () => {
  const applyLearningClassification = requireFn("applyLearningClassification");

  const result = applyLearningClassification(
    { heatScore: 30, familiarityScore: 10 },
    {
      connection: "neutral",
      impact: "minor",
      testHandling: "none",
      boundary: "safe",
      hintAlignment: "none",
    },
  );

  assertEquals(result.score, 31);
  assertEquals(result.delta, 1);
  assertEquals(result.familiarityScore, 11);
  assertEquals(result.familiarityDelta, 1);
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
