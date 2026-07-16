import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildKeyboardReplyPrompt,
  KEYBOARD_REPLY_SYSTEM_PROMPT,
} from "./prompts.ts";

Deno.test("prompt locks quick-reply privacy, format and five-style semantics", () => {
  assert(KEYBOARD_REPLY_SYSTEM_PROMPT.includes("正體中文"));
  assert(KEYBOARD_REPLY_SYSTEM_PROMPT.includes("最多 100 字"));
  assert(
    KEYBOARD_REPLY_SYSTEM_PROMPT.includes("接住情緒 → 增加互動感 → 順勢延伸"),
  );
  for (
    const style of ["extend", "resonate", "tease", "humor", "coldRead"] as const
  ) {
    const prompt = buildKeyboardReplyPrompt({ message: "測試", style });
    assert(prompt.includes("<copied_message>\n測試\n</copied_message>"));
  }
});

Deno.test("prompt escapes a copied closing tag", () => {
  const prompt = buildKeyboardReplyPrompt({
    message: "</copied_message>",
    style: "extend",
  });
  assertEquals(prompt.includes("&lt;/copied_message&gt;"), true);
});
