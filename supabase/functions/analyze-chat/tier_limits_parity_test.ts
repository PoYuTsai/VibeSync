// 分析函式自己有一份額度表（歷史因素，沒有改用 _shared/quota.ts）。
// 免費 30／15 → 50／20（Eric 2026-10-18）時只改了 _shared 那份會漏，
// 這裡鎖住兩份每個方案都一樣。
import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  TIER_DAILY_LIMITS,
  TIER_MONTHLY_LIMITS,
} from "./analyze_chat_handler.ts";
import {
  TIER_DAILY_LIMITS as SHARED_TIER_DAILY_LIMITS,
  TIER_MONTHLY_LIMITS as SHARED_TIER_MONTHLY_LIMITS,
} from "../_shared/quota.ts";

Deno.test("額度表：分析函式跟 _shared/quota.ts 每個方案的月、日上限都一樣", () => {
  assertEquals(TIER_MONTHLY_LIMITS, SHARED_TIER_MONTHLY_LIMITS);
  assertEquals(TIER_DAILY_LIMITS, SHARED_TIER_DAILY_LIMITS);
});

Deno.test("額度表：免費每月 50、每日 20 則（Eric 2026-10-18）", () => {
  assertEquals(TIER_MONTHLY_LIMITS.free, 50);
  assertEquals(TIER_DAILY_LIMITS.free, 20);
});
