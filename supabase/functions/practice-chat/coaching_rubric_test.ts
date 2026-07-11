import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  PRACTICE_COACHING_RUBRIC,
  PRACTICE_COACHING_RUBRIC_VERSION,
} from "./coaching_rubric.ts";

Deno.test("shared practice rubric carries the golden timing and accountability rules", () => {
  assertEquals(PRACTICE_COACHING_RUBRIC_VERSION, 1);
  for (
    const expected of [
      "技巧看時機，不看密度",
      "聊她／聊我／聊我們",
      "狀態＋感受",
      "callback",
      "邀約沒被接住時不追投",
      "使用者執行、Hint 品質、她的新反應",
      "不能無理由否定 Hint",
    ]
  ) {
    assertStringIncludes(PRACTICE_COACHING_RUBRIC, expected);
  }
  for (const forbidden of ["攻克", "控制對方", "情緒勒索", "物化女性"]) {
    assert(!PRACTICE_COACHING_RUBRIC.includes(forbidden));
  }
});
