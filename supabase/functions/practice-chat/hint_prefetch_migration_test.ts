import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260711120000_practice_hint_prefetch.sql",
    import.meta.url,
  ),
);
const deleteAccountSource = await Deno.readTextFile(
  new URL("../delete-account/index.ts", import.meta.url),
);

function compactSql(value: string): string {
  return value.replace(/\s+/g, " ").trim();
}

function required(snippet: string): number {
  const index = migration.indexOf(snippet);
  assert(index >= 0, `Migration must contain: ${snippet}`);
  return index;
}

function functionBody(name: string): string {
  const start = required(`CREATE OR REPLACE FUNCTION public.${name}(`);
  const next = migration.indexOf(
    "CREATE OR REPLACE FUNCTION public.",
    start + 1,
  );
  return next >= 0 ? migration.slice(start, next) : migration.slice(start);
}

Deno.test("Hint prefetch ledger is bounded, private, and session-owned", () => {
  const compact = compactSql(migration);
  required("CREATE TABLE IF NOT EXISTS public.practice_hint_requests");
  required("PRIMARY KEY (user_id, session_id, request_id)");
  required("FOREIGN KEY (user_id, session_id)");
  required("REFERENCES public.practice_chat_sessions (user_id, session_id)");
  required("ON DELETE CASCADE");
  assert(compact.includes("claimed_ai_count INTEGER"));
  assert(compact.includes("generation_token TEXT"));
  assert(compact.includes("is_prefetch BOOLEAN NOT NULL"));
  assert(compact.includes("state TEXT NOT NULL"));
  assert(compact.includes("result JSONB"));
  assert(compact.includes("charged BOOLEAN NOT NULL DEFAULT FALSE"));
  required("length(request_id) BETWEEN 1 AND 64");
  required("length(generation_token) BETWEEN 1 AND 64");
  required("state IN ('generating', 'prefetched', 'settled')");
  required("jsonb_typeof(result) = 'object'");
  required("claimed_ai_count BETWEEN 1 AND 20");
  required("claimed_ai_count IS NULL");
  required(
    "ALTER TABLE public.practice_hint_requests ENABLE ROW LEVEL SECURITY",
  );
  required("REVOKE ALL ON TABLE public.practice_hint_requests");
  required(
    "GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.practice_hint_requests",
  );
  required("TO service_role");
  required("does not store transcript, prompt, or raw provider errors");
  assertEquals(
    migration.includes("CREATE POLICY practice_hint_requests"),
    false,
    "client policy would expose stored Hint text",
  );
});

Deno.test("Hint prefetch ledger has one prefetched and one generating owner per session", () => {
  const compact = compactSql(migration);
  assert(
    /CREATE UNIQUE INDEX IF NOT EXISTS practice_hint_requests_one_prefetched_per_session[\s\S]*WHERE state = 'prefetched'/
      .test(
        migration,
      ),
  );
  assert(
    /CREATE UNIQUE INDEX IF NOT EXISTS practice_hint_requests_one_generating_per_session[\s\S]*WHERE state = 'generating'/
      .test(
        migration,
      ),
  );
  assert(
    compact.includes(
      "state = 'generating' AND result IS NULL AND charged = FALSE",
    ),
  );
  assert(
    compact.includes(
      "state = 'prefetched' AND result IS NOT NULL AND jsonb_typeof(result) = 'object' AND charged = FALSE AND is_prefetch = TRUE",
    ),
  );
  assert(
    compact.includes(
      "state = 'settled' AND result IS NOT NULL AND jsonb_typeof(result) = 'object' AND charged = TRUE",
    ),
  );
});

Deno.test("Migration backfills completed snapshots and fences legacy in-flight workers", () => {
  const compact = compactSql(migration);
  required("last_hint_request_id");
  required("last_hint_result");
  required("ON CONFLICT (user_id, session_id, request_id) DO NOTHING");
  assert(compact.includes("NULL, FALSE, 'settled'"));
  assert(compact.includes("last_hint_result, TRUE"));
  assert(compact.includes("hint_generation_started_at IS NOT NULL"));
  required("__legacy_inflight__");
  assert(compact.includes("ai_count, FALSE, 'generating'"));
});

Deno.test("Migration replaces RPC signatures without PostgREST overloads", () => {
  required(
    "DROP FUNCTION IF EXISTS public.claim_practice_hint_generation(UUID, TEXT, INTEGER, TEXT);",
  );
  required(
    "DROP FUNCTION IF EXISTS public.record_practice_hint(UUID, TEXT, BOOLEAN, INTEGER, TEXT, JSONB);",
  );
  required(
    "DROP FUNCTION IF EXISTS public.release_practice_hint_generation(UUID, TEXT);",
  );

  const claim = compactSql(functionBody("claim_practice_hint_generation"));
  assert(claim.includes("p_prefetch BOOLEAN DEFAULT FALSE"));
  assert(claim.includes("p_generation_token TEXT DEFAULT NULL"));
  assert(
    claim.includes(
      "RETURNS TABLE( current_hint_count INTEGER, replay BOOLEAN, stored_result JSONB, stored_charged BOOLEAN )",
    ),
  );

  const record = compactSql(functionBody("record_practice_hint"));
  assert(record.includes("p_charged BOOLEAN DEFAULT TRUE"));
  assert(record.includes("p_monthly_limit INTEGER DEFAULT NULL"));
  assert(record.includes("p_daily_limit INTEGER DEFAULT NULL"));
  assert(record.includes("p_max_replies INTEGER DEFAULT NULL"));
  assert(record.includes("p_generation_token TEXT DEFAULT NULL"));
  assert(
    record.includes(
      "RETURNS TABLE( new_hint_count INTEGER, did_charge BOOLEAN, stored_result JSONB, stored_charged BOOLEAN )",
    ),
  );

  const release = compactSql(functionBody("release_practice_hint_generation"));
  assert(release.includes("p_request_id TEXT DEFAULT NULL"));
  assert(release.includes("p_generation_token TEXT DEFAULT NULL"));
});

Deno.test("Subscription preparation owns reset under the subscription row lock", () => {
  const body = functionBody("prepare_practice_subscription_usage");
  const compact = compactSql(body);
  assert(body.includes("FOR UPDATE"));
  assert(body.includes("PRACTICE_SUBSCRIPTION_NOT_FOUND"));
  assert(
    compact.includes("DATE_TRUNC('month', v_now AT TIME ZONE 'UTC')"),
  );
  assert(compact.includes("DATE_TRUNC('day', v_now AT TIME ZONE 'UTC')"));
  assert(compact.includes("monthly_messages_used = 0"));
  assert(compact.includes("daily_messages_used = 0"));
  assert(
    compact.includes(
      "RETURNS TABLE( tier TEXT, monthly_messages_used INTEGER, daily_messages_used INTEGER, daily_reset_at TIMESTAMPTZ, monthly_reset_at TIMESTAMPTZ )",
    ),
  );
});

Deno.test("Claim replays exact requests before gates and fences stale generators", () => {
  const body = functionBody("claim_practice_hint_generation");
  const replay = body.indexOf("v_request.state IN ('prefetched', 'settled')");
  const cap = body.indexOf("v_session.hint_count >= p_max_hints");
  const latch = body.indexOf("PRACTICE_HINT_IN_FLIGHT");
  const cleanup = body.indexOf("DELETE FROM public.practice_hint_requests");
  const insert = body.indexOf("INSERT INTO public.practice_hint_requests");
  assert(replay >= 0 && cap >= 0 && latch >= 0 && cleanup >= 0 && insert >= 0);
  assert(replay < cap, "exact replay must beat the mutable hint cap");
  assert(replay < latch, "exact replay must beat the global latch");
  assert(
    cleanup < insert,
    "stale generating owner must be fenced before claim",
  );
  assert(body.includes("r.request_id = p_request_id"));
  assert(body.includes("claimed_ai_count = v_session.ai_count"));
  assert(body.includes("is_prefetch = p_prefetch"));
  assert(body.includes("generation_token = p_generation_token"));
  assert(
    compactSql(body).includes(
      "IF p_generation_token IS NULL AND EXISTS ( SELECT 1 FROM public.practice_hint_requests",
    ),
    "legacy no-token Edge must not take over an existing owner",
  );
  assert(body.includes("p_request_id = '__legacy_inflight__'"));
  assertEquals(body.includes("increment_usage"), false);
  assertEquals(
    body.includes("PRACTICE_HINT_OWNER_MISMATCH"),
    false,
    "completed claim replay must not require the current worker token",
  );
});

Deno.test("Record separates physical quota from formal Hint consumption", () => {
  const body = functionBody("record_practice_hint");
  const compact = compactSql(body);
  const ownerFence = body.indexOf("PRACTICE_HINT_OWNER_MISMATCH");
  const duplicate = body.indexOf("v_request.state = 'settled'");
  const cap = body.indexOf("v_session.hint_count >= p_max_hints");
  const charge = body.indexOf("PERFORM public.increment_usage(");
  assert(ownerFence >= 0 && duplicate >= 0 && cap >= 0 && charge >= 0);
  assert(
    ownerFence < duplicate,
    "owner fencing must beat duplicate record replay",
  );
  assert(duplicate < cap, "duplicate record must replay before cap");
  assert(cap < charge, "cap must be checked before physical quota charge");
  assert(compact.includes("p_charge_quota = TRUE AND p_charged = FALSE"));
  assert(
    compact.includes(
      "v_request.is_prefetch IS DISTINCT FROM (NOT p_charged)",
    ),
  );
  assert(compact.includes("v_request.claimed_ai_count <> v_session.ai_count"));
  assert(
    compact.includes(
      "v_request.generation_token IS DISTINCT FROM p_generation_token",
    ),
  );
  assert(compact.includes("p_max_replies IS NOT NULL"));
  assert(compact.includes("v_session.ai_count >= p_max_replies"));
  assert(
    compact.includes(
      "public.increment_usage( p_user_id, 1, p_monthly_limit, p_daily_limit )",
    ),
  );
  assert(compact.includes("hint_count = v_next_hint_count"));
  assert(compact.includes("state = 'prefetched'"));
  assert(compact.includes("state = 'settled'"));
  assert(compact.includes("'costDeducted'"));
  assert(compact.includes("'hintUsedCount'"));
  assert(compact.includes("'monthlyRemaining'"));
  assert(compact.includes("'dailyRemaining'"));
});

Deno.test("Settle is exact-once and validates caps, turn identity, and quota", () => {
  const body = functionBody("settle_prefetched_practice_hint");
  const compact = compactSql(body);
  const replay = body.indexOf("v_request.state = 'settled'");
  const cap = body.indexOf("v_session.hint_count >= p_max_hints");
  const charge = body.indexOf("PERFORM public.increment_usage(");
  assert(replay >= 0 && cap >= 0 && charge >= 0);
  assert(replay < cap, "settle retry must replay before mutable caps");
  assert(cap < charge, "settle must check caps before charging");
  assert(compact.includes("v_request.state <> 'prefetched'"));
  assert(compact.includes("v_request.claimed_ai_count <> v_session.ai_count"));
  assert(compact.includes("v_session.ai_count >= p_max_replies"));
  assert(
    compact.includes(
      "public.increment_usage( p_user_id, 1, p_monthly_limit, p_daily_limit )",
    ),
  );
  assert(compact.includes("state = 'settled'"));
  assert(compact.includes("charged = TRUE"));
  assert(compact.includes("last_hint_request_id = p_request_id"));
});

Deno.test("Discard and release never clear another request owner", () => {
  const discard = functionBody("discard_prefetched_practice_hint");
  assert(discard.includes("FOR UPDATE"));
  assert(discard.includes("v_request.state = 'settled'"));
  assert(discard.includes("request_id = p_request_id"));
  assert(discard.includes("state IN ('generating', 'prefetched')"));

  const release = functionBody("release_practice_hint_generation");
  const compactRelease = compactSql(release);
  assert(release.includes("FOR UPDATE"));
  assert(compactRelease.includes("request_id = p_request_id"));
  assert(compactRelease.includes("state = 'generating'"));
  assert(
    compactRelease.includes(
      "generation_token IS NOT DISTINCT FROM p_generation_token",
    ),
  );
  assert(
    compactRelease.includes("IF v_rows > 0 THEN") &&
      compactRelease.includes("hint_generation_started_at = NULL"),
    "request-aware release may clear the latch only after deleting its owner row",
  );
});

Deno.test("New RPCs are service-role only and reload the schema cache", () => {
  for (
    const name of [
      "claim_practice_hint_generation",
      "record_practice_hint",
      "settle_prefetched_practice_hint",
      "discard_prefetched_practice_hint",
      "release_practice_hint_generation",
      "prepare_practice_subscription_usage",
    ]
  ) {
    assert(
      migration.includes(`REVOKE EXECUTE ON FUNCTION public.${name}`),
      `${name} must revoke client execution`,
    );
    assert(
      migration.includes(`GRANT EXECUTE ON FUNCTION public.${name}`),
      `${name} must grant service_role execution`,
    );
  }
  required("FROM PUBLIC, anon, authenticated");
  required("TO service_role");
  required("NOTIFY pgrst, 'reload schema';");
});

Deno.test("Account deletion still removes the parent session ledger", () => {
  assert(
    deleteAccountSource.includes('{ table: "practice_chat_sessions"'),
    "practice_hint_requests relies on the existing parent delete plus FK cascade",
  );
});
