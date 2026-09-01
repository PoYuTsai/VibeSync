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
}

async function createDatabase(): Promise<PGlite> {
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
  `);
  for (const sql of migrationSql) {
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
            recommendation_json
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

    // 重送（甚至改口成 send）只回放，不再扣費、不改狀態。
    const replay = await chargeV2(db, {
      runId,
      recommendation: SEND_RECOMMENDATION,
      decisionKind: "send",
      selectedStyle: "extend",
    });
    assertEquals(replay.rows[0].decision_kind, "do_not_send");
    assertEquals(replay.rows[0].selected_style, null);
    assertEquals(await usageCalls(db), 1);

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
