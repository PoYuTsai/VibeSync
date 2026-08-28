import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildRevenueCatWebhookStoreEvent,
  normalizeRevenueCatExpirationReason,
} from "./webhook_store_event.ts";
import {
  reduceStoreSubscriptionEvent,
  resolveEffectiveEntitlementAt,
  type SubscriptionStoreState,
} from "../_shared/subscription_store_state.ts";

const baseEvent = {
  id: "rc-event-1",
  store: "PLAY_STORE",
  environment: "PRODUCTION",
  product_id: "vibesync_starter_monthly",
  expiration_at_ms: Date.parse("2026-09-23T12:00:00.000Z"),
  event_timestamp_ms: Date.parse("2026-08-23T12:00:00.000Z"),
  transaction_id: "shared-transaction-1",
};

Deno.test("webhook event builder keeps event store and billing status isolated", () => {
  const result = buildRevenueCatWebhookStoreEvent("BILLING_ISSUE", {
    ...baseEvent,
    billing_issues_detected_at_ms: Date.parse("2026-08-23T12:05:00.000Z"),
  });

  assertEquals(result.kind, "event");
  if (result.kind !== "event") throw new Error("expected event");
  assertEquals(result.event.store, "play_store");
  assertEquals(result.event.tier, "starter");
  assertEquals(result.event.status, "billing_issue");
  assertEquals(result.event.eventAt, "2026-08-23T12:05:00.000Z");
  assertEquals(result.event.eventId, "rc-event-1");
});

Deno.test("SUBSCRIPTION_PAUSED preserves access until the authoritative expiry", () => {
  const result = buildRevenueCatWebhookStoreEvent("SUBSCRIPTION_PAUSED", {
    ...baseEvent,
    product_id: "vibesync_starter:monthly",
    expiration_at_ms: Date.parse("2026-09-23T12:00:00.000Z"),
    auto_resume_at_ms: Date.parse("2026-10-23T12:00:00.000Z"),
  });

  assertEquals(result.kind, "event");
  if (result.kind !== "event") throw new Error("expected event");
  assertEquals(result.event.store, "play_store");
  assertEquals(result.event.productId, "vibesync_starter:monthly");
  assertEquals(result.event.basePlanId, "monthly");
  assertEquals(result.event.status, "active");
  assertEquals(result.event.expiresAt, new Date("2026-09-23T12:00:00.000Z"));
});

Deno.test("BILLING_ISSUE keeps access through the authoritative grace deadline", () => {
  const result = buildRevenueCatWebhookStoreEvent("BILLING_ISSUE", {
    ...baseEvent,
    billing_issues_detected_at_ms: Date.parse("2026-08-23T12:05:00.000Z"),
    grace_period_expiration_at_ms: Date.parse("2026-09-30T12:00:00.000Z"),
  });

  assertEquals(result.kind, "event");
  if (result.kind !== "event") throw new Error("expected event");
  assertEquals(result.event.status, "billing_issue");
  assertEquals(result.event.eventAt, "2026-08-23T12:05:00.000Z");
  assertEquals(result.event.expiresAt, new Date("2026-09-30T12:00:00.000Z"));
});

Deno.test("BILLING_ISSUE fails closed for a malformed grace deadline", () => {
  assertEquals(
    buildRevenueCatWebhookStoreEvent("BILLING_ISSUE", {
      ...baseEvent,
      grace_period_expiration_at_ms: "not-a-timestamp",
    }),
    { kind: "invalid", reason: "invalid_grace_period_expiration" },
  );
});

Deno.test("billing issue and pause fail closed without an authoritative expiry", () => {
  assertEquals(
    buildRevenueCatWebhookStoreEvent("BILLING_ISSUE", {
      ...baseEvent,
      expiration_at_ms: null,
    }),
    { kind: "invalid", reason: "missing_authoritative_expiration" },
  );
  assertEquals(
    buildRevenueCatWebhookStoreEvent("SUBSCRIPTION_PAUSED", {
      ...baseEvent,
      expiration_at_ms: null,
    }),
    { kind: "invalid", reason: "missing_authoritative_expiration" },
  );
});

Deno.test(
  "billing-error cancellation is ignored so billing issue ordering is harmless",
  () => {
    const initial = buildRevenueCatWebhookStoreEvent("INITIAL_PURCHASE", {
      ...baseEvent,
      id: "rc-initial-ordering",
      event_timestamp_ms: Date.parse("2026-08-23T12:00:00.000Z"),
    });
    const billing = buildRevenueCatWebhookStoreEvent("BILLING_ISSUE", {
      ...baseEvent,
      id: "rc-billing-ordering",
      billing_issues_detected_at_ms: Date.parse(
        "2026-08-23T12:05:00.000Z",
      ),
      grace_period_expiration_at_ms: Date.parse(
        "2026-09-30T12:00:00.000Z",
      ),
    });
    const billingCancellation = buildRevenueCatWebhookStoreEvent(
      "CANCELLATION",
      {
        ...baseEvent,
        id: "rc-billing-cancellation-ordering",
        cancel_reason: "billing_error",
        cancelled_at_ms: Date.parse("2026-08-23T12:06:00.000Z"),
      },
    );
    const expiration = buildRevenueCatWebhookStoreEvent("EXPIRATION", {
      ...baseEvent,
      id: "rc-expiration-ordering",
      event_timestamp_ms: Date.parse("2026-09-30T12:00:00.000Z"),
      expiration_at_ms: Date.parse("2026-09-30T12:00:00.000Z"),
    });
    const renewal = buildRevenueCatWebhookStoreEvent("RENEWAL", {
      ...baseEvent,
      id: "rc-renewal-ordering",
      event_timestamp_ms: Date.parse("2026-09-30T12:01:00.000Z"),
      expiration_at_ms: Date.parse("2026-10-30T12:00:00.000Z"),
    });

    assertEquals(billingCancellation, {
      kind: "ignored",
      reason: "billing_error_cancellation",
    });
    assertEquals(initial.kind, "event");
    assertEquals(billing.kind, "event");
    assertEquals(expiration.kind, "event");
    assertEquals(renewal.kind, "event");
    if (
      initial.kind !== "event" || billing.kind !== "event" ||
      expiration.kind !== "event" || renewal.kind !== "event"
    ) {
      throw new Error("expected lifecycle events");
    }

    function apply(
      events: readonly typeof initial[],
    ) {
      let current: SubscriptionStoreState | null = null;
      for (const result of events) {
        if (result.kind !== "event") continue;
        const reduced = reduceStoreSubscriptionEvent(current, result.event);
        assertEquals(reduced.kind, "accepted");
        if (reduced.kind !== "accepted") throw new Error("expected state");
        current = reduced.state;
      }
      return current;
    }

    const cancellationOnly = buildRevenueCatWebhookStoreEvent(
      "CANCELLATION",
      {
        ...baseEvent,
        id: "rc-billing-cancellation-ordering-2",
        cancel_reason: "BILLING_ERROR",
        cancelled_at_ms: Date.parse("2026-08-23T12:06:00.000Z"),
      },
    );
    assertEquals(cancellationOnly.kind, "ignored");

    for (
      const ordered of [
        [initial, billing, billingCancellation, expiration, renewal],
        [initial, billingCancellation, billing, expiration, renewal],
      ]
    ) {
      const afterBilling = apply(ordered.slice(0, 3));
      assertEquals(afterBilling?.status, "billing_issue");
      assertEquals(
        resolveEffectiveEntitlementAt(
          afterBilling == null ? [] : [afterBilling],
          new Date("2026-09-01T00:00:00.000Z"),
        )?.tier,
        "starter",
      );

      const afterExpiration = apply(ordered.slice(0, 4));
      assertEquals(
        resolveEffectiveEntitlementAt(
          afterExpiration == null ? [] : [afterExpiration],
          new Date("2026-10-01T00:00:00.000Z"),
        ),
        null,
      );

      const afterRenewal = apply(ordered);
      assertEquals(afterRenewal?.status, "active");
      assertEquals(
        resolveEffectiveEntitlementAt(
          afterRenewal == null ? [] : [afterRenewal],
          new Date("2026-10-01T00:00:00.000Z"),
        )?.tier,
        "starter",
      );
    }
  },
);

Deno.test(
  "paid lifecycle events require an authoritative expiry while expiration is terminal",
  () => {
    const lifecycleTypes = [
      "INITIAL_PURCHASE",
      "RENEWAL",
      "UNCANCELLATION",
      "SUBSCRIPTION_EXTENDED",
      "PRODUCT_CHANGE",
      "CANCELLATION",
      "BILLING_ISSUE",
      "TRANSFER",
      "SUBSCRIPTION_PAUSED",
    ];

    for (const type of lifecycleTypes) {
      const result = buildRevenueCatWebhookStoreEvent(type, {
        ...baseEvent,
        id: `missing-expiry-${type}`,
        expiration_at_ms: null,
        ...(type === "PRODUCT_CHANGE"
          ? { new_product_id: "vibesync_essential_monthly" }
          : {}),
      });
      assertEquals(
        result,
        { kind: "invalid", reason: "missing_authoritative_expiration" },
        `${type} must not overwrite a paid row without an expiry`,
      );
    }

    assertEquals(
      buildRevenueCatWebhookStoreEvent("RENEWAL", {
        ...baseEvent,
        expiration_at_ms: "not-a-timestamp",
      }),
      { kind: "invalid", reason: "invalid_authoritative_expiration" },
    );
    assertEquals(
      buildRevenueCatWebhookStoreEvent("EXPIRATION", {
        ...baseEvent,
        expiration_at_ms: null,
      }).kind,
      "event",
    );
  },
);

Deno.test("EXPIRATION keeps terminal authority and normalizes unknown reasons", () => {
  assertEquals(
    normalizeRevenueCatExpirationReason("not_a_future_reason"),
    "UNKNOWN",
  );
  assertEquals(
    normalizeRevenueCatExpirationReason(" subscription_paused "),
    "SUBSCRIPTION_PAUSED",
  );

  for (
    const reason of [
      "UNSUBSCRIBE",
      "BILLING_ERROR",
      "DEVELOPER_INITIATED",
      "PRICE_INCREASE",
      "CUSTOMER_SUPPORT",
      "UNKNOWN",
      "SUBSCRIPTION_PAUSED",
    ]
  ) {
    const result = buildRevenueCatWebhookStoreEvent("EXPIRATION", {
      ...baseEvent,
      expiration_reason: reason,
      event_timestamp_ms: Date.parse("2026-09-23T12:00:00.000Z"),
    });
    assertEquals(result.kind, "event");
    if (result.kind !== "event") throw new Error("expected event");
    assertEquals(result.event.status, "expired");
    assertEquals(result.event.tier, "free");
  }

  const unknown = buildRevenueCatWebhookStoreEvent("EXPIRATION", {
    ...baseEvent,
    expiration_reason: "NOT_A_REAL_REASON",
  });
  assertEquals(unknown.kind, "event");
  if (unknown.kind !== "event") throw new Error("expected event");
  assertEquals(unknown.event.status, "expired");
  assertEquals(unknown.event.tier, "free");
});

Deno.test("refund and revocation expiration fixtures cannot retain access", () => {
  const fixtures = [
    // RevenueCat can report a customer-support refund through terminal expiry.
    {
      expiration_reason: "CUSTOMER_SUPPORT",
      refunded_at_ms: Date.parse("2026-08-23T11:59:00.000Z"),
    },
    // Developer-initiated revocation is also terminal even if the reason set
    // grows later; EXPIRATION remains the authoritative signal.
    {
      expiration_reason: "DEVELOPER_INITIATED",
      revoked_at_ms: Date.parse("2026-08-23T11:59:00.000Z"),
    },
  ];

  for (const fixture of fixtures) {
    const result = buildRevenueCatWebhookStoreEvent("EXPIRATION", {
      ...baseEvent,
      ...fixture,
      expiration_at_ms: Date.parse("2026-08-23T12:00:00.000Z"),
      event_timestamp_ms: Date.parse("2026-08-23T12:00:00.000Z"),
    });
    assertEquals(result.kind, "event");
    if (result.kind !== "event") throw new Error("expected event");
    assertEquals(result.event.status, "expired");
    assertEquals(result.event.tier, "free");

    const reduced = reduceStoreSubscriptionEvent(null, result.event);
    assertEquals(reduced.kind, "accepted");
    if (reduced.kind !== "accepted") throw new Error("expected state");
    assertEquals(
      resolveEffectiveEntitlementAt(
        [reduced.state],
        new Date("2026-08-28T12:00:00.000Z"),
      ),
      null,
    );
  }
});

Deno.test("PRODUCT_CHANGE derives tier from new product, never aggregate current tier", () => {
  const result = buildRevenueCatWebhookStoreEvent("PRODUCT_CHANGE", {
    ...baseEvent,
    product_id: "vibesync_starter_monthly",
    new_product_id: "vibesync_essential_monthly",
  });

  assertEquals(result.kind, "event");
  if (result.kind !== "event") throw new Error("expected event");
  assertEquals(result.event.store, "play_store");
  assertEquals(result.event.productId, "vibesync_essential_monthly");
  assertEquals(result.event.tier, "essential");
});

Deno.test("PRODUCT_CHANGE requires both products and ignores a downgrade", () => {
  const missingNew = buildRevenueCatWebhookStoreEvent("PRODUCT_CHANGE", {
    ...baseEvent,
    new_product_id: null,
  });
  assertEquals(missingNew.kind, "invalid");

  const downgrade = buildRevenueCatWebhookStoreEvent("PRODUCT_CHANGE", {
    ...baseEvent,
    id: "rc-downgrade",
    product_id: "vibesync_essential_monthly",
    new_product_id: "vibesync_starter_monthly",
  });
  assertEquals(downgrade.kind, "ignored");
});

Deno.test("webhook cancellation and billing transitions for one transaction get distinct event ids", () => {
  const cancellation = buildRevenueCatWebhookStoreEvent("CANCELLATION", {
    ...baseEvent,
    cancelled_at_ms: Date.parse("2026-08-23T12:10:00.000Z"),
  });
  const billing = buildRevenueCatWebhookStoreEvent("BILLING_ISSUE", {
    ...baseEvent,
    id: "rc-billing-1",
    billing_issues_detected_at_ms: Date.parse("2026-08-23T12:11:00.000Z"),
  });

  assertEquals(cancellation.kind, "event");
  assertEquals(billing.kind, "event");
  if (cancellation.kind !== "event" || billing.kind !== "event") {
    throw new Error("expected events");
  }
  assert(cancellation.event.eventId !== billing.event.eventId);
  assertEquals(cancellation.event.status, "cancelled");
  assertEquals(billing.event.status, "billing_issue");
  assertEquals(cancellation.event.eventAt, "2026-08-23T12:10:00.000Z");
  assertEquals(billing.event.eventAt, "2026-08-23T12:11:00.000Z");
});

Deno.test("present webhook event id remains the exact idempotency key", () => {
  const first = buildRevenueCatWebhookStoreEvent("RENEWAL", baseEvent);
  const replayWithMutatedPayload = buildRevenueCatWebhookStoreEvent("RENEWAL", {
    ...baseEvent,
    expiration_at_ms: Date.parse("2026-10-23T12:00:00.000Z"),
  });

  assertEquals(first.kind, "event");
  assertEquals(replayWithMutatedPayload.kind, "event");
  if (first.kind !== "event" || replayWithMutatedPayload.kind !== "event") {
    throw new Error("expected events");
  }
  assertEquals(first.event.eventId, "rc-event-1");
  assertEquals(replayWithMutatedPayload.event.eventId, "rc-event-1");
});

Deno.test("webhook state event fails closed for missing product or authoritative timestamp", () => {
  assertEquals(
    buildRevenueCatWebhookStoreEvent("BILLING_ISSUE", {
      ...baseEvent,
      product_id: null,
    }).kind,
    "invalid",
  );
  assertEquals(
    buildRevenueCatWebhookStoreEvent("RENEWAL", {
      ...baseEvent,
      event_timestamp_ms: null,
      purchased_at_ms: null,
    }).kind,
    "invalid",
  );
  assertEquals(
    buildRevenueCatWebhookStoreEvent("EXPIRATION", {
      ...baseEvent,
      product_id: "unknown_product",
    }).kind,
    "invalid",
  );
});
