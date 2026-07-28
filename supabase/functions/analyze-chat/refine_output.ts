/// 回覆微調的輸出長度上限。
///
/// 相對上限，不是固定上限：固定值會讓本來就長的來源訊息永遠失敗（使用者根本
/// 沒要求變長，只是原句就長）。以輸入為基準只擋「越調越長」——「更詳細一點」
/// 連續按幾輪會把一句話養成一段文章，這在聊天產品裡是壞結果。
///
/// 超過上限一律視為無效結果、不扣費，**不截斷**。截斷會把一句完整的話切在
/// 半途送到使用者手上，比重試一次糟得多。
export const REFINE_MIN_OUTPUT_CHARS = 300;
export const REFINE_OUTPUT_HEADROOM_CHARS = 100;

/// 以 code point 計數，emoji 才不會被算成兩個字。
function charCount(value: string): number {
  return Array.from(value.trim()).length;
}

export function refineMaxOutputChars(sourceDraft: string): number {
  return Math.max(
    REFINE_MIN_OUTPUT_CHARS,
    charCount(sourceDraft) + REFINE_OUTPUT_HEADROOM_CHARS,
  );
}

export function exceedsRefineOutputLimit({
  sourceDraft,
  optimized,
}: {
  sourceDraft: string;
  optimized: string;
}): boolean {
  return charCount(optimized) > refineMaxOutputChars(sourceDraft);
}
