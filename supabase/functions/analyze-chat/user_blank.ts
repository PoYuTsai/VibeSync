// 留給用戶自己填的空格（Bruce 2026-10-18 #97：三個功能留空格一律用「＿＿」）。
//
// 對話分析 v3 的卡片早就這樣寫（guide_v3/wire.ts 的 BLANK_PATTERN、refine_card.ts 的
// BLANK_RUN）；開場救星與新話題照同一個記號，App 端用同一套判斷（guide_v3_result.dart 的
// guideV3TextHasBlank）擋「空格沒填就複製」。
//
// 純 helper：不 import server、不碰 DB、不連網。

/** 給用戶看、也寫進提示詞的空格。 */
export const USER_BLANK = "＿＿";

// 模型偶爾寫成半形底線、三個以上的全形底線，或只寫一個「＿」；都收成同一個記號。
// 半形要兩個以上才算（一個「_」可能是英文字裡的底線）。
const BLANK_VARIANTS = /＿+|_{2,}/g;

/** 把各種寫法的空格收成「＿＿」；沒有空格就原樣回傳。 */
export function normalizeUserBlanks(text: string): string {
  return text.replace(BLANK_VARIANTS, USER_BLANK);
}

/**
 * 收成「＿＿」之後再量一次長度：一個「＿」補成兩個會多一個字，剛好在上限的句子會超過
 * （主審第 1 輪 P2-2）。超過就回 null，讓呼叫端照「這一欄不合格」處理。
 */
export function normalizeUserBlanksWithin(
  text: string,
  maxLength: number,
): string | null {
  const normalized = normalizeUserBlanks(text);
  return normalized.length <= maxLength ? normalized : null;
}

/** 句子裡有沒有留給用戶填的空格（「＿」連著算一段，跟 App 的判斷一致）。 */
export function hasUserBlank(text: string): boolean {
  return text.includes("＿");
}
