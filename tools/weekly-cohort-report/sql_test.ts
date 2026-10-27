import {
  assertEquals,
  assertStringIncludes,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { assertReadOnlySql } from "../practice-weekly-report/sql.ts";
import {
  buildCohortSql,
  COHORT_SQL_TEMPLATE,
  isoWeekOf,
  lastCompleteWeek,
  parseIsoWeek,
  weeksEndingAt,
} from "./sql.ts";

const DOC_URL = new URL(
  "../../docs/integrations/weekly-cohort-report.md",
  import.meta.url,
);

Deno.test("範本跟文件「SQL 範本」那一段一字不差", async () => {
  const doc = await Deno.readTextFile(DOC_URL);
  const section = doc.indexOf("\n## SQL 範本\n");
  assertEquals(section >= 0, true, "文件少了「## SQL 範本」");
  const open = doc.indexOf("```sql\n", section);
  const close = doc.indexOf("\n```", open + 1);
  assertEquals(doc.slice(open + "```sql\n".length, close), COHORT_SQL_TEMPLATE);
});

Deno.test("代入週起訖：UTC 00:00、含頭不含尾，佔位字一個不剩", () => {
  const sql = buildCohortSql(parseIsoWeek("2026-W43"));
  assertStringIncludes(
    sql,
    "u.created_at >= '2026-10-19 00:00:00+00'::timestamptz",
  );
  assertStringIncludes(
    sql,
    "u.created_at < '2026-10-26 00:00:00+00'::timestamptz",
  );
  assertEquals(sql.includes(":week_"), false);
});

Deno.test("整條包成 SELECT 開頭，過練習室週報的唯讀守門，沒有分號", () => {
  const sql = buildCohortSql(parseIsoWeek("2026-W43"));
  assertEquals(sql.startsWith("SELECT * FROM (\nwith cohort as ("), true);
  assertEquals(sql.endsWith("\n) AS weekly_cohort"), true);
  assertEquals(sql.includes(";"), false);
  assertEquals(assertReadOnlySql(sql), sql);
});

Deno.test("包進子查詢不會開洞：裡面藏寫入的 CTE 照樣被擋", () => {
  for (
    const inner of [
      "with x as (delete from public.ai_logs returning *) select * from x",
      "with x as (insert into public.users (id) values (null) returning *) select * from x",
      "with x as (update public.users set email = '' returning *) select * from x",
    ]
  ) {
    assertThrows(
      () => assertReadOnlySql(`SELECT * FROM (\n${inner}\n) AS weekly_cohort`),
      Error,
      "read_only_guard",
      inner,
    );
  }
});

Deno.test("週起訖要是真實曆日而且起日早於迄日", () => {
  assertThrows(
    () =>
      buildCohortSql({ label: "x", start: "2026-02-31", end: "2026-03-07" }),
    Error,
    "invalid_date",
  );
  assertThrows(
    () =>
      buildCohortSql({ label: "x", start: "2026-10-26", end: "2026-10-19" }),
    Error,
    "invalid_range",
  );
});

Deno.test("排除測試帳號：vibesync.test@gmail.com 與 test_users 名單都排除", () => {
  assertStringIncludes(
    COHORT_SQL_TEMPLATE,
    "coalesce(au.email, '') <> 'vibesync.test@gmail.com'",
  );
  assertStringIncludes(
    COHORT_SQL_TEMPLATE,
    "not exists (select 1 from public.test_users t where t.user_id = u.id)",
  );
});

Deno.test("開場同時算兩段式第二段與舊版單段，不算兩段式第一段", () => {
  assertStringIncludes(
    COHORT_SQL_TEMPLATE,
    "l.request_type in ('opener_generate', 'opener')",
  );
  assertEquals(COHORT_SQL_TEMPLATE.includes("opener_analyze"), false);
});

Deno.test("isoWeekOf：週一開始、以 UTC 計，跨年照 ISO 規則", () => {
  assertEquals(isoWeekOf(new Date("2026-10-27T05:00:00Z")), {
    label: "2026-W44",
    start: "2026-10-26",
    end: "2026-11-02",
  });
  // 週日 23:59 UTC 還在同一週；台北已經是週一早上，但週界以 UTC 為準。
  assertEquals(isoWeekOf(new Date("2026-10-25T23:59:59Z")).label, "2026-W43");
  // 2026 年 1 月 1 日是週四，所以 2026 有第 53 週，一路到 2027-01-03。
  assertEquals(isoWeekOf(new Date("2026-12-31T00:00:00Z")).label, "2026-W53");
  assertEquals(isoWeekOf(new Date("2027-01-03T12:00:00Z")).label, "2026-W53");
  assertEquals(isoWeekOf(new Date("2027-01-04T00:00:00Z")).label, "2027-W01");
  // 2021-01-01 是週五，算前一年的最後一週。
  assertEquals(isoWeekOf(new Date("2021-01-01T00:00:00Z")).label, "2020-W53");
});

Deno.test("parseIsoWeek：只收存在的週", () => {
  assertEquals(parseIsoWeek("2026-W53"), {
    label: "2026-W53",
    start: "2026-12-28",
    end: "2027-01-04",
  });
  assertEquals(parseIsoWeek("2027-W01").start, "2027-01-04");
  for (
    const bad of ["2027-W53", "2026-W00", "2026-W54", "2026-W5", "2026W43", ""]
  ) {
    assertThrows(() => parseIsoWeek(bad), Error, "invalid_week", bad);
  }
});

Deno.test("lastCompleteWeek：今天所在那週的前一週", () => {
  assertEquals(
    lastCompleteWeek(new Date("2026-10-27T05:00:00Z")).label,
    "2026-W43",
  );
  // 週一 00:00 UTC 一到，上一週就算完整。
  assertEquals(
    lastCompleteWeek(new Date("2026-10-26T00:00:00Z")).label,
    "2026-W43",
  );
  assertEquals(
    lastCompleteWeek(new Date("2026-10-25T23:59:59Z")).label,
    "2026-W42",
  );
});

Deno.test("weeksEndingAt：由舊到新、跨年不跳週", () => {
  assertEquals(
    weeksEndingAt(parseIsoWeek("2027-W02"), 4).map((week) => week.label),
    ["2026-W52", "2026-W53", "2027-W01", "2027-W02"],
  );
  assertEquals(
    weeksEndingAt(parseIsoWeek("2026-W43"), 1).map((week) => week.label),
    ["2026-W43"],
  );
});
