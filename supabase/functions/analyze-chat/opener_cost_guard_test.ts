import { assert, assertEquals, assertFalse } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { handleOpenerRequest, type OpenerHandlerDeps } from "./opener_handler.ts";
import { computeOpenerInputHash } from "./opener_charge.ts";
import type { ProviderAttemptLogEntry } from "./model_call_budget.ts";

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

Deno.test("K3: legacy opener success writes one ai_logs row per provider call", async () => {
  const original = globalThis.fetch;
  let providerCalls = 0;
  const openers = { extend: "妳最近在喝哪家咖啡？", resonate: "妳也喜歡手沖嗎？", tease: "咖啡喝這麼多睡得著嗎？", humor: "妳是靠咖啡續命派嗎？", coldRead: "感覺妳是會固定去同一家店的人？" };
  globalThis.fetch = (() => {
    providerCalls++;
    return Promise.resolve(Response.json({ content: [{ type: "text", text: JSON.stringify({ openers }) }], usage: { input_tokens: 100, output_tokens: 50 }, stop_reason: "end_turn" }));
  }) as typeof fetch;
  const rows: ProviderAttemptLogEntry[] = [];
  try {
    const response = await handleOpenerRequest({
      supabase: { rpc: () => Promise.resolve({ data: true, error: null }) },
      userId: "synthetic-owner", images: null, rawProfileInfo: { name: "Synthetic", bio: "coffee" },
      rawRequestId: null, rawKnownContactName: null, rawEffectiveStyleContext: null, rawOpenerContractVersion: 2,
      responseMode: "legacy", requestStartedAtMs: Date.now(), accountIsTest: false, claudeApiKey: "fake",
      refreshTierFromRevenueCat: () => Promise.reject(new Error("must not refresh")),
      quota: () => ({ sub: { monthly_messages_used: 0, daily_messages_used: 0 }, monthlyLimit: 30, dailyLimit: 15, effectiveTier: "free", allowedFeatures: [] }),
      recordAiCall: (e) => rows.push(e),
    });
    assertEquals(response.status, 200);
    assertEquals(providerCalls, 1);
    assertEquals(rows.map((r) => [r.requestType, r.model, r.status, (r.requestBody as Record<string, unknown>).stage]), [["opener", "claude-sonnet-5", "success", "legacy"]]);
  } finally { globalThis.fetch = original; }
});

Deno.test("legacy opener charge failure does not promise no charge", async () => {
  const original = globalThis.fetch;
  const openers = { extend: "妳最近在喝哪家咖啡？", resonate: "妳也喜歡手沖嗎？", tease: "咖啡喝這麼多睡得著嗎？", humor: "妳是靠咖啡續命派嗎？", coldRead: "感覺妳是會固定去同一家店的人？" };
  globalThis.fetch = (() => Promise.resolve(Response.json({ content: [{ type: "text", text: JSON.stringify({ openers }) }], usage: { input_tokens: 100, output_tokens: 50 }, stop_reason: "end_turn" }))) as typeof fetch;
  try {
    const response = await handleOpenerRequest({
      supabase: {
        rpc: (name: string) => Promise.resolve(name === "increment_model_usage" ? { data: true, error: null } : { data: null, error: { message: "TypeError: fetch failed (timeout)" } }),
      },
      userId: "synthetic-owner", images: null, rawProfileInfo: { name: "Synthetic", bio: "coffee" },
      rawRequestId: null, rawKnownContactName: null, rawEffectiveStyleContext: null, rawOpenerContractVersion: 2,
      responseMode: "legacy", requestStartedAtMs: Date.now(), accountIsTest: false, claudeApiKey: "fake",
      refreshTierFromRevenueCat: () => Promise.reject(new Error("must not refresh")),
      quota: () => ({ sub: { monthly_messages_used: 0, daily_messages_used: 0 }, monthlyLimit: 30, dailyLimit: 15, effectiveTier: "free", allowedFeatures: [] }),
    });
    assertEquals(response.status, 500);
    const body = await response.json();
    assertEquals(body.error, "credit_deduct_failed");
    assertFalse(JSON.stringify(body).includes("不會扣額度"));
    assertFalse(JSON.stringify(body).includes("fetch failed"));
  } finally { globalThis.fetch = original; }
});

Deno.test("legacy opener provider error does not leak upstream text", async () => {
  const original = globalThis.fetch;
  // 非 JSON 200 → PARSE_ERROR；錯誤訊息只帶長度、不帶回應片段（fallback.ts），回應裡也不能有上游文字。
  globalThis.fetch = (() => Promise.resolve(new Response("upstream-secret-xyz"))) as typeof fetch;
  try {
    const response = await handleOpenerRequest({
      supabase: { rpc: () => Promise.resolve({ data: true, error: null }) },
      userId: "synthetic-owner", images: null, rawProfileInfo: { name: "Synthetic", bio: "coffee" },
      rawRequestId: null, rawKnownContactName: null, rawEffectiveStyleContext: null, rawOpenerContractVersion: 2,
      responseMode: "legacy", requestStartedAtMs: Date.now(), accountIsTest: false, claudeApiKey: "fake",
      refreshTierFromRevenueCat: () => Promise.reject(new Error("must not refresh")),
      quota: () => ({ sub: { monthly_messages_used: 0, daily_messages_used: 0 }, monthlyLimit: 30, dailyLimit: 15, effectiveTier: "free", allowedFeatures: [] }),
    });
    assertEquals(response.status, 500);
    const text = await response.text();
    assertFalse(text.includes("upstream-secret-xyz"));
  } finally { globalThis.fetch = original; }
});

// 額度 429 帶結構化 quotaScope（Eric 2026-10-18）：App 照它說本月或今日、開哪個付費頁入口。
// 結算競態回的剩餘數是預查時的舊值（看起來還夠），只有 quotaScope 分得出是哪個額度擋下。
Deno.test("legacy opener 額度 429：預查與結算競態都帶 quotaScope；競態的剩餘數是預查舊值，message 照舊", async () => {
  const original = globalThis.fetch;
  const openers = { extend: "妳最近在喝哪家咖啡？", resonate: "妳也喜歡手沖嗎？", tease: "咖啡喝這麼多睡得著嗎？", humor: "妳是靠咖啡續命派嗎？", coldRead: "感覺妳是會固定去同一家店的人？" };
  globalThis.fetch = (() => Promise.resolve(Response.json({ content: [{ type: "text", text: JSON.stringify({ openers }) }], usage: { input_tokens: 100, output_tokens: 50 }, stop_reason: "end_turn" }))) as typeof fetch;
  const cases: Array<{ name: string; monthlyUsed: number; dailyUsed: number; raise?: string; scope: "monthly" | "daily" }> = [
    { name: "預查：本月不夠", monthlyUsed: 28, dailyUsed: 0, scope: "monthly" },
    { name: "預查：本月夠、今天不夠", monthlyUsed: 0, dailyUsed: 13, scope: "daily" },
    { name: "結算競態：本月", monthlyUsed: 0, dailyUsed: 0, raise: "QUOTA_EXCEEDED_MONTHLY", scope: "monthly" },
    { name: "結算競態：今天", monthlyUsed: 0, dailyUsed: 0, raise: "QUOTA_EXCEEDED_DAILY", scope: "daily" },
  ];
  try {
    for (const c of cases) {
      const response = await handleOpenerRequest({
        supabase: {
          rpc: (name: string) => Promise.resolve(name === "increment_model_usage" || c.raise === undefined ? { data: true, error: null } : { data: null, error: { message: c.raise } }),
        },
        userId: "synthetic-owner", images: null, rawProfileInfo: { name: "Synthetic", bio: "coffee" },
        rawRequestId: null, rawKnownContactName: null, rawEffectiveStyleContext: null, rawOpenerContractVersion: 2,
        responseMode: "legacy", requestStartedAtMs: Date.now(), accountIsTest: false, claudeApiKey: "fake",
        refreshTierFromRevenueCat: () => Promise.resolve("not_paid"),
        quota: () => ({ sub: { monthly_messages_used: c.monthlyUsed, daily_messages_used: c.dailyUsed }, monthlyLimit: 30, dailyLimit: 15, effectiveTier: "free", allowedFeatures: [] }),
      });
      assertEquals(response.status, 429, c.name);
      const body = await response.json();
      assertEquals(body.quotaScope, c.scope, c.name);
      if (c.raise === undefined) {
        assert(String(body.message).startsWith(c.scope === "monthly" ? "本月" : "今日"), c.name);
      } else {
        assertEquals(body.error, c.scope === "monthly" ? "Monthly limit exceeded" : "Daily limit exceeded", c.name);
        assert(body.monthlyRemaining >= body.quotaNeeded && body.dailyRemaining >= body.quotaNeeded, `${c.name}：預查舊值看起來還夠`);
      }
    }
  } finally { globalThis.fetch = original; }
});
