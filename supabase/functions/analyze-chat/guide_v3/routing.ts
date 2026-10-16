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

/// F04：協定版本 ≥3 時，扣費字數與超額確認雜湊不算對話最後面連續的「他」的訊息。
export function billingMessagesFor<T extends { readonly isFromMe: boolean }>(
  messages: readonly T[],
  contractVersion: number,
): T[] {
  if (contractVersion < ANALYSIS_CONTRACT_VERSION_V3) return [...messages];
  let end = messages.length;
  while (end > 0 && messages[end - 1].isFromMe) end--;
  return messages.slice(0, end);
}
