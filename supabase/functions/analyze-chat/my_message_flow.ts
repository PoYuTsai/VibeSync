// MyMessage（我說模式）流程守門：請求形狀（最新訊息必須是用戶自己說的）
// 與 Essential 方案 gate（唯一仍收費牆的分析功能；RevenueCat refresh 後
// 再判一次才拒絕）。Prompt 本體在 my_message_prompt.ts。

import type { AnalyzeMessage } from "./analysis_input_compiler.ts";
import { jsonResponse } from "./http_response.ts";
import type { TierSyncRefreshStatus } from "./tier_sync_contract.ts";

/// my_message 模式要求最新一則訊息來自用戶本人（400 不扣費）。
export function validateMyMessageShape(
  messages: AnalyzeMessage[],
): Response | null {
  if (!messages[messages.length - 1]?.isFromMe) {
    return jsonResponse({
      error: "my_message mode requires the latest message to be from the user",
    }, 400);
  }
  return null;
}

/// 「我說」是唯一仍限 Essential 的分析功能（optimize/refine 已開放全方案
/// 按額度計費）。tier 不足時先試 RevenueCat refresh，refresh 後仍不足才 403。
export async function enforceMyMessageEssentialGate(args: {
  refreshTierFromRevenueCat: (
    reason: string,
  ) => Promise<TierSyncRefreshStatus>;
  /// refresh applied 會改寫 handler 端 effectiveTier，必須以 getter 重讀。
  readEffectiveTier: () => string;
}): Promise<Response | null> {
  if (args.readEffectiveTier() === "essential") return null;
  const refreshStatus = await args.refreshTierFromRevenueCat(
    "feature_gate_my_message",
  );
  const refreshed = refreshStatus === "applied";
  if (!(refreshed && args.readEffectiveTier() === "essential")) {
    return jsonResponse({
      error: "「我說」分析功能僅限 Essential 方案",
      code: "FEATURE_NOT_AVAILABLE",
      requiredTier: "essential",
    }, 403);
  }
  return null;
}
