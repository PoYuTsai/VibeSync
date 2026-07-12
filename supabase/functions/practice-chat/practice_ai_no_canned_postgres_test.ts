import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import {
  assert,
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

const hintPrefetchMigration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260711120000_practice_hint_prefetch.sql",
    import.meta.url,
  ),
);
const generatedOnlyMigration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260711150000_practice_ai_no_canned_fallback.sql",
    import.meta.url,
  ),
);
const qualitySchemaMigration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260712120000_practice_hint_quality_schema_version.sql",
    import.meta.url,
  ),
);

const userId = "11111111-1111-4111-8111-111111111111";

async function createDatabase(options: {
  legacyNullTokenLatch?: boolean;
} = {}): Promise<PGlite> {
  const db = new PGlite();
  await db.exec(`
    CREATE ROLE anon;
    CREATE ROLE authenticated;
    CREATE ROLE service_role;

    CREATE TABLE public.practice_chat_sessions (
      user_id UUID NOT NULL,
      session_id TEXT NOT NULL,
      practice_mode TEXT NOT NULL DEFAULT 'game',
      charged BOOLEAN NOT NULL DEFAULT TRUE,
      ai_count INTEGER NOT NULL DEFAULT 1,
      hint_count INTEGER NOT NULL DEFAULT 0,
      hint_generation_started_at TIMESTAMPTZ,
      last_hint_request_id TEXT,
      last_hint_result JSONB,
      debrief_count INTEGER NOT NULL DEFAULT 0,
      last_debrief_request_id TEXT,
      last_debrief_result JSONB,
      last_debrief_started_at TIMESTAMPTZ,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      PRIMARY KEY (user_id, session_id)
    );

    CREATE TABLE public.subscriptions (
      user_id UUID PRIMARY KEY,
      tier TEXT NOT NULL DEFAULT 'starter',
      monthly_messages_used INTEGER NOT NULL DEFAULT 0,
      daily_messages_used INTEGER NOT NULL DEFAULT 0,
      monthly_reset_at TIMESTAMPTZ,
      daily_reset_at TIMESTAMPTZ
    );

    CREATE OR REPLACE FUNCTION public.increment_usage(
      p_user_id UUID,
      p_amount INTEGER,
      p_monthly_limit INTEGER,
      p_daily_limit INTEGER
    ) RETURNS VOID
    LANGUAGE plpgsql
    SET search_path = public
    AS $$
    BEGIN
      UPDATE public.subscriptions
      SET monthly_messages_used = monthly_messages_used + p_amount,
          daily_messages_used = daily_messages_used + p_amount
      WHERE user_id = p_user_id
        AND monthly_messages_used + p_amount <= p_monthly_limit
        AND daily_messages_used + p_amount <= p_daily_limit;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'PRACTICE_QUOTA_EXHAUSTED';
      END IF;
    END;
    $$;
  `);
  if (options.legacyNullTokenLatch) {
    await db.query(
      `INSERT INTO public.practice_chat_sessions (
         user_id, session_id, hint_generation_started_at
       ) VALUES ($1, 'legacy-null-latch', now() - interval '3 minutes')`,
      [userId],
    );
  }
  await db.exec(hintPrefetchMigration);
  await db.exec(generatedOnlyMigration);
  await db.exec(qualitySchemaMigration);
  await db.query(
    `INSERT INTO public.subscriptions (
       user_id, monthly_messages_used, daily_messages_used,
       monthly_reset_at, daily_reset_at
     ) VALUES ($1, 0, 0, now(), now())`,
    [userId],
  );
  return db;
}

async function insertSession(
  db: PGlite,
  sessionId: string,
  hintCount = 1,
  debriefCount = 0,
): Promise<void> {
  await db.query(
    `INSERT INTO public.practice_chat_sessions (
       user_id, session_id, hint_count, debrief_count
     ) VALUES ($1, $2, $3, $4)`,
    [userId, sessionId, hintCount, debriefCount],
  );
}

async function insertLegacyHint(
  db: PGlite,
  sessionId: string,
  requestId: string,
  token: string | null,
  active: boolean,
): Promise<void> {
  try {
    await db.query(
      `INSERT INTO public.practice_hint_requests (
       user_id, session_id, request_id, generation_token,
       claimed_ai_count, is_prefetch, state, result, charged,
       legacy_replacement_pending,
       legacy_replacement_generation_token,
       legacy_replacement_started_at
     ) VALUES (
       $1, $2, $3, NULL, 1, FALSE, 'settled',
       '{"generationSource":"fallback","fallbackUsed":true,"costDeducted":0}'::jsonb,
       TRUE, $5, $4, CASE WHEN $5 THEN now() - interval '3 minutes' ELSE NULL END
       )`,
      [userId, sessionId, requestId, token, active],
    );
  } catch (error) {
    throw new Error(`insertLegacyHint(${sessionId}, ${requestId}): ${error}`);
  }
}

async function bindLegacyLatch(
  db: PGlite,
  sessionId: string,
  token: string,
): Promise<void> {
  await db.query(
    `UPDATE public.practice_chat_sessions
     SET hint_generation_started_at = now() - interval '3 minutes',
         hint_generation_owner_token = $3
     WHERE user_id = $1 AND session_id = $2`,
    [userId, sessionId, token],
  );
}

const generatedHint = {
  generationSource: "model",
  fallbackUsed: false,
  qualitySchemaVersion: "typed-facts-v1",
  replies: [
    {
      type: "warm_up",
      text: "先接住她的感受，再補一小段自己的畫面。",
      decision: {
        phase: "testing",
        targetVariable: "investment",
        move: "share_then_ask",
        inviteRoute: "none",
        rationale: "先互惠再觀察她是否接球",
      },
    },
  ],
};

Deno.test("PostgreSQL replaces an already-paid unversioned model Hint without another count or charge", async () => {
  const db = await createDatabase();
  try {
    await insertSession(db, "unversioned-model", 3);
    await db.query(
      `INSERT INTO public.practice_hint_requests (
         user_id, session_id, request_id, claimed_ai_count, is_prefetch,
         state, result, charged
       ) VALUES (
         $1, $2, 'old-model', 1, FALSE, 'settled',
         '{"generationSource":"model","fallbackUsed":false,"costDeducted":1}'::jsonb,
         TRUE
       )`,
      [userId, "unversioned-model"],
    );

    const claim = await db.query<{
      current_hint_count: number;
      claimed: boolean;
      replay: boolean;
      stored_result: unknown;
      quota_already_paid: boolean;
    }>(
      `SELECT * FROM public.claim_legacy_practice_hint_replacement(
         $1, $2, 'old-model', 'typed-replacement-token', 1
       )`,
      [userId, "unversioned-model"],
    );
    assertEquals(claim.rows[0], {
      current_hint_count: 3,
      claimed: true,
      replay: false,
      stored_result: null,
      quota_already_paid: true,
    });

    const record = await db.query<{
      new_hint_count: number;
      did_charge: boolean;
      quality_schema_version: string;
    }>(
      `SELECT new_hint_count, did_charge,
              stored_result ->> 'qualitySchemaVersion' AS quality_schema_version
       FROM public.record_legacy_practice_hint_replacement(
         $1, $2, 'old-model', 'typed-replacement-token', $3::jsonb,
         TRUE, 50, 50, 5
       )`,
      [userId, "unversioned-model", JSON.stringify(generatedHint)],
    );
    assertEquals(record.rows[0], {
      new_hint_count: 3,
      did_charge: false,
      quality_schema_version: "typed-facts-v1",
    });

    const usage = await db.query<{
      hint_count: number;
      monthly_messages_used: number;
      daily_messages_used: number;
    }>(
      `SELECT s.hint_count, sub.monthly_messages_used, sub.daily_messages_used
       FROM public.practice_chat_sessions AS s
       JOIN public.subscriptions AS sub ON sub.user_id = s.user_id
       WHERE s.user_id = $1 AND s.session_id = $2`,
      [userId, "unversioned-model"],
    );
    assertEquals(usage.rows[0], {
      hint_count: 3,
      monthly_messages_used: 0,
      daily_messages_used: 0,
    });
  } finally {
    await db.close();
  }
});

Deno.test("PostgreSQL replaces an already-counted unversioned model Debrief without another count", async () => {
  const db = await createDatabase();
  try {
    await insertSession(db, "unversioned-debrief", 0, 0);
    await db.query(
      `SELECT * FROM public.claim_practice_debrief(
         $1, $2, 3, 'old-debrief', 'old-debrief-token'
       )`,
      [userId, "unversioned-debrief"],
    );
    await db.query(
      `SELECT public.record_practice_debrief(
         $1, $2, 'old-debrief',
         '{"generationSource":"model","fallbackUsed":false,"headline":"old"}'::jsonb,
         'old-debrief-token'
       )`,
      [userId, "unversioned-debrief"],
    );

    const invalidated = await db.query<{ invalidated: boolean }>(
      `SELECT public.invalidate_legacy_practice_ai_snapshot(
         $1, $2, 'old-debrief', 'debrief'
       ) AS invalidated`,
      [userId, "unversioned-debrief"],
    );
    assertEquals(invalidated.rows[0].invalidated, true);

    const invalidatedState = await db.query<{
      debrief_count: number;
      counted: boolean;
      result: unknown;
    }>(
      `SELECT debrief_count,
              (debrief_request_ledger -> 'old-debrief' ->> 'counted')::boolean AS counted,
              debrief_request_ledger -> 'old-debrief' -> 'result' AS result
       FROM public.practice_chat_sessions
       WHERE user_id = $1 AND session_id = $2`,
      [userId, "unversioned-debrief"],
    );
    assertEquals(invalidatedState.rows[0], {
      debrief_count: 1,
      counted: true,
      result: null,
    });

    const replacementClaim = await db.query<{
      current_debrief_count: number;
      replay: boolean;
      in_flight: boolean;
      stored_result: unknown;
    }>(
      `SELECT * FROM public.claim_practice_debrief(
         $1, $2, 3, 'old-debrief', 'typed-debrief-token'
       )`,
      [userId, "unversioned-debrief"],
    );
    assertEquals(replacementClaim.rows[0], {
      current_debrief_count: 1,
      replay: false,
      in_flight: false,
      stored_result: null,
    });

    await db.query(
      `SELECT public.record_practice_debrief(
         $1, $2, 'old-debrief',
         '{"generationSource":"model","fallbackUsed":false,"qualitySchemaVersion":"typed-facts-v1","headline":"new"}'::jsonb,
         'typed-debrief-token'
       )`,
      [userId, "unversioned-debrief"],
    );
    const finalState = await db.query<{
      debrief_count: number;
      quality_schema_version: string;
    }>(
      `SELECT debrief_count,
              debrief_request_ledger -> 'old-debrief' -> 'result'
                ->> 'qualitySchemaVersion' AS quality_schema_version
       FROM public.practice_chat_sessions
       WHERE user_id = $1 AND session_id = $2`,
      [userId, "unversioned-debrief"],
    );
    assertEquals(finalState.rows[0], {
      debrief_count: 1,
      quality_schema_version: "typed-facts-v1",
    });

    const currentInvalidation = await db.query<{ invalidated: boolean }>(
      `SELECT public.invalidate_legacy_practice_ai_snapshot(
         $1, $2, 'old-debrief', 'debrief'
       ) AS invalidated`,
      [userId, "unversioned-debrief"],
    );
    assertEquals(currentInvalidation.rows[0].invalidated, false);
  } finally {
    await db.close();
  }
});

Deno.test("PostgreSQL migration drains pre-token Hint owners and enforces strict latch shape", async () => {
  const db = await createDatabase({ legacyNullTokenLatch: true });
  try {
    const drained = await db.query<{
      hint_generation_started_at: string | null;
      hint_generation_owner_token: string | null;
      generating_count: number;
    }>(
      `SELECT s.hint_generation_started_at::text,
              s.hint_generation_owner_token,
              count(r.request_id)::integer AS generating_count
       FROM public.practice_chat_sessions AS s
       LEFT JOIN public.practice_hint_requests AS r
         ON r.user_id = s.user_id AND r.session_id = s.session_id
        AND r.state = 'generating'
       WHERE s.user_id = $1 AND s.session_id = 'legacy-null-latch'
       GROUP BY s.user_id, s.session_id`,
      [userId],
    );
    assertEquals(drained.rows[0], {
      hint_generation_started_at: null,
      hint_generation_owner_token: null,
      generating_count: 0,
    });
    await assertRejects(
      () =>
        db.query(
          `UPDATE public.practice_chat_sessions
           SET hint_generation_started_at = now()
           WHERE user_id = $1 AND session_id = 'legacy-null-latch'`,
          [userId],
        ),
      Error,
      "practice_chat_sessions_hint_generation_owner_check",
    );
    await assertRejects(
      () =>
        db.query(
          `SELECT * FROM public.claim_practice_hint_generation(
             $1, 'legacy-null-latch', 5, 'new-request', FALSE, NULL::text, 1
           )`,
          [userId],
        ),
      Error,
      "invalid p_generation_token",
    );
  } finally {
    await db.close();
  }
});

Deno.test("PostgreSQL Hint latch fences stale legacy owners across normal and replacement claims", async () => {
  const db = await createDatabase();
  try {
    await insertSession(db, "legacy-to-normal");
    await insertLegacyHint(
      db,
      "legacy-to-normal",
      "legacy-a",
      "legacy-a-token",
      true,
    );
    await bindLegacyLatch(db, "legacy-to-normal", "legacy-a-token");

    await db.query(
      `SELECT * FROM public.claim_practice_hint_generation(
         $1, $2, 5, 'normal-b', TRUE, 'normal-b-token', 1
       )`,
      [userId, "legacy-to-normal"],
    );

    const afterNormalClaim = await db.query<{
      hint_generation_owner_token: string;
      legacy_started_at: string | null;
      normal_state: string;
    }>(
      `SELECT s.hint_generation_owner_token,
              a.legacy_replacement_started_at::text AS legacy_started_at,
              b.state AS normal_state
       FROM public.practice_chat_sessions AS s
       JOIN public.practice_hint_requests AS a
         ON a.user_id = s.user_id AND a.session_id = s.session_id
        AND a.request_id = 'legacy-a'
       JOIN public.practice_hint_requests AS b
         ON b.user_id = s.user_id AND b.session_id = s.session_id
        AND b.request_id = 'normal-b'
       WHERE s.user_id = $1 AND s.session_id = $2`,
      [userId, "legacy-to-normal"],
    );
    assertEquals(
      afterNormalClaim.rows[0],
      {
        hint_generation_owner_token: "normal-b-token",
        legacy_started_at: null,
        normal_state: "generating",
      },
    );

    await assertRejects(
      () =>
        db.query(
          `SELECT * FROM public.record_legacy_practice_hint_replacement(
             $1, $2, 'legacy-a', 'legacy-a-token', $3::jsonb,
             TRUE, 50, 50, 5
           )`,
          [userId, "legacy-to-normal", JSON.stringify(generatedHint)],
        ),
      Error,
      "PRACTICE_HINT_OWNER_MISMATCH",
    );
    const lateRelease = await db.query<{ released: boolean }>(
      `SELECT public.release_legacy_practice_hint_replacement(
         $1, $2, 'legacy-a', 'legacy-a-token'
       ) AS released`,
      [userId, "legacy-to-normal"],
    );
    assertEquals(lateRelease.rows[0].released, false);

    const stillNormalB = await db.query<{
      hint_generation_owner_token: string;
      hint_generation_started_at: string;
      monthly_messages_used: number;
    }>(
      `SELECT s.hint_generation_owner_token,
              s.hint_generation_started_at::text,
              sub.monthly_messages_used
       FROM public.practice_chat_sessions AS s
       JOIN public.subscriptions AS sub ON sub.user_id = s.user_id
       WHERE s.user_id = $1 AND s.session_id = $2`,
      [userId, "legacy-to-normal"],
    );
    assertEquals(
      stillNormalB.rows[0].hint_generation_owner_token,
      "normal-b-token",
    );
    assert(stillNormalB.rows[0].hint_generation_started_at !== null);
    assertEquals(stillNormalB.rows[0].monthly_messages_used, 0);

    await db.query(
      `SELECT * FROM public.record_practice_hint(
         $1, $2, FALSE, 5, 'normal-b', $3::jsonb,
         FALSE, 50, 50, 20, 'normal-b-token'
       )`,
      [userId, "legacy-to-normal", JSON.stringify(generatedHint)],
    );
    const prefetched = await db.query<{
      state: string;
      hint_generation_started_at: string | null;
      hint_generation_owner_token: string | null;
    }>(
      `SELECT r.state, s.hint_generation_started_at::text,
              s.hint_generation_owner_token
       FROM public.practice_hint_requests AS r
       JOIN public.practice_chat_sessions AS s
         ON s.user_id = r.user_id AND s.session_id = r.session_id
       WHERE r.user_id = $1 AND r.session_id = $2
         AND r.request_id = 'normal-b'`,
      [userId, "legacy-to-normal"],
    );
    assertEquals(prefetched.rows[0], {
      state: "prefetched",
      hint_generation_started_at: null,
      hint_generation_owner_token: null,
    });

    const settled = await db.query<{
      new_hint_count: number;
      did_charge: boolean;
    }>(
      `SELECT new_hint_count, did_charge
       FROM public.settle_prefetched_practice_hint(
         $1, $2, 'normal-b', TRUE, 5, 20, 50, 50, 1
       )`,
      [userId, "legacy-to-normal"],
    );
    assertEquals(settled.rows[0], { new_hint_count: 2, did_charge: true });

    await insertSession(db, "normal-release");
    await insertLegacyHint(
      db,
      "normal-release",
      "legacy-a",
      "legacy-release-a-token",
      true,
    );
    await bindLegacyLatch(
      db,
      "normal-release",
      "legacy-release-a-token",
    );
    await db.query(
      `SELECT * FROM public.claim_practice_hint_generation(
         $1, $2, 5, 'normal-b', FALSE, 'normal-release-b-token', 1
       )`,
      [userId, "normal-release"],
    );
    const normalRelease = await db.query<{ released: boolean }>(
      `SELECT released
       FROM public.release_practice_hint_generation(
         $1, $2, 'normal-b', 'normal-release-b-token'
       )`,
      [userId, "normal-release"],
    );
    assertEquals(normalRelease.rows[0].released, true);
    const afterNormalRelease = await db.query<{
      hint_generation_started_at: string | null;
      hint_generation_owner_token: string | null;
    }>(
      `SELECT hint_generation_started_at::text, hint_generation_owner_token
       FROM public.practice_chat_sessions
       WHERE user_id = $1 AND session_id = $2`,
      [userId, "normal-release"],
    );
    assertEquals(afterNormalRelease.rows[0], {
      hint_generation_started_at: null,
      hint_generation_owner_token: null,
    });

    await insertSession(db, "normal-no-id-to-legacy");
    await insertLegacyHint(
      db,
      "normal-no-id-to-legacy",
      "legacy-b",
      "legacy-b-old-token",
      true,
    );
    await db.query(
      `SELECT * FROM public.claim_practice_hint_generation(
         $1, $2, 5, NULL::text, FALSE, 'normal-no-id-a-token', 1
       )`,
      [userId, "normal-no-id-to-legacy"],
    );
    await db.query(
      `UPDATE public.practice_chat_sessions
       SET hint_generation_started_at = now() - interval '3 minutes'
       WHERE user_id = $1 AND session_id = $2`,
      [userId, "normal-no-id-to-legacy"],
    );
    await db.query(
      `SELECT * FROM public.claim_legacy_practice_hint_replacement(
         $1, $2, 'legacy-b', 'legacy-current-b-token', 1
       )`,
      [userId, "normal-no-id-to-legacy"],
    );
    const staleNoIdRelease = await db.query<{ released: boolean }>(
      `SELECT released
       FROM public.release_practice_hint_generation(
         $1, $2, NULL::text, 'normal-no-id-a-token'
       )`,
      [userId, "normal-no-id-to-legacy"],
    );
    assertEquals(staleNoIdRelease.rows[0].released, false);
    const afterStaleNoIdRelease = await db.query<{
      hint_generation_started_at: string;
      hint_generation_owner_token: string;
    }>(
      `SELECT hint_generation_started_at::text, hint_generation_owner_token
       FROM public.practice_chat_sessions
       WHERE user_id = $1 AND session_id = $2`,
      [userId, "normal-no-id-to-legacy"],
    );
    assert(afterStaleNoIdRelease.rows[0].hint_generation_started_at !== null);
    assertEquals(
      afterStaleNoIdRelease.rows[0].hint_generation_owner_token,
      "legacy-current-b-token",
    );
    const currentLegacyRelease = await db.query<{ released: boolean }>(
      `SELECT public.release_legacy_practice_hint_replacement(
         $1, $2, 'legacy-b', 'legacy-current-b-token'
       ) AS released`,
      [userId, "normal-no-id-to-legacy"],
    );
    assertEquals(currentLegacyRelease.rows[0].released, true);

    await insertSession(db, "fresh-legacy");
    await insertLegacyHint(
      db,
      "fresh-legacy",
      "legacy-a",
      "fresh-legacy-token",
      true,
    );
    await bindLegacyLatch(db, "fresh-legacy", "fresh-legacy-token");
    await db.query(
      `UPDATE public.practice_hint_requests
       SET legacy_replacement_started_at = now()
       WHERE user_id = $1 AND session_id = $2 AND request_id = 'legacy-a'`,
      [userId, "fresh-legacy"],
    );
    await db.query(
      `UPDATE public.practice_chat_sessions
       SET hint_generation_started_at = now()
       WHERE user_id = $1 AND session_id = $2`,
      [userId, "fresh-legacy"],
    );
    await assertRejects(
      () =>
        db.query(
          `SELECT * FROM public.claim_practice_hint_generation(
             $1, $2, 5, 'normal-b', FALSE, 'fresh-normal-token', 1
           )`,
          [userId, "fresh-legacy"],
        ),
      Error,
      "PRACTICE_HINT_IN_FLIGHT",
    );

    await insertSession(db, "fresh-normal");
    await db.query(
      `SELECT * FROM public.claim_practice_hint_generation(
         $1, $2, 5, 'normal-a', FALSE, 'fresh-normal-a-token', 1
       )`,
      [userId, "fresh-normal"],
    );
    await insertLegacyHint(
      db,
      "fresh-normal",
      "legacy-b",
      "legacy-b-old-token",
      true,
    );
    await assertRejects(
      () =>
        db.query(
          `SELECT * FROM public.claim_legacy_practice_hint_replacement(
             $1, $2, 'legacy-b', 'fresh-legacy-b-token', 1
           )`,
          [userId, "fresh-normal"],
        ),
      Error,
      "PRACTICE_HINT_IN_FLIGHT",
    );

    await insertSession(db, "legacy-to-legacy");
    await insertLegacyHint(
      db,
      "legacy-to-legacy",
      "legacy-a",
      "legacy-a2-token",
      true,
    );
    await insertLegacyHint(
      db,
      "legacy-to-legacy",
      "legacy-b",
      "legacy-b-old-token",
      true,
    );
    await bindLegacyLatch(db, "legacy-to-legacy", "legacy-a2-token");

    await db.query(
      `SELECT * FROM public.claim_legacy_practice_hint_replacement(
         $1, $2, 'legacy-b', 'legacy-b-token', 1
       )`,
      [userId, "legacy-to-legacy"],
    );
    await assertRejects(
      () =>
        db.query(
          `SELECT * FROM public.record_legacy_practice_hint_replacement(
             $1, $2, 'legacy-a', 'legacy-a2-token', $3::jsonb,
             TRUE, 50, 50, 5
           )`,
          [userId, "legacy-to-legacy", JSON.stringify(generatedHint)],
        ),
      Error,
      "PRACTICE_HINT_OWNER_MISMATCH",
    );
    const staleLegacyRelease = await db.query<{ released: boolean }>(
      `SELECT public.release_legacy_practice_hint_replacement(
         $1, $2, 'legacy-a', 'legacy-a2-token'
       ) AS released`,
      [userId, "legacy-to-legacy"],
    );
    assertEquals(staleLegacyRelease.rows[0].released, false);

    const currentLegacy = await db.query<{
      hint_generation_owner_token: string;
      a_started_at: string | null;
      b_started_at: string;
    }>(
      `SELECT s.hint_generation_owner_token,
              a.legacy_replacement_started_at::text AS a_started_at,
              b.legacy_replacement_started_at::text AS b_started_at
       FROM public.practice_chat_sessions AS s
       JOIN public.practice_hint_requests AS a
         ON a.user_id = s.user_id AND a.session_id = s.session_id
        AND a.request_id = 'legacy-a'
       JOIN public.practice_hint_requests AS b
         ON b.user_id = s.user_id AND b.session_id = s.session_id
        AND b.request_id = 'legacy-b'
       WHERE s.user_id = $1 AND s.session_id = $2`,
      [userId, "legacy-to-legacy"],
    );
    assertEquals(
      currentLegacy.rows[0].hint_generation_owner_token,
      "legacy-b-token",
    );
    assertEquals(currentLegacy.rows[0].a_started_at, null);
    assert(currentLegacy.rows[0].b_started_at !== null);

    await db.query(
      `SELECT * FROM public.record_legacy_practice_hint_replacement(
         $1, $2, 'legacy-b', 'legacy-b-token', $3::jsonb,
         FALSE, 50, 50, 5
       )`,
      [userId, "legacy-to-legacy", JSON.stringify(generatedHint)],
    );
    const legacySettled = await db.query<{
      hint_generation_started_at: string | null;
      hint_generation_owner_token: string | null;
      generation_source: string;
    }>(
      `SELECT s.hint_generation_started_at::text,
              s.hint_generation_owner_token,
              r.result ->> 'generationSource' AS generation_source
       FROM public.practice_chat_sessions AS s
       JOIN public.practice_hint_requests AS r
         ON r.user_id = s.user_id AND r.session_id = s.session_id
        AND r.request_id = 'legacy-b'
       WHERE s.user_id = $1 AND s.session_id = $2`,
      [userId, "legacy-to-legacy"],
    );
    assertEquals(legacySettled.rows[0], {
      hint_generation_started_at: null,
      hint_generation_owner_token: null,
      generation_source: "model",
    });
  } finally {
    await db.close();
  }
});

Deno.test("PostgreSQL Debrief count changes only when generated result commits", async () => {
  const db = await createDatabase();
  try {
    await insertSession(db, "debrief", 0, 2);
    const claimFailed = await db.query<{ current_debrief_count: number }>(
      `SELECT current_debrief_count
       FROM public.claim_practice_debrief($1, $2, 3, 'failed', 'failed-token')`,
      [userId, "debrief"],
    );
    assertEquals(claimFailed.rows[0].current_debrief_count, 2);

    const released = await db.query<{ released: boolean }>(
      `SELECT public.release_practice_debrief_generation(
         $1, $2, 'failed', 'failed-token'
       ) AS released`,
      [userId, "debrief"],
    );
    assertEquals(released.rows[0].released, true);

    const afterFailure = await db.query<{
      debrief_count: number;
      has_failed_entry: boolean;
    }>(
      `SELECT debrief_count,
              debrief_request_ledger ? 'failed' AS has_failed_entry
       FROM public.practice_chat_sessions
       WHERE user_id = $1 AND session_id = $2`,
      [userId, "debrief"],
    );
    assertEquals(afterFailure.rows[0], {
      debrief_count: 2,
      has_failed_entry: false,
    });

    await db.query(
      `SELECT * FROM public.claim_practice_debrief(
         $1, $2, 3, 'success', 'success-token'
       )`,
      [userId, "debrief"],
    );
    await db.query(
      `SELECT public.record_practice_debrief(
         $1, $2, 'success',
         '{"generationSource":"model","fallbackUsed":false,"headline":"ok"}'::jsonb,
         'success-token'
       ) AS result`,
      [userId, "debrief"],
    );

    const finalState = await db.query<{
      debrief_count: number;
      counted: boolean;
    }>(
      `SELECT debrief_count,
              (debrief_request_ledger -> 'success' ->> 'counted')::boolean AS counted
       FROM public.practice_chat_sessions
       WHERE user_id = $1 AND session_id = $2`,
      [userId, "debrief"],
    );
    assertEquals(finalState.rows[0], { debrief_count: 3, counted: true });

    await insertSession(db, "debrief-replay", 0, 0);
    for (
      const [requestId, token] of [
        ["a", "a-token"],
        ["b", "b-token"],
        ["c", "c-token"],
      ] as const
    ) {
      await db.query(
        `SELECT * FROM public.claim_practice_debrief(
           $1, $2, 3, $3::text, $4::text
         )`,
        [userId, "debrief-replay", requestId, token],
      );
      await db.query(
        `SELECT public.record_practice_debrief(
           $1, $2, $3::text,
           jsonb_build_object(
             'generationSource', 'model',
             'fallbackUsed', FALSE,
             'headline', $3::text
           ),
           $4::text
         )`,
        [userId, "debrief-replay", requestId, token],
      );
    }

    const replayA = await db.query<{
      current_debrief_count: number;
      replay: boolean;
      headline: string;
    }>(
      `SELECT current_debrief_count, replay,
              stored_result ->> 'headline' AS headline
       FROM public.claim_practice_debrief(
         $1, $2, 3, 'a', 'unused-replay-token'
       )`,
      [userId, "debrief-replay"],
    );
    assertEquals(replayA.rows[0], {
      current_debrief_count: 3,
      replay: true,
      headline: "a",
    });
    await assertRejects(
      () =>
        db.query(
          `SELECT * FROM public.claim_practice_debrief(
             $1, $2, 3, 'd', 'd-token'
           )`,
          [userId, "debrief-replay"],
        ),
      Error,
      "PRACTICE_DEBRIEF_LIMIT",
    );

    await insertSession(db, "debrief-late", 0, 0);
    await db.query(
      `SELECT * FROM public.claim_practice_debrief(
         $1, $2, 3, 'late-a', 'late-old-token'
       )`,
      [userId, "debrief-late"],
    );
    await db.query(
      `UPDATE public.practice_chat_sessions
       SET last_debrief_started_at = now() - interval '3 minutes',
           debrief_request_ledger = jsonb_set(
             debrief_request_ledger,
             '{late-a,started_at}',
             to_jsonb((now() - interval '3 minutes')::text),
             FALSE
           )
       WHERE user_id = $1 AND session_id = $2`,
      [userId, "debrief-late"],
    );
    await db.query(
      `SELECT * FROM public.claim_practice_debrief(
         $1, $2, 3, 'late-a', 'late-new-token'
       )`,
      [userId, "debrief-late"],
    );
    await assertRejects(
      () =>
        db.query(
          `SELECT public.record_practice_debrief(
             $1, $2, 'late-a',
             '{"generationSource":"model","fallbackUsed":false}'::jsonb,
             'late-old-token'
           )`,
          [userId, "debrief-late"],
        ),
      Error,
      "PRACTICE_DEBRIEF_GENERATION_MISMATCH",
    );
    const oldRelease = await db.query<{ released: boolean }>(
      `SELECT public.release_practice_debrief_generation(
         $1, $2, 'late-a', 'late-old-token'
       ) AS released`,
      [userId, "debrief-late"],
    );
    assertEquals(oldRelease.rows[0].released, false);
    const newOwner = await db.query<{
      last_debrief_generation_token: string;
      entry_token: string;
      debrief_count: number;
    }>(
      `SELECT last_debrief_generation_token,
              debrief_request_ledger -> 'late-a' ->> 'generation_token'
                AS entry_token,
              debrief_count
       FROM public.practice_chat_sessions
       WHERE user_id = $1 AND session_id = $2`,
      [userId, "debrief-late"],
    );
    assertEquals(newOwner.rows[0], {
      last_debrief_generation_token: "late-new-token",
      entry_token: "late-new-token",
      debrief_count: 0,
    });
  } finally {
    await db.close();
  }
});
