import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260628120000_practice_beginner_temperature_hint.sql",
    import.meta.url,
  ),
);

function requiredIndex(snippet: string): number {
  const index = migration.indexOf(snippet);
  assert(index >= 0, `Migration must contain: ${snippet}`);
  return index;
}

function functionBody(name: string): string {
  const start = requiredIndex(`CREATE OR REPLACE FUNCTION public.${name}(`);
  const nextFunction = migration.indexOf(
    "CREATE OR REPLACE FUNCTION public.",
    start + 1,
  );
  return nextFunction >= 0
    ? migration.slice(start, nextFunction)
    : migration.slice(start);
}

function functionBodyWithSignature(name: string, signatureSnippet: string): string {
  const start = requiredIndex(`CREATE OR REPLACE FUNCTION public.${name}(`);
  let cursor = start;

  while (cursor >= 0) {
    const nextFunction = migration.indexOf(
      "CREATE OR REPLACE FUNCTION public.",
      cursor + 1,
    );
    const body = nextFunction >= 0
      ? migration.slice(cursor, nextFunction)
      : migration.slice(cursor);

    if (body.includes(signatureSnippet)) {
      return body;
    }

    cursor = nextFunction;
  }

  assert(false, `Migration must contain ${name} overload: ${signatureSnippet}`);
}

Deno.test("ledger RPCs reject null quota charge flags before computing did_charge", () => {
  for (const name of ["commit_practice_chat_turn", "record_practice_hint"]) {
    const body = functionBody(name);
    const nullGuardIndex = body.indexOf("IF p_charge_quota IS NULL THEN");
    const didChargeIndex = body.indexOf("did_charge :=");

    assert(nullGuardIndex >= 0, `${name} must reject null p_charge_quota`);
    assert(
      body.includes(`RAISE EXCEPTION '${name}: invalid p_charge_quota';`),
      `${name} must raise a clear invalid p_charge_quota exception`,
    );
    assert(
      nullGuardIndex < didChargeIndex,
      `${name} must validate p_charge_quota before did_charge`,
    );
    assert(
      !body.includes("COALESCE(p_charge_quota, TRUE)"),
      `${name} must not charge quota on null via COALESCE`,
    );
  }
});

Deno.test("legacy 4-arg chat ledger RPC rejects null quota before did_charge", () => {
  const body = functionBodyWithSignature(
    "commit_practice_chat_turn",
    "p_max_replies  INTEGER DEFAULT 10",
  );
  const nullGuardIndex = body.indexOf("IF p_charge_quota IS NULL THEN");
  const didChargeIndex = body.indexOf("did_charge :=");

  assert(
    body.includes("p_charge_quota BOOLEAN DEFAULT TRUE"),
    "legacy commit_practice_chat_turn overload must preserve p_charge_quota default",
  );
  assert(
    nullGuardIndex >= 0,
    "legacy commit_practice_chat_turn overload must reject null p_charge_quota",
  );
  assert(
    body.includes(
      "RAISE EXCEPTION 'commit_practice_chat_turn: invalid p_charge_quota';",
    ),
    "legacy commit_practice_chat_turn overload must raise a clear invalid p_charge_quota exception",
  );
  assert(
    nullGuardIndex < didChargeIndex,
    "legacy commit_practice_chat_turn overload must validate p_charge_quota before did_charge",
  );
  assert(
    body.includes("v_should_settle AND p_charge_quota IS TRUE"),
    "legacy commit_practice_chat_turn overload must charge only on first settlement with an explicit true flag",
  );
  assert(
    !body.includes("COALESCE(p_charge_quota, TRUE)"),
    "legacy commit_practice_chat_turn overload must not charge quota on null via COALESCE",
  );
});

Deno.test("practice mode normalization trims non-empty values", () => {
  const body = functionBody("commit_practice_chat_turn");

  assert(
    body.includes(
      "v_mode := COALESCE(NULLIF(btrim(p_practice_mode), ''), 'standard');",
    ),
    "commit_practice_chat_turn must trim mode and default blanks to standard",
  );
  assert(
    body.includes("IF v_mode NOT IN ('standard', 'beginner') THEN"),
    "commit_practice_chat_turn must validate the normalized mode",
  );
});

Deno.test("temperature update reports whether a beginner row was updated", () => {
  const body = functionBody("update_practice_temperature");

  assert(
    body.includes(
      "RETURNS TABLE(updated BOOLEAN, temperature_score INTEGER)",
    ),
    "update_practice_temperature must return an updated flag plus clamped score",
  );
  assert(
    body.includes("AND practice_mode = 'beginner'"),
    "update_practice_temperature must update beginner rows only",
  );
  assert(
    body.includes("GET DIAGNOSTICS v_rows = ROW_COUNT;"),
    "update_practice_temperature must inspect whether UPDATE matched a row",
  );
  assert(
    body.includes("updated := v_rows > 0;"),
    "update_practice_temperature must expose no-update deterministically",
  );
  assertEquals(body.includes("RETURN v_score;"), false);
});
