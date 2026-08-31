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
  // 提及英文 ≠ 要求英文（R2 審查：提及誤開逃生門會整句解除守門）。
  assertEquals(isExplicitEnglishRequest("這句英文訊息怎麼回比較好"), false);
  assertEquals(
    isExplicitEnglishRequest("她傳英文訊息給我，但我要用中文回她"),
    false,
  );
  assertEquals(isExplicitEnglishRequest("她今天過得怎樣"), false);
});

// ── R1 審查修正的回歸鎖（2026-08-31 Codex 獨立審查）────────────────────

Deno.test("否定句與引用不算明確要英文（P1-4）", () => {
  assertEquals(isExplicitEnglishRequest("不要用英文回她"), false);
  assertEquals(isExplicitEnglishRequest("這不是要你用英文寫"), false);
  assertEquals(isExplicitEnglishRequest("別再用英文訊息了"), false);
  assertEquals(isExplicitEnglishRequest("她問我英文好不好，要怎麼回？"), false);
  assertEquals(isExplicitEnglishRequest("幫我用英語寫一句"), true);
  assertEquals(isExplicitEnglishRequest("給我全英文版本"), true);
});

Deno.test("來源比對是整詞不是子字串（P2-6）", () => {
  assertEquals(
    findUnsupportedLatinTokens("她今天busy嗎", "最近都是 busywork"),
    ["busy"],
  );
  assertEquals(
    findUnsupportedLatinTokens("她今天busy嗎", "她說她很 busy"),
    [],
  );
});

Deno.test("守門涵蓋所有可見欄位（rewriteReason 注入也擋）", () => {
  assertEquals(
    findUnsupportedLatinTokens("保留你的 tone，只收穩語氣。", ""),
    ["tone"],
  );
});

// ── R2 審查修正的回歸鎖 ─────────────────────────────────────────────

Deno.test("白名單片段不能替一般文字洗來源（R2）", () => {
  assertEquals(
    findUnsupportedLatinTokens("妳today過得怎樣", "看 https://today.example"),
    ["today"],
  );
  assertEquals(
    findUnsupportedLatinTokens("妳busy嗎", "標了 #busy 的貼文"),
    ["busy"],
  );
});

Deno.test("全形拉丁字母照樣被偵測（R2）", () => {
  assertEquals(findUnsupportedLatinTokens("欸妳ｔｏｄａｙ過得怎樣", ""), [
    "today",
  ]);
});
