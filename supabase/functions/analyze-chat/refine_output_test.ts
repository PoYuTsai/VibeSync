import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  exceedsRefineOutputLimit,
  REFINE_MIN_OUTPUT_CHARS,
  refineMaxOutputChars,
} from "./refine_output.ts";

Deno.test("短句的上限是地板值，不是輸入長度", () => {
  assertEquals(
    refineMaxOutputChars("要不要一起喝咖啡"),
    REFINE_MIN_OUTPUT_CHARS,
  );
  assertEquals(refineMaxOutputChars(""), REFINE_MIN_OUTPUT_CHARS);
});

Deno.test("長輸入的上限跟著輸入走，不會永遠失敗", () => {
  const long = "好".repeat(500);
  assertEquals(refineMaxOutputChars(long), 600);
  // 本來就 500 字的來源，原封不動回來必須是合法的。
  assertFalse(
    exceedsRefineOutputLimit({ sourceDraft: long, optimized: long }),
  );
});

Deno.test("越調越長會被擋下", () => {
  const source = "要不要一起喝咖啡";
  assertFalse(
    exceedsRefineOutputLimit({
      sourceDraft: source,
      optimized: "好".repeat(REFINE_MIN_OUTPUT_CHARS),
    }),
  );
  assert(
    exceedsRefineOutputLimit({
      sourceDraft: source,
      optimized: "好".repeat(REFINE_MIN_OUTPUT_CHARS + 1),
    }),
  );
});

Deno.test("邊界剛好等於上限不算超過", () => {
  const source = "好".repeat(400);
  assertEquals(refineMaxOutputChars(source), 500);
  assertFalse(
    exceedsRefineOutputLimit({
      sourceDraft: source,
      optimized: "好".repeat(500),
    }),
  );
  assert(
    exceedsRefineOutputLimit({
      sourceDraft: source,
      optimized: "好".repeat(501),
    }),
  );
});

Deno.test("emoji 算一個字，不是兩個", () => {
  // 以 UTF-16 length 計會是 2，這裡必須是 1。
  assertEquals(refineMaxOutputChars("😀"), REFINE_MIN_OUTPUT_CHARS);
  assertFalse(
    exceedsRefineOutputLimit({
      sourceDraft: "嗨",
      optimized: "😀".repeat(REFINE_MIN_OUTPUT_CHARS),
    }),
  );
});

Deno.test("前後空白不計入長度", () => {
  assertFalse(
    exceedsRefineOutputLimit({
      sourceDraft: "嗨",
      optimized: `   ${"好".repeat(REFINE_MIN_OUTPUT_CHARS)}   `,
    }),
  );
});
