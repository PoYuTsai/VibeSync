// 每週 cohort 報表的 markdown（Onboarding 第 8 步）。純函式：不打網路、不讀檔。
//
// 每格先看時間窗走完沒有：這週最晚註冊的人還沒滿 24 小時／7 天／30 天，就印
// 「未滿」而不是數字（數字還會變）。第一次分析、開場來自 ai_logs，只留 30 天，
// 這週最早註冊那幾天的紀錄可能已經刪掉，就印「紀錄已清」。

import type { CohortWeek } from "./sql.ts";

/** SQL 回傳的欄位，順序就是報表的欄位順序。 */
export const COHORT_COLUMNS = [
  "new_accounts",
  "analysis_24h",
  "opener_24h",
  "practice_24h",
  "quota_block_7d",
  "quota_paywall_7d",
  "paid_d7",
  "paid_d30",
  "refunded",
] as const;

export type CohortColumn = typeof COHORT_COLUMNS[number];
export type CohortRow = Record<CohortColumn, number>;

export interface CohortResult {
  readonly week: CohortWeek;
  readonly row: CohortRow;
}

const HEADERS: Record<CohortColumn, string> = {
  new_accounts: "新帳號",
  analysis_24h: "24h 分析",
  opener_24h: "24h 開場",
  practice_24h: "24h 練習",
  quota_block_7d: "7 天撞額度",
  quota_paywall_7d: "7 天額度付費頁",
  paid_d7: "D7 付費",
  paid_d30: "D30 付費",
  refunded: "退款（至今）",
};

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

/** ai_logs 只留 30 天（20260902160000_retention_cleanup_schedules.sql）。 */
export const AI_LOGS_RETENTION_DAYS = 30;

export const PURGED = "（紀錄已清）";

interface CellRule {
  /** 從每個人註冊起算的時間窗。 */
  readonly windowMs: number;
  readonly pending: string;
  /** 這欄來自 ai_logs，會被 30 天清理吃掉。 */
  readonly aiLogs?: boolean;
}

const RULES: Record<CohortColumn, CellRule | null> = {
  new_accounts: null,
  analysis_24h: { windowMs: DAY_MS, pending: "（未滿 24 小時）", aiLogs: true },
  opener_24h: { windowMs: DAY_MS, pending: "（未滿 24 小時）", aiLogs: true },
  practice_24h: { windowMs: DAY_MS, pending: "（未滿 24 小時）" },
  quota_block_7d: { windowMs: 7 * DAY_MS, pending: "（未滿 7 天）" },
  quota_paywall_7d: { windowMs: 7 * DAY_MS, pending: "（未滿 7 天）" },
  paid_d7: { windowMs: 7 * DAY_MS, pending: "（未滿 7 天）" },
  paid_d30: { windowMs: 30 * DAY_MS, pending: "（未滿 30 天）" },
  // 退款不綁時間窗：查詢當下為止的人數。
  refunded: null,
};

/**
 * Management API 回的那一列 → 九個人數。int8 可能回成數字也可能回成字串，
 * 兩種都收；缺欄位、負數、小數或其他形狀一律報錯，不要把壞資料印成 0。
 */
export function parseCohortRow(raw: unknown): CohortRow {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    throw new Error(`unexpected_row: ${JSON.stringify(raw)}`);
  }
  const record = raw as Record<string, unknown>;
  const row = {} as CohortRow;
  for (const column of COHORT_COLUMNS) {
    const value = record[column];
    const count = typeof value === "number"
      ? value
      : typeof value === "string" && /^\d+$/.test(value)
      ? Number(value)
      : Number.NaN;
    if (!Number.isSafeInteger(count) || count < 0) {
      throw new Error(`unexpected_row: ${column}=${JSON.stringify(value)}`);
    }
    row[column] = count;
  }
  return row;
}

/** 一格要印數字、「未滿」還是「紀錄已清」。 */
export function cellText(
  column: CohortColumn,
  week: CohortWeek,
  count: number,
  asOf: Date,
): string {
  const rule = RULES[column];
  if (!rule) return String(count);
  const start = Date.parse(`${week.start}T00:00:00Z`);
  const end = Date.parse(`${week.end}T00:00:00Z`);
  if (asOf.getTime() < end + rule.windowMs) return rule.pending;
  if (
    rule.aiLogs &&
    asOf.getTime() > start + AI_LOGS_RETENTION_DAYS * DAY_MS
  ) {
    return PURGED;
  }
  return String(count);
}

function minuteText(ms: number): string {
  return new Date(ms).toISOString().slice(0, 16).replace("T", " ");
}

function weekText(week: CohortWeek): string {
  const lastDay = new Date(Date.parse(`${week.end}T00:00:00Z`) - DAY_MS)
    .toISOString().slice(5, 10);
  return `${week.label}（${week.start.slice(5)}～${lastDay}）`;
}

export function renderReport(input: {
  asOf: Date;
  results: readonly CohortResult[];
}): string {
  const latest = input.results.at(-1);
  if (!latest) throw new Error("no_weeks: 至少要一週");
  const asOfMs = input.asOf.getTime();
  return [
    `# 每週 cohort 報表 ${latest.week.label}`,
    "",
    `查詢時間：${minuteText(asOfMs)} UTC（台北 ${
      minuteText(asOfMs + 8 * HOUR_MS)
    }）。註冊週以 UTC 週一 00:00 起算（台北週一早上 8 點）。欄位定義、讀法與上線初期不要解讀的數字見 \`docs/integrations/weekly-cohort-report.md\`。`,
    "",
    `| 註冊週 | ${
      COHORT_COLUMNS.map((column) => HEADERS[column]).join(" | ")
    } |`,
    `| --- | ${COHORT_COLUMNS.map(() => "---:").join(" | ")} |`,
    ...input.results.map(({ week, row }) =>
      `| ${weekText(week)} | ${
        COHORT_COLUMNS.map((column) =>
          cellText(column, week, row[column], input.asOf)
        ).join(" | ")
      } |`
    ),
    "",
    "- 都是人數，每個人最多算一次；時間窗從每個人自己的註冊時間起算。",
    "- 「（未滿 24 小時）」「（未滿 7 天）」「（未滿 30 天）」：這週最晚註冊的人還沒走完那個時間窗，數字還會變，看之後的週報。",
    `- 「${PURGED}」：ai_logs 只留 ${AI_LOGS_RETENTION_DAYS} 天，這週最早註冊那幾天的紀錄可能已經刪掉，數字會偏低；看這週剛出爐那幾份週報。`,
    "- 「7 天撞額度」要步驟 6（quota_block_shown）上線後才有值，之前看「7 天額度付費頁」當下限；「退款」要步驟 7 上線後才有值。上線以前的 0 不代表沒發生。",
    "- 上線前多半是 0 或個位數：只看趨勢，不比小數點。",
    "",
  ].join("\n");
}
