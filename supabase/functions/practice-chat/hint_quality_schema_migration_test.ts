import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260712200532_practice_hint_quality_schema_version.sql",
    import.meta.url,
  ),
);

Deno.test("typed fact migration makes the legacy replacement claim version-aware", () => {
  assert(
    migration.includes(
      "v_request.result ->> 'qualitySchemaVersion' = 'typed-facts-v1'",
    ),
  );
  const versionCheck = migration.indexOf("qualitySchemaVersion");
  const replayBranch = migration.indexOf(
    "IF NOT v_request.legacy_replacement_pending",
  );
  assert(versionCheck >= 0 && versionCheck < replayBranch);
  assert(
    migration.includes(
      "quota_already_paid := v_request.result -> 'costDeducted' = '1'::jsonb",
    ),
  );
  assertEquals(migration.includes("hint_count = hint_count + 1"), false);
  assertEquals(migration.includes("increment_usage"), false);
});

Deno.test("typed fact migration preserves the token-fenced replacement path", () => {
  for (
    const expected of [
      "legacy_replacement_pending = TRUE",
      "legacy_replacement_generation_token = p_generation_token",
      "hint_generation_owner_token = p_generation_token",
      "PRACTICE_HINT_IN_FLIGHT",
      "PRACTICE_HINT_STALE",
    ]
  ) {
    assert(migration.includes(expected), expected);
  }
});

Deno.test("typed fact migration invalidates only pre-version Debrief snapshots", () => {
  assert(
    migration.includes(
      "CREATE OR REPLACE FUNCTION public.invalidate_legacy_practice_ai_snapshot",
    ),
  );
  assert(
    migration.includes(
      "v_result ->> 'qualitySchemaVersion' = 'typed-facts-v1'",
    ),
  );
  assert(
    migration.includes(
      "v_entry := jsonb_set(v_entry, '{result}', 'null'::jsonb",
    ),
  );
  assertEquals(migration.includes("debrief_count = debrief_count - 1"), false);
  assertEquals(migration.includes("debrief_count = 0"), false);
});
