// 資料保留期限 migration 的真 Postgres 契約測試（PGlite）：
// 已扣費的分析 run 30 天後清除、未扣費過期 run 1 小時後清除、未到期一律保留；
// ai_logs 30 天清除；兩支清理函式 anon／authenticated 不得執行。
// pg_cron 在 PGlite 不存在，migration 的排程段會自行略過，這裡只驗函式本體。
import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import { assert, assertEquals, assertRejects } from "https://deno.land/std@0.168.0/testing/asserts.ts";

const MIGRATIONS = [
  "20260603120000_analysis_stream_runs.sql",
  "20260603120100_charge_stream_analysis_run.sql",
  "20260603120200_stream_analysis_retry_budget.sql",
  "20260813003000_stream_analysis_retry_lease.sql",
  "20260902120000_analysis_stream_runs_decision_kind.sql",
  "20260902160000_retention_cleanup_schedules.sql",
];
const migrationSql = await Promise.all(
  MIGRATIONS.map((name) => Deno.readTextFile(new URL(`../../migrations/${name}`, import.meta.url))),
);
const USER_ID = "11111111-2222-3333-4444-555555555555";

async function createDatabase(): Promise<PGlite> {
  const db = new PGlite();
  await db.exec(`
    CREATE SCHEMA auth;
    CREATE TABLE auth.users (id UUID PRIMARY KEY);
    CREATE ROLE anon;
    CREATE ROLE authenticated;
    CREATE ROLE service_role;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;
    INSERT INTO auth.users (id) VALUES ('${USER_ID}');
    CREATE TABLE public.increment_usage_calls (id SERIAL PRIMARY KEY);
    CREATE OR REPLACE FUNCTION public.increment_usage(p_user_id UUID, p_count INTEGER DEFAULT 1)
    RETURNS void LANGUAGE sql AS $$ INSERT INTO public.increment_usage_calls DEFAULT VALUES; $$;
    -- ai_logs 替身：清理函式只碰 created_at
    CREATE TABLE public.ai_logs (id SERIAL PRIMARY KEY, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    -- 忠實重現 00003_ai_logs.sql 的原函式（RETURNS void）：migration 必須能在它存在的情況下套用
    CREATE OR REPLACE FUNCTION cleanup_old_ai_logs()
    RETURNS void AS $$ BEGIN DELETE FROM ai_logs WHERE created_at < NOW() - INTERVAL '30 days'; END; $$ LANGUAGE plpgsql;
  `);
  await db.exec("SET app.allow_missing_pg_cron = on");
  for (const sql of migrationSql) await db.exec(sql);
  return db;
}

async function insertRun(db: PGlite, opts: { charged: boolean; ageDays: number; chargedDaysAgo?: number; expiredHours?: number }): Promise<string> {
  const rows = await db.query<{ id: string }>(
    `INSERT INTO public.analysis_stream_runs
       (user_id, conversation_hash, status, selected_style, recommendation_json, charged_at, created_at, expires_at)
     VALUES ($1, 'hash', $2, $3, $4::jsonb, $5, now() - ($6 || ' days')::interval, now() - ($7 || ' hours')::interval)
     RETURNING id`,
    [
      USER_ID,
      opts.charged ? "charged" : "pending",
      opts.charged ? "extend" : null,
      opts.charged ? JSON.stringify({ selectedStyle: "extend", message: "x" }) : null,
      opts.charged ? new Date(Date.now() - (opts.chargedDaysAgo ?? opts.ageDays) * 86400000).toISOString() : null,
      String(opts.ageDays),
      String(opts.expiredHours ?? -1),
    ],
  );
  return rows.rows[0].id;
}

Deno.test("已扣費 run 依扣費時間 30 天後清除；未扣費過期 run 1 小時後清除；其餘保留", async () => {
  const db = await createDatabase();
  const oldCharged = await insertRun(db, { charged: true, ageDays: 31 });
  const recentCharged = await insertRun(db, { charged: true, ageDays: 29 });
  // 建立很久但最近才扣費（重試回放）：以 charged_at 為準，應保留
  const lateCharged = await insertRun(db, { charged: true, ageDays: 40, chargedDaysAgo: 10 });
  const staleUncharged = await insertRun(db, { charged: false, ageDays: 0, expiredHours: 2 });
  const freshUncharged = await insertRun(db, { charged: false, ageDays: 0, expiredHours: -1 });

  const deleted = await db.query<{ n: number }>("SELECT public.cleanup_expired_analysis_stream_runs() AS n");
  assertEquals(deleted.rows[0].n, 2);

  const remaining = await db.query<{ id: string }>("SELECT id FROM public.analysis_stream_runs ORDER BY created_at");
  const ids = remaining.rows.map((r) => r.id);
  assert(!ids.includes(oldCharged), "31 天前的已扣費 run 應被清除");
  assert(!ids.includes(staleUncharged), "過期 2 小時的未扣費 run 應被清除");
  assert(ids.includes(recentCharged), "29 天的已扣費 run 應保留");
  assert(ids.includes(freshUncharged), "未過期的未扣費 run 應保留");
  assert(ids.includes(lateCharged), "10 天前才扣費的 run 應保留（不看 created_at）");
  await db.close();
});

Deno.test("沒有 pg_cron 且未放行時 migration 必須失敗", async () => {
  const db = new PGlite();
  await db.exec(`CREATE SCHEMA auth; CREATE TABLE auth.users (id UUID PRIMARY KEY);
    CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;
    CREATE TABLE public.ai_logs (id SERIAL PRIMARY KEY, created_at TIMESTAMPTZ NOT NULL DEFAULT now());`);
  for (const sql of migrationSql.slice(0, -1)) await db.exec(sql);
  await assertRejects(() => db.exec(migrationSql[migrationSql.length - 1]), Error, "pg_cron is required");
  await db.close();
});

Deno.test("ai_logs 30 天清除", async () => {
  const db = await createDatabase();
  await db.exec(`INSERT INTO public.ai_logs (created_at) VALUES (now() - interval '31 days'), (now() - interval '29 days'), (now())`);
  const deleted = await db.query<{ n: number }>("SELECT public.cleanup_old_ai_logs() AS n");
  assertEquals(deleted.rows[0].n, 1);
  const left = await db.query<{ c: number }>("SELECT count(*)::int AS c FROM public.ai_logs");
  assertEquals(left.rows[0].c, 2);
  await db.close();
});

Deno.test("anon／authenticated 不能呼叫兩支清理函式", async () => {
  const db = await createDatabase();
  for (const role of ["anon", "authenticated"]) {
    await db.exec(`SET ROLE ${role}`);
    await assertRejects(() => db.query("SELECT public.cleanup_expired_analysis_stream_runs()"), Error, "permission denied");
    await assertRejects(() => db.query("SELECT public.cleanup_old_ai_logs()"), Error, "permission denied");
    await db.exec("RESET ROLE");
  }
  await db.close();
});
