import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { KEYBOARD_ASSIST_STRATEGIES } from "./contract.ts";

const migrationSource = await Deno.readTextFile(
  new URL(
    "../../migrations/20260727130000_keyboard_assist_exactly_once.sql",
    import.meta.url,
  ),
);
const normalizedMigrationSource = migrationSource.replace(/\s+/g, " ").trim();

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

Deno.test("keyboard assist denies every public RPC to untrusted roles", () => {
  for (
    const signature of [
      "public.is_valid_keyboard_assist_result(JSONB)",
      "public.cleanup_expired_keyboard_assist_requests()",
      "public.claim_keyboard_assist_request( UUID, UUID, TEXT, SMALLINT, UUID )",
      "public.renew_keyboard_assist_claim( UUID, UUID, TEXT, UUID )",
      "public.release_keyboard_assist_claim( UUID, UUID, TEXT, UUID )",
      "public.settle_keyboard_assist_request( UUID, UUID, TEXT, UUID, JSONB, INTEGER, INTEGER, BOOLEAN )",
      "public.expire_keyboard_assist_request( UUID, UUID )",
      "public.keyboard_assist_hmac_key_versions()",
      "public.keyboard_assist_contract_version()",
    ]
  ) {
    assert(
      normalizedMigrationSource.includes(
        `REVOKE EXECUTE ON FUNCTION ${signature} FROM PUBLIC;`,
      ),
      `PUBLIC can execute ${signature}`,
    );
    assert(
      normalizedMigrationSource.includes(
        `REVOKE EXECUTE ON FUNCTION ${signature} FROM anon, authenticated;`,
      ),
      `untrusted app roles can execute ${signature}`,
    );
    assert(
      normalizedMigrationSource.includes(
        `GRANT EXECUTE ON FUNCTION ${signature} TO service_role;`,
      ),
      `service_role cannot execute ${signature}`,
    );
  }
});

Deno.test("the settlement validator knows the strategies we actually ship", () => {
  // The taxonomy moved to 延展／調情／幽默 in TypeScript and Swift, but this
  // allow-list — which backs both the CHECK constraint and
  // settle_keyboard_assist_request — was left on the old five. Every valid
  // result was rejected at settlement and surfaced as a bare
  // `service_unavailable` after the model had already been paid for. The Deno
  // suite stayed green throughout because it only ever exercised validate.ts.
  const migrationsDir = new URL("../../migrations/", import.meta.url);
  const names = [...Deno.readDirSync(migrationsDir)]
    .filter((entry) => entry.isFile && entry.name.endsWith(".sql"))
    .map((entry) => entry.name)
    .sort();

  // The last migration to define the function is the one Postgres is running.
  let definition: string | null = null;
  for (const name of names) {
    const source = Deno.readTextFileSync(new URL(name, migrationsDir));
    if (source.includes("FUNCTION public.is_valid_keyboard_assist_result")) {
      definition = source;
    }
  }
  assert(definition !== null, "no migration defines the settlement validator");

  const anchor = "option ->> 'strategy' NOT IN (";
  const at = definition.indexOf(anchor);
  assert(at >= 0, "the validator no longer gates on strategy");
  const list = definition.slice(
    at + anchor.length,
    definition.indexOf(")", at),
  );
  assertEquals(
    [...list.matchAll(/'([a-z_]+)'/g)].map((match) => match[1]).sort(),
    [...KEYBOARD_ASSIST_STRATEGIES].sort(),
  );
});
