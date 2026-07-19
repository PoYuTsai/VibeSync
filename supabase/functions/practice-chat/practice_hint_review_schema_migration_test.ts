import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260719170000_practice_hint_review_schema_version.sql",
    import.meta.url,
  ),
);

Deno.test("Hint review certification participates in the DB replay predicate", () => {
  assert(
    migration.includes(
      "claim_legacy_practice_hint_replacement(uuid,text,text,text,integer)",
    ),
  );
  assert(
    migration.includes(
      "v_request.result ->> ''qualitySchemaVersion'' = ''semantic-quality-v2''",
    ),
  );
  assert(
    migration.includes(
      "v_request.result ->> ''hintReviewSchemaVersion'' = ''dual-semantic-assessment-v1''",
    ),
  );
  assert(migration.includes("EXECUTE v_updated;"));
  assert(
    migration.includes(
      "claim_legacy_practice_hint_replacement review marker drifted",
    ),
  );
});

Deno.test("Hint review certification replacement preserves paid quota ownership", () => {
  assertEquals(migration.includes("hint_count = hint_count + 1"), false);
  assertEquals(migration.includes("increment_usage"), false);
  assertEquals(migration.includes("costDeducted"), false);
  assertEquals(
    migration.includes("invalidate_legacy_practice_ai_snapshot"),
    false,
  );
});

Deno.test("Hint review certification migration is ordered before the Edge rollout", () => {
  const oldPredicate = migration.indexOf("v_old_predicate");
  const guardedReplacement = migration.indexOf(
    "position(v_old_predicate IN v_definition)",
  );
  const execute = migration.indexOf("EXECUTE v_updated;");
  assert(oldPredicate >= 0 && guardedReplacement > oldPredicate);
  assert(execute > guardedReplacement);
  assert(migration.includes("safe to apply before the Edge rollout"));
  assert(migration.includes("NOTIFY pgrst, 'reload schema';"));
});
