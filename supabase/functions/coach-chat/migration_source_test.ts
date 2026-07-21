import { assert } from "https://deno.land/std@0.168.0/testing/asserts.ts";

const migrationSource = await Deno.readTextFile(
  new URL(
    "../../migrations/20260721120000_coach_exactly_once.sql",
    import.meta.url,
  ),
);

Deno.test("coach migration owns claim, settlement, retention, and privacy", () => {
  const claim = migrationSource.indexOf("claim_coach_request");
  const increment = migrationSource.indexOf("PERFORM public.increment_usage");
  const settle = migrationSource.indexOf("settle_coach_request");
  assert(claim >= 0 && settle > claim && increment > settle);
  assert(migrationSource.includes("PRIMARY KEY (user_id, request_id)"));
  assert(migrationSource.includes("input_hash ~ '^[0-9a-f]{64}$'"));
  assert(migrationSource.includes("state IN ('pending', 'done')"));
  assert(migrationSource.includes("release_coach_claim"));
  assert(migrationSource.includes("cleanup_expired_coach_requests"));
  assert(migrationSource.includes("coach_contract_version"));
  assert(migrationSource.includes("'coach-exactly-once-v1'"));
  assert(migrationSource.includes("interval '90 seconds'"));
  assert(migrationSource.includes("interval '24 hours'"));
  assert(migrationSource.includes("'37 * * * *'"));
  assert(migrationSource.includes("SECURITY DEFINER"));
  assert(migrationSource.includes("SET search_path = public"));
  assert(
    migrationSource.includes(
      "REVOKE ALL ON TABLE public.coach_requests FROM anon, authenticated",
    ),
  );
  assert(
    migrationSource.includes("GRANT SELECT ON TABLE public.coach_requests"),
  );
  assert(migrationSource.includes("TO service_role"));
  assert(migrationSource.includes("COACH_REQUEST_REPLAY_MISMATCH"));
  assert(migrationSource.includes("COACH_REQUEST_OWNER_MISMATCH"));
  assert(migrationSource.includes("increment_usage"));
  assert(migrationSource.includes("AND owner_token = p_owner_token"));
  assert(migrationSource.includes("AND state = 'pending'"));
  assert(migrationSource.includes("SET lease_expires_at = v_lease_expires_at"));
  assert(migrationSource.includes("NOTIFY pgrst, 'reload schema';"));
});

Deno.test("coach migration ledger result is envelope + card whitelist only", () => {
  // 頂層 envelope 白名單（減鍵法，Postgres CHECK 禁子查詢）。
  assert(
    migrationSource.includes(
      "- 'card' - 'sessionId' - 'provider' - 'model' - 'generatedAt'",
    ),
  );
  assert(
    migrationSource.includes(
      "?& ARRAY['card','sessionId','provider','model','generatedAt']",
    ),
  );
  assert(migrationSource.includes("'provider' = 'claude'"));
  // card 欄位白名單＝ResponseCardSchema 全欄位；多任何一鍵即拒。
  const cardWhitelist =
    "- 'responseType' - 'mode' - 'headline' - 'answer' - 'userTruth'";
  assert(migrationSource.includes(cardWhitelist));
  assert(
    migrationSource.includes(
      "- 'userState' - 'frictionType' - 'nextStep' - 'suggestedLine'",
    ),
  );
  assert(
    migrationSource.includes(
      "- 'rewriteDecision' - 'rewriteReason' - 'boundaryReminder'",
    ),
  );
  assert(
    migrationSource.includes(
      "- 'needsReflection' - 'reflectionQuestion' - 'costDeducted'",
    ),
  );
  assert(
    migrationSource.includes("IN ('coachAnswer', 'clarifyingQuestion')"),
  );
  assert(migrationSource.includes("IN ('0', '1')"));
  // 表 CHECK 與 settle 前置驗證各出現一次同組白名單。
  const occurrences = migrationSource.split(cardWhitelist).length - 1;
  assert(occurrences >= 2);
});
