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

Deno.test("quota usage: optimize-message is fixed at one regardless of context estimate", () => {
  const requestType = deriveRequestType({
    recognizeOnly: false,
    hasImages: false,
    isMyMessageMode: false,
    hasUserDraft: true,
  });

  assertEquals(requestType, "optimize_message");
  assertEquals(
    buildQuotaUsageMetadata({
      requestType,
      recognizeOnly: false,
      accountIsTest: false,
      estimatedMessageCount: 20,
    }),
    {
      shouldChargeQuota: true,
      quotaReason: "optimize_message_fixed_1",
      quotaUnit: "messages",
      chargedMessageCount: 1,
      estimatedMessageCount: 1,
    },
  );
});

Deno.test("quota usage: optimize-message remains free for test accounts", () => {
  assertEquals(
    buildQuotaUsageMetadata({
      requestType: "optimize_message",
      recognizeOnly: false,
      accountIsTest: true,
      estimatedMessageCount: 20,
    }),
    {
      shouldChargeQuota: false,
      quotaReason: "test_account_waived",
      quotaUnit: "messages",
      chargedMessageCount: 0,
      estimatedMessageCount: 1,
    },
  );
});
