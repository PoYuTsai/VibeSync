// 成本保險絲資料層的真 Postgres 契約測試（Phase 5 WP2）。
//
// 為什麼要用 PGlite 而不是字串斷言：`increment_practice_chat_daily_cost` 的
// 「upsert 累加 ＋ 回傳累加後的值」是保險絲能保證
// `practice_chat_cost_fuse_blown` 一天恰好一筆的唯一機械證明，而那要在真的
// Postgres 交易語義下才驗得出來（ON CONFLICT DO UPDATE 的 RETURNING、
// RLS 無 policy 的預設拒絕、REVOKE 之後的 has_function_privilege）。
// PGlite 是 WASM 版 Postgres，跑在測試行程內，不需要任何憑證或連線——
// 範式沿用 moments_migration_postgres_test.ts。
//
// 本檔直接載入 migration 原始 SQL，所以它同時是「SQL 真的能套用」的煙霧測試。
import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260905120000_practice_chat_daily_cost.sql",
    import.meta.url,
  ),
);

const DAY = "2026-09-05";

async function createDatabase(): Promise<PGlite> {
  const db = new PGlite();
  // 忠實重現 Supabase 的角色與預設授權：新建物件會自動拿到 anon/authenticated
  // 的權限，所以 migration 內的 REVOKE 是否真的有效，只有在這個前提下才驗得準。
  await db.exec(`
    CREATE ROLE anon;
    CREATE ROLE authenticated;
    CREATE ROLE service_role;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public
      GRANT ALL ON TABLES TO anon, authenticated, service_role;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public
      GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;
  `);
  await db.exec(migration);
  return db;
}

async function increment(db: PGlite, day: string, usd: number) {
  const result = await db.query<{ increment_practice_chat_daily_cost: string }>(
    `SELECT public.increment_practice_chat_daily_cost($1, $2)`,
    [day, usd],
  );
  return Number(result.rows[0].increment_practice_chat_daily_cost);
}

Deno.test("首次累加會建列並回傳累加後的值", async () => {
  const db = await createDatabase();
  try {
    assertEquals(await increment(db, DAY, 0.25), 0.25);
    const rows = await db.query<{ spent_usd: string }>(
      `SELECT spent_usd FROM public.practice_chat_daily_cost WHERE day = $1`,
      [DAY],
    );
    assertEquals(rows.rows.length, 1);
    assertEquals(Number(rows.rows[0].spent_usd), 0.25);
  } finally {
    await db.close();
  }
});

Deno.test("同一天重複累加是相加，回傳值一路是累加後的總額（跨門檻判斷靠這個）", async () => {
  const db = await createDatabase();
  try {
    assertEquals(await increment(db, DAY, 0.4), 0.4);
    assertEquals(await increment(db, DAY, 0.4), 0.8);
    // 第三次跨過 1.0：Edge 端用 `after - usd < budget <= after` 判斷，所以
    // 「累加前 0.8、累加後 1.2」必須是同一次呼叫就算得出來的。
    assertEquals(await increment(db, DAY, 0.4), 1.2000000000000000);
    const rows = await db.query<{ count: string }>(
      `SELECT count(*) AS count FROM public.practice_chat_daily_cost`,
    );
    assertEquals(Number(rows.rows[0].count), 1, "同一天只有一列");
  } finally {
    await db.close();
  }
});

Deno.test("不同天各自獨立（跨日自然重算）", async () => {
  const db = await createDatabase();
  try {
    await increment(db, DAY, 1.5);
    assertEquals(await increment(db, "2026-09-06", 0.25), 0.25);
    assertEquals(await increment(db, DAY, 0.5), 2);
  } finally {
    await db.close();
  }
});

Deno.test("累加會更新 updated_at", async () => {
  const db = await createDatabase();
  try {
    await increment(db, DAY, 0.1);
    const before = await db.query<{ updated_at: Date }>(
      `SELECT updated_at FROM public.practice_chat_daily_cost WHERE day = $1`,
      [DAY],
    );
    // now() 在同一個 transaction 內是固定的，所以要各自獨立的 statement。
    await increment(db, DAY, 0.1);
    const after = await db.query<{ updated_at: Date }>(
      `SELECT updated_at FROM public.practice_chat_daily_cost WHERE day = $1`,
      [DAY],
    );
    assert(
      after.rows[0].updated_at >= before.rows[0].updated_at,
      "updated_at 不得倒退",
    );
  } finally {
    await db.close();
  }
});

Deno.test("負數與 NULL 參數被 RPC 擋下（不會把累計往回扣）", async () => {
  const db = await createDatabase();
  try {
    for (const bad of [[DAY, -0.1], [null, 0.1], [DAY, null]]) {
      let threw = false;
      try {
        await db.query(
          `SELECT public.increment_practice_chat_daily_cost($1, $2)`,
          bad,
        );
      } catch {
        threw = true;
      }
      assert(threw, `RPC 必須拒絕參數 ${JSON.stringify(bad)}`);
    }
    const rows = await db.query<{ count: string }>(
      `SELECT count(*) AS count FROM public.practice_chat_daily_cost`,
    );
    assertEquals(Number(rows.rows[0].count), 0, "被拒的呼叫不得留下列");
  } finally {
    await db.close();
  }
});

Deno.test("RPC 收尾只有 service_role 能 EXECUTE，且表開了 RLS 但沒有 policy", async () => {
  const db = await createDatabase();
  try {
    const priv = await db.query<{
      anon_execute: boolean;
      authenticated_execute: boolean;
      service_execute: boolean;
      is_definer: boolean;
    }>(`
      SELECT has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_execute,
             has_function_privilege('authenticated', p.oid, 'EXECUTE')
               AS authenticated_execute,
             has_function_privilege('service_role', p.oid, 'EXECUTE')
               AS service_execute,
             p.prosecdef AS is_definer
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.proname = 'increment_practice_chat_daily_cost'
    `);
    assertEquals(priv.rows.length, 1);
    assertEquals(priv.rows[0], {
      anon_execute: false,
      authenticated_execute: false,
      service_execute: true,
      is_definer: true,
    });

    const rls = await db.query<{ relrowsecurity: boolean; policies: string }>(`
      SELECT c.relrowsecurity,
             (SELECT count(*) FROM pg_policy WHERE polrelid = c.oid) AS policies
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = 'practice_chat_daily_cost'
    `);
    assertEquals(rls.rows[0].relrowsecurity, true);
    assertEquals(Number(rls.rows[0].policies), 0, "無 policy = 預設拒絕");
  } finally {
    await db.close();
  }
});
