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

export function shouldUseGuideV3(args: {
  readonly mode: GuideV3Mode;
  readonly contractVersion: number;
  readonly accountIsTest: boolean;
}): boolean {
  if (args.contractVersion < ANALYSIS_CONTRACT_VERSION_V3) return false;
  return args.mode === "on" || (args.mode === "test" && args.accountIsTest);
}

/// F04 不算費的上限：她最後一則之後他連續傳的，最多 5 則、合計 300 字（字數照
/// billing.ts 的 trim 後長度）。超過、或整段對話都是他的，就照舊全部算費——
/// 不然可以把大段內容標成「他傳的」放在最後，免費分析還繞過 4000 字上限。
export const F04_MAX_EXCLUDED_MESSAGES = 5;
export const F04_MAX_EXCLUDED_CHARS = 300;

/// F04：協定版本 ≥3 時，扣費字數與超額確認雜湊不算對話最後面連續的「他」的訊息
///（在上限內）。
export function billingMessagesFor<
  T extends { readonly isFromMe: boolean; readonly content: string },
>(messages: readonly T[], contractVersion: number): T[] {
  if (contractVersion < ANALYSIS_CONTRACT_VERSION_V3) return [...messages];
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
