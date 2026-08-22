import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildRevenueCatUserIdCandidates,
  collectLatestExpirationFromRevenueCatPayload,
  collectTiersFromRevenueCatPayload,
  createRevenueCatTierRefresher,
} from "./revenuecat_reconciliation.ts";

const USER = "00000000-0000-4000-8000-000000000001";

function makeDeps(overrides: Partial<{
  apiKey: string | undefined;
  subTier: string;
  updateError: { message: string } | null;
  updateReturnsRow: boolean;
}> = {}) {
  const updates: Array<Record<string, unknown>> = [];
  const applied: Array<Record<string, unknown>> = [];
  const refreshedRow = {
    tier: "essential",
    monthly_messages_used: 1,
    daily_messages_used: 1,
    daily_reset_at: null,
    monthly_reset_at: null,
  };
  const sub = {
    tier: overrides.subTier ?? "free",
    monthly_messages_used: 7,
    daily_messages_used: 2,
    daily_reset_at: null,
    monthly_reset_at: null,
  };
  const supabase = {
    from(_table: string) {
      return {
        update(values: Record<string, unknown>) {
          updates.push(values);
          return {
            eq: () => ({
              select: () => ({
                maybeSingle: () =>
                  Promise.resolve({
                    data: overrides.updateReturnsRow === false
                      ? null
                      : refreshedRow,
                    error: overrides.updateError ?? null,
                  }),
              }),
            }),
          };
        },
      };
    },
    // deno-lint-ignore no-explicit-any
  } as any;
  const refresher = createRevenueCatTierRefresher({
    supabase,
    apiKey: "apiKey" in overrides ? overrides.apiKey : "rc-key",
    userId: USER,
    revenueCatAppUserId: "rc-user",
    expectedTier: "essential",
    candidates: ["rc-user", USER],
    readState: () => ({ sub, effectiveTier: sub.tier }),
    applyRefreshedSub: (nextSub) => applied.push(nextSub),
  });
  return { refresher, updates, applied, refreshedRow, sub };
}

function withFakeFetch(
  responder: (url: string) => Response | Promise<Response>,
  run: () => Promise<void>,
): Promise<void> {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = (input) => Promise.resolve(responder(String(input)));
  return run().finally(() => {
    globalThis.fetch = originalFetch;
  });
}

function subscriberResponse(subscriber: Record<string, unknown>): Response {
  return new Response(JSON.stringify({ subscriber }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

Deno.test("RC 對帳：未設 API key → not_configured 且不打網路", async () => {
  const { refresher } = makeDeps({ apiKey: undefined });
  await withFakeFetch(() => {
    throw new Error("must not fetch");
  }, async () => {
    assertEquals(await refresher("test"), "not_configured");
  });
});

Deno.test("RC 對帳：已是 essential → not_paid 不再查詢", async () => {
  const { refresher } = makeDeps({ subTier: "essential" });
  await withFakeFetch(() => {
    throw new Error("must not fetch");
  }, async () => {
    assertEquals(await refresher("test"), "not_paid");
  });
});

Deno.test("RC 對帳：查到更高 tier → 升級持久化並回寫 applied", async () => {
  const { refresher, updates, applied, refreshedRow } = makeDeps();
  await withFakeFetch(
    () =>
      subscriberResponse({
        entitlements: {
          pro: {
            product_identifier: "vibesync_essential_monthly",
            expires_date: new Date(Date.now() + 86400_000).toISOString(),
          },
        },
      }),
    async () => {
      assertEquals(await refresher("client_expected_paid_tier"), "applied");
    },
  );
  assertEquals(updates.length, 1);
  assertEquals(updates[0].tier, "essential");
  assertEquals(updates[0].status, "active");
  assert(typeof updates[0].expires_at === "string");
  assertEquals(applied, [refreshedRow]);
});

Deno.test("RC 對帳：持久化失敗仍 applied，回寫本地升級視圖", async () => {
  const { refresher, applied, sub } = makeDeps({
    updateError: { message: "boom" },
    updateReturnsRow: false,
  });
  await withFakeFetch(
    () =>
      subscriberResponse({
        subscriptions: {
          vibesync_starter_monthly: {
            expires_date: new Date(Date.now() + 86400_000).toISOString(),
          },
        },
      }),
    async () => {
      assertEquals(await refresher("monthly_limit_exceeded"), "applied");
    },
  );
  assertEquals(applied, [{ ...sub, tier: "starter" }]);
});

Deno.test("RC 對帳：全部 candidate 失敗 → unavailable；查到但沒更高 tier → not_paid", async () => {
  const failing = makeDeps();
  await withFakeFetch(
    () => new Response("nope", { status: 502 }),
    async () => {
      assertEquals(await failing.refresher("test"), "unavailable");
    },
  );
  assertEquals(failing.applied.length, 0);

  const notPaid = makeDeps();
  await withFakeFetch(
    () => subscriberResponse({ entitlements: {}, subscriptions: {} }),
    async () => {
      assertEquals(await notPaid.refresher("test"), "not_paid");
    },
  );
  assertEquals(notPaid.updates.length, 0);
});

Deno.test("RC payload：過期訂閱不算、取最高 tier 與最晚到期", () => {
  const future = new Date(Date.now() + 86400_000).toISOString();
  const later = new Date(Date.now() + 2 * 86400_000).toISOString();
  const past = new Date(Date.now() - 86400_000).toISOString();
  const subscriber = {
    entitlements: {
      a: { product_identifier: "vibesync_essential", expires_date: past },
      b: { product_identifier: "vibesync_starter", expires_date: future },
    },
    subscriptions: {
      vibesync_starter_monthly: { expires_date: later },
    },
  };
  assertEquals(collectTiersFromRevenueCatPayload(subscriber), "starter");
  assertEquals(collectLatestExpirationFromRevenueCatPayload(subscriber), later);
});

Deno.test("RC candidates：去重、去空白、保序", () => {
  assertEquals(
    buildRevenueCatUserIdCandidates({
      revenueCatAppUserId: `  ${USER}  `,
      userId: USER,
    }),
    [USER],
  );
  assertEquals(
    buildRevenueCatUserIdCandidates({ revenueCatAppUserId: "", userId: USER }),
    [USER],
  );
});
