export function deriveRequestType({
  recognizeOnly,
  hasImages,
  isMyMessageMode,
  hasUserDraft,
}: {
  recognizeOnly: boolean;
  hasImages: boolean;
  isMyMessageMode: boolean;
  hasUserDraft: boolean;
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
    return "optimize_message";
  }
  return "analyze";
}

export function buildQuotaUsageMetadata({
  requestType,
  recognizeOnly,
  accountIsTest,
  estimatedMessageCount,
}: {
  requestType: string;
  recognizeOnly: boolean;
  accountIsTest: boolean;
  estimatedMessageCount: number;
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
    return {
      shouldChargeQuota: false,
      quotaReason: "test_account_waived",
      quotaUnit: "messages",
      chargedMessageCount: 0,
      estimatedMessageCount,
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
    case "optimize_message":
      quotaReason = "optimize_message_message_based";
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
