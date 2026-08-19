import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { toTraditionalChinese } from "./traditional_chinese.ts";

// 2026-08-11：Game hint／NPC 可以摻台語與注音（Eric 拍板「台灣人的諧音梗很屌」）。
// 但「厂」在轉換表裡是「廠」的簡體字，台灣人拿它當注音ㄏ打笑聲會被轉壞
// （厂ㄠ厂ㄠ丂ㄞ → 廠ㄠ廠ㄠ丂ㄞ）。prompt 要求打真注音，但模型偶爾照樣
// 吐漢字版（2026-08-19 真機實錄「甜點單厂厂」）；改在轉換前把當注音用
// 的漢字正規化成真注音——判準是相鄰字：旁邊也是注音/同類漢字才換，
// 孤立的「厂」（工厂）留給 cn2t 轉成「廠」。
Deno.test("注音符號原樣通過繁簡轉換", () => {
  assertEquals(toTraditionalChinese("ㄏㄏ 妳很敢講"), "ㄏㄏ 妳很敢講");
  assertEquals(toTraditionalChinese("我沒那麼遜ㄟ"), "我沒那麼遜ㄟ");
  assertEquals(toTraditionalChinese("歹勢 我剛在忙ㄌ"), "歹勢 我剛在忙ㄌ");
  assertEquals(toTraditionalChinese("母湯 甘安捏"), "母湯 甘安捏");
});

Deno.test("當注音用的漢字笑聲正規化成真注音，真簡體字照樣轉繁", () => {
  assertEquals(toTraditionalChinese("厂厂"), "ㄏㄏ");
  assertEquals(
    toTraditionalChinese("改天研究股票不如研究甜點單厂厂"),
    "改天研究股票不如研究甜點單ㄏㄏ",
  );
  assertEquals(toTraditionalChinese("厂ㄠ厂ㄠ丂ㄞ"), "ㄏㄠㄏㄠㄎㄞ");
  assertEquals(toTraditionalChinese("丂丂"), "ㄎㄎ");
  // 孤立的厂不是笑聲：留給 cn2t 當簡體「廠」轉。
  assertEquals(toTraditionalChinese("这家工厂很大"), "這家工廠很大");
});
