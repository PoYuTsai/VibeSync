import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";

import { shouldResetUsageOnTierSync } from "./usage_reset.ts";

Deno.test("shouldResetUsageOnTierSync resets usage on confirmed paid upgrade", () => {
  assertEquals(
    shouldResetUsageOnTierSync({
      resetUsageRequested: true,
      previousTier: "free",
      finalTier: "essential",
      revenueCatTier: "essential",
      tierPreservedReason: null,
    }),
    true,
  );
});

Deno.test("shouldResetUsageOnTierSync preserves usage when client did not request reset", () => {
  assertEquals(
    shouldResetUsageOnTierSync({
      resetUsageRequested: false,
      previousTier: "free",
      finalTier: "essential",
      revenueCatTier: "essential",
      tierPreservedReason: null,
    }),
    false,
  );
});

Deno.test("shouldResetUsageOnTierSync preserves usage on same-tier restore", () => {
  assertEquals(
    shouldResetUsageOnTierSync({
      resetUsageRequested: true,
      previousTier: "essential",
      finalTier: "essential",
      revenueCatTier: "essential",
      tierPreservedReason: null,
    }),
    false,
  );
});

Deno.test("shouldResetUsageOnTierSync preserves usage on downgrade or free snapshot guards", () => {
  assertEquals(
    shouldResetUsageOnTierSync({
      resetUsageRequested: true,
      previousTier: "essential",
      finalTier: "essential",
      revenueCatTier: "starter",
      tierPreservedReason: "scheduled_paid_downgrade",
    }),
    false,
  );

  assertEquals(
    shouldResetUsageOnTierSync({
      resetUsageRequested: true,
      previousTier: "essential",
      finalTier: "essential",
      revenueCatTier: "free",
      tierPreservedReason: "paid_tier_free_snapshot_guard",
    }),
    false,
  );
});

Deno.test("shouldResetUsageOnTierSync never resets when final tier is free", () => {
  assertEquals(
    shouldResetUsageOnTierSync({
      resetUsageRequested: true,
      previousTier: "starter",
      finalTier: "free",
      revenueCatTier: "free",
      tierPreservedReason: null,
    }),
    false,
  );
});
