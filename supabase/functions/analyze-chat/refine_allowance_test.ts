import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  classifyRefineFreeConsumption,
  projectRefineFreeAllowance,
  REFINE_FREE_DAILY_LIMIT,
  refineQuotaOutcomeFor,
  shouldChargeAfterRefineConsumption,
  utcDayString,
} from "./refine_allowance.ts";
import { buildQuotaUsageMetadata } from "./quota_usage.ts";

const TODAY = "2026-07-29";

Deno.test("每日免費額度是十次", () => {
  assertEquals(REFINE_FREE_DAILY_LIMIT, 10);
});

Deno.test("日界以 UTC 判定", () => {
  assertEquals(
    utcDayString(new Date("2026-07-29T23:59:59.999Z")),
    "2026-07-29",
  );
  assertEquals(
    utcDayString(new Date("2026-07-30T00:00:00.000Z")),
    "2026-07-30",
  );
});

Deno.test("投影：沒有列、跨日、資料壞掉都當今天還沒用過", () => {
  for (
    const row of [
      null,
      { day_utc: "2026-07-28", used_count: 10 },
      { day_utc: TODAY, used_count: "3" },
      { day_utc: TODAY, used_count: -1 },
      { day_utc: TODAY, used_count: 2.5 },
      { day_utc: null, used_count: 4 },
    ]
  ) {
    assertEquals(
      projectRefineFreeAllowance({ row, todayUtc: TODAY }),
      { usedToday: 0, remaining: 10, willBeFree: true },
      `row=${JSON.stringify(row)}`,
    );
  }
});

Deno.test("投影：今天用過幾次就少幾次，用滿即非免費", () => {
  assertEquals(
    projectRefineFreeAllowance({
      row: { day_utc: TODAY, used_count: 3 },
      todayUtc: TODAY,
    }),
    { usedToday: 3, remaining: 7, willBeFree: true },
  );
  assertEquals(
    projectRefineFreeAllowance({
      row: { day_utc: TODAY, used_count: 10 },
      todayUtc: TODAY,
    }),
    { usedToday: 10, remaining: 0, willBeFree: false },
  );
  // timestamptz 形狀的 day_utc 也要能對上今天，不能因為帶時間就整天失效。
  assertEquals(
    projectRefineFreeAllowance({
      row: { day_utc: `${TODAY}T00:00:00.000Z`, used_count: 1 },
      todayUtc: TODAY,
    }).usedToday,
    1,
  );
});

Deno.test("授權：granted / exhausted / 壞掉三種結果", () => {
  assertEquals(
    classifyRefineFreeConsumption(
      { granted: true, used: 4, remaining: 6 },
      null,
    ),
    { kind: "granted", used: 4, remaining: 6 },
  );
  assertEquals(
    classifyRefineFreeConsumption(
      { granted: false, used: 10, remaining: 0 },
      null,
    ),
    { kind: "exhausted", used: 10, remaining: 0 },
  );
  assertEquals(
    classifyRefineFreeConsumption(null, { message: "boom" }).kind,
    "unavailable",
  );
  for (const bad of [null, undefined, [], "granted", { used: 1 }]) {
    assertEquals(
      classifyRefineFreeConsumption(bad, null).kind,
      "unavailable",
      `data=${JSON.stringify(bad)}`,
    );
  }
});

Deno.test("只有明確用完才扣費；額度函式掛掉一律不扣", () => {
  assert(
    shouldChargeAfterRefineConsumption({
      kind: "exhausted",
      used: 10,
      remaining: 0,
    }),
  );
  assertFalse(
    shouldChargeAfterRefineConsumption({
      kind: "granted",
      used: 1,
      remaining: 9,
    }),
  );
  assertFalse(
    shouldChargeAfterRefineConsumption({
      kind: "unavailable",
      message: "rpc down",
    }),
  );
});

Deno.test("refine_reply 額度內不扣、額度用完固定扣一則", () => {
  assertEquals(
    buildQuotaUsageMetadata({
      requestType: "refine_reply",
      recognizeOnly: false,
      accountIsTest: false,
      estimatedMessageCount: 7,
      refineIsFree: true,
    }),
    {
      shouldChargeQuota: false,
      quotaReason: "refine_free_daily",
      quotaUnit: "messages",
      chargedMessageCount: 0,
      estimatedMessageCount: 0,
    },
  );
  assertEquals(
    buildQuotaUsageMetadata({
      requestType: "refine_reply",
      recognizeOnly: false,
      accountIsTest: false,
      estimatedMessageCount: 7,
      refineIsFree: false,
    }),
    {
      shouldChargeQuota: true,
      quotaReason: "refine_reply_fixed_1",
      quotaUnit: "messages",
      chargedMessageCount: 1,
      estimatedMessageCount: 1,
    },
  );
});

Deno.test("測試帳號的微調估算不得落回按訊息數算", () => {
  const waivedPaid = buildQuotaUsageMetadata({
    requestType: "refine_reply",
    recognizeOnly: false,
    accountIsTest: true,
    estimatedMessageCount: 7,
    refineIsFree: false,
  });
  assertEquals(waivedPaid.quotaReason, "test_account_waived");
  assertEquals(waivedPaid.shouldChargeQuota, false);
  assertEquals(waivedPaid.chargedMessageCount, 0);
  // 7 是這通對話的訊息數；微調是固定定價，估算不能是 7。
  assertEquals(waivedPaid.estimatedMessageCount, 1);

  const waivedFree = buildQuotaUsageMetadata({
    requestType: "refine_reply",
    recognizeOnly: false,
    accountIsTest: true,
    estimatedMessageCount: 7,
    refineIsFree: true,
  });
  assertEquals(waivedFree.estimatedMessageCount, 0);
});

Deno.test("免費旗標不得外溢到其他 requestType", () => {
  for (const requestType of ["optimize_message", "analyze", "my_message"]) {
    assertEquals(
      buildQuotaUsageMetadata({
        requestType,
        recognizeOnly: false,
        accountIsTest: false,
        estimatedMessageCount: 3,
        refineIsFree: true,
      }),
      buildQuotaUsageMetadata({
        requestType,
        recognizeOnly: false,
        accountIsTest: false,
        estimatedMessageCount: 3,
      }),
      requestType,
    );
  }
});

Deno.test("RPC 故障不得被記成拿到了免費授權", () => {
  // 三態必須分得開，否則 telemetry 上「白送」與「正常免費」長得一模一樣，
  // 額度函式壞掉多久都不會有人發現。
  assertEquals(
    refineQuotaOutcomeFor({ kind: "granted", used: 3, remaining: 7 }),
    { shouldCharge: false, granted: true, quotaReason: "refine_free_daily" },
  );
  assertEquals(
    refineQuotaOutcomeFor({ kind: "exhausted", used: 10, remaining: 0 }),
    {
      shouldCharge: true,
      granted: false,
      quotaReason: "refine_reply_fixed_1",
    },
  );
  assertEquals(
    refineQuotaOutcomeFor({ kind: "unavailable", message: "rpc down" }),
    {
      // 仍然不扣費——錢的方向不變，只有觀測分得開。
      shouldCharge: false,
      granted: null,
      quotaReason: "refine_free_allowance_unavailable",
    },
  );
});
