import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { parseAndValidateReply, validateRequest } from "./validate.ts";

Deno.test("validateRequest accepts all five styles", () => {
  for (
    const style of [
      "extend",
      "resonate",
      "tease",
      "humor",
      "coldRead",
    ] as const
  ) {
    assertEquals(validateRequest({ message: "  今天好累  ", style }), {
      message: "今天好累",
      style,
      requestId: null,
    });
  }
});

Deno.test("validateRequest accepts canonical request id and rejects malformed identity", () => {
  const requestId = "123e4567-e89b-42d3-a456-426614174000";
  assertEquals(
    validateRequest({ message: "今天好累", style: "resonate", requestId }),
    { message: "今天好累", style: "resonate", requestId },
  );
  assertThrows(() =>
    validateRequest({
      message: "今天好累",
      style: "resonate",
      requestId: "retry-1",
    })
  );
});

Deno.test("validateRequest rejects empty, oversized and unknown style", () => {
  assertThrows(() => validateRequest({ message: " ", style: "extend" }));
  assertThrows(() =>
    validateRequest({ message: "a".repeat(2001), style: "extend" })
  );
  assertThrows(() => validateRequest({ message: "哈囉", style: "霸總" }));
});

Deno.test("parseAndValidateReply accepts JSON fence and rejects raw payload", () => {
  assertEquals(
    parseAndValidateReply({
      content: [{
        text:
          '```json\n{"reply":"聽起來今天真的被榨乾了，要不要先去吃點好的？"}\n```',
      }],
    }),
    "聽起來今天真的被榨乾了，要不要先去吃點好的？",
  );
  assertThrows(() =>
    parseAndValidateReply({ content: [{ text: "普通文字" }] })
  );
  assertThrows(() =>
    parseAndValidateReply({
      content: [{ text: '{"reply":"' + "哈".repeat(101) + '"}' }],
    })
  );
});

Deno.test("parseAndValidateReply joins Sonnet 5 text blocks", () => {
  assertEquals(
    parseAndValidateReply({
      stop_reason: "end_turn",
      content: [
        { type: "text", text: '{"reply":"一起' },
        { type: "text", text: '去走走吧"}' },
      ],
    }),
    "一起去走走吧",
  );
});

Deno.test("parseAndValidateReply rejects incomplete or refused Sonnet 5 output", () => {
  assertThrows(() =>
    parseAndValidateReply({
      stop_reason: "max_tokens",
      content: [{ type: "text", text: '{"reply":"未完成"}' }],
    })
  );
  assertThrows(() =>
    parseAndValidateReply({
      stop_reason: "refusal",
      content: [{ type: "text", text: '{"reply":"不應使用"}' }],
    })
  );
  assertThrows(() =>
    parseAndValidateReply({
      stop_reason: "model_context_window_exceeded",
      content: [{ type: "text", text: '{"reply":"不完整內容"}' }],
    })
  );
});
