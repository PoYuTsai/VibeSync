import {
  assertEquals,
  assertStringIncludes,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  cellText,
  COHORT_COLUMNS,
  type CohortRow,
  parseCohortRow,
  PURGED,
  renderReport,
} from "./render.ts";
import { parseIsoWeek } from "./sql.ts";

const W43 = parseIsoWeek("2026-W43"); // 2026-10-19 ～ 2026-10-26（不含）

const ROW: CohortRow = {
  new_accounts: 12,
  analysis_24h: 5,
  opener_24h: 3,
  practice_24h: 4,
  quota_block_7d: 2,
  quota_paywall_7d: 1,
  paid_d7: 1,
  paid_d30: 2,
  refunded: 1,
};

Deno.test("parseCohortRow：數字與純數字字串都收（int8 可能回成字串）", () => {
  assertEquals(parseCohortRow(ROW), ROW);
  const asStrings = Object.fromEntries(
    COHORT_COLUMNS.map((column) => [column, String(ROW[column])]),
  );
  assertEquals(parseCohortRow(asStrings), ROW);
});

Deno.test("parseCohortRow：缺欄位、負數、小數、怪字串、不是物件一律報錯", () => {
  const broken: unknown[] = [
    { ...ROW, refunded: undefined },
    { ...ROW, paid_d7: -1 },
    { ...ROW, paid_d7: 1.5 },
    { ...ROW, paid_d7: "1e3" },
    { ...ROW, paid_d7: "" },
    { ...ROW, paid_d7: null },
    null,
    [ROW],
    "12",
  ];
  for (const raw of broken) {
    assertThrows(
      () => parseCohortRow(raw),
      Error,
      "unexpected_row",
      JSON.stringify(raw),
    );
  }
});

Deno.test("24 小時欄：這週最晚註冊的人滿 24 小時才印數字", () => {
  const before = new Date("2026-10-26T23:59:59Z");
  const exactly = new Date("2026-10-27T00:00:00Z");
  for (
    const column of ["analysis_24h", "opener_24h", "practice_24h"] as const
  ) {
    assertEquals(cellText(column, W43, 5, before), "（未滿 24 小時）", column);
    assertEquals(cellText(column, W43, 5, exactly), "5", column);
  }
});

Deno.test("7 天欄與 D7：滿 7 天才印；D30 滿 30 天才印", () => {
  for (
    const column of ["quota_block_7d", "quota_paywall_7d", "paid_d7"] as const
  ) {
    assertEquals(
      cellText(column, W43, 2, new Date("2026-11-01T23:00:00Z")),
      "（未滿 7 天）",
      column,
    );
    assertEquals(
      cellText(column, W43, 2, new Date("2026-11-02T00:00:00Z")),
      "2",
      column,
    );
  }
  assertEquals(
    cellText("paid_d30", W43, 2, new Date("2026-11-24T23:00:00Z")),
    "（未滿 30 天）",
  );
  assertEquals(
    cellText("paid_d30", W43, 2, new Date("2026-11-25T00:00:00Z")),
    "2",
  );
});

Deno.test("ai_logs 欄：週一起算超過 30 天印「紀錄已清」，練習與付費不受影響", () => {
  const lastSafe = new Date("2026-11-18T00:00:00Z"); // 週一 + 30 天
  const purged = new Date("2026-11-18T00:00:01Z");
  assertEquals(cellText("analysis_24h", W43, 5, lastSafe), "5");
  assertEquals(cellText("analysis_24h", W43, 5, purged), PURGED);
  assertEquals(cellText("opener_24h", W43, 3, purged), PURGED);
  assertEquals(cellText("practice_24h", W43, 4, purged), "4");
  assertEquals(cellText("quota_block_7d", W43, 2, purged), "2");
});

Deno.test("新帳號與退款不綁時間窗，永遠印數字", () => {
  const justAfter = new Date("2026-10-26T00:00:01Z");
  assertEquals(cellText("new_accounts", W43, 12, justAfter), "12");
  assertEquals(cellText("refunded", W43, 1, justAfter), "1");
  assertEquals(
    cellText("refunded", W43, 1, new Date("2027-06-01T00:00:00Z")),
    "1",
  );
});

Deno.test("renderReport：標題是最新那週，週由舊到新、每格照成熟度印", () => {
  const w38 = parseIsoWeek("2026-W38");
  const markdown = renderReport({
    asOf: new Date("2026-10-27T04:10:00Z"),
    results: [
      { week: w38, row: { ...ROW, new_accounts: 7 } },
      { week: W43, row: ROW },
    ],
  });
  const lines = markdown.split("\n");
  assertEquals(lines[0], "# 每週 cohort 報表 2026-W43");
  assertStringIncludes(
    markdown,
    "查詢時間：2026-10-27 04:10 UTC（台北 2026-10-27 12:10）",
  );
  assertStringIncludes(
    markdown,
    "| 註冊週 | 新帳號 | 24h 分析 | 24h 開場 | 24h 練習 | 7 天撞額度 | 7 天額度付費頁 | D7 付費 | D30 付費 | 退款（至今） |",
  );
  // W38（09-14～09-20）：ai_logs 已過 30 天，D30 也走完了。
  assertStringIncludes(
    markdown,
    `| 2026-W38（09-14～09-20） | 7 | ${PURGED} | ${PURGED} | 4 | 2 | 1 | 1 | 2 | 1 |`,
  );
  // W43（10-19～10-25）：週報隔天跑，24 小時欄有數字，7 天與 30 天還沒走完。
  assertStringIncludes(
    markdown,
    "| 2026-W43（10-19～10-25） | 12 | 5 | 3 | 4 | （未滿 7 天） | （未滿 7 天） | （未滿 7 天） | （未滿 30 天） | 1 |",
  );
  assertEquals(
    lines.findIndex((line) => line.startsWith("| 2026-W38")) <
      lines.findIndex((line) => line.startsWith("| 2026-W43")),
    true,
  );
  assertStringIncludes(markdown, "docs/integrations/weekly-cohort-report.md");
});

Deno.test("renderReport：沒有任何一週就報錯", () => {
  assertThrows(
    () => renderReport({ asOf: new Date(), results: [] }),
    Error,
    "no_weeks",
  );
});
