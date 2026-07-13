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

export function toTraditionalChinese(value: string): string {
  let converted = simplifiedToTaiwanTraditional(value);
  for (const [from, to] of PRODUCT_TERMS) {
    converted = converted.split(from).join(to);
  }
  return converted;
}
