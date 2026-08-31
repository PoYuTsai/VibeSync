import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  findUnsupportedLatinTokens,
  isExplicitEnglishRequest,
} from "./zh_tw_visible_text_guard.ts";

Deno.test("拒絕黏在漢字裡的無來源英文詞", () => {
  assertEquals(
    findUnsupportedLatinTokens("欸你today過得怎樣？", "她說我很有故事"),
    ["today"],
  );
  assertEquals(
    findUnsupportedLatinTokens("她今天busy嗎", ""),
    ["busy"],
  );
});

Deno.test("白名單品牌服務名放行", () => {
  assertEquals(findUnsupportedLatinTokens("要不要改用 LINE 聊？", ""), []);
  assertEquals(findUnsupportedLatinTokens("Netflix 那部看完了嗎？", ""), []);
});

Deno.test("來源支持的英文詞放行（含大小寫不同）", () => {
  assertEquals(
    findUnsupportedLatinTokens("F1 看完要不要去吃東西？", "我們剛聊 f1 決賽"),
    [],
  );
  assertEquals(
    findUnsupportedLatinTokens("欸你today過得怎樣", "我原稿：欸你today過得怎樣"),
    [],
  );
});

Deno.test("英文對象名放行（名字在來源）", () => {
  assertEquals(
    findUnsupportedLatinTokens("Sydney 週末有空嗎？", "名字：Sydney"),
    [],
  );
});

Deno.test("網址 Email @帳號 Hashtag 不誤擋", () => {
  assertEquals(
    findUnsupportedLatinTokens(
      "詳細在 https://example.com/menu 或找 @dating_girl，標 #weekend，寄 a.b@mail.com",
      "",
    ),
    [],
  );
});

Deno.test("單一字母放行、同 token 只回報一次", () => {
  assertEquals(findUnsupportedLatinTokens("A咖 P.S. 你懂的", ""), []);
  assertEquals(
    findUnsupportedLatinTokens("today 很 chill，today 對吧", ""),
    ["today", "chill"],
  );
});

Deno.test("教練舊輸出不算來源（呼叫端只餵使用者文字即成立）", () => {
  // 守門本身不認識角色；契約是呼叫端只把使用者親手寫的文字當 source。
  // 這裡驗證：source 沒有 today 就一定擋，無論它曾出現在誰的舊輸出。
  assertEquals(
    findUnsupportedLatinTokens("欸你today過得怎樣", "教練上次說了什麼都不進來源"),
    ["today"],
  );
});

Deno.test("明確要英文的請求判定", () => {
  assertEquals(isExplicitEnglishRequest("幫我用英文回她"), true);
  assertEquals(isExplicitEnglishRequest("這句英文訊息怎麼回比較好"), true);
  assertEquals(isExplicitEnglishRequest("她今天過得怎樣"), false);
});
