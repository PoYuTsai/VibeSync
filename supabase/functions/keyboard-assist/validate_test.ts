import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  unicodeCodePointLength,
  validateKeyboardAssistLedgerResult,
} from "./validate.ts";

function readyResult() {
  return {
    contractVersion: "keyboard-assist-v1",
    status: "ready",
    source: {
      scope: "screenshot_plus_global_voice",
      messageCount: 7,
      confidence: "high",
      sideConfidence: "high",
    },
    turnState: "optional_follow_up",
    cue: "現在不一定要補一句。",
    uncertainty: null,
    options: [
      {
        strategy: "keep_pace",
        text: "可以啊，我確認一下行程再跟你說",
        why: "先保留確認空間",
        effect: "低壓且保留空間",
      },
      {
        strategy: "build_connection",
        text: "你連週末都看好了，我要認真考慮一下了 😄",
        why: "接住畫面內的週末",
        effect: "提高互動溫度",
      },
      {
        strategy: "move_forward",
        text: "我確認好再跟你說；你比較偏好哪一天？",
        why: "把安排變成可回答問題",
        effect: "直接推進安排",
      },
    ],
  };
}

Deno.test("ledger result accepts exact ready and speaker-confirmation unions", () => {
  assert(validateKeyboardAssistLedgerResult(readyResult()));
  assert(
    validateKeyboardAssistLedgerResult({
      contractVersion: "keyboard-assist-v1",
      status: "needs_speaker_confirmation",
      suggestedMySide: "right",
      sideConfidence: "low",
    }),
  );
});

Deno.test("ledger result excludes request identity, transcript, image, and labels", () => {
  assertFalse(
    validateKeyboardAssistLedgerResult({
      ...readyResult(),
      requestId: "123e4567-e89b-42d3-a456-426614174000",
    }),
  );
  assertFalse(
    validateKeyboardAssistLedgerResult({
      ...readyResult(),
      transcript: [{ text: "private" }],
    }),
  );
  assertFalse(
    validateKeyboardAssistLedgerResult({
      contractVersion: "keyboard-assist-v1",
      status: "needs_speaker_confirmation",
      suggestedMySide: "right",
      sideConfidence: "low",
      ocrPreview: "private",
    }),
  );
});

Deno.test("ready result requires three distinct bounded strategies", () => {
  const result = readyResult();
  result.options[2].strategy = "keep_pace";
  assertFalse(validateKeyboardAssistLedgerResult(result));

  const long = readyResult();
  long.options[0].text = "😀".repeat(101);
  assertFalse(validateKeyboardAssistLedgerResult(long));
  assertEquals(unicodeCodePointLength("😀".repeat(100)), 100);
});

Deno.test("ready result rejects markdown and pseudo-psychology markers", () => {
  const markdown = readyResult();
  markdown.options[0].text = "**你可以這樣回**";
  assertFalse(validateKeyboardAssistLedgerResult(markdown));

  const percentage = readyResult();
  percentage.options[0].why = "對方好感度 87%";
  assertFalse(validateKeyboardAssistLedgerResult(percentage));

  const fullwidthPercentage = readyResult();
  fullwidthPercentage.options[0].why = "互動成功率％";
  assertFalse(validateKeyboardAssistLedgerResult(fullwidthPercentage));
});
