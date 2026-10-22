// 什麼請求走 v3：開關 ANALYZE_GUIDE_V3（每次請求讀）＋App 宣告協定版本 3。
// 另外是 F04 的扣費字數：協定版本 ≥3 的 App 會把「她最後一則之後他傳的」也送進來
//（分析要看），但不算費（Eric 10/16）；這條跟開關無關，App 端照同一規則算。
import { ANALYSIS_CONTRACT_VERSION_V3 } from "../no_send_decision.ts";

export type GuideV3Mode = "off" | "test" | "on";

/// 沒設、打錯都當 off。
export function guideV3Mode(raw: string | undefined): GuideV3Mode {
  const value = raw?.trim().toLowerCase();
  return value === "on" || value === "test" ? value : "off";
}

/// 只接新的分析；續看（帶 analysisRunId）一律交給 v2 handler，它認得 v3 的 run
///（只重播、不 retry），也接得住開關剛打開前建立的 v2 run。
export function shouldUseGuideV3(args: {
  readonly mode: GuideV3Mode;
  readonly contractVersion: number;
  readonly accountIsTest: boolean;
  readonly isResume: boolean;
}): boolean {
  if (args.isResume) return false;
  if (args.contractVersion < ANALYSIS_CONTRACT_VERSION_V3) return false;
  return args.mode === "on" || (args.mode === "test" && args.accountIsTest);
}

/// v3 分析順便更新對象記憶（targetProfile）：開關 ANALYZE_GUIDE_V3_MEMORY，跟
/// ANALYZE_GUIDE_V3 一樣 off／test／on（test＝測試帳號）。沒開就不多打這一次模型
///（Eric 2026-10-18）。
export function shouldExtractGuideV3Memory(args: {
  readonly mode: GuideV3Mode;
  readonly accountIsTest: boolean;
}): boolean {
  return args.mode === "on" || (args.mode === "test" && args.accountIsTest);
}

/// 讀局面順便給關係階段、熱度與四個維度（relation.ts）：開關 ANALYZE_GUIDE_V3_RELATION，跟
/// ANALYZE_GUIDE_V3 一樣 off／test／on。沒開就讀局面的提示詞、schema 與送給 App 的判讀一字
/// 不變（Bruce 2026-10-19 路線二）。
export function shouldReadGuideV3Relation(args: {
  readonly mode: GuideV3Mode;
  readonly accountIsTest: boolean;
}): boolean {
  return args.mode === "on" || (args.mode === "test" && args.accountIsTest);
}

/// v3 分析帶上一輪脈絡（previousRound，見 previous_round.ts）：開關
/// ANALYZE_GUIDE_V3_PREV_ROUND，跟 ANALYZE_GUIDE_V3 一樣 off／test／on。沒開就不讀
/// 這個欄位，兩段提示詞一字不變（Eric 2026-10-18）。
export function shouldUseGuideV3PreviousRound(args: {
  readonly mode: GuideV3Mode;
  readonly accountIsTest: boolean;
}): boolean {
  return args.mode === "on" || (args.mode === "test" && args.accountIsTest);
}

/// 兩段式「正常回覆」實驗（Eric 2026-10-19 兩段式實驗）：開關 ANALYZE_GUIDE_V3_TWO_STAGE，
/// 跟 ANALYZE_GUIDE_V3 一樣 off／test／on。開了才讀局面多幾個標記、寫卡改用拿掉立場段的
/// 提示詞、寫完卡另打一次「為什麼這樣回」；沒開就跟今天一字不差。
export function shouldUseGuideV3TwoStage(args: {
  readonly mode: GuideV3Mode;
  readonly accountIsTest: boolean;
}): boolean {
  return args.mode === "on" || (args.mode === "test" && args.accountIsTest);
}

/// 口吻與斷句交給程式（Bruce 2026-10-20 改法 3，typing_style.ts）：開關 ANALYZE_GUIDE_V3_TYPING_STYLE，
/// 跟 ANALYZE_GUIDE_V3 一樣 off／test／on。開了才把每張卡的稱呼與斷句照他的打字習慣統一；沒開就
/// 跟今天一字不差。
export function shouldUseGuideV3TypingStyle(args: {
  readonly mode: GuideV3Mode;
  readonly accountIsTest: boolean;
}): boolean {
  return args.mode === "on" || (args.mode === "test" && args.accountIsTest);
}

/// 短版稱讚（Bruce 2026-10-20「可以」）：開關 ANALYZE_GUIDE_V3_SHORT_PRAISE，跟 ANALYZE_GUIDE_V3 一樣
/// off／test／on，只在兩段式開著時才有作用（入口把關）。沒開跟今天一字不差。
export function shouldUseGuideV3ShortPraise(args: {
  readonly mode: GuideV3Mode;
  readonly accountIsTest: boolean;
}): boolean {
  return args.mode === "on" || (args.mode === "test" && args.accountIsTest);
}

/// 帶張力改寫法 v2（Bruce 2026-10-21「改」：推拉換成三條不要，見 two_stage_prompts.ts）：開關 ANALYZE_GUIDE_V3_TENSION_STYLE，跟 ANALYZE_GUIDE_V3 一樣
/// off／test／on，只在兩段式開著時才有作用（入口把關）。排卡不變，只換寫卡與說明看到的帶張力寫法。
export function shouldUseGuideV3TensionStyle(args: {
  readonly mode: GuideV3Mode;
  readonly accountIsTest: boolean;
}): boolean {
  return args.mode === "on" || (args.mode === "test" && args.accountIsTest);
}

/// 「這題」「滿→蠻」交給程式（Bruce 2026-10-20 PR #97 再處理，2026-10-21 只用這兩條；phrase_tidy.ts）：開關
/// ANALYZE_GUIDE_V3_PHRASE_TIDY，跟 ANALYZE_GUIDE_V3 一樣 off／test／on。開了才在口吻與斷句之後改這兩種字；
/// 沒開就跟今天一字不差。
export function shouldUseGuideV3PhraseTidy(args: {
  readonly mode: GuideV3Mode;
  readonly accountIsTest: boolean;
}): boolean {
  return args.mode === "on" || (args.mode === "test" && args.accountIsTest);
}

/// 甜話短回（Eric 2026-10-22「照預設」，Bruce 2026-10-22：她說很短的甜話，短短回就好；見 rules.ts arrangeSweetShort）：開關
/// ANALYZE_GUIDE_V3_SWEET_SHORT，跟 ANALYZE_GUIDE_V3 一樣 off／test／on，只在兩段式開著時才有作用（入口把關）。讀局面逐則
/// 多標「撒嬌」，她這一輪有撒嬌的很短的一則時只有一張卡回那句、其他卡回她別的話，沒有別的話就少出幾張；沒開跟今天一字不差。
export function shouldUseGuideV3SweetShort(args: {
  readonly mode: GuideV3Mode;
  readonly accountIsTest: boolean;
}): boolean {
  return args.mode === "on" || (args.mode === "test" && args.accountIsTest);
}

/// F04 不算費的上限：她最後一則之後他連續傳的，最多 5 則、合計 300 字（字數照
/// billing.ts 的 trim 後長度）。超過、或整段對話都是他的，就照舊全部算費——
/// 不然可以把大段內容標成「他傳的」放在最後，免費分析還繞過 4000 字上限。
export const F04_MAX_EXCLUDED_MESSAGES = 5;
export const F04_MAX_EXCLUDED_CHARS = 300;

/// F04：協定版本 ≥3 的一般文字串流分析，扣費字數與超額確認雜湊不算對話最後面
/// 連續的「他」的訊息（在上限內）。「我說」模式最後一則一定是他的，不適用。
export function billingMessagesFor<
  T extends { readonly isFromMe: boolean; readonly content: string },
>(
  messages: readonly T[],
  request: {
    readonly contractVersion: number;
    readonly plainStreamAnalysis: boolean;
  },
): T[] {
  if (
    request.contractVersion < ANALYSIS_CONTRACT_VERSION_V3 ||
    !request.plainStreamAnalysis
  ) return [...messages];
  let end = messages.length;
  while (end > 0 && messages[end - 1].isFromMe) end--;
  const excluded = messages.slice(end);
  const excludedChars = excluded.reduce(
    (total, m) => total + m.content.trim().length,
    0,
  );
  if (
    end === 0 || excluded.length > F04_MAX_EXCLUDED_MESSAGES ||
    excludedChars > F04_MAX_EXCLUDED_CHARS
  ) return [...messages];
  return messages.slice(0, end);
}
