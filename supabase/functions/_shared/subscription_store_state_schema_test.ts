import { assert } from "https://deno.land/std@0.168.0/testing/asserts.ts";

const migrationSource = await Deno.readTextFile(
  new URL(
    "../../migrations/20260823090000_subscription_store_states.sql",
    import.meta.url,
  ),
);

const backfillMigrationSource = await Deno.readTextFile(
  new URL(
    "../../migrations/20260823093000_subscription_store_state_backfill.sql",
    import.meta.url,
  ),
);

const productDetailsMigrationSource = await Deno.readTextFile(
  new URL(
    "../../migrations/20260526005000_subscription_product_details.sql",
    import.meta.url,
  ),
);

const initialSchemaSource = await Deno.readTextFile(
  new URL("../../migrations/00001_initial_schema.sql", import.meta.url),
);

function requiredSql(snippet: string): void {
  assert(
    migrationSource.includes(snippet),
    `subscription_store_states migration must contain: ${snippet}`,
  );
}

function requiredBackfillSql(snippet: string): void {
  assert(
    backfillMigrationSource.includes(snippet),
    `subscription store state backfill migration must contain: ${snippet}`,
  );
}

function requiredProductDetailsSql(snippet: string): void {
  assert(
    productDetailsMigrationSource.includes(snippet),
    `subscription product details migration must contain: ${snippet}`,
  );
}

Deno.test("subscription_store_states schema is additive, per-store, and typed", () => {
  requiredSql("CREATE TABLE public.subscription_store_states (");
  requiredSql(
    "user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE",
  );
  requiredSql(
    "store TEXT NOT NULL CHECK (store IN ('app_store', 'play_store'))",
  );
  requiredSql("product_id TEXT");
  requiredSql("base_plan_id TEXT");
  requiredSql(
    "tier TEXT NOT NULL CHECK (tier IN ('free', 'starter', 'essential'))",
  );
  requiredSql(
    "status TEXT NOT NULL CHECK (status IN ('active', 'cancelled', 'expired', 'billing_issue'))",
  );
  requiredSql("expires_at TIMESTAMPTZ");
  requiredSql("event_at TIMESTAMPTZ NOT NULL");
  requiredSql("event_id TEXT");
  requiredSql(
    "verification_source TEXT NOT NULL CHECK (verification_source IN ('revenuecat_webhook', 'revenuecat_api', 'legacy_backfill'))",
  );
  requiredSql(
    "verification_status TEXT NOT NULL DEFAULT 'verified' CHECK (verification_status IN ('verified', 'unverified'))",
  );
  requiredSql(
    "revenuecat_environment TEXT CHECK (revenuecat_environment IN ('sandbox', 'production'))",
  );
  requiredSql("UNIQUE (user_id, store)");
  requiredSql("UNIQUE (user_id, store, event_id)");
  requiredSql(
    "CONSTRAINT subscription_store_states_legacy_backfill_unverified CHECK",
  );
  requiredSql(
    "verification_source <> 'legacy_backfill' OR verification_status = 'unverified'",
  );
});

Deno.test("finalizer captures and preserves one grouped legacy baseline", () => {
  assert(
    initialSchemaSource.includes(
      "tier TEXT NOT NULL DEFAULT 'free' CHECK (tier IN ('free', 'starter', 'essential'))",
    ),
    "legacy subscription tier must be non-null for the baseline sentinel",
  );

  const finalizerStart = migrationSource.indexOf(
    "CREATE OR REPLACE FUNCTION public.finalize_subscription_store_state_reconciliation(",
  );
  const finalizerEnd = migrationSource.indexOf(
    "REVOKE ALL ON FUNCTION public.finalize_subscription_store_state_reconciliation(",
    finalizerStart,
  );
  const finalizer = migrationSource.slice(finalizerStart, finalizerEnd);
  const updateStart = finalizer.indexOf("ON CONFLICT (user_id) DO UPDATE");
  const updateEnd = finalizer.indexOf("updated_at = NOW();", updateStart);
  const baselineUpdate = finalizer.slice(updateStart, updateEnd);
  const sentinel =
    "public.subscription_store_state_reconciliations.baseline_tier IS NULL";
  const baselineColumns = [
    "baseline_tier",
    "baseline_status",
    "baseline_expires_at",
    "baseline_active_product_id",
    "baseline_billing_period",
    "baseline_store",
    "baseline_revenuecat_environment",
  ];

  assert(updateStart >= 0, "finalizer must upsert the reconciliation marker");
  assert(baselineUpdate.includes(`${sentinel}\n          THEN`));
  assert(!baselineUpdate.includes("COALESCE("));
  for (const column of baselineColumns) {
    assert(
      baselineUpdate.includes(
        `${column} = CASE\n        WHEN ${sentinel}\n          THEN EXCLUDED.${column}\n        ELSE public.subscription_store_state_reconciliations.${column}\n      END`,
      ),
      `${column} must use the same baseline presence sentinel`,
    );
  }

  const rollbackStart = migrationSource.indexOf(
    "CREATE OR REPLACE FUNCTION public.rollback_subscription_store_state_reconciliation(",
  );
  const rollback = migrationSource.slice(rollbackStart);
  for (const column of baselineColumns) {
    assert(
      rollback.includes(`${column} = NULL`),
      `rollback must clear ${column} with the baseline sentinel`,
    );
  }
});

Deno.test("legacy cutover has an explicit per-user service-role state", () => {
  requiredSql(
    "CREATE TABLE public.subscription_store_state_reconciliations (",
  );
  requiredSql("status TEXT NOT NULL DEFAULT 'pending'");
  requiredSql("status IN ('pending', 'auto', 'complete')");
  requiredSql(
    "coverage IN ('unknown', 'no_paid_legacy_baseline', 'complete_revenuecat_snapshot')",
  );
  requiredSql("no_paid_legacy_baseline");
  requiredSql("baseline_tier");
  requiredSql("user_id UUID PRIMARY KEY REFERENCES public.users(id)");
  requiredSql(
    'CREATE POLICY "Users can view own subscription reconciliation"',
  );
  requiredSql(
    'CREATE POLICY "Service role can view subscription reconciliation"',
  );
  requiredSql(
    "REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER\n  ON TABLE public.subscription_store_state_reconciliations\n  FROM service_role;",
  );
  requiredSql(
    "GRANT SELECT ON TABLE public.subscription_store_state_reconciliations\n  TO service_role;",
  );
  requiredSql(
    "CREATE OR REPLACE FUNCTION public.finalize_subscription_store_state_reconciliation(",
  );
  requiredSql("ambiguous_legacy_store");
  requiredSql("coverage_not_authoritative");
  requiredSql("NULLIF(trim(covered.product_id), '') IS NOT NULL");
  requiredSql("v_state.tier IN ('starter', 'essential')");
  requiredSql("ambiguous_verified_product");
  requiredSql("covered.store = v_legacy.store");
  requiredSql("missing_cutover_baseline");
  requiredSql("baseline_active_product_id = NULL");
  requiredSql("Restore the exact pre-cutover aggregate");
  requiredSql(
    "GRANT EXECUTE ON FUNCTION public.finalize_subscription_store_state_reconciliation(",
  );
});

Deno.test("finalizer requires one immutable complete snapshot manifest", () => {
  requiredSql(
    "CREATE TABLE public.subscription_store_state_snapshot_manifests (",
  );
  requiredSql("snapshot_id TEXT NOT NULL");
  requiredSql("observed_at TIMESTAMPTZ NOT NULL");
  requiredSql("present_stores TEXT[] NOT NULL");
  requiredSql("present_store_event_ids JSONB NOT NULL");
  requiredSql("UNIQUE (user_id, snapshot_id)");
  requiredSql(
    "CREATE OR REPLACE FUNCTION public.record_revenuecat_snapshot_manifest(",
  );
  requiredSql("v_manifest.observed_at IS DISTINCT FROM p_observed_at");
  requiredSql(
    "v_manifest.present_store_event_ids IS DISTINCT FROM p_present_store_event_ids",
  );

  requiredSql("p_snapshot_id TEXT");
  requiredSql("p_observed_at TIMESTAMPTZ");
  requiredSql("p_present_stores TEXT[]");
  requiredSql("p_present_store_event_ids JSONB");
  requiredSql("v_manifest");
  requiredSql("v_store IN ('app_store', 'play_store')");
  requiredSql("v_store = ANY(v_manifest.present_stores)");
  requiredSql("v_manifest.present_store_event_ids ->> v_store");
  requiredSql(
    "state.revenuecat_environment IS NOT DISTINCT FROM v_manifest.revenuecat_environment",
  );
  requiredSql(
    "absence.revenuecat_environment IS NOT DISTINCT FROM v_manifest.revenuecat_environment",
  );
  requiredSql("missing_present_event");
  requiredSql("missing_snapshot_absence");
  requiredSql("v_expected_absence_event_id");
  requiredSql("snapshot_manifest_mismatch");
  requiredSql("p_observed_at > NOW()");
  requiredSql("p_present_store_event_ids IS NULL");
  requiredSql("ARRAY['app_store', 'play_store']::TEXT[]");
  requiredSql(
    "ALTER TABLE public.subscription_store_state_snapshot_manifests ENABLE ROW LEVEL SECURITY;",
  );
  requiredSql(
    'CREATE POLICY "Service role can view subscription snapshot manifests"',
  );
  requiredSql(
    "REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER\n  ON TABLE public.subscription_store_state_snapshot_manifests\n  FROM service_role;",
  );
  requiredSql(
    "REVOKE ALL ON TABLE public.subscription_store_state_snapshot_manifests",
  );
  requiredSql(
    "GRANT SELECT ON TABLE public.subscription_store_state_snapshot_manifests",
  );
  requiredSql(
    "REVOKE ALL ON FUNCTION public.record_revenuecat_snapshot_manifest(\n  UUID, TEXT, TIMESTAMPTZ, TEXT[], JSONB, TEXT",
  );
  requiredSql(
    "GRANT EXECUTE ON FUNCTION public.record_revenuecat_snapshot_manifest(\n  UUID, TEXT, TIMESTAMPTZ, TEXT[], JSONB, TEXT",
  );
  requiredSql(
    "REVOKE ALL ON FUNCTION public.finalize_subscription_store_state_reconciliation(\n  UUID, TEXT, TIMESTAMPTZ, TEXT[], JSONB, TEXT",
  );
  requiredSql(
    "GRANT EXECUTE ON FUNCTION public.finalize_subscription_store_state_reconciliation(\n  UUID, TEXT, TIMESTAMPTZ, TEXT[], JSONB, TEXT",
  );

  const finalizerStart = migrationSource.indexOf(
    "CREATE OR REPLACE FUNCTION public.finalize_subscription_store_state_reconciliation(",
  );
  const finalizer = migrationSource.slice(finalizerStart);
  const userLock = finalizer.indexOf(
    "PERFORM 1 FROM public.users WHERE id = p_user_id FOR UPDATE;",
  );
  const manifestLock = finalizer.indexOf(
    "FROM public.subscription_store_state_snapshot_manifests",
  );
  const proofLock = finalizer.indexOf(
    "FROM public.subscription_store_states AS state",
  );
  const legacyLock = finalizer.indexOf(
    "FROM public.subscriptions\n  WHERE user_id = p_user_id\n  FOR UPDATE;",
  );
  assert(userLock >= 0, "finalizer must lock parent user first");
  assert(manifestLock > userLock, "manifest lock must follow parent user lock");
  assert(proofLock > manifestLock, "proof rows must follow manifest lock");
  assert(legacyLock > proofLock, "legacy row must follow proof locks");
});

Deno.test("subscription_store_states schema has fail-closed access and lookup contracts", () => {
  requiredSql(
    "CREATE INDEX idx_subscription_store_states_user_store ON public.subscription_store_states(user_id, store)",
  );
  requiredSql(
    "CREATE INDEX idx_subscription_store_states_effective ON public.subscription_store_states(user_id, event_at DESC)",
  );
  requiredSql(
    "ALTER TABLE public.subscription_store_states ENABLE ROW LEVEL SECURITY",
  );
  requiredSql(
    'CREATE POLICY "Users can view own subscription store states" ON public.subscription_store_states',
  );
  requiredSql(
    'CREATE POLICY "Service role can view subscription store states" ON public.subscription_store_states',
  );
  requiredSql(
    "REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER\n  ON TABLE public.subscription_store_states\n  FROM service_role;",
  );
  requiredSql(
    "GRANT SELECT ON TABLE public.subscription_store_states\n  TO service_role;",
  );
  requiredSql("TO service_role");
  requiredSql("NOTIFY pgrst, 'reload schema';");
});

Deno.test("service-role writes stay behind SECURITY DEFINER owner functions", () => {
  const functionNames = [
    "upsert_subscription_store_state",
    "record_revenuecat_snapshot_manifest",
    "record_revenuecat_snapshot_absence",
    "finalize_subscription_store_state_reconciliation",
    "rollback_subscription_store_state_reconciliation",
  ];
  for (const functionName of functionNames) {
    const functionStart = migrationSource.indexOf(
      `CREATE OR REPLACE FUNCTION public.${functionName}(`,
    );
    const functionEnd = migrationSource.indexOf("$$;", functionStart);
    assert(functionStart >= 0, `${functionName} must exist`);
    assert(functionEnd > functionStart, `${functionName} must have a body`);
    assert(
      migrationSource.slice(functionStart, functionEnd).includes(
        "SECURITY DEFINER",
      ),
      `${functionName} must remain SECURITY DEFINER after direct DML revocation`,
    );
  }
});

Deno.test("store state writer is atomic and owns legacy aggregate updates", () => {
  requiredSql(
    "CREATE OR REPLACE FUNCTION public.upsert_subscription_store_state(",
  );
  requiredSql(
    "SELECT * INTO v_current FROM public.subscription_store_states",
  );
  requiredSql("FOR UPDATE;");
  requiredSql("ON CONFLICT (user_id, store) DO UPDATE");
  requiredSql("p_event_at");
  requiredSql("p_event_id");
  requiredSql("p_tier IN ('starter', 'essential')");
  requiredSql("NULLIF(trim(p_product_id), '') IS NULL");
  requiredSql("RETURN QUERY SELECT FALSE, 'invalid';");
  requiredSql("UPDATE public.subscriptions");
  requiredSql("RETURN QUERY SELECT TRUE, 'accepted';");
  requiredSql("RETURN QUERY SELECT FALSE, 'duplicate';");
  requiredSql("RETURN QUERY SELECT FALSE, 'stale';");
  requiredSql(
    "REVOKE ALL ON FUNCTION public.upsert_subscription_store_state(",
  );
  requiredSql(
    "GRANT EXECUTE ON FUNCTION public.upsert_subscription_store_state(",
  );
});

Deno.test("store state writer serializes missing-row races and preserves usage", () => {
  requiredSql("pg_advisory_xact_lock");
  requiredSql("v_new_status := CASE");
  requiredSql("WHEN v_winner.status = 'billing_issue' THEN 'active'");
  requiredSql("v_should_reset := p_reset_usage");
});

Deno.test("billing period inference is one canonical SQL helper", () => {
  requiredProductDetailsSql(
    "CREATE OR REPLACE FUNCTION public.infer_subscription_billing_period(",
  );
  requiredProductDetailsSql("RETURNS TEXT AS $$");
  requiredProductDetailsSql(
    "IF product_id IS NULL OR length(trim(product_id)) = 0",
  );
  requiredProductDetailsSql(
    "IF lower(product_id) LIKE '%quarter%' OR lower(product_id) LIKE '%p3m%'",
  );
  requiredProductDetailsSql(
    "IF lower(product_id) LIKE '%monthly%' OR lower(product_id) LIKE '%p1m%'",
  );
  requiredProductDetailsSql("RETURN 'unknown';");
  requiredProductDetailsSql("$$ LANGUAGE plpgsql IMMUTABLE;");
  requiredSql("public.infer_subscription_billing_period(v_winner.product_id)");
  requiredSql("public.infer_subscription_billing_period(v_state.product_id)");

  const helperStart = productDetailsMigrationSource.indexOf(
    "CREATE OR REPLACE FUNCTION public.infer_subscription_billing_period(",
  );
  const helperEnd = productDetailsMigrationSource.indexOf(
    "WITH latest_product AS (",
    helperStart,
  );
  const helper = productDetailsMigrationSource.slice(helperStart, helperEnd);
  const fixtures = [
    {
      productId: "pro-quarterly",
      expected: "quarterly",
      marker: "RETURN 'quarterly';",
    },
    {
      productId: "pro-monthly",
      expected: "monthly",
      marker: "RETURN 'monthly';",
    },
    {
      productId: "pro-lifetime",
      expected: "unknown",
      marker: "RETURN 'unknown';",
    },
    { productId: null, expected: null, marker: "RETURN NULL;" },
  ];
  for (const fixture of fixtures) {
    assert(
      helper.includes(fixture.marker),
      `${fixture.productId ?? "null"} fixture must map to ${
        fixture.expected ?? "null"
      }`,
    );
  }
});

Deno.test("legacy aggregate winner uses the same no-expiry effective predicate", () => {
  requiredSql(
    "AND ((expires_at IS NULL AND status = 'active') OR expires_at > NOW())",
  );
  requiredSql("AND status <> 'expired'");
});

Deno.test("store writer preserves an ambiguous paid legacy row until cutover is complete", () => {
  requiredSql("v_cutover_complete BOOLEAN");
  requiredSql("v_preserve_legacy BOOLEAN");
  requiredSql("preserve_legacy_unreconciled");
  requiredSql("subscription_store_state_reconciliations");
  requiredSql("v_legacy.tier");
  requiredSql("COALESCE(v_legacy.tier, 'free') IN ('starter', 'essential')");
  requiredSql("read-time projection may");
  requiredSql("no_paid_legacy_baseline");
});

Deno.test("verified provenance always outranks legacy backfill", () => {
  requiredSql("v_current.verification_status = 'verified'");
  requiredSql("v_verification_status = 'unverified'");
  requiredSql("v_current.verification_status = 'unverified'");
  requiredSql("AND v_verification_status = 'verified' THEN");
  requiredSql("RETURN QUERY SELECT FALSE, 'preserve_verified';");
});

Deno.test("single-store expiry cannot reset usage while another store remains paid", () => {
  requiredSql("v_should_reset := p_reset_usage AND (");
  requiredSql("v_new_tier = 'free'");
  requiredSql("COALESCE(v_legacy.tier, 'free') <> 'free'");
  requiredSql(
    "CASE v_new_tier",
  );
  requiredSql(
    "CASE COALESCE(v_legacy.tier, 'free')",
  );
});

Deno.test("legacy backfill is deterministic, rerunnable, and fail-closed", () => {
  requiredBackfillSql(
    "CREATE OR REPLACE FUNCTION public.backfill_subscription_store_state_from_legacy(",
  );
  requiredBackfillSql("p_user_id UUID DEFAULT NULL");
  requiredBackfillSql("legacy_backfill:");
  requiredBackfillSql("md5(");
  requiredBackfillSql("'ambiguous_legacy_store'");
  requiredBackfillSql("'missing_legacy_event_at'");
  requiredBackfillSql("'ambiguous_legacy_product'");
  requiredBackfillSql("'legacy_backfill'");
  requiredBackfillSql("'unverified'");
  requiredBackfillSql("p_reset_usage => FALSE");
  requiredSql("preserve_verified");
});

Deno.test("reconciliation diff query exposes effective winner and mismatch reason", () => {
  requiredBackfillSql(
    "CREATE OR REPLACE FUNCTION public.reconcile_subscription_store_state_diff(",
  );
  requiredBackfillSql("effective_store TEXT");
  requiredBackfillSql("has_verified_source BOOLEAN");
  requiredBackfillSql("aggregate_mismatch");
  requiredBackfillSql(
    "((expires_at IS NULL AND status = 'active') OR expires_at > NOW())",
  );
  requiredBackfillSql("AND status <> 'expired'");
  requiredBackfillSql("latest_verified");
  requiredBackfillSql("source_product_id");
  requiredBackfillSql(
    "GRANT EXECUTE ON FUNCTION public.reconcile_subscription_store_state_diff(",
  );
});

Deno.test("rollback takes the parent user lock before reconciliation and legacy rows", () => {
  const rollbackStart = migrationSource.indexOf(
    "CREATE OR REPLACE FUNCTION public.rollback_subscription_store_state_reconciliation(",
  );
  assert(rollbackStart >= 0, "rollback function must exist");
  const rollback = migrationSource.slice(rollbackStart);
  const userLock = rollback.indexOf(
    "PERFORM 1 FROM public.users WHERE id = p_user_id FOR UPDATE;",
  );
  const reconciliationLock = rollback.indexOf(
    "FROM public.subscription_store_state_reconciliations",
  );
  const legacyUpdate = rollback.indexOf(
    "UPDATE public.subscriptions",
  );

  assert(userLock >= 0, "rollback must lock the parent user first");
  assert(
    reconciliationLock > userLock,
    "reconciliation lock must follow user lock",
  );
  assert(
    legacyUpdate > reconciliationLock,
    "legacy update must follow reconciliation lock",
  );
});

Deno.test("verified RevenueCat absence is an audited service-role tombstone workflow", () => {
  requiredSql(
    "CREATE TABLE public.subscription_store_state_snapshot_absences (",
  );
  requiredSql("snapshot_id TEXT NOT NULL");
  requiredSql("observed_at TIMESTAMPTZ NOT NULL");
  requiredSql("present_stores TEXT[] NOT NULL");
  requiredSql("present_store_event_ids JSONB NOT NULL");
  requiredSql("UNIQUE (user_id, store, snapshot_id)");
  requiredSql(
    "CREATE OR REPLACE FUNCTION public.record_revenuecat_snapshot_absence(",
  );
  requiredSql("p_snapshot_id TEXT");
  requiredSql("p_observed_at TIMESTAMPTZ");
  requiredSql("p_present_stores TEXT[]");
  requiredSql("p_present_store_event_ids JSONB");
  requiredSql("snapshot_absence:");
  requiredSql("md5(");
  requiredSql("p_present_stores IS NULL");
  requiredSql("p_store = ANY(p_present_stores)");
  requiredSql("jsonb_typeof(p_present_store_event_ids) <> 'object'");
  requiredSql(
    "jsonb_typeof(p_present_store_event_ids -> listed.store_name) <> 'string'",
  );
  requiredSql("COALESCE(array_to_string(v_canonical_present_stores, ','), '')");
  requiredSql("missing_present_store");
  requiredSql("snapshot_conflict");
  requiredSql("p_observed_at > NOW()");
  requiredSql(
    "state.event_id = p_present_store_event_ids ->> listed.store_name",
  );
  requiredSql("state.verification_status = 'verified'");
  requiredSql(
    "state.revenuecat_environment IS NOT DISTINCT FROM p_revenuecat_environment",
  );
  requiredSql("state.event_at <= p_observed_at");
  requiredSql("upsert_subscription_store_state");
  requiredSql("verification_status => 'verified'");
  requiredSql("p_reset_usage => FALSE");
  requiredSql(
    "ALTER TABLE public.subscription_store_state_snapshot_absences ENABLE ROW LEVEL SECURITY;",
  );
  requiredSql(
    'CREATE POLICY "Service role can view subscription snapshot absences"',
  );
  requiredSql(
    "REVOKE ALL ON TABLE public.subscription_store_state_snapshot_absences",
  );
  requiredSql(
    "REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER\n  ON TABLE public.subscription_store_state_snapshot_absences\n  FROM service_role;",
  );
  requiredSql(
    "GRANT SELECT ON TABLE public.subscription_store_state_snapshot_absences\n  TO service_role;",
  );
  requiredSql(
    "GRANT EXECUTE ON FUNCTION public.record_revenuecat_snapshot_absence(",
  );
  requiredSql(
    "REVOKE ALL ON FUNCTION public.record_revenuecat_snapshot_absence(",
  );
  requiredSql(
    "REVOKE ALL ON FUNCTION public.record_revenuecat_snapshot_absence(\n  UUID, TEXT, TEXT, TIMESTAMPTZ, TEXT[], JSONB, TEXT",
  );
  requiredSql(
    "GRANT EXECUTE ON FUNCTION public.record_revenuecat_snapshot_absence(\n  UUID, TEXT, TEXT, TIMESTAMPTZ, TEXT[], JSONB, TEXT",
  );
  requiredSql("PERFORM 1 FROM public.users WHERE id = p_user_id FOR UPDATE;");

  const absenceStart = migrationSource.indexOf(
    "CREATE OR REPLACE FUNCTION public.record_revenuecat_snapshot_absence(",
  );
  const absenceEnd = migrationSource.indexOf(
    "-- Explicit, reviewed cutover gate.",
    absenceStart,
  );
  const absence = migrationSource.slice(absenceStart, absenceEnd);
  const eventLock = absence.indexOf("PERFORM pg_advisory_xact_lock(");
  const userLock = absence.indexOf(
    "PERFORM 1 FROM public.users WHERE id = p_user_id FOR UPDATE;",
  );
  const writerCall = absence.indexOf(
    "FROM public.upsert_subscription_store_state(",
  );
  const manifestInsert = absence.indexOf(
    "INSERT INTO public.subscription_store_state_snapshot_manifests (",
  );
  assert(eventLock >= 0, "absence workflow must take its event lock");
  assert(userLock > eventLock, "absence workflow must lock event before user");
  assert(
    writerCall > userLock,
    "absence workflow must validate before writing",
  );
  assert(
    manifestInsert > writerCall,
    "absence manifest must be anchored after the tombstone writer",
  );
});
