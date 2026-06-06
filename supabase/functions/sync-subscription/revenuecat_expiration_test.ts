import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";

import {
  latestActiveExpirationDateFromRevenueCatPayload,
  latestIsoDate,
} from "./revenuecat_expiration.ts";

Deno.test("latestIsoDate returns the latest valid ISO date", () => {
  assertEquals(
    latestIsoDate([
      "2026-06-07T06:17:47Z",
      null,
      "invalid",
      "2026-06-08T01:00:00Z",
    ]),
    "2026-06-08T01:00:00.000Z",
  );
});

Deno.test("latestActiveExpirationDateFromRevenueCatPayload ignores expired purchases", () => {
  const now = Date.parse("2026-06-06T13:18:00Z");

  assertEquals(
    latestActiveExpirationDateFromRevenueCatPayload(
      {
        entitlements: {
          premium: {
            product_identifier: "vibesync_essential_monthly_v2",
            expires_date: "2026-06-05T21:16:06Z",
          },
        },
        subscriptions: {
          vibesync_starter_quarterly_v2: {
            expires_date: "2026-05-17T14:34:01Z",
          },
        },
      },
      now,
    ),
    null,
  );
});

Deno.test("latestActiveExpirationDateFromRevenueCatPayload returns latest active expiration", () => {
  const now = Date.parse("2026-06-06T13:18:00Z");

  assertEquals(
    latestActiveExpirationDateFromRevenueCatPayload(
      {
        entitlements: {
          premium: {
            product_identifier: "vibesync_essential_quarterly_v2",
            expires_date: "2026-06-07T06:17:47Z",
          },
        },
        subscriptions: {
          vibesync_essential_quarterly_v2: {
            expires_date: "2026-06-07T06:17:47Z",
          },
          vibesync_essential_monthly_v2: {
            expires_date: "2026-06-03T00:39:51Z",
          },
        },
      },
      now,
    ),
    "2026-06-07T06:17:47.000Z",
  );
});
