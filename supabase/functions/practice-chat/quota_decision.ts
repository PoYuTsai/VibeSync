// practice-chat 額度決策（純函式、零副作用、可 deno test）。
//
// 規則（見 docs/plans/2026-06-24-practice-chat-mvp-design.md）：
//   一場練習 = 扣 1 則 Coach 額度，且只在「session 第一則 AI 回覆成功」時扣。
//   - chat 模式：aiTurnCount === 0（這次是本場第一則 AI 回覆）才扣。
//   - debrief 模式：永不扣（同一場已付過）。
//   - 測試帳號：永不扣。
//   - 任何失敗（API/format）由 handler 在扣點前 return，故失敗一律不扣。

export const MAX_AI_REPLIES = 10;
export const PRACTICE_QUOTA_COST = 1;

export type PracticeMode = "chat" | "debrief";

/** 一場已產生 aiTurnCount 則 AI 回覆後，是否已達上限（不能再聊）。 */
export function isSessionComplete(aiTurnCount: number): boolean {
  return aiTurnCount >= MAX_AI_REPLIES;
}

/**
 * 本次請求是否應扣 1 則額度。
 * @param mode          chat | debrief
 * @param aiTurnCount   本場「已存在」的 AI 回覆數（不含這次待生成的）
 * @param isTestAccount 測試帳號跳過扣點
 */
export function decideDeduction(opts: {
  mode: PracticeMode;
  aiTurnCount: number;
  isTestAccount: boolean;
}): { shouldDeduct: boolean } {
  if (opts.isTestAccount) return { shouldDeduct: false };
  if (opts.mode !== "chat") return { shouldDeduct: false };
  // 只有本場第一則 AI 回覆扣點；之後（含 debrief）免費。
  return { shouldDeduct: opts.aiTurnCount === 0 };
}
