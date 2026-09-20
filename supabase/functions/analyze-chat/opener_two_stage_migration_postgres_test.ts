// 開場救星兩段式會話 migration 的真 Postgres 契約測試（PGlite，範式沿用
// stream_runs_decision_kind_migration_postgres_test.ts）。
//
// 驗的是附件 §14.2 B01–B15 裡「必須在實際測試資料庫驗證」的部分：交易同成
// 同敗、首次扣費只扣一次、三組上限在模型前擋、同 ID 重播、同 ID 換輸入拒絕、
// 同局單一執行中作業、租約接手後舊作業不得結算、到期不扣、跨帳號不可見、
// 到期清理與 anon／authenticated 權限。
import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import {
  assert,
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

const MIGRATIONS = [
  "20260702120000_increment_usage_atomic_quota.sql",
  "20260917120000_opener_two_stage_sessions.sql",
];
const migrationSql = await Promise.all(
  MIGRATIONS.map((name) =>
    Deno.readTextFile(new URL(`../../migrations/${name}`, import.meta.url))
  ),
);

const USER_ID = "11111111-2222-3333-4444-555555555555";
const OTHER_USER_ID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
const REQ_1 = "0f0f0f0f-0f0f-4f0f-8f0f-0f0f0f0f0f01";
const REQ_2 = "0f0f0f0f-0f0f-4f0f-8f0f-0f0f0f0f0f02";
const GEN_1 = "1e1e1e1e-1e1e-4e1e-8e1e-1e1e1e1e1e01";
const GEN_2 = "1e1e1e1e-1e1e-4e1e-8e1e-1e1e1e1e1e02";
const GEN_3 = "1e1e1e1e-1e1e-4e1e-8e1e-1e1e1e1e1e03";
const GEN_4 = "1e1e1e1e-1e1e-4e1e-8e1e-1e1e1e1e1e04";
const OWNER_A = "2a2a2a2a-2a2a-4a2a-8a2a-2a2a2a2a2a2a";
const OWNER_B = "2b2b2b2b-2b2b-4b2b-8b2b-2b2b2b2b2b2b";
const HASH_A = "a".repeat(64);
const HASH_B = "b".repeat(64);

const ANALYSIS = {
  approach: { mode: "anchor_hooks", summary: "可以從她的狗開", avoid: [] },
  cues: [{ id: "cue_1", label: "養狗", source: "profile_text", subject: "recipient" }],
  question: null,
  profileDigest: "自介：有養一隻狗",
};
const CONTRIBUTION = { state: "answered", questionId: null, selectedOptionId: null, freeText: "沒養過" };
const RESULT = {
  openers: { extend: "牠散步會自己選路嗎", humor: "幽默句", tease: "調情句" },
  recommendation: { pick: "extend", reason: "直接問你想知道的事" },
  cardReasons: { extend: "直接問你想知道的事" },
  access: { contractVersion: 2, servedTier: "free", visibleTypes: ["extend", "humor", "tease"], lockedTypes: ["resonate", "coldRead"] },
  materialUse: { inputState: "answered", references: [], traceStatus: "uncertain", displayNote: null },
};

async function createDatabase(): Promise<PGlite> {
  const db = new PGlite();
  await db.exec(`
    CREATE SCHEMA auth;
    CREATE TABLE auth.users (id UUID PRIMARY KEY);
    CREATE ROLE anon;
    CREATE ROLE authenticated;
    CREATE ROLE service_role;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public
      GRANT ALL ON TABLES TO anon, authenticated, service_role;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public
      GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;
    CREATE TABLE public.users (id UUID PRIMARY KEY, total_analyses INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE public.subscriptions (
      user_id UUID PRIMARY KEY,
      monthly_messages_used INTEGER NOT NULL DEFAULT 0,
      daily_messages_used INTEGER NOT NULL DEFAULT 0
    );
    -- 20260702120000 會 DROP 這個 2-arg 版本再建 4-arg 版本。
    CREATE FUNCTION public.increment_usage(p_user_id UUID, p_messages INTEGER DEFAULT 1)
    RETURNS void LANGUAGE sql AS $$ SELECT 1; $$;
  `);
  await db.exec("SET app.allow_missing_pg_cron = 'pglite-contract-test'");
  for (const sql of migrationSql) await db.exec(sql);
  await db.query(`INSERT INTO auth.users(id) VALUES ($1), ($2)`, [USER_ID, OTHER_USER_ID]);
  await db.query(`INSERT INTO public.users(id) VALUES ($1), ($2)`, [USER_ID, OTHER_USER_ID]);
  await db.query(`INSERT INTO public.subscriptions(user_id) VALUES ($1), ($2)`, [USER_ID, OTHER_USER_ID]);
  return db;
}

async function rpc<T = Record<string, unknown>>(
  db: PGlite,
  fn: string,
  args: unknown[],
): Promise<T> {
  const placeholders = args.map((_, i) => `$${i + 1}`).join(", ");
  const rows = await db.query<{ out: T }>(`SELECT public.${fn}(${placeholders}) AS out`, args);
  return rows.rows[0].out;
}

async function readySession(
  db: PGlite,
  opts: { user?: string; requestId?: string; cost?: number; owner?: string } = {},
): Promise<string> {
  const user = opts.user ?? USER_ID;
  const requestId = opts.requestId ?? REQ_1;
  const owner = opts.owner ?? OWNER_A;
  const claim = await rpc(db, "claim_opener_analysis", [user, requestId, HASH_A, owner, 1, 2, 65]);
  assertEquals(claim.kind, "claimed");
  const settled = await rpc(db, "settle_opener_analysis", [
    user, requestId, owner, JSON.stringify(ANALYSIS), opts.cost ?? 3, 86400,
  ]);
  assertEquals(settled.replayed, false);
  return settled.sessionId as string;
}

async function usage(db: PGlite, user = USER_ID): Promise<{ monthly: number; daily: number }> {
  const rows = await db.query<{ monthly_messages_used: number; daily_messages_used: number }>(
    `SELECT monthly_messages_used, daily_messages_used FROM public.subscriptions WHERE user_id = $1`,
    [user],
  );
  return { monthly: rows.rows[0].monthly_messages_used, daily: rows.rows[0].daily_messages_used };
}

async function sessionRow(db: PGlite, sessionId: string) {
  const rows = await db.query<{
    state: string; quota_charged: boolean; charged_amount: number;
    generations_used: number; expires_at: string; first_generation_cost: number;
  }>(
    `SELECT state, quota_charged, charged_amount, generations_used, expires_at, first_generation_cost
     FROM public.opener_sessions WHERE session_id = $1`,
    [sessionId],
  );
  return rows.rows[0];
}

async function runRow(db: PGlite, generationId: string) {
  const rows = await db.query<{ state: string; charged_amount: number; result_json: unknown }>(
    `SELECT state, charged_amount, result_json FROM public.opener_generation_runs
     WHERE user_id = $1 AND generation_id = $2`,
    [USER_ID, generationId],
  );
  return rows.rows[0] ?? null;
}

Deno.test("migration 套用後 DB 能力標記為 opener-two-stage-v1", async () => {
  const db = await createDatabase();
  try {
    const rows = await db.query<{ v: string }>(`SELECT public.opener_flow_contract_version() AS v`);
    assertEquals(rows.rows[0].v, "opener-two-stage-v1");
  } finally {
    await db.close();
  }
});

Deno.test("第一段：claim→settle 建立 ready 會話、到期固定 24h、同 ID 重試取回快照（B01 分析不扣）", async () => {
  const db = await createDatabase();
  try {
    const sessionId = await readySession(db);
    const row = await sessionRow(db, sessionId);
    assertEquals(row.state, "ready");
    assertEquals(row.generations_used, 0);
    assertEquals(row.quota_charged, false);
    const ttlMs = new Date(row.expires_at).getTime() - Date.now();
    assert(ttlMs > 86400_000 - 60_000 && ttlMs <= 86400_000, `ttl≈24h，實際 ${ttlMs}ms`);
    assertEquals(await usage(db), { monthly: 0, daily: 0 });

    // 同 analysisRequestId 同輸入重試（不論 owner）→ replay，不重做分析。
    const replay = await rpc(db, "claim_opener_analysis", [USER_ID, REQ_1, HASH_A, OWNER_B, 1, 2, 65]);
    assertEquals(replay.kind, "replay");
    assertEquals(replay.sessionId, sessionId);
    assertEquals((replay.analysisJson as Record<string, unknown>).profileDigest, "自介：有養一隻狗");
    // 重複 settle 不改到期、不改版本。
    const again = await rpc(db, "settle_opener_analysis", [USER_ID, REQ_1, OWNER_A, JSON.stringify(ANALYSIS), 0, 86400]);
    assertEquals(again.replayed, true);
    assertEquals(again.firstGenerationCost, 3);
  } finally {
    await db.close();
  }
});

Deno.test("第一段：同 analysisRequestId 換輸入 → OPENER_OPERATION_INPUT_MISMATCH；他人租約有效 → pending；租約過期可接手且舊 owner 不能 settle", async () => {
  const db = await createDatabase();
  try {
    const claim = await rpc(db, "claim_opener_analysis", [USER_ID, REQ_1, HASH_A, OWNER_A, 1, 2, 65]);
    assertEquals(claim.kind, "claimed");
    await assertRejects(
      () => rpc(db, "claim_opener_analysis", [USER_ID, REQ_1, HASH_B, OWNER_B, 1, 2, 65]),
      Error,
      "OPENER_OPERATION_INPUT_MISMATCH",
    );
    const pending = await rpc(db, "claim_opener_analysis", [USER_ID, REQ_1, HASH_A, OWNER_B, 1, 2, 65]);
    assertEquals(pending.kind, "pending");
    assert((pending.retryAfterMs as number) >= 250);

    await db.query(
      `UPDATE public.opener_sessions SET lease_expires_at = now() - interval '1 second'
       WHERE user_id = $1 AND analysis_request_id = $2`,
      [USER_ID, REQ_1],
    );
    const takeover = await rpc(db, "claim_opener_analysis", [USER_ID, REQ_1, HASH_A, OWNER_B, 1, 2, 65]);
    assertEquals(takeover.kind, "claimed");
    await assertRejects(
      () => rpc(db, "settle_opener_analysis", [USER_ID, REQ_1, OWNER_A, JSON.stringify(ANALYSIS), 3, 86400]),
      Error,
      "OPENER_OPERATION_OWNER_MISMATCH",
    );
    // 舊 owner release 也不得刪掉接手者的列。
    const released = await rpc<boolean>(db, "release_opener_analysis_claim", [USER_ID, REQ_1, OWNER_A]);
    assertEquals(released, false);
    const settled = await rpc(db, "settle_opener_analysis", [USER_ID, REQ_1, OWNER_B, JSON.stringify(ANALYSIS), 3, 86400]);
    assertEquals(settled.replayed, false);
  } finally {
    await db.close();
  }
});

Deno.test("第一段 settle 拒絕帶圖片或形狀不對的快照", async () => {
  const db = await createDatabase();
  try {
    await rpc(db, "claim_opener_analysis", [USER_ID, REQ_1, HASH_A, OWNER_A, 1, 2, 65]);
    await assertRejects(
      () => rpc(db, "settle_opener_analysis", [USER_ID, REQ_1, OWNER_A, JSON.stringify({ ...ANALYSIS, images: [] }), 3, 86400]),
      Error,
      "invalid p_analysis_json",
    );
    await assertRejects(
      () => rpc(db, "settle_opener_analysis", [USER_ID, REQ_1, OWNER_A, JSON.stringify({ approach: {} }), 3, 86400]),
      Error,
      "invalid p_analysis_json",
    );
  } finally {
    await db.close();
  }
});

Deno.test("B02/B04/B05：首次成功扣 3、後兩組免費、第四組在模型前被擋；三組各自不同 generationId", async () => {
  const db = await createDatabase();
  try {
    const sessionId = await readySession(db);
    for (const [i, gen] of [GEN_1, GEN_2, GEN_3].entries()) {
      const claim = await rpc(db, "claim_opener_generation", [
        USER_ID, sessionId, gen, HASH_A, OWNER_A, JSON.stringify(CONTRIBUTION), 3, 65,
      ]);
      assertEquals(claim.kind, "claimed");
      const view = claim.session as Record<string, unknown>;
      assertEquals(view.generationsUsed, i);
      assertEquals(view.quotaCharged, i > 0);
      const settled = await rpc(db, "settle_opener_generation", [
        USER_ID, sessionId, gen, OWNER_A, JSON.stringify(RESULT), 30, 10, true, 3,
      ]);
      assertEquals(settled.replayed, false);
      assertEquals(settled.chargedNow, i === 0 ? 3 : 0);
      assertEquals(settled.sessionChargedTotal, 3);
      assertEquals(settled.generationsUsed, i + 1);
      assertEquals(settled.generationsRemaining, 2 - i);
    }
    assertEquals(await usage(db), { monthly: 3, daily: 3 });
    const row = await sessionRow(db, sessionId);
    assertEquals(row.generations_used, 3);
    assertEquals(row.charged_amount, 3);

    await assertRejects(
      () => rpc(db, "claim_opener_generation", [
        USER_ID, sessionId, GEN_4, HASH_A, OWNER_A, JSON.stringify(CONTRIBUTION), 3, 65,
      ]),
      Error,
      "OPENER_GENERATION_LIMIT_REACHED",
    );
    assertEquals(await runRow(db, GEN_4), null);
  } finally {
    await db.close();
  }
});

Deno.test("B03：零扣費會話（first_generation_cost=0）仍建立成功次數、額度不動", async () => {
  const db = await createDatabase();
  try {
    const sessionId = await readySession(db, { cost: 0 });
    await rpc(db, "claim_opener_generation", [USER_ID, sessionId, GEN_1, HASH_A, OWNER_A, JSON.stringify(CONTRIBUTION), 3, 65]);
    const settled = await rpc(db, "settle_opener_generation", [USER_ID, sessionId, GEN_1, OWNER_A, JSON.stringify(RESULT), 30, 10, true, 3]);
    assertEquals(settled.chargedNow, 0);
    assertEquals(settled.sessionChargedTotal, 0);
    assertEquals(settled.generationsUsed, 1);
    assertEquals(await usage(db), { monthly: 0, daily: 0 });
    const row = await sessionRow(db, sessionId);
    assertEquals(row.quota_charged, false);
  } finally {
    await db.close();
  }
});

Deno.test("B06：同 generationId 重試取回同組結果，不重扣、不減成功次數", async () => {
  const db = await createDatabase();
  try {
    const sessionId = await readySession(db);
    await rpc(db, "claim_opener_generation", [USER_ID, sessionId, GEN_1, HASH_A, OWNER_A, JSON.stringify(CONTRIBUTION), 3, 65]);
    await rpc(db, "settle_opener_generation", [USER_ID, sessionId, GEN_1, OWNER_A, JSON.stringify(RESULT), 30, 10, true, 3]);

    const replay = await rpc(db, "claim_opener_generation", [USER_ID, sessionId, GEN_1, HASH_A, OWNER_B, JSON.stringify(CONTRIBUTION), 3, 65]);
    assertEquals(replay.kind, "replay");
    assertEquals((replay.result as Record<string, unknown>).openers, RESULT.openers);
    const settledAgain = await rpc(db, "settle_opener_generation", [USER_ID, sessionId, GEN_1, OWNER_B, JSON.stringify(RESULT), 30, 10, true, 3]);
    assertEquals(settledAgain.replayed, true);
    assertEquals(settledAgain.chargedNow, 0);
    assertEquals(settledAgain.generationsUsed, 1);
    assertEquals(await usage(db), { monthly: 3, daily: 3 });
  } finally {
    await db.close();
  }
});

Deno.test("B07：同局只允許一個執行中作業；同 generationId 他人租約有效回 pending", async () => {
  const db = await createDatabase();
  try {
    const sessionId = await readySession(db);
    const first = await rpc(db, "claim_opener_generation", [USER_ID, sessionId, GEN_1, HASH_A, OWNER_A, JSON.stringify(CONTRIBUTION), 3, 65]);
    assertEquals(first.kind, "claimed");
    // 連點：新 generationId 進來 → session_busy，不建立第二個作業。
    const busy = await rpc(db, "claim_opener_generation", [USER_ID, sessionId, GEN_2, HASH_B, OWNER_B, JSON.stringify(CONTRIBUTION), 3, 65]);
    assertEquals(busy.kind, "session_busy");
    assertEquals(busy.generationId, GEN_1);
    assertEquals(await runRow(db, GEN_2), null);
    // 另一台裝置用同 generationId 重試 → pending（連回同一作業）。
    const pending = await rpc(db, "claim_opener_generation", [USER_ID, sessionId, GEN_1, HASH_A, OWNER_B, JSON.stringify(CONTRIBUTION), 3, 65]);
    assertEquals(pending.kind, "pending");
    // 同 owner renew 仍是 claimed。
    const renew = await rpc(db, "claim_opener_generation", [USER_ID, sessionId, GEN_1, HASH_A, OWNER_A, JSON.stringify(CONTRIBUTION), 3, 65]);
    assertEquals(renew.kind, "claimed");
  } finally {
    await db.close();
  }
});

Deno.test("B08：模型失敗 release 作業 → 不扣費、不占次數、可重新 claim", async () => {
  const db = await createDatabase();
  try {
    const sessionId = await readySession(db);
    await rpc(db, "claim_opener_generation", [USER_ID, sessionId, GEN_1, HASH_A, OWNER_A, JSON.stringify(CONTRIBUTION), 3, 65]);
    const released = await rpc<boolean>(db, "release_opener_generation_claim", [USER_ID, GEN_1, OWNER_A]);
    assertEquals(released, true);
    // R1：release 只釋放執行資格，列與輸入身分保留（state=released）。
    assertEquals((await runRow(db, GEN_1))?.state, "released");
    assertEquals((await sessionRow(db, sessionId)).generations_used, 0);
    assertEquals(await usage(db), { monthly: 0, daily: 0 });
    const again = await rpc(db, "claim_opener_generation", [USER_ID, sessionId, GEN_1, HASH_A, OWNER_B, JSON.stringify(CONTRIBUTION), 3, 65]);
    assertEquals(again.kind, "claimed");
  } finally {
    await db.close();
  }
});

Deno.test("B09：同 generationId 改答案（hash 不同）→ OPENER_OPERATION_INPUT_MISMATCH，不拿舊結果", async () => {
  const db = await createDatabase();
  try {
    const sessionId = await readySession(db);
    await rpc(db, "claim_opener_generation", [USER_ID, sessionId, GEN_1, HASH_A, OWNER_A, JSON.stringify(CONTRIBUTION), 3, 65]);
    await rpc(db, "settle_opener_generation", [USER_ID, sessionId, GEN_1, OWNER_A, JSON.stringify(RESULT), 30, 10, true, 3]);
    await assertRejects(
      () => rpc(db, "claim_opener_generation", [USER_ID, sessionId, GEN_1, HASH_B, OWNER_A, JSON.stringify(CONTRIBUTION), 3, 65]),
      Error,
      "OPENER_OPERATION_INPUT_MISMATCH",
    );
  } finally {
    await db.close();
  }
});

Deno.test("B10：首次扣費時額度已被其他功能用掉 → 整筆回滾，結果不落地、成功數不動", async () => {
  const db = await createDatabase();
  try {
    const sessionId = await readySession(db);
    await rpc(db, "claim_opener_generation", [USER_ID, sessionId, GEN_1, HASH_A, OWNER_A, JSON.stringify(CONTRIBUTION), 3, 65]);
    // 其他功能把本月用到剩 2。
    await db.query(`UPDATE public.subscriptions SET monthly_messages_used = 28 WHERE user_id = $1`, [USER_ID]);
    await assertRejects(
      () => rpc(db, "settle_opener_generation", [USER_ID, sessionId, GEN_1, OWNER_A, JSON.stringify(RESULT), 30, 10, true, 3]),
      Error,
      "QUOTA_EXCEEDED_MONTHLY",
    );
    const run = await runRow(db, GEN_1);
    assertEquals(run?.state, "pending");
    assertEquals(run?.result_json, null);
    const row = await sessionRow(db, sessionId);
    assertEquals(row.generations_used, 0);
    assertEquals(row.quota_charged, false);
    assertEquals(await usage(db), { monthly: 28, daily: 0 });
  } finally {
    await db.close();
  }
});

Deno.test("B11：首次扣費後額度歸零，同局剩餘生成仍可結算且不再扣費", async () => {
  const db = await createDatabase();
  try {
    const sessionId = await readySession(db);
    await rpc(db, "claim_opener_generation", [USER_ID, sessionId, GEN_1, HASH_A, OWNER_A, JSON.stringify(CONTRIBUTION), 3, 65]);
    await rpc(db, "settle_opener_generation", [USER_ID, sessionId, GEN_1, OWNER_A, JSON.stringify(RESULT), 30, 10, true, 3]);
    await db.query(`UPDATE public.subscriptions SET monthly_messages_used = 30, daily_messages_used = 10 WHERE user_id = $1`, [USER_ID]);
    const claim = await rpc(db, "claim_opener_generation", [USER_ID, sessionId, GEN_2, HASH_B, OWNER_A, JSON.stringify(CONTRIBUTION), 3, 65]);
    assertEquals(claim.kind, "claimed");
    assertEquals((claim.session as Record<string, unknown>).quotaCharged, true);
    const settled = await rpc(db, "settle_opener_generation", [USER_ID, sessionId, GEN_2, OWNER_A, JSON.stringify(RESULT), 30, 10, true, 3]);
    assertEquals(settled.chargedNow, 0);
    assertEquals(settled.generationsUsed, 2);
    assertEquals(await usage(db), { monthly: 30, daily: 10 });
  } finally {
    await db.close();
  }
});

Deno.test("B12：會話到期 → claim 與結算都回 OPENER_SESSION_EXPIRED，不扣費", async () => {
  const db = await createDatabase();
  try {
    const sessionId = await readySession(db);
    await rpc(db, "claim_opener_generation", [USER_ID, sessionId, GEN_1, HASH_A, OWNER_A, JSON.stringify(CONTRIBUTION), 3, 65]);
    await db.query(`UPDATE public.opener_sessions SET expires_at = now() - interval '1 second' WHERE session_id = $1`, [sessionId]);
    // 生成途中到期：結算拒絕。
    await assertRejects(
      () => rpc(db, "settle_opener_generation", [USER_ID, sessionId, GEN_1, OWNER_A, JSON.stringify(RESULT), 30, 10, true, 3]),
      Error,
      "OPENER_SESSION_EXPIRED",
    );
    await assertRejects(
      () => rpc(db, "claim_opener_generation", [USER_ID, sessionId, GEN_2, HASH_B, OWNER_A, JSON.stringify(CONTRIBUTION), 3, 65]),
      Error,
      "OPENER_SESSION_EXPIRED",
    );
    assertEquals(await usage(db), { monthly: 0, daily: 0 });
    assertEquals((await sessionRow(db, sessionId)).generations_used, 0);
    // 第一段同 ID 重試也只回 expired，不重開付費流程。
    const replay = await rpc(db, "claim_opener_analysis", [USER_ID, REQ_1, HASH_A, OWNER_A, 1, 2, 65]);
    assertEquals(replay.kind, "expired");
  } finally {
    await db.close();
  }
});

Deno.test("B13：租約過期被接手後，舊作業晚回不能結算、不能覆蓋結果", async () => {
  const db = await createDatabase();
  try {
    const sessionId = await readySession(db);
    await rpc(db, "claim_opener_generation", [USER_ID, sessionId, GEN_1, HASH_A, OWNER_A, JSON.stringify(CONTRIBUTION), 3, 65]);
    await db.query(`UPDATE public.opener_generation_runs SET lease_expires_at = now() - interval '1 second' WHERE generation_id = $1`, [GEN_1]);
    const takeover = await rpc(db, "claim_opener_generation", [USER_ID, sessionId, GEN_1, HASH_A, OWNER_B, JSON.stringify(CONTRIBUTION), 3, 65]);
    assertEquals(takeover.kind, "claimed");
    await assertRejects(
      () => rpc(db, "settle_opener_generation", [USER_ID, sessionId, GEN_1, OWNER_A, JSON.stringify(RESULT), 30, 10, true, 3]),
      Error,
      "OPENER_OPERATION_OWNER_MISMATCH",
    );
    assertEquals(await usage(db), { monthly: 0, daily: 0 });
    const settled = await rpc(db, "settle_opener_generation", [USER_ID, sessionId, GEN_1, OWNER_B, JSON.stringify({ ...RESULT, openers: { ...RESULT.openers, extend: "接手者的句子" } }), 30, 10, true, 3]);
    assertEquals(settled.chargedNow, 3);
    // 舊 owner 事後再 settle → 已 done 回存檔（接手者的結果），不覆蓋。
    const late = await rpc(db, "settle_opener_generation", [USER_ID, sessionId, GEN_1, OWNER_A, JSON.stringify(RESULT), 30, 10, true, 3]);
    assertEquals(late.replayed, true);
    assertEquals(((late.result as Record<string, unknown>).openers as Record<string, string>).extend, "接手者的句子");
  } finally {
    await db.close();
  }
});

Deno.test("B14：不同帳號猜同一 sessionId → OPENER_SESSION_INVALID，拿不到快照或結果", async () => {
  const db = await createDatabase();
  try {
    const sessionId = await readySession(db);
    await assertRejects(
      () => rpc(db, "claim_opener_generation", [OTHER_USER_ID, sessionId, GEN_1, HASH_A, OWNER_A, JSON.stringify(CONTRIBUTION), 3, 65]),
      Error,
      "OPENER_SESSION_INVALID",
    );
    await assertRejects(
      () => rpc(db, "settle_opener_generation", [OTHER_USER_ID, sessionId, GEN_1, OWNER_A, JSON.stringify(RESULT), 30, 10, true, 3]),
      Error,
      "OPENER_SESSION_INVALID",
    );
    // 他人用同一個 analysisRequestId 只會得到自己的新局，讀不到別人的快照。
    const other = await rpc(db, "claim_opener_analysis", [OTHER_USER_ID, REQ_1, HASH_A, OWNER_B, 1, 2, 65]);
    assertEquals(other.kind, "claimed");
  } finally {
    await db.close();
  }
});

Deno.test("結算拒絕形狀不對的可交付結果（推薦不在可見卡、多餘頂層鍵、空句）", async () => {
  const db = await createDatabase();
  try {
    const sessionId = await readySession(db);
    await rpc(db, "claim_opener_generation", [USER_ID, sessionId, GEN_1, HASH_A, OWNER_A, JSON.stringify(CONTRIBUTION), 3, 65]);
    for (const bad of [
      { ...RESULT, recommendation: { pick: "resonate" } },
      { ...RESULT, rawModelText: "x" },
      { ...RESULT, openers: {} },
      { ...RESULT, openers: { extend: "" } },
    ]) {
      await assertRejects(
        () => rpc(db, "settle_opener_generation", [USER_ID, sessionId, GEN_1, OWNER_A, JSON.stringify(bad), 30, 10, true, 3]),
        Error,
        "invalid p_result_json",
      );
    }
    assertEquals((await runRow(db, GEN_1))?.state, "pending");
    assertEquals(await usage(db), { monthly: 0, daily: 0 });
  } finally {
    await db.close();
  }
});

Deno.test("到期清理：ready 過期會話連同作業 CASCADE 刪除、pending 孤兒超過 1 小時刪除、其餘保留", async () => {
  const db = await createDatabase();
  try {
    const live = await readySession(db, { requestId: REQ_1 });
    const stale = await readySession(db, { requestId: REQ_2 });
    await rpc(db, "claim_opener_generation", [USER_ID, stale, GEN_1, HASH_A, OWNER_A, JSON.stringify(CONTRIBUTION), 3, 65]);
    await rpc(db, "settle_opener_generation", [USER_ID, stale, GEN_1, OWNER_A, JSON.stringify(RESULT), 30, 10, true, 3]);
    await db.query(`UPDATE public.opener_sessions SET expires_at = now() - interval '1 minute' WHERE session_id = $1`, [stale]);
    await rpc(db, "claim_opener_analysis", [OTHER_USER_ID, REQ_1, HASH_A, OWNER_B, 1, 2, 65]);
    await db.query(`UPDATE public.opener_sessions SET lease_expires_at = now() - interval '2 hours' WHERE user_id = $1`, [OTHER_USER_ID]);

    const deleted = await rpc<number>(db, "cleanup_expired_opener_sessions", []);
    assertEquals(deleted, 2);
    const remaining = await db.query<{ session_id: string }>(`SELECT session_id FROM public.opener_sessions`);
    assertEquals(remaining.rows.map((r) => r.session_id), [live]);
    const runs = await db.query<{ n: number }>(`SELECT count(*)::int AS n FROM public.opener_generation_runs`);
    assertEquals(runs.rows[0].n, 0);
  } finally {
    await db.close();
  }
});

Deno.test("anon／authenticated 不能讀兩張表、不能呼叫任何 RPC", async () => {
  const db = await createDatabase();
  try {
    const sessionId = await readySession(db);
    for (const role of ["anon", "authenticated"]) {
      await db.exec(`SET ROLE ${role}`);
      await assertRejects(() => db.query(`SELECT * FROM public.opener_sessions`), Error, "permission denied");
      await assertRejects(() => db.query(`SELECT * FROM public.opener_generation_runs`), Error, "permission denied");
      await assertRejects(
        () => rpc(db, "claim_opener_generation", [USER_ID, sessionId, GEN_1, HASH_A, OWNER_A, JSON.stringify(CONTRIBUTION), 3, 65]),
        Error,
        "permission denied",
      );
      await assertRejects(
        () => rpc(db, "claim_opener_analysis", [USER_ID, REQ_2, HASH_A, OWNER_A, 1, 2, 65]),
        Error,
        "permission denied",
      );
      await assertRejects(() => rpc(db, "cleanup_expired_opener_sessions", []), Error, "permission denied");
      await db.exec(`RESET ROLE`);
    }
  } finally {
    await db.close();
  }
});

// ── R1 回歸（2026-09-17 第一輪獨立複核 BLOCK）：同局工作資格必須涵蓋不同 generationId
// 的接手、settle 的租約 fencing、過期 run 重新 claim 的上限、release 不得抹掉輸入身分。
// reviewer 的 SQL 候選檔未收到；以下是依審查描述自行寫的等價回歸。

Deno.test("R1-a：G1 租約過期→G2 取得同局資格→G1 重試不得再 claimed（session_busy）", async () => {
  const db = await createDatabase();
  try {
    const sessionId = await readySession(db);
    await rpc(db, "claim_opener_generation", [USER_ID, sessionId, GEN_1, HASH_A, OWNER_A, JSON.stringify(CONTRIBUTION), 3, 65]);
    await db.query(`UPDATE public.opener_generation_runs SET lease_expires_at = now() - interval '1 second' WHERE generation_id = $1`, [GEN_1]);
    const g2 = await rpc(db, "claim_opener_generation", [USER_ID, sessionId, GEN_2, HASH_B, OWNER_B, JSON.stringify(CONTRIBUTION), 3, 65]);
    assertEquals(g2.kind, "claimed");
    // G1 同 owner 重試（renewal 路徑）與他人接手（takeover 路徑）都不得拿到資格。
    const retrySameOwner = await rpc(db, "claim_opener_generation", [USER_ID, sessionId, GEN_1, HASH_A, OWNER_A, JSON.stringify(CONTRIBUTION), 3, 65]);
    assertEquals(retrySameOwner.kind, "session_busy");
    assertEquals(retrySameOwner.generationId, GEN_2);
    const takeover = await rpc(db, "claim_opener_generation", [USER_ID, sessionId, GEN_1, HASH_A, "2c2c2c2c-2c2c-4c2c-8c2c-2c2c2c2c2c2c", JSON.stringify(CONTRIBUTION), 3, 65]);
    assertEquals(takeover.kind, "session_busy");
    const pending = await db.query<{ n: number }>(`SELECT count(*)::int AS n FROM public.opener_generation_runs WHERE state = 'pending' AND lease_expires_at > now()`);
    assertEquals(pending.rows[0].n, 1, "同局同時只能有一個有效租約");
  } finally {
    await db.close();
  }
});

Deno.test("R1-b：租約過期的作業不得結算；G2 接手同局後 G1 原 owner 晚回也不得結算", async () => {
  const db = await createDatabase();
  try {
    const sessionId = await readySession(db);
    await rpc(db, "claim_opener_generation", [USER_ID, sessionId, GEN_1, HASH_A, OWNER_A, JSON.stringify(CONTRIBUTION), 3, 65]);
    await db.query(`UPDATE public.opener_generation_runs SET lease_expires_at = now() - interval '1 second' WHERE generation_id = $1`, [GEN_1]);
    // 沒人接手、只是租約過期：不能憑 owner token 結算（fencing 在 DB commit 邊界）。
    await assertRejects(
      () => rpc(db, "settle_opener_generation", [USER_ID, sessionId, GEN_1, OWNER_A, JSON.stringify(RESULT), 30, 10, true, 3]),
      Error,
      "OPENER_OPERATION_LEASE_EXPIRED",
    );
    const g2 = await rpc(db, "claim_opener_generation", [USER_ID, sessionId, GEN_2, HASH_B, OWNER_B, JSON.stringify(CONTRIBUTION), 3, 65]);
    assertEquals(g2.kind, "claimed");
    await assertRejects(
      () => rpc(db, "settle_opener_generation", [USER_ID, sessionId, GEN_1, OWNER_A, JSON.stringify(RESULT), 30, 10, true, 3]),
      Error,
      "OPENER_OPERATION_LEASE_EXPIRED",
    );
    assertEquals(await usage(db), { monthly: 0, daily: 0 });
    assertEquals((await sessionRow(db, sessionId)).generations_used, 0);
    const settled = await rpc(db, "settle_opener_generation", [USER_ID, sessionId, GEN_2, OWNER_B, JSON.stringify(RESULT), 30, 10, true, 3]);
    assertEquals(settled.chargedNow, 3);
  } finally {
    await db.close();
  }
});

Deno.test("R1-c：三組已用完後，殘留的過期 pending run 重新 claim 也要在模型前被擋", async () => {
  const db = await createDatabase();
  try {
    const sessionId = await readySession(db);
    // GEN_4 先 claim 後租約過期（模型失敗沒 release 的殘留）。
    await rpc(db, "claim_opener_generation", [USER_ID, sessionId, GEN_4, HASH_B, OWNER_B, JSON.stringify(CONTRIBUTION), 3, 65]);
    await db.query(`UPDATE public.opener_generation_runs SET lease_expires_at = now() - interval '1 second' WHERE generation_id = $1`, [GEN_4]);
    for (const gen of [GEN_1, GEN_2, GEN_3]) {
      await rpc(db, "claim_opener_generation", [USER_ID, sessionId, gen, HASH_A, OWNER_A, JSON.stringify(CONTRIBUTION), 3, 65]);
      await rpc(db, "settle_opener_generation", [USER_ID, sessionId, gen, OWNER_A, JSON.stringify(RESULT), 30, 10, true, 3]);
    }
    await assertRejects(
      () => rpc(db, "claim_opener_generation", [USER_ID, sessionId, GEN_4, HASH_B, OWNER_B, JSON.stringify(CONTRIBUTION), 3, 65]),
      Error,
      "OPENER_GENERATION_LIMIT_REACHED",
    );
  } finally {
    await db.close();
  }
});

Deno.test("R1-d：失敗 release 只釋放執行資格，不抹掉同 ID 的輸入身分；同 ID 換輸入仍拒絕（生成與分析）", async () => {
  const db = await createDatabase();
  try {
    const sessionId = await readySession(db);
    await rpc(db, "claim_opener_generation", [USER_ID, sessionId, GEN_1, HASH_A, OWNER_A, JSON.stringify(CONTRIBUTION), 3, 65]);
    assertEquals(await rpc<boolean>(db, "release_opener_generation_claim", [USER_ID, GEN_1, OWNER_A]), true);
    await assertRejects(
      () => rpc(db, "claim_opener_generation", [USER_ID, sessionId, GEN_1, HASH_B, OWNER_B, JSON.stringify(CONTRIBUTION), 3, 65]),
      Error,
      "OPENER_OPERATION_INPUT_MISMATCH",
    );
    // 同輸入可重新取得資格；釋放中的列不算同局忙碌。
    const again = await rpc(db, "claim_opener_generation", [USER_ID, sessionId, GEN_1, HASH_A, OWNER_B, JSON.stringify(CONTRIBUTION), 3, 65]);
    assertEquals(again.kind, "claimed");
    const other = await rpc(db, "claim_opener_generation", [USER_ID, sessionId, GEN_2, HASH_B, OWNER_A, JSON.stringify(CONTRIBUTION), 3, 65]);
    assertEquals(other.kind, "session_busy");

    // 分析：release 後同 analysisRequestId 換輸入也要拒絕。
    await rpc(db, "claim_opener_analysis", [USER_ID, REQ_2, HASH_A, OWNER_A, 1, 2, 65]);
    assertEquals(await rpc<boolean>(db, "release_opener_analysis_claim", [USER_ID, REQ_2, OWNER_A]), true);
    await assertRejects(
      () => rpc(db, "claim_opener_analysis", [USER_ID, REQ_2, HASH_B, OWNER_B, 1, 2, 65]),
      Error,
      "OPENER_OPERATION_INPUT_MISMATCH",
    );
    const reclaim = await rpc(db, "claim_opener_analysis", [USER_ID, REQ_2, HASH_A, OWNER_B, 1, 2, 65]);
    assertEquals(reclaim.kind, "claimed");
  } finally {
    await db.close();
  }
});
