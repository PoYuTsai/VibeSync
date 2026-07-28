import { OPTIMIZE_MESSAGE_COST } from "./optimize_message_billing.ts";

export function deriveRequestType({
  recognizeOnly,
  hasImages,
  isMyMessageMode,
  hasUserDraft,
  hasRefineInstruction = false,
}: {
  recognizeOnly: boolean;
  hasImages: boolean;
  isMyMessageMode: boolean;
  hasUserDraft: boolean;
  /// 預設 false，讓沒有帶指令的舊 client 分類與今日完全相同。
  hasRefineInstruction?: boolean;
}): string {
  if (recognizeOnly) {
    return "recognize_only";
  }
  if (hasImages) {
    return "analyze_with_images";
  }
  if (isMyMessageMode) {
    return "my_message";
  }
  if (hasUserDraft) {
    return hasRefineInstruction ? "refine_reply" : "optimize_message";
  }
  return "analyze";
}

export function buildQuotaUsageMetadata({
  requestType,
  recognizeOnly,
  accountIsTest,
  estimatedMessageCount,
  refineIsFree = false,
}: {
  requestType: string;
  recognizeOnly: boolean;
  accountIsTest: boolean;
  estimatedMessageCount: number;
  /// 只對 `refine_reply` 有意義：這次是否落在今天的免費額度內。
  /// 預設 false，其餘 requestType 的行為與今日一字不差。
  refineIsFree?: boolean;
}) {
  if (recognizeOnly) {
    return {
      shouldChargeQuota: false,
      quotaReason: "recognize_only_free",
      quotaUnit: "messages",
      chargedMessageCount: 0,
      estimatedMessageCount: 0,
    };
  }

  if (accountIsTest) {
    // 微調也是固定 1 則的定價，估算不得落回按訊息數算——測試帳號雖然不扣，
    // estimatedMessageCount 會被 client 拿去顯示「這次要用幾則」。
    // 免費額度內則估 0，顯示才不會嚇到人。
    const waivedEstimate = requestType === "refine_reply"
      ? (refineIsFree ? 0 : OPTIMIZE_MESSAGE_COST)
      : requestType === "optimize_message"
      ? OPTIMIZE_MESSAGE_COST
      : estimatedMessageCount;
    return {
      shouldChargeQuota: false,
      quotaReason: "test_account_waived",
      quotaUnit: "messages",
      chargedMessageCount: 0,
      estimatedMessageCount: waivedEstimate,
    };
  }

  if (requestType === "refine_reply") {
    // 額度用完不是拒絕，是轉為扣 1 則走既有 optimize_message 帳本。
    return refineIsFree
      ? {
        shouldChargeQuota: false,
        quotaReason: "refine_free_daily",
        quotaUnit: "messages",
        chargedMessageCount: 0,
        estimatedMessageCount: 0,
      }
      : {
        shouldChargeQuota: true,
        quotaReason: "refine_reply_fixed_1",
        quotaUnit: "messages",
        chargedMessageCount: OPTIMIZE_MESSAGE_COST,
        estimatedMessageCount: OPTIMIZE_MESSAGE_COST,
      };
  }

  if (requestType === "optimize_message") {
    return {
      shouldChargeQuota: true,
      quotaReason: "optimize_message_fixed_1",
      quotaUnit: "messages",
      chargedMessageCount: OPTIMIZE_MESSAGE_COST,
      estimatedMessageCount: OPTIMIZE_MESSAGE_COST,
    };
  }

  let quotaReason = "analyze_message_based";
  switch (requestType) {
    case "analyze_with_images":
      quotaReason = "analyze_with_images_message_based";
      break;
    case "my_message":
      quotaReason = "my_message_message_based";
      break;
  }

  return {
    shouldChargeQuota: estimatedMessageCount > 0,
    quotaReason,
    quotaUnit: "messages",
    chargedMessageCount: estimatedMessageCount,
    estimatedMessageCount,
  };
}
