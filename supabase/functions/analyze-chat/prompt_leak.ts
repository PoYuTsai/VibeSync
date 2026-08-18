// analyze-chat 的反 prompt 外洩接線（2026-08-19，Eric 拍板）。
// 共用實作在 ../_shared/prompt_leak_guard.ts；這裡只放本 function 的
// sentinel 清單（各 system prompt 的內部行話長片段，正常輸出絕不出現）。
import {
  containsPromptLeak,
  PROMPT_LEAK_DEFENSE_DIRECTIVE,
} from "../_shared/prompt_leak_guard.ts";

export { PROMPT_LEAK_DEFENSE_DIRECTIVE };

export const ANALYZE_CHAT_PROMPT_SENTINELS: readonly string[] = [
  // SYSTEM_PROMPT（分析）
  "RelationshipRiskAndTimeCostFrame",
  "你比通用 LLM 更有價值的地方",
  // OPENER_PROMPT
  "Profile Read → Frame → Hook → Opener",
  "你是 VibeSync 的開場救星先鋒教練",
  // NEW_TOPIC_PROMPT
  "唯一可以當成**對方事實**的來源",
  // QUICK_SYSTEM_PROMPT
  "你是 VibeSync 的核心判斷教練",
  // OPTIMIZE_MESSAGE_PROMPT / REFINE_REPLY_SYSTEM_PROMPT
  "你是 VibeSync 的草稿潤飾器",
  "你是 VibeSync 的回覆微調器",
];

export function hasAnalyzeChatPromptLeak(
  text: string | null | undefined,
): boolean {
  return containsPromptLeak(text, ANALYZE_CHAT_PROMPT_SENTINELS);
}
