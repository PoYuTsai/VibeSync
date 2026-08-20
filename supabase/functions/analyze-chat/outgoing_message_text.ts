import { toTraditionalChinese } from "../_shared/traditional_chinese.ts";
import { stripUnexpectedForeignClauses } from "./unexpected_foreign_text.ts";

// 「要原封傳給對方的訊息」共用的確定性正規化。
//
// 只用在那類欄位——教練欄位（whyItWorks／nextMove／reason）是對使用者講話，
// 套進去會把文案主詞翻面。
//
// 為什麼是確定性正規化而不是 prompt 規則：模型會整輪飄成「你」、也會同一句
// 混用，而且是間歇的——2026-08-19 的 A/B 一次量到新話題 3/20、下一輪同一份
// prompt 又是 0/40，開場白同期 3/25。這種間歇性缺陷 prompt 治不了，但它是
// 使用者原封複製貼上寄出去的文字，錯一個字就露餡。
//
// 這裡刻意獨立成共用模組：opener_payload 與 new_topic_payload 都要用，而
// post_process 已經 import opener_payload，放那裡會成環。

/** 「你們」可能指混合群體，留著不動；其餘一律轉成「妳」。 */
export function normalizePartnerPronoun(line: string | null): string | null {
  return line === null ? null : line.replace(/你(?!們)/g, "妳");
}

/**
 * 中文之間的半形逗號、以及全形標點前面多出來的空白。
 * 2026-08-19 A/B 樣本約 600 句裡出現 6 處（「想鞠躬,講話直接我喜歡」
 * 「講話直接我喜歡 ，浪費時間我也怕」）——頻率低但使用者是原封貼出去的。
 *
 * ponytail: 只處理逗號，而且要求前後都是中日韓字元——數字千分位（1,000）與
 * 顏文字不受影響。半形問號驚嘆號目前零實例，等真的出現再說。
 */
export function normalizeOutgoingPunctuation(line: string | null): string | null {
  if (line === null) return null;
  return line
    .replace(/([\u4e00-\u9fff]),(?=[\u4e00-\u9fff])/g, "$1，")
    .replace(/[ \t]+(?=[，。！？、；：])/g, "");
}

/**
 * 簡體字混進來（2026-08-19 A/B 約 600 句出現 1 處：「感覺妳會带我去」）。
 *
 * 用練習室已經跑了半年的那支——它同時解掉了「厂厂」這種當注音用的漢字笑聲
 * 會被 cn2t 轉成「廠廠」的坑（只在旁邊也是注音時才轉成 ㄏ，「工厂」照樣變
 * 「工廠」）。自己寫一份不完整的對照表正是那支的檔頭明講不要做的事。
 *
 * 代價：analyze-chat 的 bundle 多一份 OpenCC 字典（practice-chat 已經在付）。
 * ponytail: 先靜態載入，跟 practice-chat 一致；真的量到冷啟動變慢再改成偵測到
 * 簡體字才動態載入。
 */
export function normalizeOutgoingScript(line: string | null): string | null {
  return line === null ? null : toTraditionalChinese(line);
}

/** 所有「可直接傳」文字共用同一條正規化管線，避免 Opener／新話題漏接護欄。 */
export function normalizeOutgoingMessageText(
  line: string | null,
): string | null {
  const expanded = line
    ?.replace(/\\n/g, "\n")
    .replace(/\n{2,}/g, "\n") ?? null;
  return stripUnexpectedForeignClauses(
    normalizeOutgoingScript(
      normalizeOutgoingPunctuation(normalizePartnerPronoun(expanded)),
    ),
  );
}
