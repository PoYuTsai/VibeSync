// 每週 cohort SQL 的真 Postgres 測試（PGlite，本機離線可跑）。
//
// 套真的 migration 建出報表會碰到的表，確認表名欄位名都對得上、SQL 在 Postgres
// 跑得動，而且每一欄算的是 docs/integrations/weekly-cohort-report.md 寫的那件事。
// auth schema 與三個 role 只做最小替身；測試帳號、事件全部是編的。
import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { type CohortRow, parseCohortRow } from "./render.ts";
import { buildCohortSql, parseIsoWeek } from "./sql.ts";

const MIGRATIONS = [
  "00001_initial_schema.sql", // users（auth.users 新增時 trigger 建列）
  "00003_ai_logs.sql",
  "00005_token_usage.sql", // 00006 的 view 會用到
  "00006_admin_dashboard.sql", // revenue_events、test_users
  "20260526007000_revenuecat_event_id.sql",
  "20260624074944_practice_chat_sessions.sql",
  "20260801000000_funnel_events.sql",
];
const migrationSql = await Promise.all(
  MIGRATIONS.map((name) =>
    Deno.readTextFile(
      new URL(`../../supabase/migrations/${name}`, import.meta.url),
    )
  ),
);

const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;
const W43_MONDAY = Date.parse("2026-10-19T00:00:00Z");
const iso = (ms: number) => new Date(ms).toISOString();

const A = "aaaaaaaa-0000-4000-8000-000000000001"; // 週一 01:00 註冊，什麼都做了
const B = "aaaaaaaa-0000-4000-8000-000000000002"; // 週日 23:00 註冊（週內最後一刻附近）
const G = "aaaaaaaa-0000-4000-8000-000000000003"; // 只做了不算數的事
const H = "aaaaaaaa-0000-4000-8000-000000000004"; // 剛好第 24 小時才分析
const T = "aaaaaaaa-0000-4000-8000-000000000005"; // 測試帳號 email
const L = "aaaaaaaa-0000-4000-8000-000000000006"; // 在 test_users 名單裡
const E = "aaaaaaaa-0000-4000-8000-000000000007"; // 下週一 00:00 整註冊（不屬於這週）
const F = "aaaaaaaa-0000-4000-8000-000000000008"; // 上週日 23:59:59 註冊

async function createDatabase(): Promise<PGlite> {
  const db = new PGlite();
  await db.exec(`
    CREATE SCHEMA auth;
    CREATE TABLE auth.users (id UUID PRIMARY KEY, email TEXT);
    CREATE FUNCTION auth.uid() RETURNS UUID LANGUAGE sql AS 'SELECT NULL::uuid';
    CREATE FUNCTION auth.jwt() RETURNS JSONB LANGUAGE sql AS 'SELECT ''{}''::jsonb';
    CREATE ROLE anon;
    CREATE ROLE authenticated;
    CREATE ROLE service_role;
  `);
  for (const sql of migrationSql) await db.exec(sql);
  return db;
}

async function addUser(db: PGlite, id: string, email: string, at: number) {
  await db.query("INSERT INTO auth.users (id, email) VALUES ($1, $2)", [
    id,
    email,
  ]);
  await db.query("UPDATE public.users SET created_at = $2 WHERE id = $1", [
    id,
    iso(at),
  ]);
}

async function aiLog(
  db: PGlite,
  userId: string,
  requestType: string,
  status: "success" | "failed",
  at: number,
) {
  await db.query(
    `INSERT INTO public.ai_logs
       (user_id, model, request_type, input_tokens, output_tokens, latency_ms, status, created_at)
     VALUES ($1, 'test-model', $2, 0, 0, 0, $3, $4)`,
    [userId, requestType, status, iso(at)],
  );
}

async function practice(
  db: PGlite,
  userId: string,
  sessionId: string,
  aiCount: number,
  at: number,
) {
  await db.query(
    `INSERT INTO public.practice_chat_sessions (user_id, session_id, ai_count, created_at)
     VALUES ($1, $2, $3, $4)`,
    [userId, sessionId, aiCount, iso(at)],
  );
}

async function funnel(
  db: PGlite,
  userId: string,
  event: string,
  properties: Record<string, unknown>,
  at: number,
) {
  await db.query(
    `INSERT INTO public.funnel_events (user_id, event, properties, created_at)
     VALUES ($1, $2, $3::jsonb, $4)`,
    [userId, event, JSON.stringify(properties), iso(at)],
  );
}

async function revenue(
  db: PGlite,
  userId: string,
  eventType: string,
  rawPayload: Record<string, unknown>,
  at: number,
) {
  await db.query(
    `INSERT INTO public.revenue_events
       (user_id, event_type, product_id, price_usd, event_timestamp, raw_payload)
     VALUES ($1, $2, 'vibesync_starter_monthly_v2', 0, $3, $4::jsonb)`,
    [userId, eventType, iso(at), JSON.stringify(rawPayload)],
  );
}

async function seed(db: PGlite) {
  const a = W43_MONDAY + 1 * HOUR;
  await addUser(db, A, "a@example.com", a);
  await aiLog(db, A, "analyze", "success", a + 2 * HOUR);
  await aiLog(db, A, "analyze", "success", a + 3 * HOUR); // 同一次分析的下一個階段
  await aiLog(db, A, "opener_generate", "success", a + 30 * HOUR); // 超過 24 小時
  await practice(db, A, "session-a-1", 3, a + 5 * HOUR);
  await funnel(
    db,
    A,
    "paywall_opened",
    { entry: "quota_exhausted" },
    a + 2 * DAY,
  );
  await funnel(db, A, "quota_block_shown", {}, a + 3 * DAY);
  await revenue(
    db,
    A,
    "INITIAL_PURCHASE",
    { environment: "PRODUCTION" },
    a + 5 * DAY,
  );
  await revenue(
    db,
    A,
    "CANCELLATION",
    { environment: "PRODUCTION", cancel_reason: "CUSTOMER_SUPPORT" },
    a + 10 * DAY,
  );

  const b = W43_MONDAY + 6 * DAY + 23 * HOUR;
  await addUser(db, B, "b@example.com", b);
  await aiLog(db, B, "analyze", "failed", b + 1 * HOUR); // 失敗的不算
  await aiLog(db, B, "analyze_with_images", "success", b + 20 * HOUR);
  await aiLog(db, B, "opener", "success", b + 1 * HOUR); // 舊版單段開場
  await practice(db, B, "session-b-1", 0, b + 1 * HOUR); // 沒有 AI 回覆不算
  await funnel(db, B, "paywall_opened", { entry: "general" }, b + 1 * HOUR);
  await funnel(db, B, "quota_block_shown", {}, b + 8 * DAY); // 超過 7 天
  await revenue(
    db,
    B,
    "INITIAL_PURCHASE",
    { environment: "SANDBOX" },
    b + 1 * DAY,
  );
  await revenue(
    db,
    B,
    "INITIAL_PURCHASE",
    { environment: "PRODUCTION" },
    b + 20 * DAY,
  );
  await revenue(
    db,
    B,
    "CANCELLATION",
    { environment: "PRODUCTION", cancel_reason: "UNSUBSCRIBE" },
    b + 25 * DAY,
  );

  const g = W43_MONDAY + 3 * DAY;
  await addUser(db, G, "g@example.com", g);
  await aiLog(db, G, "opener_analyze", "success", g + 1 * HOUR); // 兩段式第一段不算開場
  await aiLog(db, G, "recognize_only", "success", g + 1 * HOUR); // 只辨識不算分析
  await aiLog(db, G, "analyze", "failed", g + 2 * HOUR); // 唯一一次分析失敗：不算
  await revenue(
    db,
    G,
    "CANCELLATION",
    { environment: "SANDBOX", cancel_reason: "CUSTOMER_SUPPORT" },
    g + 2 * DAY,
  );

  const h = W43_MONDAY + 2 * DAY;
  await addUser(db, H, "h@example.com", h);
  await aiLog(db, H, "my_message", "success", h + 24 * HOUR); // 剛好 24 小時：不算

  for (
    const [id, email] of [[T, "vibesync.test@gmail.com"], [L, "l@example.com"]]
  ) {
    const t = W43_MONDAY + 1 * DAY;
    await addUser(db, id, email, t);
    await aiLog(db, id, "analyze", "success", t + 1 * HOUR);
    await revenue(
      db,
      id,
      "INITIAL_PURCHASE",
      { environment: "PRODUCTION" },
      t + 1 * DAY,
    );
  }
  await db.query(
    "INSERT INTO public.test_users (user_id, reason) VALUES ($1, 'qa')",
    [L],
  );

  const e = W43_MONDAY + 7 * DAY;
  await addUser(db, E, "e@example.com", e);
  await aiLog(db, E, "analyze", "success", e + 1 * HOUR);

  const f = W43_MONDAY - 1000;
  await addUser(db, F, "f@example.com", f);
  await aiLog(db, F, "analyze", "success", f + 1 * HOUR);
}

async function cohortRow(db: PGlite, label: string): Promise<CohortRow> {
  const result = await db.query(buildCohortSql(parseIsoWeek(label)));
  assertEquals(result.rows.length, 1);
  return parseCohortRow(result.rows[0]);
}

Deno.test("W43：每一欄算的都是文件寫的那件事（測試帳號排除、時間窗是嚴格小於）", async () => {
  const db = await createDatabase();
  try {
    await seed(db);
    assertEquals(await cohortRow(db, "2026-W43"), {
      new_accounts: 4, // A、B、G、H；T（測試 email）、L（test_users）不算
      analysis_24h: 2, // A、B（失敗那筆不算、第 20 小時的成功算）；G 只有失敗、H 剛好 24 小時都不算
      opener_24h: 1, // B 的舊版單段；A 超過 24 小時；G 的第一段不算
      practice_24h: 1, // A；B 的場次沒有 AI 回覆
      quota_block_7d: 1, // A；B 在第 8 天
      quota_paywall_7d: 1, // A 的 quota_exhausted；B 的 general 不算
      paid_d7: 1, // A；B 的沙盒購買不算
      paid_d30: 2, // A、B（第 20 天的正式購買）
      refunded: 1, // A；B 是關掉自動續訂、G 是沙盒
    });
  } finally {
    await db.close();
  }
});

Deno.test("週界含頭不含尾：週一 00:00 整算新的一週，前一秒算上一週", async () => {
  const db = await createDatabase();
  try {
    await seed(db);
    const w44 = await cohortRow(db, "2026-W44");
    assertEquals([w44.new_accounts, w44.analysis_24h], [1, 1]); // E
    const w42 = await cohortRow(db, "2026-W42");
    assertEquals([w42.new_accounts, w42.analysis_24h], [1, 1]); // F
  } finally {
    await db.close();
  }
});
