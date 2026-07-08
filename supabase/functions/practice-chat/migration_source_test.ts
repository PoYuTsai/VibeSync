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
const dualAxisMigration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260628130000_practice_chat_dual_axis_learning.sql",
    import.meta.url,
  ),
);
const dualAxisHotfixMigration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260629153500_fix_practice_learning_state_update_alias.sql",
    import.meta.url,
  ),
);
const hintIdempotencyMigration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260703150000_practice_hint_idempotency.sql",
    import.meta.url,
  ),
);
const rpcCleanupMigration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260703160000_practice_rpc_cleanup.sql",
    import.meta.url,
  ),
);
const partnerStateMigration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260707053000_practice_partner_state.sql",
    import.meta.url,
  ),
);
const gameModeMigration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260708120000_practice_game_mode.sql",
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

function functionBodyWithSignature(
  name: string,
  signatureSnippet: string,
): string {
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

function requiredDualAxisIndex(snippet: string): number {
  const index = dualAxisMigration.indexOf(snippet);
  assert(index >= 0, `Dual-axis migration must contain: ${snippet}`);
  return index;
}

function dualAxisFunctionBody(name: string): string {
  const start = requiredDualAxisIndex(
    `CREATE OR REPLACE FUNCTION public.${name}(`,
  );
  const nextFunction = dualAxisMigration.indexOf(
    "CREATE OR REPLACE FUNCTION public.",
    start + 1,
  );
  return nextFunction >= 0
    ? dualAxisMigration.slice(start, nextFunction)
    : dualAxisMigration.slice(start);
}

function requiredDualAxisHotfixIndex(snippet: string): number {
  const index = dualAxisHotfixMigration.indexOf(snippet);
  assert(index >= 0, `Dual-axis hotfix migration must contain: ${snippet}`);
  return index;
}

function dualAxisHotfixFunctionBody(name: string): string {
  const start = requiredDualAxisHotfixIndex(
    `CREATE OR REPLACE FUNCTION public.${name}(`,
  );
  const nextFunction = dualAxisHotfixMigration.indexOf(
    "CREATE OR REPLACE FUNCTION public.",
    start + 1,
  );
  return nextFunction >= 0
    ? dualAxisHotfixMigration.slice(start, nextFunction)
    : dualAxisHotfixMigration.slice(start);
}

function compactSql(value: string): string {
  return value.replace(/\s+/g, " ");
}

function assertLearningUpdateRpcAppliesGuardedDeltas(body: string): void {
  const compactBody = compactSql(body);

  assert(
    body.includes(
      "RETURNS TABLE(updated BOOLEAN, temperature_score INTEGER, familiarity_score INTEGER)",
    ),
  );
  assert(compactBody.includes("p_expected_temperature_score INTEGER"));
  assert(compactBody.includes("p_expected_familiarity_score INTEGER"));
  assert(compactBody.includes("p_temperature_delta INTEGER"));
  assert(compactBody.includes("p_familiarity_delta INTEGER"));
  assert(
    compactBody.includes("UPDATE public.practice_chat_sessions AS s SET"),
  );
  assert(body.includes("AND s.practice_mode = 'beginner'"));
  assert(body.includes("AND s.temperature_score = v_expected_temperature"));
  assert(body.includes("AND s.familiarity_score = v_expected_familiarity"));
  assert(compactBody.includes("SET temperature_score = v_new_temperature"));
  assert(body.includes("familiarity_score = v_new_familiarity"));
  assert(body.includes("updated := v_rows > 0;"));
  assert(compactBody.includes("IF updated THEN"));
  assert(
    compactBody.includes("SELECT s.temperature_score, s.familiarity_score"),
  );
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

Deno.test("hint generation claim serializes provider calls before success settlement", () => {
  const claimBody = functionBody("claim_practice_hint_generation");
  const releaseBody = functionBody("release_practice_hint_generation");
  const recordBody = functionBody("record_practice_hint");

  requiredIndex(
    "ADD COLUMN IF NOT EXISTS hint_generation_started_at TIMESTAMPTZ",
  );
  assert(
    claimBody.includes("FOR UPDATE"),
    "claim_practice_hint_generation must lock the ledger row",
  );
  assert(
    claimBody.includes("PRACTICE_HINT_IN_FLIGHT"),
    "claim_practice_hint_generation must reject concurrent in-flight hints",
  );
  assert(
    claimBody.includes("hint_count >= p_max_hints"),
    "claim_practice_hint_generation must check hint cap before provider",
  );
  assert(
    claimBody.includes("hint_generation_started_at = now()"),
    "claim_practice_hint_generation must mark an in-flight generation",
  );
  assert(
    releaseBody.includes("hint_generation_started_at = NULL"),
    "release_practice_hint_generation must clear failed in-flight generations",
  );
  assert(
    recordBody.includes("hint_generation_started_at = NULL"),
    "record_practice_hint must clear the claim on successful settlement",
  );
  assert(
    recordBody.indexOf("IF v_row.hint_count >= p_max_hints THEN") <
      recordBody.indexOf("PERFORM public.increment_usage"),
    "record_practice_hint must re-check the cap before charging",
  );
  requiredIndex(
    "GRANT EXECUTE ON FUNCTION public.claim_practice_hint_generation(UUID, TEXT, INTEGER)",
  );
  requiredIndex(
    "GRANT EXECUTE ON FUNCTION public.release_practice_hint_generation(UUID, TEXT)",
  );
});

Deno.test("dual-axis migration adds familiarity_score with bounded constraint", () => {
  requiredDualAxisIndex("ADD COLUMN IF NOT EXISTS familiarity_score INTEGER");
  requiredDualAxisIndex(
    "practice_chat_sessions_familiarity_score_check",
  );
  requiredDualAxisIndex(
    "CHECK (familiarity_score IS NULL OR familiarity_score BETWEEN 0 AND 100)",
  );
});

Deno.test("dual-axis commit RPC accepts and initializes familiarity score", () => {
  const body = dualAxisFunctionBody("commit_practice_chat_turn");

  assert(body.includes("p_familiarity_score INTEGER"));
  assert(body.includes("v_initial_familiarity"));
  assert(body.includes("familiarity_score"));
  assert(
    body.includes(
      "CASE WHEN v_mode = 'beginner' THEN v_initial_familiarity ELSE NULL END",
    ),
  );
  requiredDualAxisIndex(
    "GRANT EXECUTE ON FUNCTION public.commit_practice_chat_turn(UUID, TEXT, BOOLEAN, INTEGER, TEXT, INTEGER, INTEGER)",
  );
});

Deno.test("dual-axis readiness RPC exists for pre-provider schema gate", () => {
  const body = dualAxisFunctionBody("assert_practice_learning_ready");
  const compactBody = compactSql(body);

  assert(body.includes("RETURNS BOOLEAN"));
  assert(body.includes("information_schema.columns"));
  assert(body.includes("column_name = 'familiarity_score'"));
  assert(
    compactBody.includes(
      "to_regprocedure('public.commit_practice_chat_turn(uuid,text,boolean,integer,text,integer,integer)')",
    ),
  );
  assert(
    compactBody.includes(
      "to_regprocedure('public.update_practice_learning_state(uuid,text,integer,integer,integer,integer)')",
    ),
  );
  assert(body.includes("PRACTICE_LEARNING_NOT_READY"));
  assert(body.includes("RETURN true;"));
  requiredDualAxisIndex(
    "GRANT EXECUTE ON FUNCTION public.assert_practice_learning_ready(UUID, TEXT)",
  );
});

Deno.test("dual-axis learning update RPC applies guarded deltas atomically", () => {
  const body = dualAxisFunctionBody("update_practice_learning_state");
  assertLearningUpdateRpcAppliesGuardedDeltas(body);
  requiredDualAxisIndex(
    "GRANT EXECUTE ON FUNCTION public.update_practice_learning_state(UUID, TEXT, INTEGER, INTEGER, INTEGER, INTEGER)",
  );
});

Deno.test("dual-axis hotfix migration keeps learning update guard aliases", () => {
  const body = dualAxisHotfixFunctionBody("update_practice_learning_state");
  assertLearningUpdateRpcAppliesGuardedDeltas(body);
  requiredDualAxisHotfixIndex(
    "GRANT EXECUTE ON FUNCTION public.update_practice_learning_state(UUID, TEXT, INTEGER, INTEGER, INTEGER, INTEGER)",
  );
});

// ── 20260703150000 hint requestId 冪等 migration ────────────────────────────

function requiredIdempotencyIndex(snippet: string): number {
  const index = hintIdempotencyMigration.indexOf(snippet);
  assert(index >= 0, `Hint idempotency migration must contain: ${snippet}`);
  return index;
}

function idempotencyFunctionBody(name: string): string {
  const start = requiredIdempotencyIndex(
    `CREATE OR REPLACE FUNCTION public.${name}(`,
  );
  const nextFunction = hintIdempotencyMigration.indexOf(
    "CREATE OR REPLACE FUNCTION public.",
    start + 1,
  );
  return nextFunction >= 0
    ? hintIdempotencyMigration.slice(start, nextFunction)
    : hintIdempotencyMigration.slice(start);
}

Deno.test("hint idempotency migration adds replay ledger columns with a length check", () => {
  requiredIdempotencyIndex(
    "ADD COLUMN IF NOT EXISTS last_hint_request_id TEXT",
  );
  requiredIdempotencyIndex("ADD COLUMN IF NOT EXISTS last_hint_result JSONB");
  requiredIdempotencyIndex(
    "practice_chat_sessions_last_hint_request_id_check",
  );
  requiredIdempotencyIndex(
    "length(last_hint_request_id) BETWEEN 1 AND 64",
  );
});

Deno.test("hint idempotency migration drops the old signatures so no overloads remain", () => {
  requiredIdempotencyIndex(
    "DROP FUNCTION IF EXISTS public.claim_practice_hint_generation(UUID, TEXT, INTEGER);",
  );
  requiredIdempotencyIndex(
    "DROP FUNCTION IF EXISTS public.record_practice_hint(UUID, TEXT, BOOLEAN, INTEGER);",
  );
});

Deno.test("hint idempotency claim replays a matching request before latch, cap, and charge", () => {
  const body = idempotencyFunctionBody("claim_practice_hint_generation");
  const compactBody = compactSql(body);

  assert(compactBody.includes("p_request_id TEXT DEFAULT NULL"));
  assert(
    body.includes(
      "RETURNS TABLE(current_hint_count INTEGER, replay BOOLEAN, stored_result JSONB)",
    ),
    "claim must expose replay flag and stored result",
  );
  assert(body.includes("FOR UPDATE"), "claim must keep the row lock");

  const replayIndex = body.indexOf(
    "v_row.last_hint_request_id = p_request_id",
  );
  assert(replayIndex >= 0, "claim must compare the stored request id");
  assert(
    body.includes("v_row.last_hint_result IS NOT NULL"),
    "claim replay requires a stored result",
  );

  const capIndex = body.indexOf("hint_count >= p_max_hints");
  const inFlightIndex = body.indexOf("PRACTICE_HINT_IN_FLIGHT");
  const latchIndex = body.indexOf("hint_generation_started_at = now()");
  assert(capIndex >= 0 && inFlightIndex >= 0 && latchIndex >= 0);
  assert(
    replayIndex < capIndex,
    "replay must beat the hint cap so cap-edge retries succeed",
  );
  assert(
    replayIndex < inFlightIndex,
    "replay must beat the in-flight guard",
  );
  assert(
    replayIndex < latchIndex,
    "replay must return before taking the latch",
  );
  assert(
    !body.includes("increment_usage"),
    "claim must never charge quota",
  );
});

Deno.test("hint idempotency record stores the replay snapshot with the authoritative count", () => {
  const body = idempotencyFunctionBody("record_practice_hint");
  const compactBody = compactSql(body);

  assert(compactBody.includes("p_request_id TEXT DEFAULT NULL"));
  assert(compactBody.includes("p_result JSONB DEFAULT NULL"));
  assert(
    body.includes("last_hint_request_id = p_request_id"),
    "record must persist the request id",
  );
  assert(
    compactBody.includes(
      "jsonb_build_object('hintUsedCount', hint_count + 1)",
    ),
    "record must merge the authoritative new hint count into the stored result",
  );

  // 既有保護不得回退：null p_charge_quota 拒絕、cap 複檢先於扣費、清 latch。
  assert(body.includes("IF p_charge_quota IS NULL THEN"));
  assert(
    body.indexOf("IF v_row.hint_count >= p_max_hints THEN") <
      body.indexOf("PERFORM public.increment_usage"),
    "record must re-check the cap before charging",
  );
  assert(body.includes("hint_generation_started_at = NULL"));
});

Deno.test("hint idempotency migration locks down grants and reloads the schema cache", () => {
  requiredIdempotencyIndex(
    "REVOKE EXECUTE ON FUNCTION public.claim_practice_hint_generation(UUID, TEXT, INTEGER, TEXT)",
  );
  requiredIdempotencyIndex(
    "GRANT EXECUTE ON FUNCTION public.claim_practice_hint_generation(UUID, TEXT, INTEGER, TEXT)",
  );
  requiredIdempotencyIndex(
    "REVOKE EXECUTE ON FUNCTION public.record_practice_hint(UUID, TEXT, BOOLEAN, INTEGER, TEXT, JSONB)",
  );
  requiredIdempotencyIndex(
    "GRANT EXECUTE ON FUNCTION public.record_practice_hint(UUID, TEXT, BOOLEAN, INTEGER, TEXT, JSONB)",
  );
  assert(
    /GRANT EXECUTE ON FUNCTION public\.claim_practice_hint_generation\(UUID, TEXT, INTEGER, TEXT\)\s+TO service_role/
      .test(
        hintIdempotencyMigration,
      ),
  );
  assert(
    /GRANT EXECUTE ON FUNCTION public\.record_practice_hint\(UUID, TEXT, BOOLEAN, INTEGER, TEXT, JSONB\)\s+TO service_role/
      .test(
        hintIdempotencyMigration,
      ),
  );
  requiredIdempotencyIndex("NOTIFY pgrst, 'reload schema';");
});

// ── 20260703160000 殘留 RPC 清理 migration ──────────────────────────────────

function requiredCleanupIndex(snippet: string): number {
  const index = rpcCleanupMigration.indexOf(snippet);
  assert(index >= 0, `RPC cleanup migration must contain: ${snippet}`);
  return index;
}

function requiredPartnerStateIndex(snippet: string): number {
  const index = partnerStateMigration.indexOf(snippet);
  assert(index >= 0, `Partner-state migration must contain: ${snippet}`);
  return index;
}

function partnerStateFunctionBody(name: string): string {
  const start = requiredPartnerStateIndex(
    `CREATE OR REPLACE FUNCTION public.${name}(`,
  );
  const nextFunction = partnerStateMigration.indexOf(
    "CREATE OR REPLACE FUNCTION public.",
    start + 1,
  );
  return nextFunction >= 0
    ? partnerStateMigration.slice(start, nextFunction)
    : partnerStateMigration.slice(start);
}

function requiredGameModeIndex(snippet: string): number {
  const index = gameModeMigration.indexOf(snippet);
  assert(index >= 0, `Game-mode migration must contain: ${snippet}`);
  return index;
}

function gameModeFunctionBody(name: string): string {
  const start = requiredGameModeIndex(
    `CREATE OR REPLACE FUNCTION public.${name}(`,
  );
  const nextFunction = gameModeMigration.indexOf(
    "CREATE OR REPLACE FUNCTION public.",
    start + 1,
  );
  return nextFunction >= 0
    ? gameModeMigration.slice(start, nextFunction)
    : gameModeMigration.slice(start);
}

Deno.test("rpc cleanup migration warns it must run only after the new Edge deploy", () => {
  requiredCleanupIndex("必須在新版 practice-chat Edge 部署完成後才可套用");
});

Deno.test("rpc cleanup migration drops the dead temperature RPC and legacy commit overloads", () => {
  requiredCleanupIndex(
    "DROP FUNCTION IF EXISTS public.update_practice_temperature(UUID, TEXT, INTEGER);",
  );
  requiredCleanupIndex(
    "DROP FUNCTION IF EXISTS public.commit_practice_chat_turn(UUID, TEXT, BOOLEAN, INTEGER);",
  );
  requiredCleanupIndex(
    "DROP FUNCTION IF EXISTS public.commit_practice_chat_turn(UUID, TEXT, BOOLEAN, INTEGER, TEXT, INTEGER);",
  );
  requiredCleanupIndex("NOTIFY pgrst, 'reload schema';");
});

Deno.test("rpc cleanup migration must not drop the live 7-arg commit RPC", () => {
  assert(
    !rpcCleanupMigration.includes(
      "commit_practice_chat_turn(UUID, TEXT, BOOLEAN, INTEGER, TEXT, INTEGER, INTEGER)",
    ),
    "the dual-axis 7-arg signature is the live one and must survive cleanup",
  );
});

Deno.test("partner-state migration adds bounded relationship state columns", () => {
  requiredPartnerStateIndex("ADD COLUMN IF NOT EXISTS partner_mood TEXT");
  requiredPartnerStateIndex(
    "ADD COLUMN IF NOT EXISTS partner_inner_thought TEXT",
  );
  requiredPartnerStateIndex(
    "ADD COLUMN IF NOT EXISTS partner_state_updated_at TIMESTAMPTZ",
  );
  requiredPartnerStateIndex("practice_chat_sessions_partner_mood_check");
  requiredPartnerStateIndex(
    "partner_mood IN ('neutral', 'curious', 'amused', 'comfortable', 'guarded', 'annoyed')",
  );
  requiredPartnerStateIndex("char_length(partner_inner_thought) <= 80");
});

Deno.test("partner-state readiness RPC checks both tracker columns", () => {
  const body = partnerStateFunctionBody("assert_practice_learning_ready");

  assert(body.includes("column_name = 'partner_mood'"));
  assert(body.includes("column_name = 'partner_inner_thought'"));
  assert(body.includes("missing partner_mood"));
  assert(body.includes("missing partner_inner_thought"));
});

Deno.test("partner-state commit RPC initializes state without charging behavior changes", () => {
  const body = partnerStateFunctionBody("commit_practice_chat_turn");

  assert(body.includes("p_partner_mood          TEXT"));
  assert(body.includes("p_partner_inner_thought TEXT"));
  assertEquals(body.includes("p_partner_mood TEXT DEFAULT NULL"), false);
  assert(body.includes("partner_mood"));
  assert(body.includes("partner_inner_thought"));
  assert(body.includes("v_should_settle AND p_charge_quota IS TRUE"));
  requiredPartnerStateIndex(
    "GRANT EXECUTE ON FUNCTION public.commit_practice_chat_turn(UUID, TEXT, BOOLEAN, INTEGER, TEXT, INTEGER, INTEGER, TEXT, TEXT)",
  );
});

Deno.test("partner-state learning update RPC atomically persists scores and state", () => {
  const body = partnerStateFunctionBody("update_practice_learning_state");
  const compactBody = compactSql(body);

  assert(
    body.includes(
      "RETURNS TABLE(updated BOOLEAN, temperature_score INTEGER, familiarity_score INTEGER, partner_mood TEXT, partner_inner_thought TEXT)",
    ),
  );
  assert(compactBody.includes("p_partner_mood TEXT"));
  assert(compactBody.includes("p_partner_inner_thought TEXT"));
  assertEquals(compactBody.includes("p_partner_mood TEXT DEFAULT NULL"), false);
  assert(compactBody.includes("SET temperature_score = v_new_temperature"));
  assert(compactBody.includes("familiarity_score = v_new_familiarity"));
  assert(compactBody.includes("partner_mood = v_partner_mood"));
  assert(
    compactBody.includes("partner_inner_thought = v_partner_inner_thought"),
  );
  assert(body.includes("AND s.temperature_score = v_expected_temperature"));
  assert(body.includes("AND s.familiarity_score = v_expected_familiarity"));
  requiredPartnerStateIndex(
    "GRANT EXECUTE ON FUNCTION public.update_practice_learning_state(UUID, TEXT, INTEGER, INTEGER, INTEGER, INTEGER, TEXT, TEXT)",
  );
});

Deno.test("game-mode migration expands the practice_mode constraint", () => {
  requiredGameModeIndex(
    "DROP CONSTRAINT IF EXISTS practice_chat_sessions_practice_mode_check",
  );
  requiredGameModeIndex(
    "CHECK (practice_mode IN ('standard', 'beginner', 'game'))",
  );
  requiredGameModeIndex("NOTIFY pgrst, 'reload schema';");
});

Deno.test("game-mode commit RPC treats game as an assisted mode", () => {
  const body = gameModeFunctionBody("commit_practice_chat_turn");
  const compactBody = compactSql(body);

  assert(
    body.includes("IF v_mode NOT IN ('standard', 'beginner', 'game') THEN"),
  );
  assert(
    compactBody.includes(
      "CASE WHEN v_mode IN ('beginner', 'game') THEN v_initial_temp ELSE NULL END",
    ),
  );
  assert(
    compactBody.includes(
      "WHEN practice_mode IN ('beginner', 'game') AND temperature_score IS NULL THEN v_initial_temp",
    ),
  );
  assert(
    compactBody.includes(
      "WHEN practice_mode IN ('beginner', 'game') AND familiarity_score IS NULL THEN v_initial_familiarity",
    ),
  );
  requiredGameModeIndex(
    "GRANT EXECUTE ON FUNCTION public.commit_practice_chat_turn(UUID, TEXT, BOOLEAN, INTEGER, TEXT, INTEGER, INTEGER, TEXT, TEXT)",
  );
});

Deno.test("game-mode hint RPC allows beginner and game but still rejects standard", () => {
  const claimBody = gameModeFunctionBody("claim_practice_hint_generation");
  const recordBody = gameModeFunctionBody("record_practice_hint");

  assert(claimBody.includes("v_row.practice_mode NOT IN ('beginner', 'game')"));
  assert(
    recordBody.includes("v_row.practice_mode NOT IN ('beginner', 'game')"),
  );
  assertEquals(claimBody.includes("v_row.practice_mode <> 'beginner'"), false);
  assertEquals(recordBody.includes("v_row.practice_mode <> 'beginner'"), false);
  requiredGameModeIndex(
    "GRANT EXECUTE ON FUNCTION public.claim_practice_hint_generation(UUID, TEXT, INTEGER, TEXT)",
  );
  requiredGameModeIndex(
    "GRANT EXECUTE ON FUNCTION public.record_practice_hint(UUID, TEXT, BOOLEAN, INTEGER, TEXT, JSONB)",
  );
});

Deno.test("game-mode learning update RPC applies guarded deltas to beginner and game", () => {
  const body = gameModeFunctionBody("update_practice_learning_state");

  assert(body.includes("AND s.practice_mode IN ('beginner', 'game')"));
  assertEquals(body.includes("AND s.practice_mode = 'beginner'"), false);
  requiredGameModeIndex(
    "GRANT EXECUTE ON FUNCTION public.update_practice_learning_state(UUID, TEXT, INTEGER, INTEGER, INTEGER, INTEGER, TEXT, TEXT)",
  );
});
