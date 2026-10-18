// 額度表有三份（歷史因素，沒有都改用 _shared/quota.ts）：共用那份、分析函式自己一份、
// sync-subscription 一份（回給 App 顯示的上限）。免費 30／15 → 50／20 → 30／15（Eric
// 2026-10-18 放寬，10-19 照 Bruce 改回）每次都要三份一起改，這裡鎖住每個方案都一樣。
import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  TIER_DAILY_LIMITS,
  TIER_MONTHLY_LIMITS,
} from "./analyze_chat_handler.ts";
import {
  TIER_DAILY_LIMITS as SHARED_TIER_DAILY_LIMITS,
  TIER_MONTHLY_LIMITS as SHARED_TIER_MONTHLY_LIMITS,
} from "../_shared/quota.ts";

/// sync-subscription 一載入就起伺服器，不能 import：從原始碼讀它的 TIER_LIMITS。
async function syncSubscriptionLimits(): Promise<
  Record<string, { monthly: number; daily: number }>
> {
  const source = await Deno.readTextFile(
    new URL("../sync-subscription/index.ts", import.meta.url),
  );
  const start = source.indexOf("const TIER_LIMITS");
  const block = source.slice(start, source.indexOf("\n};", start));
  return Object.fromEntries(
    [...block.matchAll(/(\w+): \{ monthly: (\d+), daily: (\d+) \}/g)].map((
      [, tier, monthly, daily],
    ) => [tier, { monthly: Number(monthly), daily: Number(daily) }]),
  );
}

Deno.test("額度表：分析函式、sync-subscription 跟 _shared/quota.ts 每個方案的月、日上限都一樣", async () => {
  assertEquals(TIER_MONTHLY_LIMITS, SHARED_TIER_MONTHLY_LIMITS);
  assertEquals(TIER_DAILY_LIMITS, SHARED_TIER_DAILY_LIMITS);
  const shared = Object.fromEntries(
    Object.keys(SHARED_TIER_MONTHLY_LIMITS).map((tier) => [tier, {
      monthly: SHARED_TIER_MONTHLY_LIMITS[tier],
      daily: SHARED_TIER_DAILY_LIMITS[tier],
    }]),
  );
  assertEquals(await syncSubscriptionLimits(), shared);
});

Deno.test("額度表：免費每月 30、每日 15 則（Bruce 10/18 維持，Eric 2026-10-19 照他改回）", () => {
  assertEquals(TIER_MONTHLY_LIMITS.free, 30);
  assertEquals(TIER_DAILY_LIMITS.free, 15);
});
