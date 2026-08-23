import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

import {
  type RevenueCatSnapshotPersistencePolicy,
  selectRevenueCatSnapshotEventsForPersistence,
} from "./store_event_policy.ts";

const lowerSnapshotEvents = [
  {
    store: "app_store" as const,
    productId: "starter-monthly",
    tier: "starter" as const,
    status: "active" as const,
  },
];

for (const cutoverStatus of ["auto", "complete"] as const) {
  Deno.test(
    `scheduled paid downgrade does not persist lower snapshot during ${cutoverStatus} cutover`,
    () => {
      const policy: RevenueCatSnapshotPersistencePolicy = {
        previousTier: "essential",
        finalTier: "essential",
        revenueCatTier: "starter",
        tierPreservedReason: "scheduled_paid_downgrade",
        cutoverStatus,
      };

      assertEquals(
        selectRevenueCatSnapshotEventsForPersistence(
          lowerSnapshotEvents,
          policy,
        ),
        [],
      );
    },
  );
}

Deno.test("a renewal that is not a scheduled downgrade remains persistable", () => {
  const policy: RevenueCatSnapshotPersistencePolicy = {
    previousTier: "starter",
    finalTier: "essential",
    revenueCatTier: "essential",
    tierPreservedReason: null,
    cutoverStatus: "complete",
  };

  assertEquals(
    selectRevenueCatSnapshotEventsForPersistence(lowerSnapshotEvents, policy),
    lowerSnapshotEvents,
  );
});

Deno.test("paid provenance validation happens before scheduled-event filtering", async () => {
  const indexSource = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );

  assert(
    indexSource.includes(
      'if (candidateSnapshotEvents.length === 0 && revenueCatTier !== "free")',
    ),
  );
  assert(
    !indexSource.includes(
      'if (snapshotEvents.length === 0 && revenueCatTier !== "free")',
    ),
  );
});
