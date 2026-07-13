import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260713120000_practice_debrief_semantic_owner_window.sql",
    import.meta.url,
  ),
);

Deno.test("semantic Debrief owner window stays above both 90s client timeouts", () => {
  assert(migration.includes("INTERVAL '105 seconds'"));
  assertEquals(migration.includes("INTERVAL '45 seconds'"), false);
  assertEquals(migration.includes("INTERVAL '90 seconds'"), false);
});

Deno.test("semantic Debrief owner migration preserves token fencing and replay-before-cap", () => {
  const replay = migration.indexOf("Exact completed replay");
  const activeFence = migration.indexOf("INTERVAL '105 seconds'");
  const tokenWrite = migration.indexOf(
    "last_debrief_generation_token = p_generation_token",
  );
  const cap = migration.indexOf("v_row.debrief_count >= p_max_debriefs");
  assert(replay >= 0 && activeFence > replay);
  assert(tokenWrite > activeFence && cap > tokenWrite);
  assert(migration.includes("FOR UPDATE"));
  assert(migration.includes("v_entry -> 'result' <> 'null'::jsonb"));
  assert(migration.includes("p_generation_token TEXT DEFAULT NULL"));
});

Deno.test("semantic Debrief owner migration remains service-role only", () => {
  const signature =
    "public.claim_practice_debrief(UUID, TEXT, INTEGER, TEXT, TEXT)";
  assert(
    migration.includes(
      `REVOKE EXECUTE ON FUNCTION ${signature}\n  FROM PUBLIC, anon, authenticated;`,
    ),
  );
  assert(
    migration.includes(
      `GRANT EXECUTE ON FUNCTION ${signature}\n  TO service_role;`,
    ),
  );
  assert(migration.includes("NOTIFY pgrst, 'reload schema';"));
});

Deno.test("semantic quality schema invalidates pre-review Hint and Debrief snapshots", () => {
  assert(
    migration.includes(
      "claim_legacy_practice_hint_replacement(uuid,text,text,text,integer)",
    ),
  );
  assert(
    migration.includes(
      "invalidate_legacy_practice_ai_snapshot(uuid,text,text,text)",
    ),
  );
  assert(migration.includes("'typed-facts-v1'"));
  assert(migration.includes("'semantic-quality-v2'"));
  assertEquals(
    migration.match(/quality marker drifted/g)?.length,
    2,
  );
});
