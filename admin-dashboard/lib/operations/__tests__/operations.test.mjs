// B0 聚焦測試。執行：cd admin-dashboard && node --test lib/operations/__tests__/operations.test.mjs
// 用 .mjs＋Node 22 內建 type stripping 直接載入 .ts 契約，不需安裝任何測試框架。
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

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
    // 未型檢呼叫端漏傳 isDegraded：undefined 是 falsy，不得因此冒充 healthy。
    resolveHealth({ observedAt: "2026-08-30T23:59:30Z" }, now, MINUTE),
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

test("旗標開啟：可見輸出仍是 legacy，差異只有匿名路徑與型別、不含值也不含 key", async () => {
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
    "$.{}: number vs string",
    "$.{}: string vs missing",
    "$.{}[].{}: missing vs boolean",
    "$.{}[].{}: value-mismatch",
  ]);
  const serialized = JSON.stringify(result.shadow);
  assert.ok(!serialized.includes("@"));
  assert.ok(!serialized.includes("alice"));
  assert.ok(!serialized.includes("user-1234"));
  assert.ok(!serialized.includes("user-9999"));
  // 動態 key（可能是 email/user id）不得出現在差異報告。
  for (const key of ["total", "contact", "rows", "userId", "score", "extra"]) {
    assert.ok(!serialized.includes(key), `key 洩漏: ${key}`);
  }
});

test("陣列長度不同：只記 array-length-mismatch，不洩漏實際長度", () => {
  const diff = structuralDiff({ items: [1, 2, 3] }, { items: [1] });
  assert.equal(diff.equal, false);
  assert.deepEqual(diff.mismatches, ["$.{}: array-length-mismatch"]);
  assert.ok(!/\d/.test(JSON.stringify(diff.mismatches)));
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

test("structuralDiff 截斷（深度／節點預算／上限）絕不宣稱 equal", () => {
  // 超過深度上限：沒看完就不能說相同。
  const deep = (depth) => (depth === 0 ? "leaf" : { child: deep(depth - 1) });
  const deepDiff = structuralDiff(deep(30), deep(30));
  assert.equal(deepDiff.equal, false);
  assert.deepEqual(deepDiff.mismatches, ["$: diff-truncated"]);
  // 超過節點預算：即使目前為止全相同也一樣。
  const wide = (n, v) => ({ rows: Array.from({ length: n }, () => ({ v })) });
  const nodeDiff = structuralDiff(wide(3000, 1), wide(3000, 1));
  assert.equal(nodeDiff.equal, false);
  assert.deepEqual(nodeDiff.mismatches, ["$: diff-truncated"]);
  // mismatch 數量上限：最多 20 筆，不被巨大差異拖垮。
  const wideA = Object.fromEntries(Array.from({ length: 100 }, (_, i) => [`k${i}`, 1]));
  const wideB = Object.fromEntries(Array.from({ length: 100 }, (_, i) => [`k${i}`, 2]));
  const capped = structuralDiff(wideA, wideB);
  assert.equal(capped.equal, false);
  assert.equal(capped.mismatches.length, 20);
});

test("超寬物件：節點預算真正限制工作量，不整包展開 key，也不洩漏 key", () => {
  // 兩側各 10 萬個 key，用 getter 計數實際被讀到的欄位值；
  // 預算生效時只會讀到節點上限（2000）附近，遠小於全寬。
  const makeWide = (n, counter) => {
    const obj = {};
    for (let i = 0; i < n; i += 1) {
      Object.defineProperty(obj, `secretKey${i}`, {
        enumerable: true,
        get() {
          counter.reads += 1;
          return 1;
        },
      });
    }
    return obj;
  };
  const countA = { reads: 0 };
  const countB = { reads: 0 };
  const diff = structuralDiff(makeWide(100_000, countA), makeWide(100_000, countB));
  assert.equal(diff.equal, false);
  assert.deepEqual(diff.mismatches, ["$: diff-truncated"]);
  assert.ok(countA.reads < 3_000, `A 讀了 ${countA.reads} 個欄位，預算沒擋住`);
  assert.ok(countB.reads < 3_000, `B 讀了 ${countB.reads} 個欄位，預算沒擋住`);
  assert.ok(!JSON.stringify(diff).includes("secretKey"));
});

test("nextReadTimeoutMs 超過 2000ms 會被 clamp，壞值退回預設", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const never = () => new Promise(() => {});
  const pending = [
    shadowRead(() => "legacy", never, { ADMIN_V2: "1" }, { nextReadTimeoutMs: 999_999 }),
    shadowRead(() => "legacy", never, { ADMIN_V2: "1" }, { nextReadTimeoutMs: Number.NaN }),
    shadowRead(() => "legacy", never, { ADMIN_V2: "1" }, { nextReadTimeoutMs: -1 }),
    shadowRead(() => "legacy", never, { ADMIN_V2: "1" }, { nextReadTimeoutMs: Number.POSITIVE_INFINITY }),
  ];
  // 讓每個 shadowRead 都跑到掛 timer（setImmediate 沒被 mock，可用來排空 microtask）。
  await new Promise((resolve) => setImmediate(resolve));
  // 若 999_999 沒被 clamp、或壞值沒退回預設，2000ms 時 timer 不會全數觸發，await 會卡住。
  t.mock.timers.tick(2000);
  for (const result of await Promise.all(pending)) {
    assert.equal(result.value, "legacy");
    assert.deepEqual(result.shadow, { equal: false, mismatches: ["$: next-read-timeout"] });
  }
});

test("migration 靜態守則：不得條件式建立/取代，先 revoke all 再最小 grant", () => {
  const raw = readFileSync(
    new URL(
      "../../../../supabase/migrations/20260831120000_admin_ops_v2_baseline.sql",
      import.meta.url,
    ),
    "utf8",
  );
  // 只檢查可執行 SQL，去掉 -- 註解行避免對註解字面誤判。
  const sql = raw
    .split("\n")
    .map((line) => line.replace(/--.*$/u, ""))
    .join("\n");
  assert.ok(!/IF\s+NOT\s+EXISTS/iu.test(sql), "不得使用 IF NOT EXISTS");
  assert.ok(!/OR\s+REPLACE/iu.test(sql), "不得使用 OR REPLACE");
  const objects = [
    "public.admin_ops_source_checkpoints",
    "public.admin_ops_incidents",
    "public.admin_ops_decision_cards",
    "public.admin_ops_source_freshness",
  ];
  for (const obj of objects) {
    const escaped = obj.replace(".", "\\.");
    const revokeAt = sql.search(
      new RegExp(
        String.raw`REVOKE ALL PRIVILEGES ON TABLE ${escaped}\s+FROM PUBLIC, anon, authenticated, service_role;`,
        "u",
      ),
    );
    const grantAt = sql.search(
      new RegExp(String.raw`GRANT [^;]*ON TABLE ${escaped}\s+TO service_role;`, "u"),
    );
    assert.ok(revokeAt >= 0, `缺 revoke all（含 service_role）: ${obj}`);
    assert.ok(grantAt > revokeAt, `grant 必須在 revoke all 之後: ${obj}`);
  }
  // table 僅 SELECT, INSERT, UPDATE；view 僅 SELECT；任何 GRANT 不得帶 DELETE/TRUNCATE。
  for (const table of objects.slice(0, 3)) {
    assert.match(
      sql,
      new RegExp(
        String.raw`GRANT SELECT, INSERT, UPDATE ON TABLE ${table.replace(".", "\\.")}\s+TO service_role;`,
        "u",
      ),
    );
  }
  assert.match(sql, /GRANT SELECT ON TABLE public\.admin_ops_source_freshness TO service_role;/u);
  assert.ok(!/GRANT[^;]*\b(DELETE|TRUNCATE)\b/iu.test(sql), "GRANT 不得含 DELETE/TRUNCATE");
});

test("nextRead 超時：可見輸出仍是 legacy，遲到的失敗也不會爆", async () => {
  const legacyValue = { ok: true };
  let rejectLater;
  const result = await shadowRead(
    () => legacyValue,
    () => new Promise((_, reject) => {
      rejectLater = reject;
    }),
    { ADMIN_V2: "1" },
    { nextReadTimeoutMs: 5 },
  );
  assert.equal(result.value, legacyValue);
  assert.deepEqual(result.shadow, { equal: false, mismatches: ["$: next-read-timeout"] });
  // 超時之後才 reject：不得變成 unhandled rejection。
  rejectLater(new Error("late failure"));
  await new Promise((resolve) => setTimeout(resolve, 20));
});
