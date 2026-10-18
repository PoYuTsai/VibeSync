import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  hasUserBlank,
  normalizeUserBlanks,
  normalizeUserBlanksWithin,
  USER_BLANK,
} from "./user_blank.ts";

Deno.test("留空格一律收成「＿＿」：全形一個或多個、半形兩個以上都算；一個半形底線不動", () => {
  assertEquals(USER_BLANK, "＿＿");
  assertEquals(normalizeUserBlanks("我住＿附近"), "我住＿＿附近");
  assertEquals(normalizeUserBlanks("我做＿＿＿＿的"), "我做＿＿的");
  assertEquals(
    normalizeUserBlanks("我週__有空，在___附近"),
    "我週＿＿有空，在＿＿附近",
  );
  assertEquals(normalizeUserBlanks("帳號 a_b 不算"), "帳號 a_b 不算");
  assertEquals(normalizeUserBlanks("沒有空格"), "沒有空格");
});

Deno.test("收完空格再量長度：變長超過上限回 null，變短或剛好照收（主審 P2-2）", () => {
  assertEquals(normalizeUserBlanksWithin("ab＿", 4), "ab＿＿");
  assertEquals(
    normalizeUserBlanksWithin("abc＿", 4),
    null,
    "一個＿補成兩個，超過上限",
  );
  assertEquals(
    normalizeUserBlanksWithin("a＿＿＿＿", 3),
    "a＿＿",
    "多個＿收短後在上限內",
  );
  assertEquals(normalizeUserBlanksWithin("abcd", 4), "abcd");
});

Deno.test("有沒有空格：跟 App 的 guideV3TextHasBlank 一樣看全形「＿」", () => {
  assert(hasUserBlank("我最近都在＿＿夜跑"));
  assertFalse(hasUserBlank("我最近都在河濱夜跑"));
  assertFalse(hasUserBlank("a__b"), "半形要先經過 normalizeUserBlanks");
});
