// 要傳給對方的訊息，人稱一律「妳」。
//
// 為什麼是確定性正規化而不是 prompt 規則：模型會整輪飄成「你」、也會同一句
// 混用，而且是間歇的——2026-08-19 的 A/B 一次量到新話題 3/20、下一輪同一份
// prompt 又是 0/40，開場白同期 3/25。這種間歇性缺陷 prompt 治不了，但它是
// 使用者原封複製貼上寄出去的文字，錯一個字就露餡。
//
// 這裡刻意獨立成一個沒有 import 的模組：opener_payload 與 new_topic_payload
// 都要用，而 post_process 已經 import opener_payload，放那裡會成環。
//
// 只用在「傳給對方的訊息」欄位。教練欄位（whyItWorks／nextMove／reason）是對
// 使用者講話，那裡的「你」是他本人，一起轉會把文案主詞翻面。

/** 「你們」可能指混合群體，留著不動；其餘一律轉成「妳」。 */
export function normalizePartnerPronoun(line: string | null): string | null {
  return line === null ? null : line.replace(/你(?!們)/g, "妳");
}
