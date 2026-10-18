// analyze-chat 的反 prompt 外洩接線（2026-08-19，Eric 拍板）。
// 共用實作在 ../_shared/prompt_leak_guard.ts；這裡只放本 function 的
// sentinel 清單（各 system prompt 的內部行話長片段，正常輸出絕不出現）。
import {
  containsPromptLeak,
  PROMPT_LEAK_DEFENSE_DIRECTIVE,
} from "../_shared/prompt_leak_guard.ts";

export { PROMPT_LEAK_DEFENSE_DIRECTIVE };

/// 對話分析 v3 讀局面、寫卡提示詞（guide_v3/prompts.ts）的片段（Eric 2026-10-18 盤點）：
/// 舊清單沒有 v3 的；說明書每節第一行另有哨兵（guide_v3/finalize.ts）。都是給模型的角色與
/// 輸出格式指示，不含「用戶」這類簡轉繁會改的詞；prompt_leak_test 鎖住它們都在提示詞裡、
/// 重播錄音的卡與判讀一句都不會中。
export const GUIDE_V3_PROMPT_SENTINELS: readonly string[] = [
  "你是 VibeSync 對話分析的「讀局面」步驟",
  "你是 VibeSync 對話分析的「寫句子」步驟",
  "每張卡輸出一行 JSON，照卡片編號順序",
  "編出來的細節要把 hasInventedDetail 設成 true",
  "情境條目的觸發（只回符合的編號）",
  "matchedEntries：下面情境條目的觸發",
];

export const ANALYZE_CHAT_PROMPT_SENTINELS: readonly string[] = [
  // SYSTEM_PROMPT（分析）
  "RelationshipRiskAndTimeCostFrame",
  "你比通用 LLM 更有價值的地方",
  // OPENER_PROMPT
  "Profile Read → Frame → Hook → Opener",
  "你是 VibeSync 的開場救星先鋒教練",
  // 舊版新話題提示詞（2026-10-09 移除；片段留著擋舊輸出外洩）
  "唯一可以當成**對方事實**的來源",
  // QUICK_SYSTEM_PROMPT
  "你是 VibeSync 的核心判斷教練",
  // OPTIMIZE_MESSAGE_PROMPT / REFINE_REPLY_SYSTEM_PROMPT
  "你是 VibeSync 的草稿潤飾器",
  "你是 VibeSync 的回覆微調器",
  // 對話分析 v3（guide_v3/prompts.ts）
  ...GUIDE_V3_PROMPT_SENTINELS,
];

export function hasAnalyzeChatPromptLeak(
  text: string | null | undefined,
): boolean {
  return containsPromptLeak(text, ANALYZE_CHAT_PROMPT_SENTINELS);
}

/** 新話題結構刀（ADR #53）的系統提示詞片段；正常輸出不會出現。 */
export const NEW_TOPIC_SLOTS_PROMPT_SENTINELS: readonly string[] = [
  "這次的五題已經由教練排好",
  "一題一個任務各寫一題",
];

export function hasNewTopicSlotsPromptLeak(
  text: string | null | undefined,
): boolean {
  return containsPromptLeak(text, [
    ...ANALYZE_CHAT_PROMPT_SENTINELS,
    ...NEW_TOPIC_SLOTS_PROMPT_SENTINELS,
  ]);
}
