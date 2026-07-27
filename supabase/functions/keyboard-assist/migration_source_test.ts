import { assert } from "https://deno.land/std@0.168.0/testing/asserts.ts";

const migrationSource = await Deno.readTextFile(
  new URL(
    "../../migrations/20260727130000_keyboard_assist_exactly_once.sql",
    import.meta.url,
  ),
);

Deno.test("keyboard assist migration owns a private versioned replay ledger", () => {
  assert(
    migrationSource.includes(
      "CREATE TABLE IF NOT EXISTS public.keyboard_assist_requests",
    ),
  );
  assert(migrationSource.includes("hmac_key_version SMALLINT"));
  assert(migrationSource.includes("PRIMARY KEY (user_id, request_id)"));
  assert(migrationSource.includes("ENABLE ROW LEVEL SECURITY"));
  assert(
    migrationSource.includes(
      "REVOKE ALL ON TABLE public.keyboard_assist_requests FROM anon, authenticated",
    ),
  );
  assert(migrationSource.includes("interval '24 hours'"));
  assert(migrationSource.includes("interval '55 seconds'"));
  assert(migrationSource.includes("is_valid_keyboard_assist_result"));
  assert(migrationSource.includes("result_json ->> 'status' = 'ready'"));
  assert(
    migrationSource.includes(
      "result_json ->> 'status' = 'needs_speaker_confirmation'",
    ),
  );
  assert(migrationSource.includes("jsonb_array_length"));
  assert(migrationSource.includes("COUNT(DISTINCT"));
  assert(migrationSource.includes("好感度"));
  assert(migrationSource.includes("心理診斷"));
  assert(migrationSource.includes("|[%％]"));
});

Deno.test("keyboard assist migration owns claim, renew, release, settle, and expiry", () => {
  for (
    const functionName of [
      "claim_keyboard_assist_request",
      "renew_keyboard_assist_claim",
      "release_keyboard_assist_claim",
      "settle_keyboard_assist_request",
      "expire_keyboard_assist_request",
      "cleanup_expired_keyboard_assist_requests",
    ]
  ) {
    assert(migrationSource.includes(functionName), functionName);
  }
  assert(migrationSource.includes("p_hmac_key_version SMALLINT"));
  assert(migrationSource.includes("KEYBOARD_ASSIST_REPLAY_MISMATCH"));
  assert(migrationSource.includes("KEYBOARD_ASSIST_OWNER_MISMATCH"));
  assert(migrationSource.includes("AND owner_token = p_owner_token"));
  assert(migrationSource.includes("AND input_hash = p_input_hash"));
  assert(migrationSource.includes("AND lease_expires_at <= now()"));
  assert(migrationSource.includes("PERFORM public.increment_usage("));
  assert(migrationSource.includes("p_user_id,\n      1,"));
  assert(migrationSource.includes("FOR UPDATE"));
});

Deno.test("keyboard assist DB health exposes contract and retained HMAC versions", () => {
  assert(migrationSource.includes("keyboard_assist_contract_version"));
  assert(migrationSource.includes("'keyboard-assist-v1'::TEXT"));
  assert(migrationSource.includes("keyboard_assist_hmac_key_versions"));
  assert(
    migrationSource.includes(
      "WHERE created_at >= now() - interval '25 hours'",
    ),
  );
  assert(
    migrationSource.includes(
      "WHERE created_at < now() - interval '24 hours';",
    ),
  );
});
