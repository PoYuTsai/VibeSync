// supabase/functions/_shared/quota_test.ts
//
// T6 — quota machinery pure-helper tests. Covers the full edge-case matrix
// (Codex Plan-Review P1 #3) WITHOUT touching real Supabase / RevenueCat:
//   1. tier normalisation + unknown/null fallback
//   2. limit resolution + unknown tier fallback to free
//   3. daily / monthly reset detection (boundary days, year wraparound, null timestamps)
//   4. quota check including test-account bypass + cost > 1 + boundary equality
//   5. RevenueCat payload parsing (active vs expired entitlements / subscriptions)
//
// Integration of these helpers with the actual Supabase / RC HTTP plumbing
// is exercised via curl smoke in T10 — that's where the live edge cases land.

import {
  assertEquals,
  assertObjectMatch,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  applyResetsIfNeeded,
  checkQuota,
  isPlainObject,
  normalizeTier,
  parseRevenueCatSubscriber,
  resolveLimits,
  type SubscriptionRow,
  TEST_EMAILS,
  TIER_DAILY_LIMITS,
  TIER_MONTHLY_LIMITS,
  tierRank,
} from "./quota.ts";

// ---------------------------------------------------------------------------
// normalizeTier — unknown / null / wrong-type all fall back to "free"
// ---------------------------------------------------------------------------

Deno.test("normalizeTier passes through canonical names", () => {
  assertEquals(normalizeTier("free"), "free");
  assertEquals(normalizeTier("starter"), "starter");
  assertEquals(normalizeTier("essential"), "essential");
});

Deno.test("normalizeTier lower-cases + trims", () => {
  assertEquals(normalizeTier("  Starter "), "starter");
  assertEquals(normalizeTier("ESSENTIAL"), "essential");
});

Deno.test("normalizeTier falls back to free for unknown / null / undefined / wrong type", () => {
  assertEquals(normalizeTier("mystery_tier"), "free");
  assertEquals(normalizeTier(null), "free");
  assertEquals(normalizeTier(undefined), "free");
  assertEquals(normalizeTier(""), "free");
  assertEquals(normalizeTier(42), "free");
  assertEquals(normalizeTier({}), "free");
});

// ---------------------------------------------------------------------------
// tierRank — strictly ordered for RC refresh comparison
// ---------------------------------------------------------------------------

Deno.test("tierRank is strictly ordered free < starter < essential", () => {
  assertEquals(tierRank("free"), 0);
  assertEquals(tierRank("starter"), 1);
  assertEquals(tierRank("essential"), 2);
});

// ---------------------------------------------------------------------------
// resolveLimits — unknown / null tier falls back to free limits
// ---------------------------------------------------------------------------

Deno.test("resolveLimits returns matching tier limits", () => {
  assertEquals(resolveLimits("free"), { monthly: 30, daily: 15 });
  assertEquals(resolveLimits("starter"), { monthly: 300, daily: 50 });
  assertEquals(resolveLimits("essential"), { monthly: 800, daily: 120 });
});

Deno.test("resolveLimits falls back to free for unknown tier", () => {
  assertEquals(resolveLimits("mystery_tier"), { monthly: 30, daily: 15 });
});

Deno.test("resolveLimits falls back to free for null / undefined tier", () => {
  assertEquals(resolveLimits(null), { monthly: 30, daily: 15 });
  assertEquals(resolveLimits(undefined), { monthly: 30, daily: 15 });
});

// ---------------------------------------------------------------------------
// applyResetsIfNeeded — daily / monthly window boundaries
// ---------------------------------------------------------------------------

const baseSub = (): SubscriptionRow => ({
  tier: "free",
  monthly_messages_used: 25,
  daily_messages_used: 10,
  daily_reset_at: "2026-05-02T00:00:00.000Z",
  monthly_reset_at: "2026-05-01T00:00:00.000Z",
});

Deno.test("applyResetsIfNeeded leaves counters untouched when same day", () => {
  const now = new Date("2026-05-02T18:00:00.000Z");
  const r = applyResetsIfNeeded(baseSub(), now);
  assertEquals(r.dailyReset, false);
  assertEquals(r.monthlyReset, false);
  assertEquals(r.sub.daily_messages_used, 10);
  assertEquals(r.sub.monthly_messages_used, 25);
});

Deno.test("applyResetsIfNeeded triggers daily reset when daily_reset_at is yesterday", () => {
  const sub = { ...baseSub(), daily_reset_at: "2026-05-01T20:00:00.000Z" };
  const now = new Date("2026-05-02T08:00:00.000Z");
  const r = applyResetsIfNeeded(sub, now);
  assertEquals(r.dailyReset, true);
  assertEquals(r.monthlyReset, false);
  assertEquals(r.sub.daily_messages_used, 0);
  assertEquals(r.sub.monthly_messages_used, 25);
  assertEquals(r.sub.daily_reset_at, now.toISOString());
});

Deno.test("applyResetsIfNeeded triggers monthly reset when monthly_reset_at is last month", () => {
  const sub = { ...baseSub(), monthly_reset_at: "2026-04-30T20:00:00.000Z" };
  const now = new Date("2026-05-02T08:00:00.000Z");
  const r = applyResetsIfNeeded(sub, now);
  assertEquals(r.monthlyReset, true);
  assertEquals(r.sub.monthly_messages_used, 0);
  assertEquals(r.sub.monthly_reset_at, now.toISOString());
});

Deno.test("applyResetsIfNeeded triggers monthly reset on year wraparound", () => {
  const sub = { ...baseSub(), monthly_reset_at: "2025-12-31T20:00:00.000Z" };
  const now = new Date("2026-01-01T01:00:00.000Z");
  const r = applyResetsIfNeeded(sub, now);
  assertEquals(r.monthlyReset, true);
});

Deno.test("applyResetsIfNeeded triggers both resets when both stale", () => {
  const sub = {
    ...baseSub(),
    daily_reset_at: "2026-04-30T00:00:00.000Z",
    monthly_reset_at: "2026-04-30T00:00:00.000Z",
  };
  const now = new Date("2026-05-02T08:00:00.000Z");
  const r = applyResetsIfNeeded(sub, now);
  assertEquals(r.dailyReset, true);
  assertEquals(r.monthlyReset, true);
  assertEquals(r.sub.daily_messages_used, 0);
  assertEquals(r.sub.monthly_messages_used, 0);
});

Deno.test("applyResetsIfNeeded treats null timestamps as never-reset (forces both resets)", () => {
  const sub = { ...baseSub(), daily_reset_at: null, monthly_reset_at: null };
  const now = new Date("2026-05-02T08:00:00.000Z");
  const r = applyResetsIfNeeded(sub, now);
  assertEquals(r.dailyReset, true);
  assertEquals(r.monthlyReset, true);
});

Deno.test("applyResetsIfNeeded returns a NEW sub object (immutable)", () => {
  const original = baseSub();
  const now = new Date("2026-05-02T18:00:00.000Z");
  const r = applyResetsIfNeeded(original, now);
  assertEquals(r.sub === original, false);
});

// ---------------------------------------------------------------------------
// checkQuota — cost / boundary / test-account bypass
// ---------------------------------------------------------------------------

Deno.test("checkQuota passes when usage + cost is under both limits", () => {
  const r = checkQuota({
    sub: { ...baseSub(), monthly_messages_used: 5, daily_messages_used: 2 },
    cost: 1,
    isTestAccount: false,
    monthlyLimit: 30,
    dailyLimit: 15,
  });
  assertEquals(r.ok, true);
});

Deno.test("checkQuota fails monthly when monthly + cost would exceed", () => {
  const r = checkQuota({
    sub: { ...baseSub(), monthly_messages_used: 30, daily_messages_used: 2 },
    cost: 1,
    isTestAccount: false,
    monthlyLimit: 30,
    dailyLimit: 15,
  });
  assertEquals(r.ok, false);
  if (!r.ok) {
    assertEquals(r.reason, "monthly_limit_exceeded");
    assertEquals(r.limit, 30);
  }
});

Deno.test("checkQuota fails daily when daily + cost would exceed (monthly under)", () => {
  const r = checkQuota({
    sub: { ...baseSub(), monthly_messages_used: 5, daily_messages_used: 15 },
    cost: 1,
    isTestAccount: false,
    monthlyLimit: 30,
    dailyLimit: 15,
  });
  assertEquals(r.ok, false);
  if (!r.ok) {
    assertEquals(r.reason, "daily_limit_exceeded");
    assertEquals(r.limit, 15);
  }
});

Deno.test("checkQuota: monthly takes precedence over daily when both fail", () => {
  const r = checkQuota({
    sub: { ...baseSub(), monthly_messages_used: 30, daily_messages_used: 15 },
    cost: 1,
    isTestAccount: false,
    monthlyLimit: 30,
    dailyLimit: 15,
  });
  assertEquals(r.ok, false);
  if (!r.ok) assertEquals(r.reason, "monthly_limit_exceeded");
});

Deno.test("checkQuota: boundary — usage exactly at limit fails (cost would push over)", () => {
  const r = checkQuota({
    sub: { ...baseSub(), monthly_messages_used: 30, daily_messages_used: 5 },
    cost: 1,
    isTestAccount: false,
    monthlyLimit: 30,
    dailyLimit: 15,
  });
  assertEquals(r.ok, false);
});

Deno.test("checkQuota: zero-cost preflight passes at exact limit but not over limit", () => {
  const atLimit = checkQuota({
    sub: { ...baseSub(), monthly_messages_used: 30, daily_messages_used: 15 },
    cost: 0,
    isTestAccount: false,
    monthlyLimit: 30,
    dailyLimit: 15,
  });
  const overLimit = checkQuota({
    sub: { ...baseSub(), monthly_messages_used: 31, daily_messages_used: 15 },
    cost: 0,
    isTestAccount: false,
    monthlyLimit: 30,
    dailyLimit: 15,
  });
  assertEquals(atLimit.ok, true);
  assertEquals(overLimit.ok, false);
});

Deno.test("checkQuota: boundary — usage one below limit passes", () => {
  const r = checkQuota({
    sub: { ...baseSub(), monthly_messages_used: 29, daily_messages_used: 5 },
    cost: 1,
    isTestAccount: false,
    monthlyLimit: 30,
    dailyLimit: 15,
  });
  assertEquals(r.ok, true);
});

Deno.test("checkQuota: test account bypasses ALL caps regardless of usage", () => {
  const r = checkQuota({
    sub: {
      ...baseSub(),
      monthly_messages_used: 99999,
      daily_messages_used: 99999,
    },
    cost: 1,
    isTestAccount: true,
    monthlyLimit: 30,
    dailyLimit: 15,
  });
  assertEquals(r.ok, true);
});

Deno.test("checkQuota: cost > 1 uses cost in calculation (boundary)", () => {
  const r = checkQuota({
    sub: { ...baseSub(), monthly_messages_used: 28, daily_messages_used: 5 },
    cost: 3, // 28 + 3 = 31 > 30
    isTestAccount: false,
    monthlyLimit: 30,
    dailyLimit: 15,
  });
  assertEquals(r.ok, false);
});

// ---------------------------------------------------------------------------
// parseRevenueCatSubscriber — payload sanity + active vs expired filtering
// ---------------------------------------------------------------------------

Deno.test("parseRevenueCatSubscriber returns null for non-object input", () => {
  assertEquals(parseRevenueCatSubscriber(null), null);
  assertEquals(parseRevenueCatSubscriber("oops"), null);
  assertEquals(parseRevenueCatSubscriber(42), null);
});

Deno.test("parseRevenueCatSubscriber returns free when no entitlements / subscriptions", () => {
  const r = parseRevenueCatSubscriber({});
  assertEquals(r?.tier, "free");
  assertEquals(r?.expiresAt, null);
});

Deno.test("parseRevenueCatSubscriber promotes to essential when active essential entitlement", () => {
  const r = parseRevenueCatSubscriber({
    entitlements: {
      pro: {
        product_identifier: "vibesync_essential_monthly",
        expires_date: "2099-01-01T00:00:00Z",
      },
    },
  });
  assertEquals(r?.tier, "essential");
  assertEquals(typeof r?.expiresAt, "string");
});

Deno.test("parseRevenueCatSubscriber ignores expired entitlements", () => {
  const r = parseRevenueCatSubscriber({
    entitlements: {
      pro: {
        product_identifier: "vibesync_essential_monthly",
        expires_date: "2020-01-01T00:00:00Z",
      },
    },
  });
  assertEquals(r?.tier, "free");
});

Deno.test("parseRevenueCatSubscriber picks highest active tier across entitlements + subscriptions", () => {
  const r = parseRevenueCatSubscriber({
    entitlements: {
      promo: {
        product_identifier: "vibesync_starter_monthly",
        expires_date: "2099-01-01T00:00:00Z",
      },
    },
    subscriptions: {
      vibesync_essential_quarterly: {
        expires_date: "2099-06-01T00:00:00Z",
      },
    },
  });
  assertEquals(r?.tier, "essential");
});

// ---------------------------------------------------------------------------
// Module surface sanity
// ---------------------------------------------------------------------------

Deno.test("TIER_MONTHLY_LIMITS / TIER_DAILY_LIMITS pricing-final.md values", () => {
  assertObjectMatch(TIER_MONTHLY_LIMITS, {
    free: 30,
    starter: 300,
    essential: 800,
  });
  assertObjectMatch(TIER_DAILY_LIMITS, {
    free: 15,
    starter: 50,
    essential: 120,
  });
});

Deno.test("TEST_EMAILS contains the canonical vibesync.test@gmail.com only", () => {
  assertEquals(TEST_EMAILS, ["vibesync.test@gmail.com"]);
});

Deno.test("isPlainObject discriminates objects from arrays / null / primitives", () => {
  assertEquals(isPlainObject({}), true);
  assertEquals(isPlainObject({ a: 1 }), true);
  assertEquals(isPlainObject([]), false);
  assertEquals(isPlainObject(null), false);
  assertEquals(isPlainObject("x"), false);
  assertEquals(isPlainObject(0), false);
});
