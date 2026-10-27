// 每週 cohort 報表的 SQL 產生器（Onboarding 第 8 步）。
//
// 這支只組字串、不打網路。`COHORT_SQL_TEMPLATE` 跟
// docs/integrations/weekly-cohort-report.md「SQL 範本」那一段一字不差
// （sql_test.ts 會比對），唯一的變數是 `:week_start`／`:week_end`，換成先驗過的
// UTC 日期。
//
// 唯讀守門直接沿用練習室週報的 `assertReadOnlySql`（定位一樣：防手誤的護欄，
// 不是安全邊界）。它只放行 SELECT 開頭的單一語句，而範本是 WITH 開頭的 CTE，
// 所以整條包進 `SELECT * FROM (…) AS weekly_cohort` 再交給它；分號、逸出寫法、
// 寫入關鍵字的規則一條不少。

import {
  assertRange,
  assertReadOnlySql,
} from "../practice-weekly-report/sql.ts";

/**
 * 一週新帳號一列：24 小時內有沒有第一次分析／開場／練習、7 天內有沒有撞額度、
 * 付費、退款。欄位定義與讀法見 docs/integrations/weekly-cohort-report.md。
 */
export const COHORT_SQL_TEMPLATE =
  `with cohort as (               -- 這週註冊的新帳號，排除測試帳號
  select u.id as user_id, u.created_at
  from public.users u
  join auth.users au on au.id = u.id
  where u.created_at >= :week_start
    and u.created_at < :week_end
    and coalesce(au.email, '') <> 'vibesync.test@gmail.com'
    and not exists (select 1 from public.test_users t where t.user_id = u.id)
),
first_analysis as (            -- 新版分析每階段一列，取最早成功的那筆
  select l.user_id, min(l.created_at) as at
  from public.ai_logs l join cohort c on c.user_id = l.user_id
  where l.status = 'success'
    and l.request_type in ('analyze', 'analyze_with_images', 'my_message')
  group by l.user_id
),
first_opener as (              -- 兩段式的第二段，加上舊版單段（舊 App 與伺服器旗標關閉時）
  select l.user_id, min(l.created_at) as at
  from public.ai_logs l join cohort c on c.user_id = l.user_id
  where l.status = 'success'
    and l.request_type in ('opener_generate', 'opener')
  group by l.user_id
),
first_practice as (            -- 一般練習對話不寫 ai_logs，改看伺服器帳本
  select s.user_id, min(s.created_at) as at
  from public.practice_chat_sessions s join cohort c on c.user_id = s.user_id
  where s.ai_count > 0
  group by s.user_id
),
quota_block as (               -- 步驟 6 之後才有
  select f.user_id, min(f.created_at) as at
  from public.funnel_events f join cohort c on c.user_id = f.user_id
  where f.event = 'quota_block_shown'
  group by f.user_id
),
quota_paywall as (             -- 額度不夠打開付費頁：步驟 6 上線前的下限
  select f.user_id, min(f.created_at) as at
  from public.funnel_events f join cohort c on c.user_id = f.user_id
  where f.event = 'paywall_opened'
    and f.properties ->> 'entry' = 'quota_exhausted'
  group by f.user_id
),
first_purchase as (
  select r.user_id, min(r.event_timestamp) as at
  from public.revenue_events r join cohort c on c.user_id = r.user_id
  where r.event_type = 'INITIAL_PURCHASE'
    and r.raw_payload ->> 'environment' = 'PRODUCTION'
  group by r.user_id
),
refunded as (                  -- 步驟 7 之後才有
  select distinct r.user_id
  from public.revenue_events r join cohort c on c.user_id = r.user_id
  where r.event_type = 'CANCELLATION'
    and r.raw_payload ->> 'environment' = 'PRODUCTION'
    and r.raw_payload ->> 'cancel_reason' = 'CUSTOMER_SUPPORT'
)
select
  count(*)                                                              as new_accounts,
  count(*) filter (where fa.at < c.created_at + interval '24 hours')   as analysis_24h,
  count(*) filter (where fo.at < c.created_at + interval '24 hours')   as opener_24h,
  count(*) filter (where fp.at < c.created_at + interval '24 hours')   as practice_24h,
  count(*) filter (where qb.at < c.created_at + interval '7 days')     as quota_block_7d,
  count(*) filter (where qp.at < c.created_at + interval '7 days')     as quota_paywall_7d,
  count(*) filter (where pu.at < c.created_at + interval '7 days')     as paid_d7,
  count(*) filter (where pu.at < c.created_at + interval '30 days')    as paid_d30,
  count(rf.user_id)                                                     as refunded
from cohort c
left join first_analysis fa on fa.user_id = c.user_id
left join first_opener   fo on fo.user_id = c.user_id
left join first_practice fp on fp.user_id = c.user_id
left join quota_block    qb on qb.user_id = c.user_id
left join quota_paywall  qp on qp.user_id = c.user_id
left join first_purchase pu on pu.user_id = c.user_id
left join refunded       rf on rf.user_id = c.user_id`;

/** 一個註冊週：ISO 週，週一 00:00 UTC 起算（台北是週一早上 8 點）。 */
export interface CohortWeek {
  /** 例如 `2026-W43`。 */
  readonly label: string;
  /** 週一（含），`YYYY-MM-DD`。 */
  readonly start: string;
  /** 下週一（不含），`YYYY-MM-DD`。 */
  readonly end: string;
}

const DAY_MS = 24 * 60 * 60 * 1000;
const WEEK_MS = 7 * DAY_MS;
const ISO_WEEK = /^(\d{4})-W(\d{2})$/;

function utcMidnight(date: Date): number {
  return Date.UTC(
    date.getUTCFullYear(),
    date.getUTCMonth(),
    date.getUTCDate(),
  );
}

function toIsoDate(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

/** 那一週的週一（週一＝0、週日＝6）。 */
function mondayOf(dayMs: number): number {
  return dayMs - ((new Date(dayMs).getUTCDay() + 6) % 7) * DAY_MS;
}

/** ISO 第 1 週的週一：含 1 月 4 日的那一週。 */
function week1Monday(year: number): number {
  return mondayOf(Date.UTC(year, 0, 4));
}

/** `date` 所在的 ISO 週（以 UTC 計）。週四落在哪一年，這週就算哪一年。 */
export function isoWeekOf(date: Date): CohortWeek {
  const monday = mondayOf(utcMidnight(date));
  const year = new Date(monday + 3 * DAY_MS).getUTCFullYear();
  const week = Math.round((monday - week1Monday(year)) / WEEK_MS) + 1;
  return {
    label: `${year}-W${String(week).padStart(2, "0")}`,
    start: toIsoDate(monday),
    end: toIsoDate(monday + WEEK_MS),
  };
}

/** 解析 `YYYY-Www`。不存在的週（W00、W54、只有 52 週那年的 W53）一律報錯。 */
export function parseIsoWeek(label: string): CohortWeek {
  const match = ISO_WEEK.exec(label);
  if (!match) {
    throw new Error(`invalid_week: ${label}（格式是 2026-W43）`);
  }
  const week = Number(match[2]);
  const parsed = isoWeekOf(
    new Date(week1Monday(Number(match[1])) + (week - 1) * WEEK_MS),
  );
  if (week < 1 || parsed.label !== label) {
    throw new Error(`invalid_week: ${label}（這一年沒有這一週）`);
  }
  return parsed;
}

/** 最近一個已經結束的 ISO 週：`now` 所在那一週的前一週。 */
export function lastCompleteWeek(now: Date): CohortWeek {
  return isoWeekOf(new Date(utcMidnight(now) - WEEK_MS));
}

/** 從 `latest` 往回共 `count` 週（含 `latest`），由舊到新。 */
export function weeksEndingAt(
  latest: CohortWeek,
  count: number,
): CohortWeek[] {
  const latestStart = Date.parse(`${latest.start}T00:00:00Z`);
  return Array.from(
    { length: count },
    (_, index) =>
      isoWeekOf(new Date(latestStart - (count - 1 - index) * WEEK_MS)),
  );
}

/** 一週一條唯讀語句：範本代入週起訖（UTC，含頭不含尾）後包成 SELECT 開頭。 */
export function buildCohortSql(week: CohortWeek): string {
  const { from, to } = assertRange({ from: week.start, to: week.end });
  const sql = COHORT_SQL_TEMPLATE
    .replaceAll(":week_start", `'${from} 00:00:00+00'::timestamptz`)
    .replaceAll(":week_end", `'${to} 00:00:00+00'::timestamptz`);
  return assertReadOnlySql(`SELECT * FROM (\n${sql}\n) AS weekly_cohort`);
}
