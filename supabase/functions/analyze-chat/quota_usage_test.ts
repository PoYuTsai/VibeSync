import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { buildQuotaUsageMetadata, deriveRequestType } from "./quota_usage.ts";

Deno.test("quota usage: recognizeOnly is always free and does not charge messages", () => {
  const requestType = deriveRequestType({
    recognizeOnly: true,
    hasImages: true,
    isMyMessageMode: false,
    hasUserDraft: false,
  });

  assertEquals(requestType, "recognize_only");
  assertEquals(
    buildQuotaUsageMetadata({
      requestType,
      recognizeOnly: true,
      accountIsTest: false,
      estimatedMessageCount: 18,
    }),
    {
      shouldChargeQuota: false,
      quotaReason: "recognize_only_free",
      quotaUnit: "messages",
      chargedMessageCount: 0,
      estimatedMessageCount: 0,
    },
  );
});

Deno.test("quota usage: free screenshot follow-up analysis remains message-based", () => {
  const requestType = deriveRequestType({
    recognizeOnly: false,
    hasImages: false,
    isMyMessageMode: false,
    hasUserDraft: false,
  });

  assertEquals(requestType, "analyze");
  assertEquals(
    buildQuotaUsageMetadata({
      requestType,
      recognizeOnly: false,
      accountIsTest: false,
      estimatedMessageCount: 12,
    }),
    {
      shouldChargeQuota: true,
      quotaReason: "analyze_message_based",
      quotaUnit: "messages",
      chargedMessageCount: 12,
      estimatedMessageCount: 12,
    },
  );
});

Deno.test("quota usage: direct image analysis is charged by message count, not image count", () => {
  const requestType = deriveRequestType({
    recognizeOnly: false,
    hasImages: true,
    isMyMessageMode: false,
    hasUserDraft: false,
  });

  assertEquals(requestType, "analyze_with_images");
  assertEquals(
    buildQuotaUsageMetadata({
      requestType,
      recognizeOnly: false,
      accountIsTest: false,
      estimatedMessageCount: 3,
    }),
    {
      shouldChargeQuota: true,
      quotaReason: "analyze_with_images_message_based",
      quotaUnit: "messages",
      chargedMessageCount: 3,
      estimatedMessageCount: 3,
    },
  );
});
