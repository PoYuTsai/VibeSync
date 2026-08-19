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
// 這裡刻意獨立成一個沒有 import 的模組：opener_payload 與 new_topic_payload
// 都要用，而 post_process 已經 import opener_payload，放那裡會成環。

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
