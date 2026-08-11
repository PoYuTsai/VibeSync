const RAW_IMAGE_FILENAME_PATTERN_SOURCE = String
  .raw`(?:[A-Za-z]:)?(?:[\\/][^\s\\/]+)*[\\/]?(?:S__\d+(?:\.(?:jpe?g|png|webp|heic))?|IMG_\d+(?:\.(?:jpe?g|png|webp|heic))?|[^\\/\s]+\.(?:jpe?g|png|webp|heic))`;

const RAW_IMAGE_FILENAME_REPLACE_PATTERN = new RegExp(
  RAW_IMAGE_FILENAME_PATTERN_SOURCE,
  "gi",
);
const RAW_IMAGE_FILENAME_TEST_PATTERN = new RegExp(
  RAW_IMAGE_FILENAME_PATTERN_SOURCE,
  "i",
);

export const IMAGE_CONCEPT_PLACEHOLDER = "[image concept omitted]";

export function containsRawImageFilename(text: string): boolean {
  return RAW_IMAGE_FILENAME_TEST_PATTERN.test(text);
}

export function scrubRawImageFilenames(text: string): string {
  return text.replace(
    RAW_IMAGE_FILENAME_REPLACE_PATTERN,
    IMAGE_CONCEPT_PLACEHOLDER,
  );
}

export function clipUtf16Safe(text: string, maxCodeUnits: number): string {
  if (maxCodeUnits <= 0) return "";
  if (text.length <= maxCodeUnits) return text;
  let end = maxCodeUnits;
  const lastCodeUnit = text.charCodeAt(end - 1);
  if (lastCodeUnit >= 0xD800 && lastCodeUnit <= 0xDBFF) {
    end -= 1;
  }
  return text.slice(0, end);
}

/**
 * 多則訊息攤平成逐字稿單行時保留則界。
 *
 * 2026-08-11 起 NPC 可以像真人一樣一次連發 2-3 則（換行分則）。逐字稿是
 * `role: text` 的逐行格式，直接帶換行會讓第二則看起來像新的一行、甚至像
 * 沒有角色前綴的注入內容；直接壓成空白則會把三則讀成一則、丟掉「她連發＝
 * 很投入」這個訊號。
 *
 * 用引號把每一則包起來，不要用「｜」這種分隔符——2026-08-11 離線重放實測：
 * 模型會把逐字稿裡的分隔符當成輸出格式抄走，產出「追劇喔｜那妳會邊吃東西嗎」
 * 這種單則裡塞直線的句子。引號是內容標記不是分隔符，不會被誤抄。
 */
export function flattenMultiBubbleText(text: string): string {
  const parts = text.split(/\n+/u).map((part) => part.trim()).filter(Boolean);
  if (parts.length <= 1) return text.replace(/\s*\n+\s*/gu, " ").trim();
  return parts.map((part) => `「${part}」`).join("");
}

/**
 * 模型偶爾把換行寫成字面的反斜線 n 而不是真的換行（2026-08-11 離線重放實測
 * 抓到兩則）。分則靠換行，字面反斜線會直接顯示給使用者，看起來像壞掉。
 * 中文聊天不會有人真的想打反斜線 n，直接修成換行。
 */
export function normalizeLiteralNewlines(text: string): string {
  return text.replace(/\\n/g, "\n");
}
