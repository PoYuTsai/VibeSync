// 兩段式「正常回覆」實驗（開關 ANALYZE_GUIDE_V3_TWO_STAGE，Eric 2026-10-19 兩段式實驗）的提示詞：
// 照 Bruce 10/19「先生成回覆，再用說明書的內容來教」。這裡放開關開了才用的字，開關沒開的
// 提示詞（prompts.ts）一字不動。說明書原文仍只在 guide_text.ts、entries.ts。
import { PROMPT_LEAK_DEFENSE_DIRECTIVE } from "../../_shared/prompt_leak_guard.ts";
import { GUIDE_V3_ENTRIES, type GuideV3Entry } from "./entries.ts";
import { GUIDE_V3_SECTIONS, type GuideV3SectionId } from "./guide_text.ts";
import type { GuideV3PreviousRound } from "./previous_round.ts";
import {
  type GuideV3Background,
  readSystemPrompt,
  readUserPrompt,
} from "./prompts.ts";
import type { Turn } from "./turns.ts";

/// 讀局面多輸出的四欄，以及作戰板標籤靠不住時怎麼判（研究報告 §5.3、§7.2：v3 把 App 預設的
/// 「交友軟體／剛認識」當事實，真的情侶被當成剛認識、親暱稱呼被標成風險）。
export const READ_TWO_STAGE_NOTES = `## 兩段式多輸出的欄位
- establishedCouple：兩人已經在交往。作戰板寫「已是伴侶」，或對話看得很清楚（她叫他男朋友或老公、聊到住在一起、提到交往多久）才算；還在曖昧不算。
- herAffection：她這一輪在撒嬌或示愛，例如說想他、要抱抱、說愛他、傳愛心或親親。
- herHappyShare：她這一輪在分享開心或得意的事，例如好消息、自己做的料理、剛經歷的一個好時刻。
- worthyLines：她最新這一輪值得接的訊息，一則一項。line 填對話稿上那一則前面的編號；label 用幾個字寫那則在講什麼；kind 填「情感」（撒嬌、示愛，或帶著開心、難過、生氣的情緒）、「照片或貼圖」（照片、貼圖或只有表情符號），其他都填「其他」。單純附和、語助詞，或跟前一則講同一件事的，可以不列。

## 作戰板標籤跟對話對不上時
- 作戰板上的認識方式、認識多久，有可能只是 App 的預設值，不一定是他自己選的。跟對話內容對不上時，照對話判斷。
- 已經在交往的兩人互用親暱的稱呼、撒嬌，是感情好，不是風險。`;

export function readSystemPromptTwoStage(
  sections: Readonly<Record<GuideV3SectionId, string>> = GUIDE_V3_SECTIONS,
  entries: readonly GuideV3Entry[] = GUIDE_V3_ENTRIES,
  leakDirective: string = PROMPT_LEAK_DEFENSE_DIRECTIVE,
): string {
  return readSystemPrompt(
    sections,
    entries,
    leakDirective,
    READ_TWO_STAGE_NOTES,
  );
}

/// 她最新這一輪逐則編號，worthyLines 才填得出編號。
export function readUserPromptTwoStage(
  turns: readonly Turn[],
  background?: GuideV3Background,
  previousRound?: GuideV3PreviousRound,
): string {
  return readUserPrompt(turns, background, previousRound, true);
}
