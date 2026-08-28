import { assert } from "https://deno.land/std@0.168.0/testing/asserts.ts";

const writerFiles = [
  "../revenuecat-webhook/index.ts",
  "../sync-subscription/index.ts",
  "../analyze-chat/revenuecat_reconciliation.ts",
  "../coach-chat/index.ts",
  "../coach-follow-up/index.ts",
  "../keyboard-assist/index.ts",
  "../keyboard-reply/index.ts",
];

async function readWriter(file: string): Promise<string> {
  return await Deno.readTextFile(new URL(file, import.meta.url));
}

function refreshBody(source: string): string {
  const start = [
    "maybeRefreshTierFromRevenueCat",
    "maybeRefreshTier(",
  ].map((marker) => source.indexOf(marker)).find((index) => index >= 0) ?? -1;
  assert(start >= 0, "writer must expose a RevenueCat refresh boundary");
  const end = source.indexOf("\n}\n", start);
  assert(end > start, "RevenueCat refresh boundary must be parseable");
  return source.slice(start, end);
}

Deno.test("all RC snapshot writers use the shared atomic store-state boundary", async () => {
  for (const file of writerFiles) {
    const source = await readWriter(file);
    assert(
      source.includes("persistSubscriptionStoreState"),
      `${file} must call persistSubscriptionStoreState`,
    );
  }

  for (
    const file of [
      "../revenuecat-webhook/index.ts",
      "../sync-subscription/index.ts",
      "../analyze-chat/revenuecat_reconciliation.ts",
    ]
  ) {
    const source = await readWriter(file);
    assert(
      !source.includes('.from("subscriptions").update'),
      `${file} must not directly update legacy subscriptions from an RC snapshot`,
    );
  }

  for (
    const file of [
      "../coach-chat/index.ts",
      "../coach-follow-up/index.ts",
      "../keyboard-assist/index.ts",
      "../keyboard-reply/index.ts",
    ]
  ) {
    const body = refreshBody(await readWriter(file));
    assert(
      body.includes("persistSubscriptionStoreState"),
      `${file} RevenueCat refresh must use shared persistence`,
    );
    assert(
      !body.includes('.from("subscriptions").update'),
      `${file} RevenueCat refresh must not directly update legacy subscriptions`,
    );
  }
});

Deno.test("RevenueCat webhook uses shared Play base-plan extraction", async () => {
  const source = await readWriter(
    "../revenuecat-webhook/webhook_store_event.ts",
  );
  assert(
    source.includes("extractRevenueCatBasePlanId"),
    "webhook must preserve Play base-plan provenance through shared extraction",
  );
});

Deno.test("all RC refresh consumers fail closed when legacy read is missing", async () => {
  for (
    const file of [
      "../coach-chat/index.ts",
      "../coach-follow-up/index.ts",
      "../keyboard-assist/index.ts",
      "../keyboard-reply/index.ts",
    ]
  ) {
    const source = await readWriter(file);
    assert(
      !source.includes("refreshed ?? { ...sub, tier:"),
      `${file} must not fabricate a legacy row after store persistence`,
    );
    assert(
      !source.includes("data ?? { ...sub, tier:"),
      `${file} must not fabricate a legacy row after store persistence`,
    );
  }
});

Deno.test("webhook requires authoritative event time before state persistence", async () => {
  const source = await readWriter(
    "../revenuecat-webhook/webhook_store_event.ts",
  );
  assert(
    !source.includes(
      "event_timestamp_ms) ??\n      normalizeTimestampMs(event.purchased_at_ms) ?? new Date().toISOString()",
    ),
    "webhook state events must not synthesize a current event time",
  );
  assert(
    source.includes("eventAt == null"),
    "webhook must fail closed when authoritative event time is absent",
  );
});

Deno.test("webhook routes subscription pause through the per-store state writer", async () => {
  const source = await readWriter("../revenuecat-webhook/index.ts");
  assert(
    source.includes('case "SUBSCRIPTION_PAUSED":'),
    "subscription pause must use the same per-store persistence path",
  );
  assert(
    source.includes('type === "EXPIRATION"'),
    "terminal expiration handling must remain explicit",
  );
});

Deno.test("webhook state decisions cannot consult a cross-store legacy tier or expiry", async () => {
  const source = await readWriter("../revenuecat-webhook/index.ts");
  assert(
    !source.includes("currentTier"),
    "webhook must not use legacy currentTier",
  );
  assert(
    !source.includes("currentExpiresAt"),
    "webhook must not use legacy currentExpiresAt",
  );
  assert(
    source.includes("buildRevenueCatWebhookStoreEvent"),
    "webhook must use the per-event store builder",
  );
  assert(
    source.includes("hasInvalidUuidList") &&
      source.includes("Invalid transfer targets") &&
      source.includes('from("users")'),
    "transfer targets must be validated before any recipient/source write",
  );
});

Deno.test("transfer targets retain the webhook event id as their idempotency key", async () => {
  const source = await readWriter("../revenuecat-webhook/index.ts");
  assert(
    !source.includes("transferEvent.eventId}:transfer"),
    "transfer must not rewrite an existing RevenueCat event id",
  );
});
