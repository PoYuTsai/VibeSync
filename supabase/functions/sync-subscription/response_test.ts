import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { readAuthoritativeSubscriptionAggregate } from "./response.ts";

Deno.test("sync response uses the re-read legacy aggregate as authority", () => {
  const aggregate = readAuthoritativeSubscriptionAggregate({
    tier: "essential",
    monthly_messages_used: 4,
    daily_messages_used: 2,
    monthly_reset_at: "2026-08-01T00:00:00.000Z",
    daily_reset_at: "2026-08-23T00:00:00.000Z",
    expires_at: "2026-10-23T12:00:00.000Z",
    active_product_id: "essential:essential-monthly",
    billing_period: "monthly",
    store: "play_store",
    revenuecat_environment: "production",
  });

  assertEquals(aggregate, {
    tier: "essential",
    monthlyMessagesUsed: 4,
    dailyMessagesUsed: 2,
    monthlyResetAt: "2026-08-01T00:00:00.000Z",
    dailyResetAt: "2026-08-23T00:00:00.000Z",
    expiresAt: "2026-10-23T12:00:00.000Z",
    activeProductId: "essential:essential-monthly",
    billingPeriod: "monthly",
    store: "play_store",
    revenueCatEnvironment: "production",
  });
});

Deno.test("sync response fails closed when the legacy aggregate is absent", () => {
  assertEquals(readAuthoritativeSubscriptionAggregate(null), null);
});
