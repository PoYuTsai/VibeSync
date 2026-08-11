import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { toTraditionalChinese } from "./traditional_chinese.ts";

// 2026-08-11：Game hint／NPC 可以摻台語與注音（Eric 拍板「台灣人的諧音梗很屌」）。
// 但「厂」在轉換表裡是「廠」的簡體字，台灣人拿它當注音ㄏ打笑聲會被轉壞
// （厂ㄠ厂ㄠ丂ㄞ → 廠ㄠ廠ㄠ丂ㄞ）。prompt 已改成要求打真注音符號；
// 這條測試把這個已知行為釘住，之後有人想放寬轉換表才知道踩到什麼。
Deno.test("注音符號原樣通過繁簡轉換，但漢字「厂」仍會被當成簡體「廠」", () => {
  assertEquals(toTraditionalChinese("ㄏㄏ 妳很敢講"), "ㄏㄏ 妳很敢講");
  assertEquals(toTraditionalChinese("我沒那麼遜ㄟ"), "我沒那麼遜ㄟ");
  assertEquals(toTraditionalChinese("歹勢 我剛在忙ㄌ"), "歹勢 我剛在忙ㄌ");
  assertEquals(toTraditionalChinese("母湯 甘安捏"), "母湯 甘安捏");
  // 已知限制：這就是 prompt 要求用 ㄏㄏ 而不是 厂厂 的原因。
  assertEquals(toTraditionalChinese("厂厂"), "廠廠");
});
