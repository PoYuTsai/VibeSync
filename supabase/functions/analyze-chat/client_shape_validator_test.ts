import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  findClientShapeViolations,
  findRecordShapeViolations,
} from "./client_shape_validator.ts";
import { REPLY_OPTION_FIELD_SHAPES } from "./reframer.ts";

// 一個完全符合 client 硬 cast 契約的 finalResult，碰到多個 shape 分支
// （record／巢狀 record／recordArray／stringArray／int／number／boolean／
// string／dynamic replies／dynamic replyOptions）。守門後的乾淨輸出長這樣。
function goodFinalResult(): Record<string, unknown> {
  return {
    gameStage: { current: "升溫", status: "ok", nextStep: "約" },
    topicDepth: { current: "深", suggestion: "繼續" },
    psychology: {
      subtext: "她在試探",
      qualificationSignal: true,
      shitTest: { detected: false, type: "none", suggestion: "略" },
    },
    enthusiasm: { score: 78, level: "warm" },
    healthCheck: {
      issues: ["太快"],
      suggestions: ["放慢"],
      hasNeedySignals: false,
      hasInterviewStyle: false,
      speakingRatio: 0.5,
    },
    finalRecommendation: {
      pick: "coldRead",
      content: "內容",
      reason: "理由",
      psychology: "心理",
      replySegments: [
        { label: "a", sourceMessage: "x", reply: "y", reason: "z" },
      ],
    },
    dimensions: {
      heat: 80,
      engagement: 70,
      topicDepth: 60,
      replyWillingness: 75,
      emotionalConnection: 65,
    },
    warnings: ["注意一下"],
    strategy: "穩接",
    reminder: "別急",
    replies: { coldRead: "句子一", tease: "句子二" },
    replyOptions: {
      coldRead: {
        sourceMessage: "x",
        reason: "r",
        messages: [{ label: "a", sourceMessage: "x", reply: "y", reason: "z" }],
      },
    },
    recognizedConversation: {
      contactName: "Wen",
      messageCount: 5,
      summary: "摘要",
      classification: "friend",
      importPolicy: "auto",
      confidence: "high",
      sideConfidence: "high",
      uncertainSideCount: 0,
      warning: "",
      messages: [
        {
          side: "left",
          isFromMe: false,
          content: "hi",
          quotedReplyPreview: "",
          quotedReplyPreviewIsFromMe: false,
        },
      ],
    },
  };
}

Deno.test("good finalResult yields no violations", () => {
  assertEquals(findClientShapeViolations(goodFinalResult()), []);
});

Deno.test("top-level warnings as string is a violation (array-only key)", () => {
  const fr = goodFinalResult();
  fr.warnings = "字串而非陣列";
  const violations = findClientShapeViolations(fr);
  assertEquals(violations.length, 1);
  assertEquals(violations[0].path, "warnings");
});

Deno.test("warnings array with non-string element is a violation", () => {
  const fr = goodFinalResult();
  fr.warnings = ["ok", 42];
  const violations = findClientShapeViolations(fr);
  assertEquals(violations.length, 1);
  assert(violations[0].path.startsWith("warnings"));
});

Deno.test("enthusiasm.score as float is a violation (int field)", () => {
  const fr = goodFinalResult();
  (fr.enthusiasm as Record<string, unknown>).score = 72.5;
  const violations = findClientShapeViolations(fr);
  assertEquals(violations.length, 1);
  assertEquals(violations[0].path, "enthusiasm.score");
});

Deno.test("enthusiasm.score as integer-valued number passes", () => {
  const fr = goodFinalResult();
  (fr.enthusiasm as Record<string, unknown>).score = 80;
  assertEquals(findClientShapeViolations(fr), []);
});

Deno.test("psychology.shitTest as string is a violation (nested record)", () => {
  const fr = goodFinalResult();
  (fr.psychology as Record<string, unknown>).shitTest = "有測試";
  const violations = findClientShapeViolations(fr);
  assertEquals(violations.length, 1);
  assertEquals(violations[0].path, "psychology.shitTest");
});

Deno.test("dimensions.heat as string is a violation (number field)", () => {
  const fr = goodFinalResult();
  (fr.dimensions as Record<string, unknown>).heat = "hot";
  const violations = findClientShapeViolations(fr);
  assertEquals(violations.length, 1);
  assertEquals(violations[0].path, "dimensions.heat");
});

Deno.test("recognizedConversation.messages as array of non-records is a violation (recordArray)", () => {
  const fr = goodFinalResult();
  (fr.recognizedConversation as Record<string, unknown>).messages = [1, 2];
  const violations = findClientShapeViolations(fr);
  assertEquals(violations.length, 2);
  assert(violations.every((v) => v.path.startsWith("recognizedConversation.messages[")));
});

Deno.test("record-shaped top-level key present as bare string is a violation", () => {
  const fr = goodFinalResult();
  fr.psychology = "她在試探"; // gate4 守門前產物長這樣——client as Map? 會 throw
  const violations = findClientShapeViolations(fr);
  assertEquals(violations.length, 1);
  assertEquals(violations[0].path, "psychology");
});

Deno.test("present null and undefined values are allowed (nullable cast)", () => {
  const fr = goodFinalResult();
  fr.psychology = null;
  fr.warnings = null;
  (fr.enthusiasm as Record<string, unknown>).score = null;
  fr.strategy = undefined;
  assertEquals(findClientShapeViolations(fr), []);
});

Deno.test("keys not in any shape table are ignored", () => {
  const fr = goodFinalResult();
  fr.someUnknownKey = 12345;
  fr.anotherFreeform = { whatever: [1, 2, 3] };
  assertEquals(findClientShapeViolations(fr), []);
});

Deno.test("strategy as object is a violation (string-only key)", () => {
  const fr = goodFinalResult();
  fr.strategy = { nope: true };
  const violations = findClientShapeViolations(fr);
  assertEquals(violations.length, 1);
  assertEquals(violations[0].path, "strategy");
});

Deno.test("dynamic replies with non-string value is a violation", () => {
  const fr = goodFinalResult();
  (fr.replies as Record<string, unknown>).tease = { nested: "x" };
  const violations = findClientShapeViolations(fr);
  assertEquals(violations.length, 1);
  assertEquals(violations[0].path, "replies.tease");
});

Deno.test("dynamic replyOptions value conforms via REPLY_OPTION table", () => {
  const fr = goodFinalResult();
  (fr.replyOptions as Record<string, Record<string, unknown>>).coldRead.reason =
    99;
  const violations = findClientShapeViolations(fr);
  assertEquals(violations.length, 1);
  assertEquals(violations[0].path, "replyOptions.coldRead.reason");
});

Deno.test("non-record replyOptions value is allowed (client tolerant)", () => {
  const fr = goodFinalResult();
  (fr.replyOptions as Record<string, unknown>).tease = "純字串";
  assertEquals(findClientShapeViolations(fr), []);
});

Deno.test("non-record finalResult yields no violations", () => {
  assertEquals(findClientShapeViolations("not a record"), []);
  assertEquals(findClientShapeViolations(null), []);
});

Deno.test("findRecordShapeViolations checks a reply_option against REPLY_OPTION table", () => {
  const replyOption = {
    sourceMessage: "x",
    reason: "r",
    messages: [{ label: "a", sourceMessage: 5, reply: "y", reason: "z" }],
  };
  const violations = findRecordShapeViolations(
    replyOption,
    REPLY_OPTION_FIELD_SHAPES,
    "replyOption",
  );
  assertEquals(violations.length, 1);
  assertEquals(violations[0].path, "replyOption.messages[0].sourceMessage");
});
