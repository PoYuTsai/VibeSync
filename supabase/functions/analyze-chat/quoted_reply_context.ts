// supabase/functions/analyze-chat/quoted_reply_context.ts
// 把「引用回覆」脈絡前綴的組裝抽成可測純函式（原本內嵌在 index.ts
// formatConversationLine 的 closure 裡，無法單測）。

export interface QuotedReplyContext {
  quotedReplyPreview?: string;
  quotedReplyPreviewIsFromMe?: boolean | null;
}

/**
 * 組裝餵給模型的引用回覆前綴，例如 ` (replying to: "原文")`。
 *
 * 設計拍板（Eric 2026-06-13）：一律中性、不做認人歸屬。
 * 認人（把引用卡對應到你/她）不可靠——單側截圖無「我說」可當錨點，模型只能
 * 靠「引用卡名＝對方名」推自我引用，推不準就把女生「接著自己稍早說的」誤寫成
 * 「引用剛剛對方說的」。中性永不錯，故刻意丟棄 quotedReplyPreviewIsFromMe，
 * 不輸出 my/her earlier message。
 */
export function buildQuotedReplyPrefix(message: QuotedReplyContext): string {
  const quotedReplyPreview = message.quotedReplyPreview?.trim()
    ? message.quotedReplyPreview.trim().replace(/\s+/g, " ").replace(/"/g, "'")
    : "";
  return quotedReplyPreview ? ` (replying to: "${quotedReplyPreview}")` : "";
}
