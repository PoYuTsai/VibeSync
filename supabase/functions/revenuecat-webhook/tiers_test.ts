import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";

import { resolveBillingIssueTier } from "./tiers.ts";

Deno.test(
  "resolveBillingIssueTier preserves paid tier from product id when DB row is missing",
  () => {
    assertEquals(
      resolveBillingIssueTier({
        currentTier: "free",
        productId: "vibesync_essential_monthly_v2",
      }),
      "essential",
    );
  },
);

Deno.test(
  "resolveBillingIssueTier keeps existing paid tier when product id is unavailable",
  () => {
    assertEquals(
      resolveBillingIssueTier({
        currentTier: "starter",
        productId: "unknown_product",
      }),
      "starter",
    );
  },
);

Deno.test(
  "resolveBillingIssueTier refuses to persist free when neither DB nor product id is paid",
  () => {
    assertEquals(
      resolveBillingIssueTier({
        currentTier: "free",
        productId: "unknown_product",
      }),
      null,
    );
  },
);
