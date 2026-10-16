// Analyze Phase 1a 的真 Postgres 契約測試：no-send 決策的扣費、約束與 retry lease。
//
// 用 PGlite（WASM Postgres）直接套用 analysis_stream_runs 全部 migration 原始 SQL，
// 所以同時是「SQL 真的能套用在既有 schema 上」的煙霧測試。只有真 Postgres 才驗得出
// CHECK 改寫是否放行舊資料、v1 RPC 是否一字未變、v2 RPC 的 exactly-once 與
// retry lease 是否認得 no-send。範式沿用 moments_migration_postgres_test.ts。
import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import {
  assert,
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

const MIGRATIONS = [
  "20260603120000_analysis_stream_runs.sql",
  "20260603120100_charge_stream_analysis_run.sql",
  "20260603120200_stream_analysis_retry_budget.sql",
  "20260813003000_stream_analysis_retry_lease.sql",
  "20260902120000_analysis_stream_runs_decision_kind.sql",
  // 正式環境的 cleanup 是這份 retention 版本（扣費 30 天後清），測試要驗的是它
  // （第 0 片審查第 1 輪）。pg_cron 排程靠下面的 GUC 在 PGlite 跳過。
  "20260902160000_retention_cleanup_schedules.sql",
  // 第 3 階段第 0 片（v3 任務卡）。放進同一份清單：上面 v1、v2、retry lease 的測試
  // 因此也在套上它之後重跑，證明它沒改到舊行為。
  "20261016120000_analysis_stream_runs_card_task.sql",
];

const migrationSql = await Promise.all(
  MIGRATIONS.map((name) =>
    Deno.readTextFile(new URL(`../../migrations/${name}`, import.meta.url))
  ),
);

const USER_ID = "11111111-2222-3333-4444-555555555555";
const OTHER_USER_ID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
const HASH = "conversation-hash-1";

const NO_SEND_RECOMMENDATION: Record<string, unknown> = {
  decisionKind: "do_not_send",
  action: "pause",
  reason: "最新片段沒有新增內容或互動窗口",
  stopCondition: "等待對方主動新增內容",
  raw: { type: "analysis.decision", schemaVersion: 2 },
};

const SEND_RECOMMENDATION = {
  selectedStyle: "extend",
  message: "那家排超久是哪一家？",
  raw: { type: "analysis.decision" },
};

interface RunRow {
  id: string;
  status: string;
  selected_style: string | null;
  decision_kind: string | null;
  charged_at: string | null;
  retry_count: number;
  recommendation_json: Record<string, unknown> | null;
  card_task: string | null;
}

async function createDatabase(
  migrations: readonly string[] = migrationSql,
): Promise<PGlite> {
  const db = new PGlite();
  // 忠實重現 Supabase 的角色與預設授權，migration 內的 REVOKE 才驗得準。
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
    INSERT INTO auth.users (id) VALUES ('${USER_ID}'), ('${OTHER_USER_ID}');
    -- 扣費 RPC 只 PERFORM increment_usage；這裡用可計數的替身取代真 quota 表。
    CREATE TABLE usage_calls (user_id UUID NOT NULL, message_count INTEGER NOT NULL);
    CREATE FUNCTION public.increment_usage(p_user_id UUID, p_message_count INTEGER)
    RETURNS VOID LANGUAGE sql AS $$
      INSERT INTO usage_calls (user_id, message_count) VALUES (p_user_id, p_message_count);
    $$;
    -- retention migration 會改寫 ai_logs 的清理函式：照 retention 測試放替身。
    CREATE TABLE public.ai_logs (id SERIAL PRIMARY KEY, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE OR REPLACE FUNCTION cleanup_old_ai_logs()
    RETURNS void AS $$ BEGIN DELETE FROM ai_logs WHERE created_at < NOW() - INTERVAL '30 days'; END; $$ LANGUAGE plpgsql;
  `);
  await db.exec("SET app.allow_missing_pg_cron = 'pglite-contract-test'");
  for (const sql of migrations) {
    await db.exec(sql);
  }
  return db;
}

async function createPendingRun(
  db: PGlite,
  userId = USER_ID,
  hash = HASH,
): Promise<string> {
  const result = await db.query<{ id: string }>(
    `INSERT INTO public.analysis_stream_runs (user_id, conversation_hash)
     VALUES ($1, $2) RETURNING id`,
    [userId, hash],
  );
  return result.rows[0].id;
}

async function getRun(db: PGlite, runId: string): Promise<RunRow> {
  const result = await db.query<RunRow>(
    `SELECT id, status, selected_style, decision_kind, charged_at, retry_count,
            recommendation_json, card_task
       FROM public.analysis_stream_runs WHERE id = $1`,
    [runId],
  );
  return result.rows[0];
}

async function usageCalls(db: PGlite, userId = USER_ID): Promise<number> {
  const result = await db.query<{ n: number }>(
    `SELECT count(*)::int AS n FROM usage_calls WHERE user_id = $1`,
    [userId],
  );
  return result.rows[0].n;
}

function chargeV2(
  db: PGlite,
  args: {
    runId: string;
    userId?: string;
    hash?: string;
    recommendation: Record<string, unknown>;
    decisionKind: string | null;
    selectedStyle?: string | null;
    messageCount?: number;
    chargeQuota?: boolean;
  },
) {
  return db.query<RunRow>(
    `SELECT * FROM public.charge_stream_analysis_run_v2(
       p_run_id => $1, p_user_id => $2, p_conversation_hash => $3,
       p_recommendation_json => $4, p_decision_kind => $5,
       p_selected_style => $6, p_message_count => $7, p_charge_quota => $8)`,
    [
      args.runId,
      args.userId ?? USER_ID,
      args.hash ?? HASH,
      JSON.stringify(args.recommendation),
      args.decisionKind,
      args.selectedStyle ?? null,
      args.messageCount ?? 1,
      args.chargeQuota ?? true,
    ],
  );
}

function reserveRetry(db: PGlite, runId: string) {
  return db.query<RunRow>(
    `SELECT * FROM public.reserve_stream_analysis_retry($1, $2, $3, 2)`,
    [runId, USER_ID, HASH],
  );
}

async function markFailed(db: PGlite, runId: string) {
  await db.query(
    `UPDATE public.analysis_stream_runs SET status = 'failed', last_error_code = 'x'
      WHERE id = $1`,
    [runId],
  );
}

Deno.test("migration applies on top of the existing stream run schema", async () => {
  const db = await createDatabase();
  try {
    const columns = await db.query<{ column_name: string }>(
      `SELECT column_name FROM information_schema.columns
        WHERE table_name = 'analysis_stream_runs' AND column_name = 'decision_kind'`,
    );
    assertEquals(columns.rows.length, 1);
  } finally {
    await db.close();
  }
});

Deno.test("charged CHECK keeps legacy send rows and admits no-send rows", async () => {
  const db = await createDatabase();
  try {
    const insertCharged = (
      style: string | null,
      kind: string | null,
    ) =>
      db.query(
        `INSERT INTO public.analysis_stream_runs
           (user_id, conversation_hash, status, charged_at, recommendation_json,
            selected_style, decision_kind)
         VALUES ($1, $2, 'charged', now(), '{"x":1}'::jsonb, $3, $4)`,
        [USER_ID, HASH, style, kind],
      );

    // 舊資料形狀：有風格、decision_kind NULL。
    await insertCharged("extend", null);
    // 舊資料形狀加上明確 send。
    await insertCharged("tease", "send");
    // 新形狀：三種 no-send 都不帶風格。
    await insertCharged(null, "do_not_send");
    await insertCharged(null, "acknowledge_and_stop");
    await insertCharged(null, "need_context");

    // 已扣費卻既無風格也非 no-send：仍然違規。
    await assertRejects(
      () => insertCharged(null, null),
      Error,
      "analysis_stream_runs_charged_has_recommendation",
    );
    await assertRejects(
      () => insertCharged(null, "send"),
      Error,
      "analysis_stream_runs_charged_has_recommendation",
    );
    // no-send 不得帶風格。
    await assertRejects(
      () => insertCharged("extend", "do_not_send"),
      Error,
      "analysis_stream_runs_no_send_has_no_style",
    );
    // 未知決策種類（用未扣費列驗，避免同時撞到 charged 約束）。
    await assertRejects(
      () =>
        db.query(
          `INSERT INTO public.analysis_stream_runs (user_id, conversation_hash, decision_kind)
           VALUES ($1, $2, 'maybe')`,
          [USER_ID, HASH],
        ),
      Error,
      "analysis_stream_runs_decision_kind_check",
    );
  } finally {
    await db.close();
  }
});

Deno.test("v1 charge RPC is unchanged and leaves decision_kind NULL", async () => {
  const db = await createDatabase();
  try {
    const runId = await createPendingRun(db);
    const result = await db.query<RunRow>(
      `SELECT * FROM public.charge_stream_analysis_run($1, $2, $3, $4, 'extend', 1, true)`,
      [runId, USER_ID, HASH, JSON.stringify(SEND_RECOMMENDATION)],
    );
    assertEquals(result.rows[0].status, "charged");
    assertEquals(result.rows[0].selected_style, "extend");
    assertEquals(result.rows[0].decision_kind, null);
    assertEquals(await usageCalls(db), 1);

    // v1 仍拒絕 no-send 形狀（它根本不認得 decision_kind）。
    const other = await createPendingRun(db);
    await assertRejects(
      () =>
        db.query(
          `SELECT * FROM public.charge_stream_analysis_run($1, $2, $3, $4, NULL, 1, true)`,
          [other, USER_ID, HASH, JSON.stringify(NO_SEND_RECOMMENDATION)],
        ),
      Error,
      "STREAM_INVALID_SELECTED_STYLE",
    );
  } finally {
    await db.close();
  }
});

Deno.test("v2 charge RPC validates decision kind against style and payload", async () => {
  const db = await createDatabase();
  try {
    const runId = await createPendingRun(db);
    const reject = (
      args: Parameters<typeof chargeV2>[1],
      expected: string,
    ) => assertRejects(() => chargeV2(db, args), Error, expected);

    await reject(
      { runId, recommendation: SEND_RECOMMENDATION, decisionKind: null },
      "STREAM_INVALID_DECISION_KIND",
    );
    await reject(
      { runId, recommendation: SEND_RECOMMENDATION, decisionKind: "hold" },
      "STREAM_INVALID_DECISION_KIND",
    );
    // send 一定要有合法風格。
    await reject(
      { runId, recommendation: SEND_RECOMMENDATION, decisionKind: "send" },
      "STREAM_INVALID_SELECTED_STYLE",
    );
    await reject(
      {
        runId,
        recommendation: SEND_RECOMMENDATION,
        decisionKind: "send",
        selectedStyle: "sarcastic",
      },
      "STREAM_INVALID_SELECTED_STYLE",
    );
    // send 的 JSON 若自稱 no-send，拒收。
    await reject(
      {
        runId,
        recommendation: { ...SEND_RECOMMENDATION, decisionKind: "do_not_send" },
        decisionKind: "send",
        selectedStyle: "extend",
      },
      "STREAM_MALFORMED_RECOMMENDATION",
    );
    // no-send 不得帶風格。
    await reject(
      {
        runId,
        recommendation: NO_SEND_RECOMMENDATION,
        decisionKind: "do_not_send",
        selectedStyle: "extend",
      },
      "STREAM_INVALID_SELECTED_STYLE",
    );
    // no-send 空殼決策不准扣費：decisionKind 不符、缺 action／reason／stopCondition。
    await reject(
      {
        runId,
        recommendation: {
          ...NO_SEND_RECOMMENDATION,
          decisionKind: "need_context",
        },
        decisionKind: "do_not_send",
      },
      "STREAM_MALFORMED_RECOMMENDATION",
    );
    for (const field of ["action", "reason", "stopCondition"]) {
      await reject(
        {
          runId,
          recommendation: { ...NO_SEND_RECOMMENDATION, [field]: "  " },
          decisionKind: "do_not_send",
        },
        "STREAM_MALFORMED_RECOMMENDATION",
      );
      const { [field]: _dropped, ...without } = NO_SEND_RECOMMENDATION;
      await reject(
        { runId, recommendation: without, decisionKind: "do_not_send" },
        "STREAM_MALFORMED_RECOMMENDATION",
      );
    }
    await reject(
      {
        runId,
        recommendation: NO_SEND_RECOMMENDATION,
        decisionKind: "do_not_send",
        messageCount: 0,
      },
      "p_message_count must be positive",
    );

    // 以上全部在扣費前就擋下：既沒扣額度、也沒動 run。
    assertEquals(await usageCalls(db), 0);
    assertEquals((await getRun(db, runId)).status, "pending");
  } finally {
    await db.close();
  }
});

Deno.test("v2 charge RPC charges a no-send decision exactly once", async () => {
  const db = await createDatabase();
  try {
    const runId = await createPendingRun(db);
    const first = await chargeV2(db, {
      runId,
      recommendation: NO_SEND_RECOMMENDATION,
      decisionKind: "do_not_send",
    });
    assertEquals(first.rows[0].status, "charged");
    assertEquals(first.rows[0].decision_kind, "do_not_send");
    assertEquals(first.rows[0].selected_style, null);
    assert(first.rows[0].charged_at !== null);
    assertEquals(first.rows[0].recommendation_json, NO_SEND_RECOMMENDATION);
    assertEquals(await usageCalls(db), 1);

    // 重送只回放，不再扣費、不改狀態——不管第二次送的是改口成 send、
    // 空殼 no-send、非法 decision kind 還是 message_count 0。
    for (
      const replayArgs of [
        {
          recommendation: SEND_RECOMMENDATION,
          decisionKind: "send",
          selectedStyle: "extend",
        },
        {
          recommendation: { decisionKind: "do_not_send" },
          decisionKind: "do_not_send",
        },
        { recommendation: NO_SEND_RECOMMENDATION, decisionKind: "bogus" },
        { recommendation: NO_SEND_RECOMMENDATION, decisionKind: null },
        {
          recommendation: NO_SEND_RECOMMENDATION,
          decisionKind: "do_not_send",
          messageCount: 0,
        },
      ]
    ) {
      const replay = await chargeV2(db, { runId, ...replayArgs });
      assertEquals(replay.rows[0].decision_kind, "do_not_send");
      assertEquals(replay.rows[0].selected_style, null);
      assertEquals(replay.rows[0].recommendation_json, NO_SEND_RECOMMENDATION);
      assertEquals(await usageCalls(db), 1);
    }
    // 但 owner／conversation 不符仍然擋，不會把別人的 run 回放出去。
    await assertRejects(
      () =>
        chargeV2(db, {
          runId,
          recommendation: NO_SEND_RECOMMENDATION,
          decisionKind: "do_not_send",
          userId: OTHER_USER_ID,
        }),
      Error,
      "STREAM_RUN_OWNER_MISMATCH",
    );

    // send 走 v2 也會記下 decision_kind。
    const sendRun = await createPendingRun(db);
    const send = await chargeV2(db, {
      runId: sendRun,
      recommendation: SEND_RECOMMENDATION,
      decisionKind: "send",
      selectedStyle: "extend",
    });
    assertEquals(send.rows[0].decision_kind, "send");
    assertEquals(send.rows[0].selected_style, "extend");
    assertEquals(await usageCalls(db), 2);

    // retry／resume 附掛時 p_charge_quota=false：記錄決策但不扣額度。
    const freeRun = await createPendingRun(db);
    await chargeV2(db, {
      runId: freeRun,
      recommendation: NO_SEND_RECOMMENDATION,
      decisionKind: "do_not_send",
      chargeQuota: false,
    });
    assertEquals((await getRun(db, freeRun)).status, "charged");
    assertEquals(await usageCalls(db), 2);
  } finally {
    await db.close();
  }
});

Deno.test("v2 charge RPC keeps the v1 ownership and lifecycle guards", async () => {
  const db = await createDatabase();
  try {
    const runId = await createPendingRun(db);
    const base = {
      runId,
      recommendation: NO_SEND_RECOMMENDATION,
      decisionKind: "do_not_send",
    };
    await assertRejects(
      () => chargeV2(db, { ...base, userId: OTHER_USER_ID }),
      Error,
      "STREAM_RUN_OWNER_MISMATCH",
    );
    await assertRejects(
      () => chargeV2(db, { ...base, hash: "another-hash" }),
      Error,
      "RUN_CONVERSATION_MISMATCH",
    );
    await assertRejects(
      () =>
        chargeV2(db, {
          ...base,
          runId: "00000000-0000-0000-0000-000000000000",
        }),
      Error,
      "STREAM_RUN_NOT_FOUND",
    );

    await markFailed(db, runId);
    await assertRejects(
      () => chargeV2(db, base),
      Error,
      "STREAM_RUN_NOT_PENDING",
    );

    const expired = await createPendingRun(db);
    await db.query(
      `UPDATE public.analysis_stream_runs SET expires_at = now() - interval '1 minute' WHERE id = $1`,
      [expired],
    );
    await assertRejects(
      () => chargeV2(db, { ...base, runId: expired }),
      Error,
      "STREAM_RUN_EXPIRED",
    );
    assertEquals(await usageCalls(db), 0);
  } finally {
    await db.close();
  }
});

Deno.test("retry lease admits charged no-send runs and still refuses uncharged ones", async () => {
  const db = await createDatabase();
  try {
    const noSend = await createPendingRun(db);
    await chargeV2(db, {
      runId: noSend,
      recommendation: NO_SEND_RECOMMENDATION,
      decisionKind: "do_not_send",
    });
    await markFailed(db, noSend);
    const leased = await reserveRetry(db, noSend);
    assertEquals(leased.rows[0].status, "charged");
    assertEquals(leased.rows[0].retry_count, 1);
    assertEquals(leased.rows[0].decision_kind, "do_not_send");

    // 舊 v1 send run 的 lease 行為不變。
    const legacy = await createPendingRun(db);
    await db.query(
      `SELECT * FROM public.charge_stream_analysis_run($1, $2, $3, $4, 'extend', 1, true)`,
      [legacy, USER_ID, HASH, JSON.stringify(SEND_RECOMMENDATION)],
    );
    await markFailed(db, legacy);
    assertEquals((await reserveRetry(db, legacy)).rows[0].retry_count, 1);

    // 未扣費的 failed run 仍不可 retry。
    const uncharged = await createPendingRun(db);
    await markFailed(db, uncharged);
    await assertRejects(
      () => reserveRetry(db, uncharged),
      Error,
      "STREAM_RETRY_NOT_AVAILABLE",
    );

    // 額度用盡（max 2）後不再放行。
    await markFailed(db, noSend);
    await reserveRetry(db, noSend);
    await markFailed(db, noSend);
    await assertRejects(
      () => reserveRetry(db, noSend),
      Error,
      "STREAM_RETRY_NOT_AVAILABLE",
    );
  } finally {
    await db.close();
  }
});

Deno.test("cleanup keeps charged no-send runs durable", async () => {
  const db = await createDatabase();
  try {
    const noSend = await createPendingRun(db);
    await chargeV2(db, {
      runId: noSend,
      recommendation: NO_SEND_RECOMMENDATION,
      decisionKind: "do_not_send",
    });
    const abandoned = await createPendingRun(db);
    await db.query(
      `UPDATE public.analysis_stream_runs SET expires_at = now() - interval '2 hours'
        WHERE id = ANY($1::uuid[])`,
      [[noSend, abandoned]],
    );
    const deleted = await db.query<{ n: number }>(
      `SELECT public.cleanup_expired_analysis_stream_runs() AS n`,
    );
    assertEquals(deleted.rows[0].n, 1);
    assertEquals((await getRun(db, noSend)).status, "charged");
  } finally {
    await db.close();
  }
});

Deno.test("v2 charge RPC is service-role only", async () => {
  const db = await createDatabase();
  try {
    const signature =
      "public.charge_stream_analysis_run_v2(uuid, uuid, text, jsonb, text, text, integer, boolean)";
    const privileges = await db.query<{ role: string; allowed: boolean }>(
      `SELECT role, has_function_privilege(role, $1, 'EXECUTE') AS allowed
         FROM unnest(ARRAY['anon', 'authenticated', 'service_role']) AS role`,
      [signature],
    );
    assertEquals(
      Object.fromEntries(privileges.rows.map((row) => [row.role, row.allowed])),
      { anon: false, authenticated: false, service_role: true },
    );
  } finally {
    await db.close();
  }
});

// ---------------------------------------------------------------------------
// 第 3 階段第 0 片：v3 任務卡（migration 20261016120000）

const V3_SEND_RECOMMENDATION: Record<string, unknown> = {
  decisionKind: "send",
  cardTask: "accept",
  guideVersion: "v3.3",
  message: "有啊，願意試新口味這點我很欣賞",
};

function chargeV3(
  db: PGlite,
  args: {
    runId: string;
    userId?: string;
    hash?: string;
    recommendation: Record<string, unknown> | null;
    decisionKind: string | null;
    cardTask?: string | null;
    messageCount?: number | null;
    chargeQuota?: boolean;
  },
) {
  return db.query<RunRow>(
    `SELECT * FROM public.charge_stream_analysis_run_v3(
       p_run_id => $1, p_user_id => $2, p_conversation_hash => $3,
       p_recommendation_json => $4, p_decision_kind => $5,
       p_card_task => $6, p_message_count => $7, p_charge_quota => $8)`,
    [
      args.runId,
      args.userId ?? USER_ID,
      args.hash ?? HASH,
      args.recommendation === null ? null : JSON.stringify(args.recommendation),
      args.decisionKind,
      args.cardTask ?? null,
      args.messageCount === undefined ? 1 : args.messageCount,
      args.chargeQuota ?? true,
    ],
  );
}

async function functionDefs(db: PGlite): Promise<Record<string, string>> {
  const result = await db.query<{ name: string; def: string }>(
    `SELECT p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS name,
            pg_get_functiondef(p.oid) AS def
       FROM pg_proc p
       JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.proname IN ('charge_stream_analysis_run', 'charge_stream_analysis_run_v2',
                          'reserve_stream_analysis_retry',
                          'cleanup_expired_analysis_stream_runs')`,
  );
  return Object.fromEntries(result.rows.map((row) => [row.name, row.def]));
}

Deno.test("card_task migration leaves v1, v2, retry lease and cleanup function bodies unchanged", async () => {
  const before = await createDatabase(migrationSql.slice(0, -1));
  const after = await createDatabase();
  try {
    const beforeDefs = await functionDefs(before);
    assertEquals(Object.keys(beforeDefs).length, 4);
    assertEquals(await functionDefs(after), beforeDefs);
    const columns = await after.query<{ column_name: string }>(
      `SELECT column_name FROM information_schema.columns
        WHERE table_name = 'analysis_stream_runs' AND column_name = 'card_task'`,
    );
    assertEquals(columns.rows.length, 1);
  } finally {
    await before.close();
    await after.close();
  }
});

Deno.test("charged CHECK admits v3 send rows with a matching task card and keeps card_task off styled and no-send rows", async () => {
  const db = await createDatabase();
  try {
    const insert = (
      style: string | null,
      kind: string | null,
      task: string | null,
      recommendation: unknown = { x: 1 },
    ) =>
      db.query(
        `INSERT INTO public.analysis_stream_runs
           (user_id, conversation_hash, status, charged_at, recommendation_json,
            selected_style, decision_kind, card_task)
         VALUES ($1, $2, 'charged', now(), $3::jsonb, $4, $5, $6)`,
        [USER_ID, HASH, JSON.stringify(recommendation), style, kind, task],
      );
    const v3 = (task: string) => ({ decisionKind: "send", cardTask: task });
    // v3 送出型：沒有風格、有任務卡、內容一致。
    await insert(null, "send", "push", v3("push"));
    // 舊列照舊合法。
    await insert("extend", null, null);
    await insert(null, "do_not_send", null);
    // 扣過費的送出型兩個都沒有 → 擋。
    await assertRejects(
      () => insert(null, "send", null),
      Error,
      "analysis_stream_runs_charged_has_recommendation",
    );
    // 任務卡不能跟風格並存、不能在不送型或舊的 NULL 決策上、不能是未知值。
    await assertRejects(
      () => insert("extend", "send", "accept", v3("accept")),
      Error,
      "analysis_stream_runs_card_task_send_only",
    );
    await assertRejects(
      () => insert(null, "do_not_send", "accept", v3("accept")),
      Error,
      "analysis_stream_runs_card_task_send_only",
    );
    await assertRejects(
      () => insert(null, null, "accept", v3("accept")),
      Error,
      "analysis_stream_runs_card_task_send_only",
    );
    await assertRejects(
      () => insert(null, "send", "flirt", v3("flirt")),
      Error,
      "analysis_stream_runs_card_task_check",
    );
    // 第 0 片審查第 1 輪：任務卡列的內容要跟欄位一致（缺欄位、JSON null、不是物件都擋）。
    for (
      const bad of [
        { x: 1 },
        { decisionKind: "send" },
        { cardTask: "push" },
        { decisionKind: "do_not_send", cardTask: "push" },
        { decisionKind: "send", cardTask: "accept" },
        null,
        ["send", "push"],
      ]
    ) {
      await assertRejects(
        () => insert(null, "send", "push", bad),
        Error,
        "analysis_stream_runs_card_task_recommendation",
      );
    }
  } finally {
    await db.close();
  }
});

Deno.test("v3 charge RPC charges a send run exactly once on its first card", async () => {
  const db = await createDatabase();
  try {
    const runId = await createPendingRun(db);
    const first = await chargeV3(db, {
      runId,
      recommendation: V3_SEND_RECOMMENDATION,
      decisionKind: "send",
      cardTask: "accept",
    });
    assertEquals(first.rows[0].status, "charged");
    assertEquals(first.rows[0].selected_style, null);
    assertEquals(first.rows[0].decision_kind, "send");
    assertEquals(first.rows[0].card_task, "accept");
    assert(first.rows[0].charged_at !== null);
    assertEquals(await usageCalls(db), 1);

    // 第二次（不同內容）照回已存的列，不再扣。
    const replay = await chargeV3(db, {
      runId,
      recommendation: { ...V3_SEND_RECOMMENDATION, cardTask: "push" },
      decisionKind: "send",
      cardTask: "push",
    });
    assertEquals(replay.rows[0].card_task, "accept");
    assertEquals(replay.rows[0].recommendation_json, V3_SEND_RECOMMENDATION);
    assertEquals(await usageCalls(db), 1);
  } finally {
    await db.close();
  }
});

Deno.test("v3 charge RPC validates the task card and payload before charging", async () => {
  const db = await createDatabase();
  try {
    const runId = await createPendingRun(db);
    const reject = (
      args: Omit<Parameters<typeof chargeV3>[1], "runId">,
      expected: string,
    ) => assertRejects(() => chargeV3(db, { runId, ...args }), Error, expected);

    await reject({
      recommendation: null,
      decisionKind: "send",
      cardTask: "accept",
    }, "STREAM_MALFORMED_RECOMMENDATION");
    await reject({
      recommendation: V3_SEND_RECOMMENDATION,
      decisionKind: null,
      cardTask: "accept",
    }, "STREAM_INVALID_DECISION_KIND");
    await reject({
      recommendation: V3_SEND_RECOMMENDATION,
      decisionKind: "hold",
      cardTask: "accept",
    }, "STREAM_INVALID_DECISION_KIND");
    await reject({
      recommendation: V3_SEND_RECOMMENDATION,
      decisionKind: "send",
      cardTask: null,
    }, "STREAM_INVALID_CARD_TASK");
    await reject({
      recommendation: V3_SEND_RECOMMENDATION,
      decisionKind: "send",
      cardTask: "extend",
    }, "STREAM_INVALID_CARD_TASK");
    await reject({
      recommendation: V3_SEND_RECOMMENDATION,
      decisionKind: "send",
      cardTask: "push",
    }, "STREAM_MALFORMED_RECOMMENDATION");
    await reject(
      {
        recommendation: {
          ...V3_SEND_RECOMMENDATION,
          decisionKind: "do_not_send",
        },
        decisionKind: "send",
        cardTask: "accept",
      },
      "STREAM_MALFORMED_RECOMMENDATION",
    );
    await reject(
      {
        recommendation: V3_SEND_RECOMMENDATION,
        decisionKind: "send",
        cardTask: "accept",
        messageCount: 0,
      },
      "p_message_count must be positive when charging",
    );
    // 驗證失敗不扣、列仍是 pending。
    assertEquals(await usageCalls(db), 0);
    assertEquals((await getRun(db, runId)).status, "pending");
  } finally {
    await db.close();
  }
});

Deno.test("v3 charge RPC handles no-send like v2 and refuses a task card on it", async () => {
  const db = await createDatabase();
  try {
    const runId = await createPendingRun(db);
    await assertRejects(
      () =>
        chargeV3(db, {
          runId,
          recommendation: NO_SEND_RECOMMENDATION,
          decisionKind: "do_not_send",
          cardTask: "accept",
        }),
      Error,
      "STREAM_INVALID_CARD_TASK",
    );
    await assertRejects(
      () =>
        chargeV3(db, {
          runId,
          recommendation: { ...NO_SEND_RECOMMENDATION, stopCondition: " " },
          decisionKind: "do_not_send",
        }),
      Error,
      "STREAM_MALFORMED_RECOMMENDATION",
    );
    const charged = await chargeV3(db, {
      runId,
      recommendation: NO_SEND_RECOMMENDATION,
      decisionKind: "do_not_send",
    });
    assertEquals(charged.rows[0].decision_kind, "do_not_send");
    assertEquals(charged.rows[0].card_task, null);
    assertEquals(charged.rows[0].selected_style, null);
    assertEquals(await usageCalls(db), 1);
  } finally {
    await db.close();
  }
});

Deno.test("v3 charge RPC keeps ownership, hash, pending, expiry and test-account guards", async () => {
  const db = await createDatabase();
  try {
    const send = {
      recommendation: V3_SEND_RECOMMENDATION,
      decisionKind: "send",
      cardTask: "accept",
    };
    await assertRejects(
      () =>
        chargeV3(db, {
          runId: "00000000-0000-0000-0000-000000000000",
          ...send,
        }),
      Error,
      "STREAM_RUN_NOT_FOUND",
    );
    const runId = await createPendingRun(db);
    await assertRejects(
      () => chargeV3(db, { runId, userId: OTHER_USER_ID, ...send }),
      Error,
      "STREAM_RUN_OWNER_MISMATCH",
    );
    await assertRejects(
      () => chargeV3(db, { runId, hash: "other-hash", ...send }),
      Error,
      "RUN_CONVERSATION_MISMATCH",
    );

    const failed = await createPendingRun(db);
    await markFailed(db, failed);
    await assertRejects(
      () => chargeV3(db, { runId: failed, ...send }),
      Error,
      "STREAM_RUN_NOT_PENDING",
    );

    const expired = await createPendingRun(db);
    await db.query(
      `UPDATE public.analysis_stream_runs SET expires_at = now() - interval '1 minute' WHERE id = $1`,
      [expired],
    );
    await assertRejects(
      () => chargeV3(db, { runId: expired, ...send }),
      Error,
      "STREAM_RUN_EXPIRED",
    );

    // 測試帳號：不扣用量，但一樣進 charged；不扣時 message_count 不檢查。
    const testAccount = await chargeV3(db, {
      runId,
      ...send,
      chargeQuota: false,
      messageCount: 0,
    });
    assertEquals(testAccount.rows[0].status, "charged");
    assertEquals(await usageCalls(db), 0);
  } finally {
    await db.close();
  }
});

Deno.test("failed v3 send runs are not leasable for retry and charged ones survive cleanup", async () => {
  const db = await createDatabase();
  try {
    const runId = await createPendingRun(db);
    await chargeV3(db, {
      runId,
      recommendation: V3_SEND_RECOMMENDATION,
      decisionKind: "send",
      cardTask: "accept",
    });
    await markFailed(db, runId);
    await assertRejects(
      () => reserveRetry(db, runId),
      Error,
      "STREAM_RETRY_NOT_AVAILABLE",
    );

    const abandoned = await createPendingRun(db);
    await db.query(
      `UPDATE public.analysis_stream_runs SET expires_at = now() - interval '2 hours'
        WHERE id = ANY($1::uuid[])`,
      [[runId, abandoned]],
    );
    const deleted = await db.query<{ n: number }>(
      `SELECT public.cleanup_expired_analysis_stream_runs() AS n`,
    );
    assertEquals(deleted.rows[0].n, 1);
    assertEquals((await getRun(db, runId)).card_task, "accept");
  } finally {
    await db.close();
  }
});

Deno.test("v3 charge RPC is service-role only", async () => {
  const db = await createDatabase();
  try {
    const signature =
      "public.charge_stream_analysis_run_v3(uuid, uuid, text, jsonb, text, text, integer, boolean)";
    const privileges = await db.query<{ role: string; allowed: boolean }>(
      `SELECT role, has_function_privilege(role, $1, 'EXECUTE') AS allowed
         FROM unnest(ARRAY['anon', 'authenticated', 'service_role']) AS role`,
      [signature],
    );
    assertEquals(
      Object.fromEntries(privileges.rows.map((row) => [row.role, row.allowed])),
      { anon: false, authenticated: false, service_role: true },
    );
  } finally {
    await db.close();
  }
});

Deno.test("legacy rows present before the card_task migration stay untouched; its CHECKs skip the old rows but bind new writes", async () => {
  const db = await createDatabase(migrationSql.slice(0, -1));
  try {
    const legacy = await createPendingRun(db);
    await db.query(
      `SELECT * FROM public.charge_stream_analysis_run($1, $2, $3, $4, 'extend', 1, true)`,
      [legacy, USER_ID, HASH, JSON.stringify(SEND_RECOMMENDATION)],
    );
    const noSend = await createPendingRun(db);
    await chargeV2(db, {
      runId: noSend,
      recommendation: NO_SEND_RECOMMENDATION,
      decisionKind: "do_not_send",
    });
    const pending = await createPendingRun(db);
    const snapshot = async () =>
      (await db.query(
        `SELECT id, status, selected_style, decision_kind, charged_at::text AS charged_at,
                recommendation_json
           FROM public.analysis_stream_runs ORDER BY id`,
      )).rows;
    const before = await snapshot();
    assertEquals(before.length, 3);

    await db.exec(migrationSql[migrationSql.length - 1]);

    assertEquals(await snapshot(), before);
    assertEquals((await getRun(db, pending)).status, "pending");
    const constraints = await db.query<
      { conname: string; convalidated: boolean }
    >(
      `SELECT conname, convalidated FROM pg_constraint
        WHERE conrelid = 'public.analysis_stream_runs'::regclass
          AND conname IN ('analysis_stream_runs_card_task_check',
                          'analysis_stream_runs_card_task_send_only',
                          'analysis_stream_runs_card_task_recommendation',
                          'analysis_stream_runs_charged_has_recommendation')
        ORDER BY conname`,
    );
    assertEquals(constraints.rows.map((r) => [r.conname, r.convalidated]), [
      ["analysis_stream_runs_card_task_check", false],
      ["analysis_stream_runs_card_task_recommendation", false],
      ["analysis_stream_runs_card_task_send_only", false],
      ["analysis_stream_runs_charged_has_recommendation", false],
    ]);
    // NOT VALID 只是不掃舊列；之後的寫入照樣擋（哪一條任務卡 CHECK 先報都算）。
    await assertRejects(
      () =>
        db.query(
          `UPDATE public.analysis_stream_runs SET card_task = 'accept' WHERE id = $1`,
          [legacy],
        ),
      Error,
      'violates check constraint "analysis_stream_runs_card_task',
    );
  } finally {
    await db.close();
  }
});

Deno.test("v3 replay keys on charged_at, ignores an invalid second payload and still checks owner and hash first", async () => {
  const db = await createDatabase();
  try {
    const runId = await createPendingRun(db);
    await chargeV3(db, {
      runId,
      recommendation: V3_SEND_RECOMMENDATION,
      decisionKind: "send",
      cardTask: "accept",
    });
    // 第二次帶不合法的內容：照回已存的列，不驗證、不再扣。
    const replay = await chargeV3(db, {
      runId,
      recommendation: null,
      decisionKind: "hold",
      cardTask: "flirt",
      messageCount: 0,
    });
    assertEquals(replay.rows[0].card_task, "accept");
    assertEquals(await usageCalls(db), 1);
    // 扣過費之後就算 status 變成 failed，也是照回（看 charged_at，不看 status）。
    await markFailed(db, runId);
    const afterFail = await chargeV3(db, {
      runId,
      recommendation: V3_SEND_RECOMMENDATION,
      decisionKind: "send",
      cardTask: "accept",
    });
    assertEquals(afterFail.rows[0].status, "failed");
    assertEquals(await usageCalls(db), 1);
    // 照回之前先查擁有者與對話：別人拿到 run id 也讀不到。
    await assertRejects(
      () =>
        chargeV3(db, {
          runId,
          userId: OTHER_USER_ID,
          recommendation: V3_SEND_RECOMMENDATION,
          decisionKind: "send",
          cardTask: "accept",
        }),
      Error,
      "STREAM_RUN_OWNER_MISMATCH",
    );
    await assertRejects(
      () =>
        chargeV3(db, {
          runId,
          hash: "other-hash",
          recommendation: V3_SEND_RECOMMENDATION,
          decisionKind: "send",
          cardTask: "accept",
        }),
      Error,
      "RUN_CONVERSATION_MISMATCH",
    );
  } finally {
    await db.close();
  }
});

Deno.test("v3 payload keys: send must name decisionKind and no selectedStyle; no-send must not name a cardTask", async () => {
  const db = await createDatabase();
  try {
    const runId = await createPendingRun(db);
    const reject = (args: Omit<Parameters<typeof chargeV3>[1], "runId">) =>
      assertRejects(
        () => chargeV3(db, { runId, ...args }),
        Error,
        "STREAM_MALFORMED_RECOMMENDATION",
      );
    await reject({
      recommendation: { cardTask: "accept" },
      decisionKind: "send",
      cardTask: "accept",
    });
    await reject({
      recommendation: { ...V3_SEND_RECOMMENDATION, selectedStyle: "extend" },
      decisionKind: "send",
      cardTask: "accept",
    });
    await reject({
      recommendation: { ...NO_SEND_RECOMMENDATION, cardTask: "accept" },
      decisionKind: "do_not_send",
    });
    assertEquals(await usageCalls(db), 0);
    assertEquals((await getRun(db, runId)).status, "pending");
  } finally {
    await db.close();
  }
});

Deno.test("v3 no-send runs follow the v2 retry lease; production cleanup purges v3 rows 30 days after charge", async () => {
  const db = await createDatabase();
  try {
    const noSend = await createPendingRun(db);
    await chargeV3(db, {
      runId: noSend,
      recommendation: NO_SEND_RECOMMENDATION,
      decisionKind: "do_not_send",
    });
    await markFailed(db, noSend);
    assertEquals((await reserveRetry(db, noSend)).rows[0].retry_count, 1);

    const old = await createPendingRun(db);
    const recent = await createPendingRun(db);
    for (const runId of [old, recent]) {
      await chargeV3(db, {
        runId,
        recommendation: V3_SEND_RECOMMENDATION,
        decisionKind: "send",
        cardTask: "accept",
      });
    }
    await db.query(
      `UPDATE public.analysis_stream_runs SET charged_at = now() - interval '31 days' WHERE id = $1`,
      [old],
    );
    await db.query(
      `UPDATE public.analysis_stream_runs SET charged_at = now() - interval '29 days' WHERE id = $1`,
      [recent],
    );
    const deleted = await db.query<{ n: number }>(
      `SELECT public.cleanup_expired_analysis_stream_runs() AS n`,
    );
    assertEquals(deleted.rows[0].n, 1);
    assertEquals(await getRun(db, old), undefined);
    assertEquals((await getRun(db, recent)).card_task, "accept");
  } finally {
    await db.close();
  }
});

Deno.test("v3 charge RPC takes the row lock before deciding (PGlite has one connection, so pin it in the definition)", async () => {
  // 真併發要兩條連線，PGlite 測不到；第 0 片反向預審在 Postgres 16 上驗過拿掉 FOR UPDATE 會雙扣。
  const db = await createDatabase();
  try {
    const def = await db.query<{ def: string }>(
      `SELECT pg_get_functiondef(
         'public.charge_stream_analysis_run_v3(uuid, uuid, text, jsonb, text, text, integer, boolean)'::regprocedure
       ) AS def`,
    );
    const body = def.rows[0].def;
    const lock = body.indexOf("FOR UPDATE");
    assert(lock > 0, "v3 RPC 要先鎖住 run 這一列");
    assert(lock < body.indexOf("IF stream_run.charged_at IS NOT NULL"));
    assert(lock < body.indexOf("PERFORM public.increment_usage"));
  } finally {
    await db.close();
  }
});
