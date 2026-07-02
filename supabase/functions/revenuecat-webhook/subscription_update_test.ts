import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";

import { resolveSubscriptionUpdateForWebhookEvent } from "./subscription_update.ts";

const nowIso = "2026-06-06T06:30:00.000Z";
const expiresAt = "2026-06-07T06:17:47.000Z";
const event = {
  store: "APP_STORE",
  environment: "SANDBOX",
};

Deno.test("EXPIRATION downgrades to free and resets local quota counters", () => {
  const decision = resolveSubscriptionUpdateForWebhookEvent({
    type: "EXPIRATION",
    effectiveProductId: "vibesync_essential_quarterly_v2",
    currentTier: "essential",
    expiresAt,
    nowIso,
    event,
  });

  assertEquals(decision.kind, "update");
  if (decision.kind !== "update") throw new Error("expected update");

  assertEquals(decision.newTier, "free");
  assertEquals(decision.subscriptionUpdate.tier, "free");
  assertEquals(decision.subscriptionUpdate.status, "expired");
  assertEquals(decision.subscriptionUpdate.monthly_messages_used, 0);
  assertEquals(decision.subscriptionUpdate.daily_messages_used, 0);
  assertEquals(
    decision.subscriptionUpdate.active_product_id,
    "vibesync_essential_quarterly_v2",
  );
});

Deno.test("EXPIRATION for an older period does not overwrite a newer active subscription", () => {
  // Stale EXPIRATION event (expires 2026-06-07) arrives after the user already
  // re-subscribed with a later expiry recorded in the DB (2026-09-01).
  const decision = resolveSubscriptionUpdateForWebhookEvent({
    type: "EXPIRATION",
    effectiveProductId: "vibesync_essential_quarterly_v2",
    currentTier: "essential",
    currentExpiresAt: "2026-09-01T00:00:00.000Z",
    expiresAt,
    nowIso,
    event,
  });

  assertEquals(decision.kind, "ignore");
  if (decision.kind !== "ignore") throw new Error("expected ignore");
  assertEquals(decision.newTier, "essential");
  assertEquals(decision.subscriptionUpdate, undefined);
});

Deno.test("EXPIRATION matching the tracked period still downgrades", () => {
  const decision = resolveSubscriptionUpdateForWebhookEvent({
    type: "EXPIRATION",
    effectiveProductId: "vibesync_essential_quarterly_v2",
    currentTier: "essential",
    currentExpiresAt: expiresAt,
    expiresAt,
    nowIso,
    event,
  });

  assertEquals(decision.kind, "update");
  if (decision.kind !== "update") throw new Error("expected update");
  assertEquals(decision.newTier, "free");
});

Deno.test("EXPIRATION with unknown DB expiry falls back to downgrade", () => {
  const decision = resolveSubscriptionUpdateForWebhookEvent({
    type: "EXPIRATION",
    effectiveProductId: "vibesync_essential_quarterly_v2",
    currentTier: "essential",
    currentExpiresAt: null,
    expiresAt,
    nowIso,
    event,
  });

  assertEquals(decision.kind, "update");
  if (decision.kind !== "update") throw new Error("expected update");
  assertEquals(decision.newTier, "free");
});

Deno.test("CANCELLATION marks cancelled but preserves paid tier until expiration", () => {
  const decision = resolveSubscriptionUpdateForWebhookEvent({
    type: "CANCELLATION",
    effectiveProductId: "vibesync_starter_monthly_v2",
    currentTier: "starter",
    expiresAt,
    nowIso,
    event,
  });

  assertEquals(decision.kind, "update");
  if (decision.kind !== "update") throw new Error("expected update");

  assertEquals(decision.newTier, "starter");
  assertEquals(decision.subscriptionUpdate.tier, "starter");
  assertEquals(decision.subscriptionUpdate.status, "cancelled");
  assertEquals(decision.subscriptionUpdate.expires_at, expiresAt);
});

Deno.test("BILLING_ISSUE preserves paid tier and does not reset quota", () => {
  const decision = resolveSubscriptionUpdateForWebhookEvent({
    type: "BILLING_ISSUE",
    effectiveProductId: "vibesync_essential_monthly_v2",
    currentTier: "starter",
    expiresAt,
    nowIso,
    event,
  });

  assertEquals(decision.kind, "update");
  if (decision.kind !== "update") throw new Error("expected update");

  assertEquals(decision.newTier, "essential");
  assertEquals(decision.subscriptionUpdate.tier, "essential");
  assertEquals(decision.subscriptionUpdate.status, "active");
  assertEquals(decision.subscriptionUpdate.monthly_messages_used, undefined);
  assertEquals(decision.subscriptionUpdate.daily_messages_used, undefined);
});

Deno.test("BILLING_ISSUE with no paid evidence is ignored", () => {
  const decision = resolveSubscriptionUpdateForWebhookEvent({
    type: "BILLING_ISSUE",
    effectiveProductId: "unknown_product",
    currentTier: "free",
    expiresAt,
    nowIso,
    event,
  });

  assertEquals(decision.kind, "ignore");
  if (decision.kind !== "ignore") throw new Error("expected ignore");
  assertEquals(decision.newTier, "free");
});

Deno.test("PRODUCT_CHANGE downgrade is ignored until renewal", () => {
  const decision = resolveSubscriptionUpdateForWebhookEvent({
    type: "PRODUCT_CHANGE",
    effectiveProductId: "vibesync_starter_quarterly_v2",
    currentTier: "essential",
    expiresAt,
    nowIso,
    event,
  });

  assertEquals(decision.kind, "ignore");
  if (decision.kind !== "ignore") throw new Error("expected ignore");
  assertEquals(decision.newTier, "starter");
});
