import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260710120000_practice_debrief_idempotency.sql",
    import.meta.url,
  ),
);

function compact(value: string): string {
  return value.replace(/\s+/g, " ");
}

function functionBody(name: string): string {
  const start = migration.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
  assert(start >= 0, `missing ${name}`);
  const next = migration.indexOf(
    "CREATE OR REPLACE FUNCTION public.",
    start + 1,
  );
  return next >= 0 ? migration.slice(start, next) : migration.slice(start);
}

Deno.test("debrief idempotency migration adds bounded replay columns without raw transcript", () => {
  assert(migration.includes("last_debrief_request_id TEXT"));
  assert(migration.includes("last_debrief_result JSONB"));
  assert(migration.includes("last_debrief_started_at TIMESTAMPTZ"));
  assert(
    migration.includes(
      "practice_chat_sessions_last_debrief_request_id_check",
    ),
  );
  assert(
    migration.includes(
      "length(last_debrief_request_id) BETWEEN 1 AND 64",
    ),
  );
  assertEquals(migration.includes("raw_transcript JSONB"), false);
});

Deno.test("debrief claim keeps legacy calls compatible and replays before cap", () => {
  const body = functionBody("claim_practice_debrief");
  const compactBody = compact(body);
  assert(
    migration.includes(
      "DROP FUNCTION IF EXISTS public.claim_practice_debrief(UUID, TEXT, INTEGER);",
    ),
  );
  assert(compactBody.includes("p_request_id TEXT DEFAULT NULL"));
  assert(
    body.includes(
      "current_debrief_count INTEGER,\n  replay BOOLEAN,\n  in_flight BOOLEAN,\n  stored_result JSONB",
    ),
  );
  assert(body.includes("FOR UPDATE"));
  const replayAt = body.indexOf(
    "v_row.last_debrief_request_id = p_request_id",
  );
  const capAt = body.indexOf("v_row.debrief_count >= p_max_debriefs");
  assert(replayAt >= 0 && capAt >= 0 && replayAt < capAt);
  assert(body.includes("v_row.last_debrief_result IS NOT NULL"));
});

Deno.test("fresh unfinished debrief is single-flight and stale same request can recover without another slot", () => {
  const body = functionBody("claim_practice_debrief");
  const freshLatch = body.indexOf("last_debrief_started_at > now()");
  const inFlight = body.indexOf("in_flight := TRUE", freshLatch);
  const sameRequestBranch = body.indexOf(
    "v_row.last_debrief_request_id = p_request_id THEN",
    inFlight,
  );
  const increment = body.indexOf("debrief_count = debrief_count + 1");
  assert(freshLatch >= 0 && inFlight > freshLatch);
  assert(sameRequestBranch > inFlight && increment > sameRequestBranch);
  assert(sameRequestBranch < increment);
  const branch = body.slice(sameRequestBranch, increment);
  assert(branch.includes("replay := FALSE"));
  assert(branch.includes("in_flight := FALSE"));
  assert(branch.includes("last_debrief_started_at = now()"));
  assertEquals(branch.includes("debrief_count + 1"), false);
});

Deno.test("debrief record stores only the matching request response", () => {
  const body = functionBody("record_practice_debrief");
  assert(body.includes(")\nRETURNS JSONB\nLANGUAGE plpgsql"));
  assert(body.includes("jsonb_typeof(p_result) <> 'object'"));
  assert(body.includes("FOR UPDATE"));
  assert(
    body.includes(
      "v_row.last_debrief_request_id IS DISTINCT FROM p_request_id",
    ),
  );
  assert(body.includes("PRACTICE_DEBRIEF_REQUEST_MISMATCH"));
  assert(body.includes("IF v_row.last_debrief_result IS NOT NULL THEN"));
  assert(body.includes("RETURN v_row.last_debrief_result"));
  assert(body.includes("last_debrief_result = p_result"));
  assert(body.includes("last_debrief_started_at = NULL"));
  assert(body.includes("RETURN p_result"));
});

Deno.test("debrief idempotency RPCs remain service-role only", () => {
  for (
    const signature of [
      "claim_practice_debrief(UUID, TEXT, INTEGER, TEXT)",
      "record_practice_debrief(UUID, TEXT, TEXT, JSONB)",
    ]
  ) {
    assert(
      migration.includes(
        `REVOKE EXECUTE ON FUNCTION public.${signature}\n  FROM PUBLIC, anon, authenticated;`,
      ),
    );
    assert(
      migration.includes(
        `GRANT EXECUTE ON FUNCTION public.${signature}\n  TO service_role;`,
      ),
    );
  }
  assert(migration.includes("NOTIFY pgrst, 'reload schema';"));
});
