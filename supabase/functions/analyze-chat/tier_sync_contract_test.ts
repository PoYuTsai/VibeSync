import {
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  finalizeTierSyncRefreshStatus,
  shouldFailPaidTierSync,
  streamReplyStylesForTier,
  type TierSyncRefreshStatus,
} from "./tier_sync_contract.ts";

Deno.test("shouldFailPaidTierSync blocks paid expected tier when RevenueCat refresh is unavailable", () => {
  const unavailableStatuses: TierSyncRefreshStatus[] = [
    "not_configured",
    "unavailable",
  ];

  for (const refreshStatus of unavailableStatuses) {
    assertEquals(
      shouldFailPaidTierSync({
        expectedTier: "essential",
        currentTier: "free",
        refreshStatus,
      }),
      true,
    );
  }
});

Deno.test("shouldFailPaidTierSync does not trust client expected tier when RevenueCat says not paid", () => {
  assertFalse(
    shouldFailPaidTierSync({
      expectedTier: "essential",
      currentTier: "free",
      refreshStatus: "not_paid",
    }),
  );
});

Deno.test("finalizeTierSyncRefreshStatus treats a valid free subscriber as authoritative not paid", () => {
  assertEquals(
    finalizeTierSyncRefreshStatus({
      sawValidSubscriber: true,
      sawUnavailableCandidate: true,
    }),
    "not_paid",
  );
});

Deno.test("shouldFailPaidTierSync allows already-confirmed paid server tier", () => {
  assertFalse(
    shouldFailPaidTierSync({
      expectedTier: "essential",
      currentTier: "essential",
      refreshStatus: "not_configured",
    }),
  );
});

Deno.test("streamReplyStylesForTier returns the required style set for each tier", () => {
  assertEquals(streamReplyStylesForTier("free"), ["extend"]);
  assertEquals(streamReplyStylesForTier("starter"), [
    "extend",
    "resonate",
    "tease",
    "humor",
    "coldRead",
  ]);
  assertEquals(streamReplyStylesForTier("essential"), [
    "extend",
    "resonate",
    "tease",
    "humor",
    "coldRead",
  ]);
});
