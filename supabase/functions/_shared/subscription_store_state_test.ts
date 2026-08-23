import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  aggregateLegacySubscription,
  buildRevenueCatStoreEvents,
  buildSourceAwareSubscriptionRead,
  legacyAggregateFromRow,
  mergeSourceAwareLegacyAggregate,
  persistSubscriptionStoreState,
  readSourceAwareSubscriptionStates,
  reduceStoreSubscriptionEvent,
  resolveEffectiveEntitlementAt,
  splitRevenueCatSnapshot,
  type SubscriptionStoreState,
} from "./subscription_store_state.ts";

const at = new Date("2026-08-23T12:00:00.000Z");

function state(
  overrides: Partial<SubscriptionStoreState> = {},
): SubscriptionStoreState {
  return {
    store: "app_store",
    productId: "starter-monthly",
    basePlanId: "starter-monthly",
    tier: "starter",
    status: "active",
    expiresAt: new Date("2026-09-23T12:00:00.000Z"),
    eventAt: new Date("2026-08-23T11:00:00.000Z"),
    eventId: "app-event-1",
    verificationSource: "revenuecat_webhook",
    verificationStatus: "verified",
    revenueCatEnvironment: "production",
    ...overrides,
  };
}

Deno.test("effective entitlement returns one complete winning store row", () => {
  const appStore = state({
    userId: "user-1",
    store: "app_store",
    tier: "starter",
    expiresAt: new Date("2026-09-23T12:00:00.000Z"),
    eventId: "app-event-1",
  });
  const playStore = state({
    userId: "user-1",
    store: "play_store",
    productId: "essential-base",
    basePlanId: "essential-monthly",
    tier: "essential",
    expiresAt: new Date("2026-10-23T12:00:00.000Z"),
    eventId: "play-event-1",
  });

  const resolved = resolveEffectiveEntitlementAt([appStore, playStore], at);

  assertEquals(resolved, playStore);
});

Deno.test("effective entitlement does not guess a cancelled row with no expiry", () => {
  assertEquals(
    resolveEffectiveEntitlementAt([
      state({ status: "cancelled", expiresAt: null }),
    ], at),
    null,
  );
});

Deno.test("effective entitlement never accepts expired status even with future expiry", () => {
  assertEquals(
    resolveEffectiveEntitlementAt([
      state({
        status: "expired",
        expiresAt: new Date("2026-12-23T12:00:00.000Z"),
      }),
    ], at),
    null,
  );
});

Deno.test("store event reducer accepts a newer typed event for that same store", () => {
  const current = state({
    tier: "starter",
    eventAt: new Date("2026-08-23T11:00:00.000Z"),
    eventId: "app-event-1",
  });

  const result = reduceStoreSubscriptionEvent(current, {
    store: "app_store",
    source: "revenuecat_webhook",
    productId: "essential-quarterly",
    basePlanId: "essential-quarterly",
    tier: "essential",
    status: "active",
    expiresAt: new Date("2026-11-23T12:00:00.000Z"),
    eventAt: new Date("2026-08-23T12:30:00.000Z"),
    eventId: "app-event-2",
    revenueCatEnvironment: "production",
  });

  assertEquals(result.kind, "accepted");
  if (result.kind === "accepted") {
    assertEquals(result.state.store, "app_store");
    assertEquals(result.state.tier, "essential");
    assertEquals(result.state.expiresAt, new Date("2026-11-23T12:00:00.000Z"));
  }
});

Deno.test("authoritative absence tombstone obeys store event ordering", () => {
  const current = state({
    eventAt: new Date("2026-08-23T10:00:00.000Z"),
    eventId: "paid-before-snapshot",
  });
  const absence = {
    store: "app_store" as const,
    source: "revenuecat_api" as const,
    productId: null,
    basePlanId: null,
    tier: "free" as const,
    status: "expired" as const,
    expiresAt: new Date("2026-08-23T12:00:00.000Z"),
    eventAt: new Date("2026-08-23T12:00:00.000Z"),
    eventId: "snapshot_absence:current",
    verificationStatus: "verified" as const,
    revenueCatEnvironment: "production" as const,
  };

  const tombstoned = reduceStoreSubscriptionEvent(current, absence);
  assertEquals(tombstoned.kind, "accepted");
  if (tombstoned.kind !== "accepted") return;
  assertEquals(resolveEffectiveEntitlementAt([tombstoned.state], at), null);

  const newerPurchase = reduceStoreSubscriptionEvent(tombstoned.state, {
    ...absence,
    productId: "essential-monthly",
    basePlanId: "essential-monthly",
    tier: "essential",
    status: "active",
    expiresAt: new Date("2026-09-23T13:00:00.000Z"),
    eventAt: new Date("2026-08-23T13:00:00.000Z"),
    eventId: "purchase-after-snapshot",
  });
  assertEquals(newerPurchase.kind, "accepted");

  assertEquals(
    reduceStoreSubscriptionEvent(tombstoned.state, {
      ...absence,
      eventAt: new Date("2026-08-23T11:00:00.000Z"),
      eventId: "snapshot_absence:older",
    }),
    { kind: "ignored", reason: "stale" },
  );
});

Deno.test("store event reducer fails closed for duplicate, stale, and unknown events", () => {
  const current = state({
    eventAt: new Date("2026-08-23T12:00:00.000Z"),
    eventId: "app-event-2",
  });
  const event = {
    store: "app_store",
    source: "revenuecat_webhook",
    productId: "starter-monthly",
    basePlanId: "starter-monthly",
    tier: "starter",
    status: "active",
    expiresAt: new Date("2026-09-23T12:00:00.000Z"),
    eventAt: new Date("2026-08-23T12:00:00.000Z"),
    eventId: "app-event-2",
    revenueCatEnvironment: "production",
  };

  assertEquals(
    reduceStoreSubscriptionEvent(current, event),
    { kind: "ignored", reason: "duplicate" },
  );
  assertEquals(
    reduceStoreSubscriptionEvent(current, {
      ...event,
      eventAt: new Date("2026-08-23T11:59:00.000Z"),
      eventId: "app-event-old",
    }),
    { kind: "ignored", reason: "stale" },
  );
  assertEquals(
    reduceStoreSubscriptionEvent(current, { ...event, store: "play_store" }),
    { kind: "ignored", reason: "store_mismatch" },
  );
  assertEquals(
    reduceStoreSubscriptionEvent(current, { ...event, store: undefined }),
    { kind: "ignored", reason: "invalid" },
  );
  assertEquals(
    reduceStoreSubscriptionEvent(current, { ...event, source: "manual" }),
    { kind: "ignored", reason: "invalid" },
  );

  const legacy = reduceStoreSubscriptionEvent(null, {
    ...event,
    source: "legacy_backfill",
    eventId: "legacy-event",
  });
  assertEquals(legacy.kind, "accepted");
  if (legacy.kind === "accepted") {
    assertEquals(legacy.state.verificationStatus, "unverified");
    assert(
      resolveEffectiveEntitlementAt([legacy.state], at) === null,
      "unverified legacy state must not grant effective entitlement",
    );
  }
});

Deno.test("paid store events require a product provenance value", () => {
  const result = reduceStoreSubscriptionEvent(null, {
    store: "play_store",
    source: "revenuecat_api",
    productId: null,
    basePlanId: "starter-monthly",
    tier: "starter",
    status: "active",
    expiresAt: new Date("2026-09-23T12:00:00.000Z"),
    eventAt: new Date("2026-08-23T11:00:00.000Z"),
    eventId: "missing-product",
    revenueCatEnvironment: "production",
  });

  assertEquals(result, { kind: "ignored", reason: "invalid" });
});

Deno.test("verification provenance outranks event ordering in the reducer", () => {
  const verifiedCurrent = state({
    eventAt: new Date("2026-08-23T11:00:00.000Z"),
    eventId: "verified-current",
    verificationStatus: "verified",
  });
  const unverifiedNewer = {
    store: "app_store" as const,
    source: "revenuecat_api" as const,
    productId: "starter-monthly",
    basePlanId: "starter-monthly",
    tier: "starter" as const,
    status: "active" as const,
    expiresAt: new Date("2026-10-23T12:00:00.000Z"),
    eventAt: new Date("2026-08-23T12:00:00.000Z"),
    eventId: "unverified-newer",
    verificationStatus: "unverified" as const,
    revenueCatEnvironment: "production" as const,
  };
  assertEquals(
    reduceStoreSubscriptionEvent(verifiedCurrent, unverifiedNewer),
    { kind: "ignored", reason: "preserve_verified" },
  );

  const unverifiedCurrent = state({
    eventAt: new Date("2026-08-23T12:00:00.000Z"),
    eventId: "unverified-current",
    verificationStatus: "unverified",
  });
  const verifiedOlder = {
    ...unverifiedNewer,
    eventAt: new Date("2026-08-23T11:00:00.000Z"),
    eventId: "verified-older",
    verificationStatus: "verified" as const,
  };
  assertEquals(
    reduceStoreSubscriptionEvent(unverifiedCurrent, verifiedOlder).kind,
    "accepted",
  );
});

Deno.test("legacy backfill cannot claim verified entitlement", () => {
  const result = reduceStoreSubscriptionEvent(null, {
    store: "app_store",
    source: "legacy_backfill",
    productId: "starter-monthly",
    basePlanId: "starter-monthly",
    tier: "starter",
    status: "active",
    expiresAt: new Date("2026-09-23T12:00:00.000Z"),
    eventAt: at,
    eventId: "legacy-verified-1",
    verificationStatus: "verified",
    revenueCatEnvironment: "production",
  });

  assertEquals(result, { kind: "ignored", reason: "invalid" });
});

Deno.test("RevenueCat snapshot splits each subscription by its own store and preserves empty", () => {
  const entries = splitRevenueCatSnapshot([
    {
      store: "app_store",
      productId: "starter-monthly",
      basePlanId: "starter-monthly",
      tier: "starter",
      status: "active",
      expiresAt: new Date("2026-09-23T12:00:00.000Z"),
      eventAt: at,
      eventId: "app-snapshot-1",
      revenueCatEnvironment: "production",
    },
    {
      store: "play_store",
      productId: "essential-base",
      basePlanId: "essential-monthly",
      tier: "essential",
      status: "active",
      expiresAt: new Date("2026-10-23T12:00:00.000Z"),
      eventAt: at,
      eventId: "play-snapshot-1",
      revenueCatEnvironment: "production",
    },
  ]);

  assertEquals(entries.length, 2);
  assertEquals(entries.map((entry) => entry.store), [
    "app_store",
    "play_store",
  ]);
  assertEquals(splitRevenueCatSnapshot([]), []);
});

Deno.test("RevenueCat API snapshots keep only supported per-store winners", () => {
  const events = buildRevenueCatStoreEvents({
    subscriptions: {
      "starter-monthly": {
        store: "APP_STORE",
        expires_date: "2026-09-23T12:00:00.000Z",
        purchase_date: "2026-08-23T11:00:00.000Z",
        transaction_id: "app-tx-1",
      },
      "essential-monthly": {
        store: "PLAY_STORE",
        product_plan_identifier: "essential-monthly",
        expires_date: "2026-10-23T12:00:00.000Z",
        purchase_date: "2026-08-23T11:30:00.000Z",
        transaction_id: "play-tx-1",
        is_sandbox: true,
      },
      "unknown-plan": {
        store: "mystery_store",
        expires_date: "2026-12-23T12:00:00.000Z",
      },
    },
  }, { now: at });

  assertEquals(events.length, 2);
  assertEquals(events.map((event) => event.store), ["app_store", "play_store"]);
  assertEquals(events[0].tier, "starter");
  assert(String(events[0].eventId).startsWith("app-tx-1:app_store:"));
  assertEquals(events[1].tier, "essential");
  assertEquals(events[1].basePlanId, "essential-monthly");
  assertEquals(events[1].revenueCatEnvironment, "sandbox");
});

Deno.test("Play snapshot derives base plan from colon product id without truncating product", () => {
  const events = buildRevenueCatStoreEvents({
    subscriptions: {
      "vibesync:essential-monthly": {
        store: "play_store",
        purchase_date: "2026-08-23T11:30:00.000Z",
        expires_date: "2026-10-23T12:00:00.000Z",
        transaction_id: "play-tx-derived",
      },
    },
  }, { now: at });

  assertEquals(events.length, 1);
  assertEquals(events[0].productId, "vibesync:essential-monthly");
  assertEquals(events[0].basePlanId, "essential-monthly");
});

Deno.test("snapshot without store fails closed", () => {
  const subscriber = {
    subscriptions: {
      "vibesync_starter_monthly": {
        purchase_date: "2026-08-23T11:30:00.000Z",
        expires_date: "2026-10-23T12:00:00.000Z",
        transaction_id: "missing-store-1",
      },
    },
  };
  assertEquals(buildRevenueCatStoreEvents(subscriber, { now: at }), []);
});

Deno.test("snapshot without an authoritative timestamp is skipped", () => {
  const events = buildRevenueCatStoreEvents({
    subscriptions: {
      "vibesync_starter_monthly": {
        store: "app_store",
        expires_date: "2026-10-23T12:00:00.000Z",
        purchase_date: null,
        transaction_id: "missing-time-1",
      },
    },
  }, { now: at });
  assertEquals(events, []);
});

Deno.test("snapshot skips null timestamp fields and uses the first valid event time", () => {
  const events = buildRevenueCatStoreEvents({
    subscriptions: {
      "vibesync_starter_monthly": {
        store: "app_store",
        event_at: null,
        updated_at: "2026-08-23T11:30:00.000Z",
        expires_date: "2026-10-23T12:00:00.000Z",
        transaction_id: "fallback-time-1",
      },
    },
  }, { now: at });

  assertEquals(events.length, 1);
  assertEquals(events[0].eventAt, new Date("2026-08-23T11:30:00.000Z"));
});

Deno.test("snapshot keeps an earlier event timestamp stale instead of making it current", () => {
  const [event] = buildRevenueCatStoreEvents({
    subscriptions: {
      "vibesync_starter_monthly": {
        store: "app_store",
        purchase_date: "2026-08-23T11:00:00.000Z",
        expires_date: "2026-10-23T12:00:00.000Z",
        transaction_id: "earlier-time-1",
      },
    },
  }, { now: at });
  assertEquals(
    reduceStoreSubscriptionEvent(state({ eventAt: at }), event),
    { kind: "ignored", reason: "stale" },
  );
});

Deno.test("snapshot renewal with the same original transaction gets a new event id", () => {
  const first = buildRevenueCatStoreEvents({
    subscriptions: {
      "vibesync_starter_monthly": {
        store: "app_store",
        original_transaction_id: "original-1",
        store_transaction_id: "store-tx-1",
        purchase_date: "2026-08-23T11:00:00.000Z",
        expires_date: "2026-09-23T11:00:00.000Z",
      },
    },
  }, { now: at });
  const renewal = buildRevenueCatStoreEvents({
    subscriptions: {
      "vibesync_starter_monthly": {
        store: "app_store",
        original_transaction_id: "original-1",
        store_transaction_id: "store-tx-2",
        purchase_date: "2026-09-23T11:00:00.000Z",
        expires_date: "2026-10-23T11:00:00.000Z",
      },
    },
  }, { now: at });

  assertEquals(first.length, 1);
  assertEquals(renewal.length, 1);
  assert(first[0].eventId !== renewal[0].eventId);
  assertEquals(
    reduceStoreSubscriptionEvent(
      state({
        eventAt: first[0].eventAt as Date,
        eventId: first[0].eventId as string,
        expiresAt: first[0].expiresAt as Date,
      }),
      renewal[0],
    ).kind,
    "accepted",
  );
});

Deno.test("snapshot cancellation uses detected-at time and changes event id", () => {
  const purchase = buildRevenueCatStoreEvents({
    subscriptions: {
      "vibesync_starter_monthly": {
        store: "app_store",
        transaction_id: "same-transaction",
        purchase_date: "2026-08-23T11:00:00.000Z",
        expires_date: "2026-09-23T11:00:00.000Z",
      },
    },
  }, { now: at });
  const cancellation = buildRevenueCatStoreEvents({
    subscriptions: {
      "vibesync_starter_monthly": {
        store: "app_store",
        transaction_id: "same-transaction",
        purchase_date: "2026-08-23T11:00:00.000Z",
        unsubscribe_detected_at: "2026-08-23T12:10:00.000Z",
        expires_date: "2026-09-23T11:00:00.000Z",
      },
    },
  }, { now: at });

  assertEquals(purchase.length, 1);
  assertEquals(cancellation.length, 1);
  assertEquals(cancellation[0].status, "cancelled");
  assertEquals(cancellation[0].eventAt, new Date("2026-08-23T12:10:00.000Z"));
  assert(purchase[0].eventId !== cancellation[0].eventId);
});

Deno.test("snapshot billing issue uses detected-at time and changes event id", () => {
  const purchase = buildRevenueCatStoreEvents({
    subscriptions: {
      "vibesync_starter_monthly": {
        store: "play_store",
        transaction_id: "same-transaction-billing",
        purchase_date: "2026-08-23T11:00:00.000Z",
        expires_date: "2026-09-23T11:00:00.000Z",
      },
    },
  }, { now: at });
  const billing = buildRevenueCatStoreEvents({
    subscriptions: {
      "vibesync_starter_monthly": {
        store: "play_store",
        transaction_id: "same-transaction-billing",
        purchase_date: "2026-08-23T11:00:00.000Z",
        billing_issues_detected_at: "2026-08-23T12:10:00.000Z",
        expires_date: "2026-09-23T11:00:00.000Z",
      },
    },
  }, { now: at });

  assertEquals(purchase.length, 1);
  assertEquals(billing.length, 1);
  assertEquals(billing[0].status, "billing_issue");
  assertEquals(billing[0].eventAt, new Date("2026-08-23T12:10:00.000Z"));
  assert(purchase[0].eventId !== billing[0].eventId);
});

Deno.test("legacy aggregate uses one verified winner and source-aware read keeps sources", () => {
  const appStore = state({
    userId: "user-1",
    store: "app_store",
    tier: "starter",
    productId: "starter-monthly",
    expiresAt: new Date("2026-09-23T12:00:00.000Z"),
  });
  const playStore = state({
    userId: "user-1",
    store: "play_store",
    tier: "essential",
    productId: "essential-quarterly",
    expiresAt: new Date("2026-10-23T12:00:00.000Z"),
  });

  const aggregate = aggregateLegacySubscription([appStore, playStore], at);
  assertEquals(aggregate.kind, "aggregate");
  if (aggregate.kind === "aggregate") {
    assertEquals(aggregate.value.tier, "essential");
    assertEquals(aggregate.value.store, "play_store");
    assertEquals(aggregate.value.expiresAt, playStore.expiresAt);
    assertEquals(aggregate.value.activeProductId, playStore.productId);
  }

  const read = buildSourceAwareSubscriptionRead([appStore, playStore], at);
  assertEquals(read.effective, playStore);
  assertEquals(read.sources, [appStore, playStore]);
  assertEquals(aggregateLegacySubscription([], at), {
    kind: "preserve",
    reason: "no_verified_source",
  });
  assertEquals(
    aggregateLegacySubscription([
      state({ verificationStatus: "unverified" }),
    ], at),
    { kind: "preserve", reason: "no_verified_source" },
  );
});

Deno.test("legacy aggregate keeps a paid store when another store expires", () => {
  const expiredAppStore = state({
    store: "app_store",
    tier: "starter",
    status: "expired",
    expiresAt: new Date("2026-08-22T12:00:00.000Z"),
    eventAt: new Date("2026-08-22T11:00:00.000Z"),
  });
  const paidPlayStore = state({
    store: "play_store",
    tier: "essential",
    status: "active",
    expiresAt: new Date("2026-10-23T12:00:00.000Z"),
  });

  const aggregate = aggregateLegacySubscription(
    [expiredAppStore, paidPlayStore],
    at,
  );
  assertEquals(aggregate.kind, "aggregate");
  if (aggregate.kind === "aggregate") {
    assertEquals(aggregate.value.store, "play_store");
    assertEquals(aggregate.value.tier, "essential");
  }
});

Deno.test("legacy aggregate maps billing issue to legacy active status", () => {
  const aggregate = aggregateLegacySubscription([
    state({
      status: "billing_issue",
      expiresAt: new Date("2026-09-23T12:00:00.000Z"),
    }),
  ], at);
  assertEquals(aggregate.kind, "aggregate");
  if (aggregate.kind === "aggregate") {
    assertEquals(aggregate.value.status, "active");
  }
});

Deno.test("legacy row billing issue is normalized before source-aware reads", () => {
  const aggregate = legacyAggregateFromRow({
    tier: "starter",
    status: "billing_issue",
    expires_at: "2026-09-23T12:00:00.000Z",
    active_product_id: "starter-monthly",
    store: "app_store",
    revenuecat_environment: "production",
  });

  assertEquals(aggregate.status, "active");
});

Deno.test("unreconciled paid legacy aggregate is preserved below a verified store winner", () => {
  const legacy = {
    tier: "essential" as const,
    status: "active" as const,
    expiresAt: new Date("2026-12-23T12:00:00.000Z"),
    activeProductId: "legacy-essential",
    store: null,
    revenueCatEnvironment: null,
    verificationSource: "legacy_backfill" as const,
  };
  const verifiedPlayStarter = state({
    store: "play_store",
    tier: "starter",
    productId: "play-starter",
    expiresAt: new Date("2026-09-23T12:00:00.000Z"),
  });
  const read = buildSourceAwareSubscriptionRead(
    [verifiedPlayStarter],
    at,
    "pending",
  );

  const merged = mergeSourceAwareLegacyAggregate(legacy, read);

  assertEquals(merged.reason, "preserve_legacy_unreconciled");
  assertEquals(merged.sourceAuthoritative, false);
  assertEquals(merged.value, legacy);
});

Deno.test("free legacy aggregate can safely upgrade from a verified store before cutover", () => {
  const legacy = {
    tier: "free" as const,
    status: "active" as const,
    expiresAt: null,
    activeProductId: null,
    store: null,
    revenueCatEnvironment: null,
    verificationSource: "legacy_backfill" as const,
  };
  const verifiedPlayStarter = state({
    store: "play_store",
    tier: "starter",
    productId: "play-starter",
  });
  const merged = mergeSourceAwareLegacyAggregate(
    legacy,
    buildSourceAwareSubscriptionRead([verifiedPlayStarter], at, "pending"),
  );

  assertEquals(merged.reason, "safe_upgrade");
  assertEquals(merged.value.tier, "starter");
  assertEquals(merged.value.store, "play_store");
});

Deno.test("pending paid safe upgrade is read-time only and expires back to its baseline", () => {
  const legacy = {
    tier: "starter" as const,
    status: "active" as const,
    expiresAt: new Date("2026-12-23T12:00:00.000Z"),
    activeProductId: "legacy-starter",
    store: null,
    revenueCatEnvironment: null,
    verificationSource: "legacy_backfill" as const,
  };
  const temporaryEssential = state({
    store: "play_store",
    tier: "essential",
    productId: "play-essential",
    expiresAt: new Date("2026-08-23T13:00:00.000Z"),
  });

  const during = mergeSourceAwareLegacyAggregate(
    legacy,
    buildSourceAwareSubscriptionRead(
      [temporaryEssential],
      new Date("2026-08-23T12:30:00.000Z"),
      "pending",
    ),
  );
  assertEquals(during.reason, "safe_upgrade");
  assertEquals(during.value.tier, "essential");

  const after = mergeSourceAwareLegacyAggregate(
    legacy,
    buildSourceAwareSubscriptionRead(
      [temporaryEssential],
      new Date("2026-08-23T14:00:00.000Z"),
      "pending",
    ),
  );
  assertEquals(after.reason, "preserve_legacy_unreconciled");
  assertEquals(after.value, legacy);
});

Deno.test("auto cutover keeps a free baseline authoritative after source expiry", () => {
  const legacy = {
    tier: "free" as const,
    status: "active" as const,
    expiresAt: null,
    activeProductId: null,
    store: null,
    revenueCatEnvironment: null,
    verificationSource: "legacy_backfill" as const,
  };
  const starter = state({
    store: "play_store",
    tier: "starter",
    productId: "play-starter",
    expiresAt: new Date("2026-08-23T13:00:00.000Z"),
  });

  const after = mergeSourceAwareLegacyAggregate(
    legacy,
    buildSourceAwareSubscriptionRead(
      [starter],
      new Date("2026-08-23T14:00:00.000Z"),
      "auto",
    ),
  );
  assertEquals(after.reason, "cutover_complete");
  assertEquals(after.value.tier, "free");
  assertEquals(after.value.activeProductId, "play-starter");
});

Deno.test("complete reconciliation allows a verified expiry to cut over legacy paid state", () => {
  const legacy = {
    tier: "essential" as const,
    status: "active" as const,
    expiresAt: new Date("2026-12-23T12:00:00.000Z"),
    activeProductId: "legacy-essential",
    store: null,
    revenueCatEnvironment: null,
    verificationSource: "legacy_backfill" as const,
  };
  const expired = state({
    status: "expired",
    expiresAt: new Date("2026-08-22T12:00:00.000Z"),
  });
  const merged = mergeSourceAwareLegacyAggregate(
    legacy,
    buildSourceAwareSubscriptionRead([expired], at, "complete"),
  );

  assertEquals(merged.reason, "cutover_complete");
  assertEquals(merged.value.tier, "free");
  assertEquals(merged.value.status, "expired");
});

Deno.test("read-time aggregation follows clock advance without a new event", () => {
  const appStore = state({
    store: "app_store",
    tier: "essential",
    expiresAt: new Date("2026-08-23T13:00:00.000Z"),
  });
  const playStore = state({
    store: "play_store",
    tier: "starter",
    expiresAt: new Date("2026-08-23T20:00:00.000Z"),
  });

  assertEquals(
    buildSourceAwareSubscriptionRead(
      [appStore, playStore],
      new Date("2026-08-23T12:30:00.000Z"),
      "complete",
    ).effective,
    appStore,
  );
  assertEquals(
    buildSourceAwareSubscriptionRead(
      [appStore, playStore],
      new Date("2026-08-23T14:00:00.000Z"),
      "complete",
    ).effective,
    playStore,
  );
});

Deno.test("subscription store persistence delegates to the atomic RPC and fails closed", async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const supabase = {
    rpc(name: string, args: Record<string, unknown>) {
      calls.push({ name, args });
      return Promise.resolve({
        data: [{ accepted: true, reason: "accepted" }],
        error: null,
      });
    },
  };

  const result = await persistSubscriptionStoreState(
    supabase,
    "user-1",
    {
      store: "app_store",
      source: "revenuecat_api",
      productId: "starter-monthly",
      basePlanId: "starter-monthly",
      tier: "starter",
      status: "active",
      expiresAt: new Date("2026-09-23T12:00:00.000Z"),
      eventAt: at,
      eventId: "api-event-1",
      revenueCatEnvironment: "production",
    },
    { resetUsage: true },
  );

  assertEquals(result, { accepted: true, reason: "accepted" });
  assertEquals(calls, [{
    name: "upsert_subscription_store_state",
    args: {
      p_user_id: "user-1",
      p_store: "app_store",
      p_product_id: "starter-monthly",
      p_base_plan_id: "starter-monthly",
      p_tier: "starter",
      p_status: "active",
      p_expires_at: "2026-09-23T12:00:00.000Z",
      p_event_at: "2026-08-23T12:00:00.000Z",
      p_event_id: "api-event-1",
      p_verification_source: "revenuecat_api",
      p_verification_status: "verified",
      p_revenuecat_environment: "production",
      p_reset_usage: true,
    },
  }]);

  const failed = await persistSubscriptionStoreState(
    {
      rpc: () =>
        Promise.resolve({ data: null, error: { message: "db unavailable" } }),
    },
    "user-1",
    {
      store: "app_store",
      source: "revenuecat_api",
      productId: "starter-monthly",
      basePlanId: null,
      tier: "starter",
      status: "active",
      expiresAt: null,
      eventAt: at,
      eventId: "api-event-2",
      revenueCatEnvironment: "production",
    },
  );
  assertEquals(failed, { accepted: false, reason: "database_error" });

  const invalidUser = await persistSubscriptionStoreState(
    supabase,
    "   ",
    {
      store: "app_store",
      source: "revenuecat_api",
      productId: "starter-monthly",
      basePlanId: null,
      tier: "starter",
      status: "active",
      expiresAt: null,
      eventAt: at,
      eventId: "api-event-3",
      revenueCatEnvironment: "production",
    },
  );
  assertEquals(invalidUser, { accepted: false, reason: "invalid" });

  const preservedVerified = await persistSubscriptionStoreState(
    {
      rpc: () =>
        Promise.resolve({
          data: [{ accepted: false, reason: "preserve_verified" }],
          error: null,
        }),
    },
    "user-1",
    {
      store: "app_store",
      source: "revenuecat_api",
      productId: "starter-monthly",
      basePlanId: null,
      tier: "starter",
      status: "active",
      expiresAt: null,
      eventAt: at,
      eventId: "api-event-unverified",
      verificationStatus: "unverified",
      revenueCatEnvironment: "production",
    },
  );
  assertEquals(preservedVerified, {
    accepted: false,
    reason: "preserve_verified",
  });
});

Deno.test("verified absence tombstone is replaced by a newer purchase, not an older replay", () => {
  const tombstone = state({
    tier: "free",
    status: "expired",
    productId: null,
    basePlanId: null,
    expiresAt: null,
    eventAt: new Date("2026-08-23T12:00:00.000Z"),
    eventId: "snapshot_absence:reviewed-snapshot:app_store",
  });

  const purchase = reduceStoreSubscriptionEvent(tombstone, {
    store: "app_store",
    productId: "starter-monthly",
    basePlanId: "starter-monthly",
    tier: "starter",
    status: "active",
    expiresAt: new Date("2026-09-23T12:00:00.000Z"),
    eventAt: new Date("2026-08-23T13:00:00.000Z"),
    eventId: "purchase-after-tombstone",
    source: "revenuecat_api",
    verificationStatus: "verified",
    revenueCatEnvironment: "production",
  });
  assertEquals(purchase.kind, "accepted");
  if (purchase.kind !== "accepted") throw new Error("purchase must apply");

  const olderReplay = reduceStoreSubscriptionEvent(purchase.state, {
    store: "app_store",
    productId: null,
    basePlanId: null,
    tier: "free",
    status: "expired",
    expiresAt: null,
    eventAt: new Date("2026-08-23T12:00:00.000Z"),
    eventId: "snapshot_absence:reviewed-snapshot:app_store",
    source: "revenuecat_api",
    verificationStatus: "verified",
    revenueCatEnvironment: "production",
  });
  assertEquals(olderReplay, { kind: "ignored", reason: "stale" });
});

Deno.test("source-aware client read returns effective row and all valid sources", async () => {
  const appStore = state({
    userId: "user-1",
    store: "app_store",
    tier: "starter",
    productId: "starter-monthly",
  });
  const playStore = state({
    userId: "user-1",
    store: "play_store",
    tier: "essential",
    productId: "essential-monthly",
  });
  const client = {
    from(table: string) {
      assertEquals(table, "subscription_store_states");
      return {
        select: () => ({
          eq: () =>
            Promise.resolve({
              data: [
                {
                  user_id: "user-1",
                  store: appStore.store,
                  product_id: appStore.productId,
                  base_plan_id: appStore.basePlanId,
                  tier: appStore.tier,
                  status: appStore.status,
                  expires_at: appStore.expiresAt?.toISOString(),
                  event_at: appStore.eventAt.toISOString(),
                  event_id: appStore.eventId,
                  verification_source: appStore.verificationSource,
                  verification_status: appStore.verificationStatus,
                  revenuecat_environment: appStore.revenueCatEnvironment,
                },
                {
                  user_id: "user-1",
                  store: playStore.store,
                  product_id: playStore.productId,
                  base_plan_id: playStore.basePlanId,
                  tier: playStore.tier,
                  status: playStore.status,
                  expires_at: playStore.expiresAt?.toISOString(),
                  event_at: playStore.eventAt.toISOString(),
                  event_id: playStore.eventId,
                  verification_source: playStore.verificationSource,
                  verification_status: playStore.verificationStatus,
                  revenuecat_environment: playStore.revenueCatEnvironment,
                },
                {
                  user_id: "user-2",
                  store: "play_store",
                  product_id: "essential-monthly",
                  base_plan_id: "essential-monthly",
                  tier: "essential",
                  status: "active",
                  expires_at: "2026-12-23T12:00:00.000Z",
                  event_at: "2026-08-23T13:00:00.000Z",
                  event_id: "other-user-event",
                  verification_source: "revenuecat_webhook",
                  verification_status: "verified",
                  revenuecat_environment: "production",
                },
              ],
              error: null,
            }),
        }),
      };
    },
  };

  const result = await readSourceAwareSubscriptionStates(
    client,
    "user-1",
    at,
  );
  assertEquals(result.error, null);
  assertEquals(result.read.effective, playStore);
  assertEquals(result.read.sources, [appStore, playStore]);
});
