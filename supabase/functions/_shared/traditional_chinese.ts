import OpenCC from "npm:opencc-js@1.4.1/cn2t";

// Use OpenCC's complete Simplified Chinese -> Taiwan Traditional Chinese
// dictionaries instead of maintaining an inevitably incomplete local map.
const simplifiedToTaiwanTraditional = OpenCC.Converter({
  from: "cn",
  // `tw` gives complete character/phrase conversion without the aggressive
  // Taiwan idiom pass that rewrites dating terms such as「邀約窗口」to「視窗」.
  to: "tw",
});

const PRODUCT_TERMS: Array<[string, string]> = [
  ["用戶", "使用者"],
  ["軟件", "軟體"],
  ["信息", "資訊"],
  ["神秘", "神祕"],
  // The app and transcript corpus consistently use「台」; keeping it stable
  // prevents normalization from breaking exact evidence comparisons.
  ["臺", "台"],
];

// 台灣人打注音笑聲常用長得像的漢字（厂厂＝ㄏㄏ、丂＝ㄎ）。prompt 有要求
// 打真注音，但模型偶爾照樣吐漢字版，過了 cn2t 就變「廠廠」端給使用者
// （2026-08-19 Eric：厂厂和廠廠都不行）。轉換前先把「當注音用的漢字」
// 正規化成真注音：只在相鄰字也是注音符號或同類漢字時才換，避免把真的
// 「工厂」吃成「工ㄏ」——那種要留給 cn2t 轉成「工廠」。
const ZHUYIN_LOOKALIKES: Array<[RegExp, string]> = [
  [/厂(?=[厂丂ㄅ-ㄩ])|(?<=[厂丂ㄅ-ㄩ])厂/gu, "ㄏ"],
  [/丂(?=[厂丂ㄅ-ㄩ])|(?<=[厂丂ㄅ-ㄩ])丂/gu, "ㄎ"],
];

function normalizeZhuyinLookalikes(value: string): string {
  let normalized = value;
  for (const [pattern, zhuyin] of ZHUYIN_LOOKALIKES) {
    normalized = normalized.replace(pattern, zhuyin);
  }
  return normalized;
}

export function toTraditionalChinese(value: string): string {
  let converted = simplifiedToTaiwanTraditional(normalizeZhuyinLookalikes(value));
  for (const [from, to] of PRODUCT_TERMS) {
    converted = converted.split(from).join(to);
  }
  return converted;
}
