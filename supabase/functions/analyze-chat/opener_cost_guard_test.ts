import { assertEquals, assertFalse } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { handleOpenerRequest, type OpenerHandlerDeps } from "./opener_handler.ts";
import { computeOpenerInputHash } from "./opener_charge.ts";

Deno.test("C08 legacy/stream/paid-receipt retries cannot bypass a failed shared limiter", async () => {
  const original = globalThis.fetch;
  let providerCalls = 0;
  globalThis.fetch = (() => { providerCalls++; throw new Error("provider must not run"); }) as typeof fetch;
  const profile = { name: "Synthetic", bio: "coffee" };
  const inputHash = await computeOpenerInputHash({ images: null, profileInfo: profile });
  try {
    for (const responseMode of ["legacy", "stream"] as const) {
      for (const replay of [false, true]) {
        for (const throws of [false, true]) {
          const rpcs: string[] = [];
          const row = replay ? { input_hash: inputHash, replay_count: 0 } : null;
          const query = {
            select: () => query, eq: () => query,
            maybeSingle: () => Promise.resolve({ data: row, error: null }),
          };
          const deps: OpenerHandlerDeps = {
            supabase: {
              from: () => query,
              rpc: (name: string) => {
                rpcs.push(name);
                if (throws) throw new Error("database unavailable");
                return Promise.resolve({ data: null, error: { message: "database unavailable" } });
              },
            },
            userId: "synthetic-owner", images: null, rawProfileInfo: profile,
            rawRequestId: replay ? "2aa16d52-4fd5-419f-b879-59bf4b0e3638" : null,
            rawKnownContactName: null, rawEffectiveStyleContext: null, rawOpenerContractVersion: 2,
            responseMode, requestStartedAtMs: Date.now(), accountIsTest: false, claudeApiKey: "fake-never-used",
            refreshTierFromRevenueCat: () => Promise.reject(new Error("must not refresh")),
            quota: () => ({ sub: { monthly_messages_used: 30, daily_messages_used: 15 }, monthlyLimit: 30, dailyLimit: 15, effectiveTier: "free", allowedFeatures: [] }),
          };
          const response = await handleOpenerRequest(deps);
          assertEquals(response.status, 503);
          const body = await response.json();
          assertEquals(body.code, "MODEL_RATE_LIMIT_UNAVAILABLE");
          assertEquals(body.shouldChargeQuota, false);
          for (const key of ["quotaNeeded", "monthlyRemaining", "dailyRemaining"]) assertFalse(key in body);
          assertEquals(rpcs, ["increment_model_usage"]);
          assertEquals(providerCalls, 0);
        }
      }
    }
  } finally { globalThis.fetch = original; }
});
