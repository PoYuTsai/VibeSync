import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260711150000_practice_ai_no_canned_fallback.sql",
    import.meta.url,
  ),
);

function functionBody(name: string): string {
  const create = `CREATE FUNCTION public.${name}(`;
  const replace = `CREATE OR REPLACE FUNCTION public.${name}(`;
  const start = Math.max(migration.indexOf(create), migration.indexOf(replace));
  assert(start >= 0, `missing ${name}`);
  const nextCreate = migration.indexOf("CREATE FUNCTION public.", start + 1);
  const nextReplace = migration.indexOf(
    "CREATE OR REPLACE FUNCTION public.",
    start + 1,
  );
  const candidates = [nextCreate, nextReplace].filter((value) => value >= 0);
  const end = candidates.length > 0
    ? Math.min(...candidates)
    : migration.length;
  return migration.slice(start, end);
}

Deno.test("debrief generation is token-fenced and retryable without another count", () => {
  assert(migration.includes("last_debrief_generation_token TEXT"));
  assert(migration.includes("debrief_request_ledger JSONB NOT NULL"));
  const claim = functionBody("claim_practice_debrief");
  assert(claim.includes("p_generation_token TEXT DEFAULT NULL"));
  const exactRequest = claim.indexOf("IF v_entry IS NOT NULL THEN");
  assert(exactRequest >= 0);
  const retryBranch = claim.slice(exactRequest);
  assert(
    retryBranch.includes("'generation_token', p_generation_token"),
  );
  assertEquals(claim.includes("debrief_count = debrief_count + 1"), false);
  assert(claim.includes("'counted', FALSE"));

  const record = functionBody("record_practice_debrief");
  assert(record.includes("PRACTICE_DEBRIEF_GENERATION_MISMATCH"));
  assert(record.includes("v_entry ->> 'started_at' IS NULL"));
  assert(
    record.includes(
      "v_entry ->> 'generation_token' IS DISTINCT FROM p_generation_token",
    ),
  );
  assert(
    record.includes(
      "v_row.last_debrief_request_id IS DISTINCT FROM p_request_id",
    ),
  );
  assert(
    record.includes("p_result ->> 'generationSource' IS DISTINCT FROM 'model'"),
  );
  assert(
    record.includes(
      "p_result -> 'fallbackUsed' IS DISTINCT FROM 'false'::jsonb",
    ),
  );
  assert(record.includes("v_new_debrief_count := v_row.debrief_count + 1"));
  assert(record.includes("SET debrief_count = v_new_debrief_count"));
  assert(record.includes("'counted', TRUE"));
  assert(record.includes("'generation_token', NULL"));
});

Deno.test("bounded debrief ledger keeps A to B to A exact replay before cap", () => {
  const validator = functionBody("is_valid_practice_debrief_request_ledger");
  assert(
    validator.includes("(SELECT count(*) FROM jsonb_each(p_ledger)) > 3"),
  );
  assert(
    validator.includes("jsonb_typeof(entry.payload) IS DISTINCT FROM 'object'"),
  );
  assert(
    validator.includes(
      "(SELECT count(*) FROM jsonb_each(entry.payload)) <> 4",
    ),
  );
  assert(validator.includes("entry.payload -> 'counted'"));
  assert(validator.includes("IS DISTINCT FROM 'boolean'"));
  assert(validator.includes("length(entry.request_id) NOT BETWEEN 1 AND 64"));

  assert(
    migration.includes(
      "NOT s.debrief_request_ledger ? s.last_debrief_request_id",
    ),
  );
  assert(migration.includes("'result', s.last_debrief_result"));
  assert(migration.includes("'counted', TRUE"));

  const claim = functionBody("claim_practice_debrief");
  const exactReplay = claim.indexOf("v_entry -> 'result' <> 'null'::jsonb");
  const cap = claim.indexOf("v_row.debrief_count >= p_max_debriefs");
  assert(exactReplay >= 0 && exactReplay < cap);
  assertEquals(claim.includes("debrief_count = debrief_count + 1"), false);
  assert(claim.includes("v_entry := v_ledger -> p_request_id"));
  assert(claim.includes("stored_result := v_entry -> 'result'"));
});

Deno.test("debrief rejects tokenless legacy claims before count mutation", () => {
  const claim = functionBody("claim_practice_debrief");
  const rejectMissingId = claim.indexOf("IF p_request_id IS NULL");
  const rejectMissingToken = claim.indexOf("IF p_generation_token IS NULL");
  const ledgerWrite = claim.indexOf("SET debrief_request_ledger = v_ledger");
  assert(rejectMissingId >= 0 && rejectMissingId < ledgerWrite);
  assert(rejectMissingToken >= 0 && rejectMissingToken < ledgerWrite);
});

Deno.test("debrief release clears only the matching unfinished token owner", () => {
  const release = functionBody("release_practice_debrief_generation");
  assert(release.includes("v_entry := v_ledger -> p_request_id"));
  assert(release.includes("v_entry -> 'result' <> 'null'::jsonb"));
  assert(
    release.includes(
      "v_entry ->> 'generation_token' IS DISTINCT FROM p_generation_token",
    ),
  );
  assert(
    release.includes(
      "v_session.last_debrief_request_id IS DISTINCT FROM p_request_id",
    ),
  );
  assert(release.includes("'{started_at}'"));
  assert(release.includes("'null'::jsonb"));
  assertEquals(release.includes("'{generation_token}'"), false);
  assertEquals(release.includes("SET debrief_count ="), false);
  assert(release.includes("v_entry -> 'counted' = 'false'::jsonb"));
  assert(release.includes("v_ledger := v_ledger - p_request_id"));
  assert(release.includes("last_debrief_request_id = NULL"));
});

Deno.test("released or superseded debrief worker cannot resurrect its result", () => {
  const claim = functionBody("claim_practice_debrief");
  assert(
    claim.includes(
      "v_previous_entry := v_ledger -> v_row.last_debrief_request_id",
    ),
  );
  assert(
    claim.includes(
      "v_previous_entry -> 'counted' = 'false'::jsonb",
    ),
  );
  assert(
    claim.includes("v_ledger := v_ledger - v_row.last_debrief_request_id"),
  );
  const previousTombstone = claim.slice(
    claim.indexOf("v_previous_entry := jsonb_set("),
  );
  assert(
    previousTombstone.indexOf("'{started_at}'") >= 0 &&
      previousTombstone.indexOf("'{started_at}'") <
        previousTombstone.indexOf("'null'::jsonb"),
  );

  const release = functionBody("release_practice_debrief_generation");
  assert(release.includes("v_entry ->> 'started_at' IS NULL"));
  assertEquals(release.includes("'{generation_token}'"), false);

  const record = functionBody("record_practice_debrief");
  const activeFence = record.indexOf("v_entry ->> 'started_at' IS NULL");
  const recordWrite = record.indexOf("'result', p_result");
  assert(activeFence >= 0 && activeFence < recordWrite);
  assert(record.includes("PRACTICE_DEBRIEF_GENERATION_MISMATCH"));
});

Deno.test("debrief count is committed only with generated result persistence", () => {
  const claim = functionBody("claim_practice_debrief");
  assertEquals(claim.includes("debrief_count = debrief_count + 1"), false);
  assert(claim.includes("'counted', FALSE"));

  const record = functionBody("record_practice_debrief");
  const activeFence = record.indexOf("PRACTICE_DEBRIEF_GENERATION_MISMATCH");
  const countedBranch = record.indexOf(
    "v_entry -> 'counted' = 'false'::jsonb",
  );
  const increment = record.indexOf(
    "v_new_debrief_count := v_row.debrief_count + 1",
  );
  const resultWrite = record.indexOf("'result', p_result");
  assert(
    activeFence >= 0 && activeFence < countedBranch &&
      countedBranch < increment && increment < resultWrite,
  );

  const release = functionBody("release_practice_debrief_generation");
  assertEquals(release.includes("debrief_count ="), false);
  assert(release.includes("v_ledger := v_ledger - p_request_id"));
});

Deno.test("Hint decision resolver trusts only a settled charged matching snapshot", () => {
  const resolve = functionBody("resolve_practice_hint_decision");
  for (
    const expected of [
      "r.state = 'settled'",
      "r.charged = TRUE",
      "r.result ->> 'generationSource' = 'model'",
      "r.result -> 'fallbackUsed' = 'false'::jsonb",
      "reply.value ->> 'type' = p_hint_type",
      "reply.value ->> 'text'",
      "v_decision := v_reply -> 'decision'",
      "PRACTICE_HINT_LINEAGE_MISMATCH",
      "PRACTICE_HINT_DECISION_NOT_READY",
    ]
  ) {
    assert(resolve.includes(expected), expected);
  }
  assertEquals(resolve.includes("v_result -> 'decision'"), false);
});

Deno.test("matched warm and steady replies keep distinct authoritative decisions", () => {
  const replies = [
    { type: "warm_up", text: "warm", decision: { move: "share_then_ask" } },
    { type: "steady", text: "steady", decision: { move: "invite_softly" } },
  ];
  const resolveMove = (type: string, text: string) =>
    replies.find((reply) => reply.type === type && reply.text === text)
      ?.decision
      .move;
  assertEquals(resolveMove("warm_up", "warm"), "share_then_ask");
  assertEquals(resolveMove("steady", "steady"), "invite_softly");
  assertEquals(
    functionBody("resolve_practice_hint_decision").includes(
      "v_decision := v_reply -> 'decision'",
    ),
    true,
  );
});

Deno.test("legacy Hint replacement preserves count and quota provenance", () => {
  const invalidate = functionBody("invalidate_legacy_practice_ai_snapshot");
  assert(invalidate.includes("PRACTICE_HINT_REPLACEMENT_REQUIRED"));
  assertEquals(invalidate.includes("hint_count = GREATEST"), false);

  const claim = functionBody("claim_legacy_practice_hint_replacement");
  assert(claim.includes("legacy_replacement_pending = TRUE"));
  assertEquals(claim.includes("v_safe_legacy_direct"), false);
  assert(
    claim.includes(
      "v_request.result -> 'costDeducted' IS DISTINCT FROM '0'::jsonb",
    ),
  );
  assert(
    claim.includes(
      "v_request.result -> 'costDeducted' IS DISTINCT FROM '1'::jsonb",
    ),
  );
  assert(
    claim.includes(
      "quota_already_paid := v_request.result -> 'costDeducted' = '1'::jsonb",
    ),
  );
  assertEquals(claim.includes("hint_count = hint_count + 1"), false);

  const record = functionBody("record_legacy_practice_hint_replacement");
  assert(
    record.includes(
      "did_charge := p_charge_quota AND NOT v_quota_already_paid",
    ),
  );
  assert(record.includes("WHEN v_quota_already_paid OR did_charge THEN 1"));
  assert(record.includes("'hintUsedCount', v_session.hint_count"));
  assertEquals(record.includes("hint_count ="), false);

  const release = functionBody("release_legacy_practice_hint_replacement");
  assert(release.includes("legacy_replacement_started_at = NULL"));
  assertEquals(
    release.includes("legacy_replacement_generation_token = NULL"),
    false,
  );
  assertEquals(invalidate.includes("debrief_count = debrief_count - 1"), false);
});

Deno.test("normal and legacy Hint claims share one strict token-fenced latch", () => {
  assert(migration.includes("hint_generation_owner_token TEXT"));
  assert(migration.includes(
    "practice_chat_sessions_hint_generation_owner_check",
  ));
  assert(migration.includes(
    "hint_generation_started_at IS NULL\n      AND hint_generation_owner_token IS NULL",
  ));
  assert(migration.includes(
    "hint_generation_started_at IS NOT NULL\n      AND hint_generation_owner_token IS NOT NULL",
  ));

  const normalClaim = functionBody("claim_practice_hint_generation");
  const normalFreshFence = normalClaim.indexOf(
    "v_session.hint_generation_started_at > now() - interval '2 minutes'",
  );
  const normalLegacyTombstone = normalClaim.indexOf(
    "SET legacy_replacement_started_at = NULL",
  );
  assert(normalClaim.includes("p_generation_token IS NULL"));
  assert(
    normalFreshFence >= 0 && normalFreshFence < normalLegacyTombstone,
  );
  assert(normalClaim.includes(
    "hint_generation_owner_token = p_generation_token",
  ));

  const legacyClaim = functionBody("claim_legacy_practice_hint_replacement");
  const legacyFreshFence = legacyClaim.lastIndexOf(
    "v_session.hint_generation_started_at > now() - interval '2 minutes'",
  );
  const legacyTombstone = legacyClaim.indexOf(
    "SET legacy_replacement_started_at = NULL",
  );
  const normalDelete = legacyClaim.indexOf("AND r.state = 'generating'");
  const legacyTokenWrite = legacyClaim.indexOf(
    "hint_generation_owner_token = p_generation_token",
  );
  assert(
    legacyFreshFence >= 0 && legacyFreshFence < legacyTombstone &&
      legacyTombstone < normalDelete && normalDelete < legacyTokenWrite,
  );
});

Deno.test("late legacy Hint workers cannot charge or release a newer latch", () => {
  const record = functionBody("record_legacy_practice_hint_replacement");
  const activeLatchFence = record.indexOf(
    "v_session.hint_generation_started_at IS NULL",
  );
  const tokenFence = record.indexOf(
    "v_session.hint_generation_owner_token IS DISTINCT FROM p_generation_token",
  );
  const charge = record.indexOf("PERFORM public.increment_usage(");
  assert(
    activeLatchFence >= 0 && tokenFence > activeLatchFence &&
      charge > tokenFence,
  );
  assert(record.includes(
    "AND s.hint_generation_owner_token = p_generation_token",
  ));
  assert(record.includes("IF v_session_rows <> 1 THEN"));

  const release = functionBody("release_legacy_practice_hint_replacement");
  const releaseFence = release.indexOf(
    "v_session.hint_generation_owner_token IS DISTINCT FROM p_generation_token",
  );
  const requestTombstone = release.indexOf(
    "SET legacy_replacement_started_at = NULL",
  );
  assert(releaseFence >= 0 && releaseFence < requestTombstone);
  assert(release.includes(
    "AND s.hint_generation_owner_token = p_generation_token",
  ));
  assert(release.includes("RETURN FALSE;"));

  const clearLatch = functionBody("clear_practice_hint_owner_token");
  assert(clearLatch.includes("NEW.hint_generation_owner_token := NULL"));
  assertEquals(
    clearLatch.includes("UPDATE public.practice_hint_requests"),
    false,
  );

  const normalRelease = functionBody("release_practice_hint_generation");
  const normalReleaseTokenFence = normalRelease.indexOf(
    "v_session.hint_generation_owner_token IS DISTINCT FROM p_generation_token",
  );
  const normalReleaseDelete = normalRelease.indexOf(
    "DELETE FROM public.practice_hint_requests",
  );
  assert(
    normalReleaseTokenFence >= 0 &&
      normalReleaseTokenFence < normalReleaseDelete,
  );
  assert(normalRelease.includes(
    "AND s.hint_generation_owner_token = p_generation_token",
  ));
  assertEquals(normalRelease.includes("v_had_latch"), false);
});

Deno.test("generated-only Hint CHECK fails closed for missing markers", () => {
  assert(migration.includes(
    "result ->> 'generationSource' IS NOT DISTINCT FROM 'model'",
  ));
  assert(migration.includes(
    "result -> 'fallbackUsed' IS NOT DISTINCT FROM 'false'::jsonb",
  ));
  assertEquals(
    migration.includes(
      "result ->> 'generationSource' = 'model'\n          AND result -> 'fallbackUsed' = 'false'::jsonb",
    ),
    false,
  );
});

Deno.test("prefetch discard never deletes a generating token owner", () => {
  const discard = functionBody("discard_prefetched_practice_hint");
  assert(discard.includes("v_request.state = 'generating'"));
  assert(discard.includes("RAISE EXCEPTION 'PRACTICE_HINT_IN_FLIGHT'"));
  assert(discard.includes("r.state = 'prefetched'"));
  assertEquals(
    discard.includes("state IN ('generating', 'prefetched')"),
    false,
  );
});

Deno.test("new generated-only RPCs remain service-role only", () => {
  for (
    const signature of [
      "is_valid_practice_debrief_request_ledger(JSONB)",
      "claim_practice_hint_generation(UUID, TEXT, INTEGER, TEXT, BOOLEAN, TEXT, INTEGER)",
      "release_practice_hint_generation(UUID, TEXT, TEXT, TEXT)",
      "claim_practice_debrief(UUID, TEXT, INTEGER, TEXT, TEXT)",
      "record_practice_debrief(UUID, TEXT, TEXT, JSONB, TEXT)",
      "release_practice_debrief_generation(UUID, TEXT, TEXT, TEXT)",
      "invalidate_legacy_practice_ai_snapshot(UUID, TEXT, TEXT, TEXT)",
      "claim_legacy_practice_hint_replacement(UUID, TEXT, TEXT, TEXT, INTEGER)",
      "record_legacy_practice_hint_replacement(UUID, TEXT, TEXT, TEXT, JSONB, BOOLEAN, INTEGER, INTEGER, INTEGER)",
      "release_legacy_practice_hint_replacement(UUID, TEXT, TEXT, TEXT)",
      "resolve_practice_hint_decision(UUID, TEXT, TEXT, TEXT, TEXT)",
    ]
  ) {
    assert(migration.includes(
      `REVOKE EXECUTE ON FUNCTION public.${signature}\n  FROM PUBLIC, anon, authenticated;`,
    ));
    assert(migration.includes(
      `GRANT EXECUTE ON FUNCTION public.${signature}\n  TO service_role;`,
    ));
  }
  assert(migration.includes(
    "REVOKE EXECUTE ON FUNCTION public.clear_practice_hint_owner_token()\n  FROM PUBLIC, anon, authenticated, service_role;",
  ));
});
