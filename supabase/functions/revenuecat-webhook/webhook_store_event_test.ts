import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { buildRevenueCatWebhookStoreEvent } from "./webhook_store_event.ts";

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
