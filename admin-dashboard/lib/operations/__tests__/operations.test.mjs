// B0 聚焦測試。執行：cd admin-dashboard && node --test lib/operations/__tests__/operations.test.mjs
// 用 .mjs＋Node 22 內建 type stripping 直接載入 .ts 契約，不需安裝任何測試框架。
import { test } from "node:test";
import assert from "node:assert/strict";

import {
  OPS_TIMEZONE,
  taipeiDayKey,
  resolveFreshness,
  resolveHealth,
} from "../contracts.ts";
import {
  isAdminV2Enabled,
  shadowRead,
  structuralDiff,
} from "../admin-v2.ts";

const MINUTE = 60_000;

test("台灣日界：台北午夜（UTC 16:00）前後落在不同天", () => {
  assert.equal(OPS_TIMEZONE, "Asia/Taipei");
  assert.equal(taipeiDayKey(new Date("2026-08-30T15:59:59Z")), "2026-08-30");
  assert.equal(taipeiDayKey(new Date("2026-08-30T16:00:00Z")), "2026-08-31");
});

test("freshness：缺值與爛時間戳一律 unknown，逾期為 stale", () => {
  const now = new Date("2026-08-31T00:00:00Z");
  assert.equal(resolveFreshness(null, now, MINUTE), "unknown");
  assert.equal(resolveFreshness(undefined, now, MINUTE), "unknown");
  assert.equal(resolveFreshness("not-a-timestamp", now, MINUTE), "unknown");
  assert.equal(resolveFreshness("2026-08-30T23:59:30Z", now, MINUTE), "fresh");
  assert.equal(resolveFreshness("2026-08-30T23:58:00Z", now, MINUTE), "stale");
});

test("health：缺資料必為 unknown，不冒充 healthy 或 0", () => {
  const now = new Date("2026-08-31T00:00:00Z");
  for (const missing of [
    resolveHealth(null, now, MINUTE),
    resolveHealth(undefined, now, MINUTE),
    resolveHealth({ observedAt: null, isDegraded: false }, now, MINUTE),
    resolveHealth({ observedAt: "garbage", isDegraded: false }, now, MINUTE),
  ]) {
    assert.equal(missing, "unknown");
    assert.notEqual(missing, "healthy");
    assert.notEqual(missing, 0);
  }
  assert.equal(
    resolveHealth({ observedAt: "2026-08-30T23:59:30Z", isDegraded: false }, now, MINUTE),
    "healthy",
  );
  assert.equal(
    resolveHealth({ observedAt: "2026-08-30T23:59:30Z", isDegraded: true }, now, MINUTE),
    "degraded",
  );
  // stale 的壞消息仍是 degraded；stale 的好消息不得宣稱 healthy。
  assert.equal(
    resolveHealth({ observedAt: "2026-08-30T23:00:00Z", isDegraded: true }, now, MINUTE),
    "degraded",
  );
  assert.equal(
    resolveHealth({ observedAt: "2026-08-30T23:00:00Z", isDegraded: false }, now, MINUTE),
    "unknown",
  );
});

test("ADMIN_V2 預設關閉，只認 1/true", () => {
  assert.equal(isAdminV2Enabled({}), false);
  assert.equal(isAdminV2Enabled({ ADMIN_V2: "" }), false);
  assert.equal(isAdminV2Enabled({ ADMIN_V2: "0" }), false);
  assert.equal(isAdminV2Enabled({ ADMIN_V2: "false" }), false);
  assert.equal(isAdminV2Enabled({ ADMIN_V2: "1" }), true);
  assert.equal(isAdminV2Enabled({ ADMIN_V2: " TRUE " }), true);
});

test("旗標關閉：只跑 legacy、輸出原封不動、完全不碰新讀取", async () => {
  const legacyValue = { users: 3, note: "legacy" };
  let nextCalls = 0;
  const result = await shadowRead(
    () => legacyValue,
    () => {
      nextCalls += 1;
      return { users: 999 };
    },
    {},
  );
  assert.equal(result.value, legacyValue); // 同一個物件，不是複製或改寫
  assert.equal(result.shadow, null);
  assert.equal(nextCalls, 0);
});

test("旗標開啟：可見輸出仍是 legacy，差異只有路徑與型別、不含任何值", async () => {
  const legacyValue = {
    total: 5,
    contact: "alice@example.com",
    rows: [{ userId: "user-1234", score: 10 }],
  };
  const nextValue = {
    total: "5",
    rows: [{ userId: "user-9999", score: 10, extra: true }],
  };
  const result = await shadowRead(() => legacyValue, () => nextValue, { ADMIN_V2: "1" });
  assert.equal(result.value, legacyValue);
  assert.equal(result.shadow.equal, false);
  assert.deepEqual(result.shadow.mismatches.sort(), [
    "$.contact: string vs missing",
    "$.rows[].extra: missing vs boolean",
    "$.rows[].userId: value-mismatch",
    "$.total: number vs string",
  ]);
  const serialized = JSON.stringify(result.shadow);
  assert.ok(!serialized.includes("@"));
  assert.ok(!serialized.includes("alice"));
  assert.ok(!serialized.includes("user-1234"));
  assert.ok(!serialized.includes("user-9999"));
});

test("結構相同時 shadow 回報 equal，仍不影響輸出", async () => {
  const value = { a: 1, b: [1, 2] };
  const result = await shadowRead(() => value, () => ({ a: 1, b: [1, 2] }), { ADMIN_V2: "true" });
  assert.equal(result.value, value);
  assert.deepEqual(result.shadow, { equal: true, mismatches: [] });
});

test("新讀取丟例外不影響可見輸出，只留匿名錯誤標記", async () => {
  const legacyValue = { ok: true };
  const result = await shadowRead(
    () => legacyValue,
    () => {
      throw new Error("secret-detail should not leak");
    },
    { ADMIN_V2: "1" },
  );
  assert.equal(result.value, legacyValue);
  assert.deepEqual(result.shadow, { equal: false, mismatches: ["$: next-read-error"] });
  assert.ok(!JSON.stringify(result.shadow).includes("secret-detail"));
});

test("回滾＝關旗標：同一段程式立即停用 shadow", async () => {
  let nextCalls = 0;
  const nextRead = () => {
    nextCalls += 1;
    return {};
  };
  const on = await shadowRead(() => ({}), nextRead, { ADMIN_V2: "1" });
  assert.notEqual(on.shadow, null);
  assert.equal(nextCalls, 1);
  const off = await shadowRead(() => ({}), nextRead, { ADMIN_V2: "0" });
  assert.equal(off.shadow, null);
  assert.equal(nextCalls, 1);
});

test("structuralDiff 深度與數量有上限，不會被巨大 payload 拖垮", () => {
  const deep = (depth) => (depth === 0 ? "leaf" : { child: deep(depth - 1) });
  const diff = structuralDiff(deep(30), deep(30));
  assert.equal(diff.equal, true);
  const wideA = Object.fromEntries(Array.from({ length: 100 }, (_, i) => [`k${i}`, 1]));
  const wideB = Object.fromEntries(Array.from({ length: 100 }, (_, i) => [`k${i}`, 2]));
  const capped = structuralDiff(wideA, wideB);
  assert.equal(capped.mismatches.length, 20);
});
