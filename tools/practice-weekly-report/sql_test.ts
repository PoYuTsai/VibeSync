import {
  assertEquals,
  assertStringIncludes,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  assertRange,
  assertReadOnlySql,
  buildAiLogsSql,
  buildLogsSql,
  buildSessionsSql,
  dayWindows,
  defaultRange,
  logsEndpoint,
} from "./sql.ts";

const RANGE = { from: "2026-08-29", to: "2026-09-05" };

Deno.test("sessions SQL 只查 practice_chat_sessions 且綁時間窗", () => {
  const sql = buildSessionsSql(RANGE);
  assertStringIncludes(sql, "public.practice_chat_sessions");
  assertStringIncludes(sql, "'2026-08-29 00:00:00+00'");
  assertStringIncludes(sql, "'2026-09-05 00:00:00+00'");
  assertStringIncludes(sql, "GROUP BY practice_mode, ai_count");
  assertReadOnlySql(sql);
});

Deno.test("ai_logs SQL 只撈 practice_ 前綴且帶 retry_count", () => {
  const sql = buildAiLogsSql(RANGE);
  assertStringIncludes(sql, "public.ai_logs");
  assertStringIncludes(sql, "request_type LIKE 'practice\\_%'");
  assertStringIncludes(sql, "retry_count");
  assertReadOnlySql(sql);
});

Deno.test("非法日期不得進 SQL 字串", () => {
  assertThrows(
    () => buildSessionsSql({ from: "2026-08-29'; DROP TABLE x --", to: "x" }),
    Error,
    "invalid_date",
  );
});

Deno.test("assertReadOnlySql 擋掉所有寫入語句", () => {
  for (
    const sql of [
      "INSERT INTO ai_logs VALUES (1)",
      "update practice_chat_sessions set ai_count = 0",
      "DELETE FROM ai_logs",
      "drop table ai_logs",
      "ALTER TABLE ai_logs ADD COLUMN x int",
      "TRUNCATE ai_logs",
      "create view v as select 1",
      "GRANT ALL ON ai_logs TO anon",
    ]
  ) {
    assertThrows(() => assertReadOnlySql(sql), Error);
  }
});

Deno.test("assertReadOnlySql 擋掉開頭不是 SELECT 與多語句夾帶", () => {
  assertThrows(() => assertReadOnlySql("SELECT 1; SELECT 2"), Error);
  assertThrows(() => assertReadOnlySql("EXPLAIN ANALYZE SELECT 1"), Error);
  assertThrows(() => assertReadOnlySql("  "), Error);
});

Deno.test("assertReadOnlySql 不會把 created_at／updated_at 誤判成關鍵字", () => {
  const sql = "SELECT created_at, updated_at FROM public.ai_logs";
  assertEquals(assertReadOnlySql(sql), sql);
});

Deno.test("defaultRange 預設回推 7 天且 to 為當日", () => {
  assertEquals(defaultRange(new Date("2026-09-05T10:00:00Z")), {
    from: "2026-08-29",
    to: "2026-09-05",
  });
});

Deno.test("logs SQL 鎖 practice_chat_succeeded，且時間窗絕不寫進 SQL", () => {
  const sql = buildLogsSql(5000);
  assertStringIncludes(sql, "function_logs");
  assertStringIncludes(sql, "practice_chat_succeeded");
  assertStringIncludes(sql, "limit 5000");
  // 實跑證實：WHERE timestamp >= '…' 會讓結果變空，時間窗只能走 query string。
  assertEquals(sql.includes("timestamp >="), false);
  assertEquals(sql.includes("timestamp <"), false);
  assertReadOnlySql(sql);
});

Deno.test("logs SQL 的 limit 必須是正整數", () => {
  assertThrows(() => buildLogsSql(0), Error, "invalid_limit");
  assertThrows(() => buildLogsSql(1.5), Error, "invalid_limit");
});

Deno.test("dayWindows 一天一段，最後一段止於 --to", () => {
  assertEquals(dayWindows(RANGE).length, 7);
  assertEquals(dayWindows(RANGE)[0], {
    day: "2026-08-29",
    isoStart: "2026-08-29T00:00:00Z",
    isoEnd: "2026-08-30T00:00:00Z",
  });
  assertEquals(dayWindows(RANGE)[6], {
    day: "2026-09-04",
    isoStart: "2026-09-04T00:00:00Z",
    isoEnd: "2026-09-05T00:00:00Z",
  });
});

Deno.test("dayWindows 跨月正確", () => {
  assertEquals(
    dayWindows({ from: "2026-08-30", to: "2026-09-02" }).map((w) => w.day),
    ["2026-08-30", "2026-08-31", "2026-09-01"],
  );
  assertEquals(dayWindows({ from: "2026-09-05", to: "2026-09-06" }).length, 1);
});

Deno.test("logs 端點把 SQL 與 iso 時間窗都放進 query string", () => {
  const url = logsEndpoint("myref", "select 1 from t where a = 'b c'", {
    day: "2026-08-29",
    isoStart: "2026-08-29T00:00:00Z",
    isoEnd: "2026-08-30T00:00:00Z",
  });
  assertStringIncludes(
    url,
    "https://api.supabase.com/v1/projects/myref/analytics/endpoints/logs.all?sql=",
  );
  assertStringIncludes(url, "iso_timestamp_start=2026-08-29T00%3A00%3A00Z");
  assertStringIncludes(url, "iso_timestamp_end=2026-08-30T00%3A00%3A00Z");
  assertEquals(url.includes(" "), false);
});

Deno.test("守門擋掉「一條 SELECT 也能有副作用」的那一類（Codex R1 P1）", () => {
  for (
    const sql of [
      "SELECT * INTO evil FROM ai_logs",
      "SELECT nextval('seq')",
      "SELECT setval('seq', 1)",
      "SELECT currval('seq')",
      "SELECT set_config('role', 'postgres', false)",
      "SELECT pg_advisory_lock(1)",
      "SELECT pg_advisory_xact_lock(1)",
      "SELECT pg_advisory_unlock_all()",
      "SELECT pg_sleep(60)",
      "SELECT pg_sleep_for('5 minutes')",
      "SELECT pg_terminate_backend(1)",
      "SELECT pg_cancel_backend(1)",
      "SELECT lo_import('/etc/passwd')",
      "SELECT lo_from_bytea(0, 'x')",
      "SELECT dblink('...', 'delete from ai_logs')",
      "SELECT dblink_exec('...', 'drop table ai_logs')",
    ]
  ) {
    assertThrows(() => assertReadOnlySql(sql), Error, "read_only_guard", sql);
  }
});

Deno.test("守門不誤殺正常欄位名", () => {
  for (
    const sql of [
      "SELECT created_at, updated_at, inserted_by FROM public.ai_logs",
      "SELECT settings, dropped_count, intoxication FROM t",
      "SELECT logo_url, copy_me FROM t",
    ]
  ) {
    assertEquals(assertReadOnlySql(sql), sql);
  }
});

Deno.test("日期要是真實曆日，形狀對但不存在的日子照樣擋", () => {
  for (const bad of ["2026-02-31", "2026-13-01", "2026-00-10", "2026-04-31"]) {
    assertThrows(
      () => assertRange({ from: bad, to: "2026-09-05" }),
      Error,
      "invalid_date",
    );
  }
  assertEquals(
    assertRange({ from: "2028-02-29", to: "2028-03-01" }).from,
    "2028-02-29",
  );
});

Deno.test("--from 必須早於 --to；相等或顛倒都報錯（不產零資料報告）", () => {
  assertThrows(
    () => assertRange({ from: "2026-09-05", to: "2026-09-05" }),
    Error,
    "invalid_range",
  );
  assertThrows(
    () => assertRange({ from: "2026-09-06", to: "2026-09-05" }),
    Error,
    "invalid_range",
  );
});

Deno.test("守門擋掉逸出寫法：關鍵字拆形狀繞不過去", () => {
  for (
    const sql of [
      "SELECT pg_catalog.U&\"nextv\\0061l\"('seq')",
      'SELECT U&"drop" FROM t',
      "SELECT E'\\x41' FROM t",
      "SELECT e'\\ndelete' FROM t",
    ]
  ) {
    assertThrows(() => assertReadOnlySql(sql), Error, "read_only_guard", sql);
  }
  // 正常的欄位名／別名不受影響。
  assertEquals(
    assertReadOnlySql("SELECT value, price FROM t"),
    "SELECT value, price FROM t",
  );
});
