import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { parseAndValidateReply, validateRequest } from "./validate.ts";

Deno.test("validateRequest accepts all five styles", () => {
  for (const style of ["extend", "resonate", "tease", "humor", "coldRead"]) {
    assertEquals(validateRequest({ message: "  今天好累  ", style }), {
      message: "今天好累",
      style,
    });
  }
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
