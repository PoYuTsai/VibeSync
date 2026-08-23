-- M3 BILL-07：每個 user/store 的已驗證訂閱狀態。
--
-- 這張表只新增來源分層，不改動既有 subscriptions 欄位或既有 client
-- contract。legacy subscriptions 仍由既有讀者使用，後續 reconciliation 會
-- 以這裡可證明的 store state 重算 aggregate。

-- Reuse public.infer_subscription_billing_period from the earlier product
-- details migration. Upsert and finalization must call that one canonical
-- helper instead of carrying separate product-id inference branches.

CREATE TABLE public.subscription_store_states (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  store TEXT NOT NULL CHECK (store IN ('app_store', 'play_store')),
  product_id TEXT,
  base_plan_id TEXT,
  tier TEXT NOT NULL CHECK (tier IN ('free', 'starter', 'essential')),
  status TEXT NOT NULL CHECK (status IN ('active', 'cancelled', 'expired', 'billing_issue')),
  expires_at TIMESTAMPTZ,
  event_at TIMESTAMPTZ NOT NULL,
  event_id TEXT NOT NULL,
  verification_source TEXT NOT NULL CHECK (verification_source IN ('revenuecat_webhook', 'revenuecat_api', 'legacy_backfill')),
  verification_status TEXT NOT NULL DEFAULT 'verified' CHECK (verification_status IN ('verified', 'unverified')),
  revenuecat_environment TEXT CHECK (revenuecat_environment IN ('sandbox', 'production')),
  CONSTRAINT subscription_store_states_legacy_backfill_unverified CHECK (
    verification_source <> 'legacy_backfill' OR verification_status = 'unverified'
  ),
  CONSTRAINT subscription_store_states_user_store_key UNIQUE (user_id, store),
  CONSTRAINT subscription_store_states_user_store_event_key
    UNIQUE (user_id, store, event_id)
);

CREATE INDEX idx_subscription_store_states_user_store ON public.subscription_store_states(user_id, store);

CREATE INDEX idx_subscription_store_states_effective ON public.subscription_store_states(user_id, event_at DESC);

-- A verified row is not, by itself, proof that an ambiguous legacy paid row has
-- been fully reconciled. This per-user marker is the explicit cutover gate.
CREATE TABLE public.subscription_store_state_reconciliations (
  user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'auto', 'complete')),
  coverage TEXT NOT NULL DEFAULT 'unknown'
    CHECK (coverage IN ('unknown', 'no_paid_legacy_baseline', 'complete_revenuecat_snapshot')),
  completed_at TIMESTAMPTZ,
  completed_by TEXT,
  baseline_tier TEXT CHECK (baseline_tier IN ('free', 'starter', 'essential')),
  baseline_status TEXT CHECK (baseline_status IN ('active', 'cancelled', 'expired', 'billing_issue')),
  baseline_expires_at TIMESTAMPTZ,
  baseline_active_product_id TEXT,
  baseline_billing_period TEXT,
  baseline_store TEXT CHECK (baseline_store IN ('app_store', 'play_store')),
  baseline_revenuecat_environment TEXT CHECK (baseline_revenuecat_environment IN ('sandbox', 'production')),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Immutable evidence for one complete RevenueCat CustomerInfo snapshot. The
-- manifest is separate from the per-store materialization: a transient empty
-- API response cannot manufacture a complete snapshot, and a later state row
-- cannot silently change which snapshot was reviewed.
CREATE TABLE public.subscription_store_state_snapshot_manifests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  snapshot_id TEXT NOT NULL CHECK (length(trim(snapshot_id)) > 0),
  observed_at TIMESTAMPTZ NOT NULL,
  present_stores TEXT[] NOT NULL,
  present_store_event_ids JSONB NOT NULL,
  revenuecat_environment TEXT CHECK (revenuecat_environment IN ('sandbox', 'production')),
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT subscription_snapshot_manifest_supported_stores CHECK (
    present_stores <@ ARRAY['app_store', 'play_store']::TEXT[]
  ),
  CONSTRAINT subscription_snapshot_manifest_event_map_object CHECK (
    jsonb_typeof(present_store_event_ids) = 'object'
  ),
  UNIQUE (user_id, snapshot_id)
);

-- A missing store is meaningful only when it comes from one complete,
-- authoritative RevenueCat snapshot. Keep that proof separately from the
-- materialized store row so a transient empty API response can never be
-- mistaken for an expiry event.
CREATE TABLE public.subscription_store_state_snapshot_absences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  store TEXT NOT NULL CHECK (store IN ('app_store', 'play_store')),
  snapshot_id TEXT NOT NULL CHECK (length(trim(snapshot_id)) > 0),
  observed_at TIMESTAMPTZ NOT NULL,
  present_stores TEXT[] NOT NULL,
  present_store_event_ids JSONB NOT NULL,
  absence_event_id TEXT NOT NULL,
  revenuecat_environment TEXT CHECK (revenuecat_environment IN ('sandbox', 'production')),
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT subscription_snapshot_absence_store_not_present CHECK (
    NOT (store = ANY(present_stores))
  ),
  CONSTRAINT subscription_snapshot_absence_supported_present_stores CHECK (
    present_stores <@ ARRAY['app_store', 'play_store']::TEXT[]
  ),
  CONSTRAINT subscription_snapshot_absence_event_map_object CHECK (
    jsonb_typeof(present_store_event_ids) = 'object'
  ),
  UNIQUE (user_id, store, snapshot_id),
  UNIQUE (user_id, store, absence_event_id)
);

ALTER TABLE public.subscription_store_states ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own subscription store states" ON public.subscription_store_states
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Service role can manage subscription store states" ON public.subscription_store_states
  FOR ALL TO service_role
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Users can view own subscription reconciliation"
  ON public.subscription_store_state_reconciliations
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Service role can manage subscription reconciliation"
  ON public.subscription_store_state_reconciliations
  FOR ALL TO service_role
  USING (true)
  WITH CHECK (true);

ALTER TABLE public.subscription_store_state_reconciliations ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.subscription_store_state_snapshot_manifests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role can view subscription snapshot manifests"
  ON public.subscription_store_state_snapshot_manifests
  FOR SELECT TO service_role
  USING (true);

REVOKE ALL ON TABLE public.subscription_store_state_snapshot_manifests
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.subscription_store_state_snapshot_manifests
  TO service_role;

ALTER TABLE public.subscription_store_state_snapshot_absences ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role can view subscription snapshot absences"
  ON public.subscription_store_state_snapshot_absences
  FOR SELECT TO service_role
  USING (true);

REVOKE ALL ON TABLE public.subscription_store_state_snapshot_absences
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.subscription_store_state_snapshot_absences
  TO service_role;

-- All RevenueCat snapshot/webhook writers call this function. The store row
-- lock, event ordering decision, and legacy aggregate update intentionally live
-- in one transaction so a stale edge pre-read cannot clobber a newer state.
CREATE OR REPLACE FUNCTION public.upsert_subscription_store_state(
  p_user_id UUID,
  p_store TEXT,
  p_product_id TEXT,
  p_base_plan_id TEXT,
  p_tier TEXT,
  p_status TEXT,
  p_expires_at TIMESTAMPTZ,
  p_event_at TIMESTAMPTZ,
  p_event_id TEXT,
  p_verification_source TEXT,
  p_verification_status TEXT DEFAULT NULL,
  p_revenuecat_environment TEXT DEFAULT NULL,
  p_reset_usage BOOLEAN DEFAULT FALSE
)
RETURNS TABLE(accepted BOOLEAN, reason TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_current public.subscription_store_states%ROWTYPE;
  v_legacy public.subscriptions%ROWTYPE;
  v_winner public.subscription_store_states%ROWTYPE;
  v_latest public.subscription_store_states%ROWTYPE;
  v_verification_status TEXT;
  v_new_tier TEXT;
  v_new_status TEXT;
  v_has_verified BOOLEAN;
  v_should_reset BOOLEAN;
  v_cutover_complete BOOLEAN;
  v_preserve_legacy BOOLEAN;
BEGIN
  IF p_user_id IS NULL
     OR p_store IS NULL
     OR p_store NOT IN ('app_store', 'play_store')
     OR p_tier IS NULL
     OR p_tier NOT IN ('free', 'starter', 'essential')
     OR (
       p_tier IN ('starter', 'essential')
       AND NULLIF(trim(p_product_id), '') IS NULL
     )
     OR p_status IS NULL
     OR p_status NOT IN ('active', 'cancelled', 'expired', 'billing_issue')
     OR p_event_at IS NULL
     OR p_event_id IS NULL
     OR length(trim(p_event_id)) = 0
     OR p_verification_source IS NULL
     OR p_verification_source NOT IN (
       'revenuecat_webhook', 'revenuecat_api', 'legacy_backfill'
     )
     OR (p_verification_status IS NOT NULL AND p_verification_status NOT IN ('verified', 'unverified'))
     OR (p_revenuecat_environment IS NOT NULL AND p_revenuecat_environment NOT IN ('sandbox', 'production'))
  THEN
    RETURN QUERY SELECT FALSE, 'invalid';
    RETURN;
  END IF;

  v_verification_status := COALESCE(
    p_verification_status,
    CASE WHEN p_verification_source = 'legacy_backfill' THEN 'unverified' ELSE 'verified' END
  );
  IF p_verification_source = 'legacy_backfill' AND v_verification_status <> 'unverified' THEN
    RETURN QUERY SELECT FALSE, 'invalid';
    RETURN;
  END IF;

  -- Lock both the event key and the parent user before reading either row.
  -- This closes the missing-row race when two stores are first seen at once;
  -- the event lock makes the global (store,event_id) duplicate check atomic.
  PERFORM pg_advisory_xact_lock(hashtextextended(
    p_store || ':' || trim(p_event_id), 0
  ));
  PERFORM 1 FROM public.users WHERE id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, 'invalid';
    RETURN;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.subscription_store_state_reconciliations
    WHERE user_id = p_user_id AND status IN ('auto', 'complete')
  ) INTO v_cutover_complete;

  SELECT * INTO v_current FROM public.subscription_store_states
  WHERE user_id = p_user_id AND store = p_store
  FOR UPDATE;

  IF FOUND THEN
    IF v_verification_status = 'unverified'
       AND v_current.verification_status = 'verified' THEN
      RETURN QUERY SELECT FALSE, 'preserve_verified';
      RETURN;
    END IF;
    IF v_current.verification_status = 'unverified'
       AND v_verification_status = 'verified' THEN
      -- A verified event is authoritative even when its event time predates
      -- an unverified backfill row for the same store.
      NULL;
    ELSE
      IF v_current.event_id = trim(p_event_id) THEN
        RETURN QUERY SELECT FALSE, 'duplicate';
        RETURN;
      END IF;
      IF v_current.event_at >= p_event_at THEN
        RETURN QUERY SELECT FALSE, 'stale';
        RETURN;
      END IF;
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.subscription_store_states
    WHERE user_id = p_user_id
      AND store = p_store
      AND event_id = trim(p_event_id)
      AND NOT (
        user_id = p_user_id
        AND v_current.event_id = trim(p_event_id)
        AND v_current.verification_status = 'unverified'
        AND v_verification_status = 'verified'
      )
  ) THEN
    RETURN QUERY SELECT FALSE, 'duplicate';
    RETURN;
  END IF;

  INSERT INTO public.subscription_store_states (
    user_id,
    store,
    product_id,
    base_plan_id,
    tier,
    status,
    expires_at,
    event_at,
    event_id,
    verification_source,
    verification_status,
    revenuecat_environment
  ) VALUES (
    p_user_id,
    p_store,
    NULLIF(trim(p_product_id), ''),
    NULLIF(trim(p_base_plan_id), ''),
    p_tier,
    p_status,
    p_expires_at,
    p_event_at,
    trim(p_event_id),
    p_verification_source,
    v_verification_status,
    p_revenuecat_environment
  )
  ON CONFLICT (user_id, store) DO UPDATE
  SET product_id = EXCLUDED.product_id,
      base_plan_id = EXCLUDED.base_plan_id,
      tier = EXCLUDED.tier,
      status = EXCLUDED.status,
      expires_at = EXCLUDED.expires_at,
      event_at = EXCLUDED.event_at,
      event_id = EXCLUDED.event_id,
      verification_source = EXCLUDED.verification_source,
      verification_status = EXCLUDED.verification_status,
      revenuecat_environment = EXCLUDED.revenuecat_environment;

  SELECT * INTO v_legacy FROM public.subscriptions
  WHERE user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO public.subscriptions (
      user_id,
      tier,
      status,
      monthly_messages_used,
      daily_messages_used,
      monthly_reset_at,
      daily_reset_at,
      started_at
    ) VALUES (
      p_user_id,
      'free',
      'active',
      0,
      0,
      NOW(),
      NOW(),
      NOW()
    );
    SELECT * INTO v_legacy FROM public.subscriptions
    WHERE user_id = p_user_id
    FOR UPDATE;
  END IF;

  -- A free legacy baseline has no paid entitlement to protect. Mark that
  -- narrow fact atomically before materializing a verified upgrade; this is
  -- different from declaring an ambiguous paid legacy row reconciled.
  IF NOT v_cutover_complete
     AND COALESCE(v_legacy.tier, 'free') = 'free'
     AND v_verification_status = 'verified'
  THEN
    INSERT INTO public.subscription_store_state_reconciliations (
      user_id, status, coverage, baseline_tier, baseline_status,
      baseline_expires_at, baseline_active_product_id, baseline_billing_period,
      baseline_store, baseline_revenuecat_environment, updated_at
    ) VALUES (
      p_user_id, 'auto', 'no_paid_legacy_baseline', v_legacy.tier,
      v_legacy.status, v_legacy.expires_at, v_legacy.active_product_id,
      v_legacy.billing_period, v_legacy.store,
      v_legacy.revenuecat_environment, NOW()
    )
    ON CONFLICT (user_id) DO UPDATE
    SET status = 'auto',
        coverage = 'no_paid_legacy_baseline',
        baseline_tier = COALESCE(
          public.subscription_store_state_reconciliations.baseline_tier,
          EXCLUDED.baseline_tier
        ),
        baseline_status = COALESCE(
          public.subscription_store_state_reconciliations.baseline_status,
          EXCLUDED.baseline_status
        ),
        baseline_expires_at = COALESCE(
          public.subscription_store_state_reconciliations.baseline_expires_at,
          EXCLUDED.baseline_expires_at
        ),
        baseline_active_product_id = COALESCE(
          public.subscription_store_state_reconciliations.baseline_active_product_id,
          EXCLUDED.baseline_active_product_id
        ),
        baseline_billing_period = COALESCE(
          public.subscription_store_state_reconciliations.baseline_billing_period,
          EXCLUDED.baseline_billing_period
        ),
        baseline_store = COALESCE(
          public.subscription_store_state_reconciliations.baseline_store,
          EXCLUDED.baseline_store
        ),
        baseline_revenuecat_environment = COALESCE(
          public.subscription_store_state_reconciliations.baseline_revenuecat_environment,
          EXCLUDED.baseline_revenuecat_environment
        ),
        updated_at = NOW();
    v_cutover_complete := TRUE;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.subscription_store_states
    WHERE user_id = p_user_id AND verification_status = 'verified'
      AND event_at <= NOW()
  ) INTO v_has_verified;
  IF NOT v_has_verified THEN
    RETURN QUERY SELECT TRUE, 'preserve_no_verified_source';
    RETURN;
  END IF;

  SELECT * INTO v_winner
  FROM public.subscription_store_states
  WHERE user_id = p_user_id
    AND verification_status = 'verified'
    AND event_at <= NOW()
    AND status <> 'expired'
    AND ((expires_at IS NULL AND status = 'active') OR expires_at > NOW())
  ORDER BY
    CASE tier WHEN 'essential' THEN 2 WHEN 'starter' THEN 1 ELSE 0 END DESC,
    event_at DESC,
    store ASC
  LIMIT 1;

  IF FOUND THEN
    v_new_tier := v_winner.tier;
    v_new_status := CASE
      WHEN v_winner.status = 'billing_issue' THEN 'active'
      ELSE v_winner.status
    END;
  ELSE
    SELECT * INTO v_latest
    FROM public.subscription_store_states
    WHERE user_id = p_user_id
      AND verification_status = 'verified'
      AND event_at <= NOW()
    ORDER BY event_at DESC, store ASC
    LIMIT 1;
    v_new_tier := 'free';
    v_new_status := 'expired';
    v_winner := v_latest;
  END IF;

  -- Pending cutover is deliberately conservative. A paid legacy row whose
  -- store or historical coverage is ambiguous is never materialized from a
  -- single store snapshot; read-time projection may temporarily show a
  -- stronger verified source, while this baseline remains intact until the
  -- service-role finalizer marks the user complete.
  v_preserve_legacy := NOT v_cutover_complete
    AND COALESCE(v_legacy.tier, 'free') IN ('starter', 'essential');
  IF v_preserve_legacy THEN
    RETURN QUERY SELECT TRUE, 'preserve_legacy_unreconciled';
    RETURN;
  END IF;

  -- Recomputing the entitlement must never erase quota counters. A caller
  -- may request an explicit reset for a product event, but a tier transition
  -- alone is not permission to reset usage.
  v_should_reset := p_reset_usage AND (
    (
      v_new_tier = 'free'
      AND COALESCE(v_legacy.tier, 'free') <> 'free'
    )
    OR (
      CASE v_new_tier
        WHEN 'essential' THEN 2
        WHEN 'starter' THEN 1
        ELSE 0
      END > CASE COALESCE(v_legacy.tier, 'free')
        WHEN 'essential' THEN 2
        WHEN 'starter' THEN 1
        ELSE 0
      END
    )
  );

  IF v_should_reset THEN
    UPDATE public.subscriptions
    SET tier = v_new_tier,
        status = v_new_status,
        expires_at = v_winner.expires_at,
        active_product_id = v_winner.product_id,
        billing_period = public.infer_subscription_billing_period(v_winner.product_id),
        store = v_winner.store,
        revenuecat_environment = v_winner.revenuecat_environment,
        monthly_messages_used = 0,
        daily_messages_used = 0,
        monthly_reset_at = NOW(),
        daily_reset_at = NOW()
    WHERE user_id = p_user_id;
  ELSE
    UPDATE public.subscriptions
    SET tier = v_new_tier,
        status = v_new_status,
        expires_at = v_winner.expires_at,
        active_product_id = v_winner.product_id,
        billing_period = public.infer_subscription_billing_period(v_winner.product_id),
        store = v_winner.store,
        revenuecat_environment = v_winner.revenuecat_environment
    WHERE user_id = p_user_id;
  END IF;

  RETURN QUERY SELECT TRUE, 'accepted';
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_subscription_store_state(
  uuid, text, text, text, text, text, timestamptz, timestamptz, text,
  text, text, text, boolean
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_subscription_store_state(
  uuid, text, text, text, text, text, timestamptz, timestamptz, text,
  text, text, text, boolean
) TO service_role;

-- Record the immutable manifest for a complete RevenueCat snapshot. Present
-- store events must already be verified and match the supplied event map; the
-- absence writer below records the complementary tombstone rows. Keeping this
-- manifest in a service-role table lets finalization prove the exact snapshot
-- instead of trusting a caller's coverage label.
CREATE OR REPLACE FUNCTION public.record_revenuecat_snapshot_manifest(
  p_user_id UUID,
  p_snapshot_id TEXT,
  p_observed_at TIMESTAMPTZ,
  p_present_stores TEXT[],
  p_present_store_event_ids JSONB,
  p_revenuecat_environment TEXT DEFAULT NULL
)
RETURNS TABLE(recorded BOOLEAN, reason TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_canonical_present_stores TEXT[];
  v_manifest RECORD;
BEGIN
  IF p_user_id IS NULL
     OR NULLIF(trim(p_snapshot_id), '') IS NULL
     OR p_observed_at IS NULL
     OR p_observed_at > NOW()
     OR p_present_stores IS NULL
     OR p_present_store_event_ids IS NULL
     OR jsonb_typeof(p_present_store_event_ids) <> 'object'
     OR (
       p_revenuecat_environment IS NOT NULL
       AND p_revenuecat_environment NOT IN ('sandbox', 'production')
     )
  THEN
    RETURN QUERY SELECT FALSE, 'invalid_snapshot';
    RETURN;
  END IF;

  SELECT COALESCE(array_agg(listed.store_name ORDER BY listed.store_name), ARRAY[]::TEXT[])
  INTO v_canonical_present_stores
  FROM unnest(p_present_stores) AS listed(store_name);

  IF cardinality(p_present_stores) <> (
       SELECT count(DISTINCT listed.store_name)::INTEGER
       FROM unnest(p_present_stores) AS listed(store_name)
     )
     OR EXISTS (
       SELECT 1
       FROM unnest(p_present_stores) AS listed(store_name)
       WHERE listed.store_name NOT IN ('app_store', 'play_store')
          OR jsonb_typeof(p_present_store_event_ids -> listed.store_name) <> 'string'
          OR NULLIF(trim(p_present_store_event_ids ->> listed.store_name), '') IS NULL
     )
     OR EXISTS (
       SELECT 1
       FROM jsonb_object_keys(p_present_store_event_ids) AS supplied(store_name)
       WHERE NOT (supplied.store_name = ANY(p_present_stores))
     )
  THEN
    RETURN QUERY SELECT FALSE, 'invalid_snapshot';
    RETURN;
  END IF;

  -- The parent lock serializes manifest creation with the writer/finalizer.
  PERFORM 1 FROM public.users WHERE id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, 'missing_user';
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM unnest(v_canonical_present_stores) AS listed(store_name)
    LEFT JOIN public.subscription_store_states AS state
      ON state.user_id = p_user_id
     AND state.store = listed.store_name
     AND state.event_id = p_present_store_event_ids ->> listed.store_name
     AND state.verification_status = 'verified'
     AND state.revenuecat_environment IS NOT DISTINCT FROM p_revenuecat_environment
     AND state.event_at <= p_observed_at
    WHERE state.user_id IS NULL
  ) THEN
    RETURN QUERY SELECT FALSE, 'missing_present_event';
    RETURN;
  END IF;

  SELECT * INTO v_manifest
  FROM public.subscription_store_state_snapshot_manifests
  WHERE user_id = p_user_id AND snapshot_id = trim(p_snapshot_id)
  FOR UPDATE;

  IF FOUND THEN
    IF v_manifest.observed_at IS DISTINCT FROM p_observed_at
       OR v_manifest.present_stores IS DISTINCT FROM v_canonical_present_stores
       OR v_manifest.present_store_event_ids IS DISTINCT FROM p_present_store_event_ids
       OR v_manifest.revenuecat_environment IS DISTINCT FROM p_revenuecat_environment
    THEN
      RETURN QUERY SELECT FALSE, 'snapshot_conflict';
      RETURN;
    END IF;
    RETURN QUERY SELECT TRUE, 'duplicate';
    RETURN;
  END IF;

  INSERT INTO public.subscription_store_state_snapshot_manifests (
    user_id,
    snapshot_id,
    observed_at,
    present_stores,
    present_store_event_ids,
    revenuecat_environment
  ) VALUES (
    p_user_id,
    trim(p_snapshot_id),
    p_observed_at,
    v_canonical_present_stores,
    p_present_store_event_ids,
    p_revenuecat_environment
  );

  RETURN QUERY SELECT TRUE, 'recorded';
END;
$$;

REVOKE ALL ON FUNCTION public.record_revenuecat_snapshot_manifest(
  UUID, TEXT, TIMESTAMPTZ, TEXT[], JSONB, TEXT
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_revenuecat_snapshot_manifest(
  UUID, TEXT, TIMESTAMPTZ, TEXT[], JSONB, TEXT
) TO service_role;

-- Record one store that is absent from a complete RevenueCat snapshot. The
-- caller must supply the complete set of stores that were present plus their
-- event ids. An empty array/object is valid and represents a fully empty
-- snapshot; NULL or internally inconsistent evidence fails closed.
CREATE OR REPLACE FUNCTION public.record_revenuecat_snapshot_absence(
  p_user_id UUID,
  p_store TEXT,
  p_snapshot_id TEXT,
  p_observed_at TIMESTAMPTZ,
  p_present_stores TEXT[],
  p_present_store_event_ids JSONB,
  p_revenuecat_environment TEXT DEFAULT NULL
)
RETURNS TABLE(accepted BOOLEAN, reason TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_canonical_present_stores TEXT[];
  v_event_id TEXT;
  v_accepted BOOLEAN;
  v_reason TEXT;
BEGIN
  IF p_user_id IS NULL
     OR p_store IS NULL
     OR p_store NOT IN ('app_store', 'play_store')
     OR NULLIF(trim(p_snapshot_id), '') IS NULL
     OR p_observed_at IS NULL
     OR p_observed_at > NOW()
     OR p_present_stores IS NULL
     OR p_present_store_event_ids IS NULL
     OR jsonb_typeof(p_present_store_event_ids) <> 'object'
     OR (
       p_revenuecat_environment IS NOT NULL
       AND p_revenuecat_environment NOT IN ('sandbox', 'production')
     )
  THEN
    RETURN QUERY SELECT FALSE, 'invalid';
    RETURN;
  END IF;

  SELECT COALESCE(array_agg(listed.store_name ORDER BY listed.store_name), ARRAY[]::TEXT[])
  INTO v_canonical_present_stores
  FROM unnest(p_present_stores) AS listed(store_name);

  IF p_store = ANY(p_present_stores)
     OR cardinality(p_present_stores) <> (
       SELECT count(DISTINCT listed.store_name)::INTEGER
       FROM unnest(p_present_stores) AS listed(store_name)
     )
     OR EXISTS (
       SELECT 1
       FROM unnest(p_present_stores) AS listed(store_name)
       WHERE listed.store_name NOT IN ('app_store', 'play_store')
          OR jsonb_typeof(p_present_store_event_ids -> listed.store_name) <> 'string'
          OR NULLIF(trim(p_present_store_event_ids ->> listed.store_name), '') IS NULL
     )
     OR EXISTS (
       SELECT 1
       FROM jsonb_object_keys(p_present_store_event_ids) AS supplied(store_name)
       WHERE NOT (supplied.store_name = ANY(p_present_stores))
     )
  THEN
    RETURN QUERY SELECT FALSE, 'missing_present_store';
    RETURN;
  END IF;

  v_event_id := 'snapshot_absence:' || md5(
    p_user_id::TEXT || '|' || p_store || '|' || trim(p_snapshot_id) || '|' ||
    extract(epoch FROM p_observed_at)::TEXT || '|' ||
    COALESCE(array_to_string(v_canonical_present_stores, ','), '') || '|' ||
    p_present_store_event_ids::TEXT
  );

  -- Match the atomic writer's advisory-event -> parent-user lock order. Taking
  -- the same advisory lock up front is re-entrant when the writer is called
  -- below and avoids a user/event lock inversion with a concurrent webhook.
  PERFORM pg_advisory_xact_lock(hashtextextended(
    p_store || ':' || trim(v_event_id), 0
  ));
  PERFORM 1 FROM public.users WHERE id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, 'missing_user';
    RETURN;
  END IF;

  -- Present stores must already have the exact verified event from this same
  -- snapshot. This makes the absence proof complete rather than trusting an
  -- arbitrary list supplied by the service caller.
  IF EXISTS (
    SELECT 1
    FROM unnest(v_canonical_present_stores) AS listed(store_name)
    LEFT JOIN public.subscription_store_states AS state
      ON state.user_id = p_user_id
     AND state.store = listed.store_name
     AND state.event_id = p_present_store_event_ids ->> listed.store_name
     AND state.verification_status = 'verified'
     AND state.revenuecat_environment IS NOT DISTINCT FROM p_revenuecat_environment
     AND state.event_at <= p_observed_at
    WHERE state.user_id IS NULL
  ) THEN
    RETURN QUERY SELECT FALSE, 'missing_present_store';
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.subscription_store_state_snapshot_absences AS prior
    WHERE prior.user_id = p_user_id
      AND prior.store = p_store
      AND prior.snapshot_id = trim(p_snapshot_id)
      AND (
        prior.observed_at IS DISTINCT FROM p_observed_at
        OR prior.present_stores IS DISTINCT FROM v_canonical_present_stores
        OR prior.present_store_event_ids IS DISTINCT FROM p_present_store_event_ids
        OR prior.revenuecat_environment IS DISTINCT FROM p_revenuecat_environment
      )
  ) THEN
    RETURN QUERY SELECT FALSE, 'snapshot_conflict';
    RETURN;
  END IF;

  -- Every absence anchors the same immutable complete-snapshot manifest only
  -- after the tombstone writer has completed all checks. This ordering avoids
  -- leaving an orphan manifest when the atomic state writer rejects input.
  IF EXISTS (
    SELECT 1
    FROM public.subscription_store_state_snapshot_manifests AS prior_manifest
    WHERE prior_manifest.user_id = p_user_id
      AND prior_manifest.snapshot_id = trim(p_snapshot_id)
      AND (
        prior_manifest.observed_at IS DISTINCT FROM p_observed_at
        OR prior_manifest.present_stores IS DISTINCT FROM v_canonical_present_stores
        OR prior_manifest.present_store_event_ids IS DISTINCT FROM p_present_store_event_ids
        OR prior_manifest.revenuecat_environment IS DISTINCT FROM p_revenuecat_environment
      )
  ) THEN
    RETURN QUERY SELECT FALSE, 'snapshot_conflict';
    RETURN;
  END IF;

  SELECT write_result.accepted, write_result.reason
  INTO v_accepted, v_reason
  FROM public.upsert_subscription_store_state(
    p_user_id => p_user_id,
    p_store => p_store,
    p_product_id => NULL,
    p_base_plan_id => NULL,
    p_tier => 'free',
    p_status => 'expired',
    p_expires_at => p_observed_at,
    p_event_at => p_observed_at,
    p_event_id => v_event_id,
    p_verification_source => 'revenuecat_api',
    p_verification_status => 'verified',
    p_revenuecat_environment => p_revenuecat_environment,
    p_reset_usage => FALSE
  ) AS write_result;

  IF NOT COALESCE(v_accepted, FALSE)
     AND COALESCE(v_reason, 'invalid_response') NOT IN ('duplicate', 'stale')
  THEN
    RETURN QUERY SELECT COALESCE(v_accepted, FALSE), COALESCE(v_reason, 'invalid_response');
    RETURN;
  END IF;

  INSERT INTO public.subscription_store_state_snapshot_manifests (
    user_id,
    snapshot_id,
    observed_at,
    present_stores,
    present_store_event_ids,
    revenuecat_environment
  ) VALUES (
    p_user_id,
    trim(p_snapshot_id),
    p_observed_at,
    v_canonical_present_stores,
    p_present_store_event_ids,
    p_revenuecat_environment
  )
  ON CONFLICT (user_id, snapshot_id) DO NOTHING;

  INSERT INTO public.subscription_store_state_snapshot_absences (
    user_id,
    store,
    snapshot_id,
    observed_at,
    present_stores,
    present_store_event_ids,
    absence_event_id,
    revenuecat_environment
  ) VALUES (
    p_user_id,
    p_store,
    trim(p_snapshot_id),
    p_observed_at,
    v_canonical_present_stores,
    p_present_store_event_ids,
    v_event_id,
    p_revenuecat_environment
  )
  ON CONFLICT (user_id, store, snapshot_id) DO NOTHING;

  RETURN QUERY SELECT COALESCE(v_accepted, FALSE), COALESCE(v_reason, 'invalid_response');
END;
$$;

REVOKE ALL ON FUNCTION public.record_revenuecat_snapshot_absence(
  UUID, TEXT, TEXT, TIMESTAMPTZ, TEXT[], JSONB, TEXT
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_revenuecat_snapshot_absence(
  UUID, TEXT, TEXT, TIMESTAMPTZ, TEXT[], JSONB, TEXT
) TO service_role;

-- Explicit, reviewed cutover gate. Paid legacy rows must carry an unambiguous
-- store/product baseline and that exact store must have current verified
-- coverage. Even then, a caller must provide evidence of a complete
-- multi-store RevenueCat snapshot; one non-empty subscription is insufficient.
CREATE OR REPLACE FUNCTION public.finalize_subscription_store_state_reconciliation(
  p_user_id UUID,
  p_snapshot_id TEXT,
  p_observed_at TIMESTAMPTZ,
  p_present_stores TEXT[],
  p_present_store_event_ids JSONB,
  p_completed_by TEXT DEFAULT 'service_role'
)
RETURNS TABLE(finalized BOOLEAN, reason TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_legacy public.subscriptions%ROWTYPE;
  v_state public.subscription_store_states%ROWTYPE;
  v_manifest public.subscription_store_state_snapshot_manifests%ROWTYPE;
  v_proof_state public.subscription_store_states%ROWTYPE;
  v_canonical_present_stores TEXT[];
  v_store TEXT;
  v_present_event_id TEXT;
  v_expected_absence_event_id TEXT;
BEGIN
  -- Finalization is bound to an immutable service-role manifest. A caller's
  -- former coverage label is not evidence: every store must match either its
  -- exact verified event or the exact audited absence for this snapshot.
  IF p_user_id IS NULL
     OR NULLIF(trim(p_snapshot_id), '') IS NULL
     OR p_observed_at IS NULL
     OR p_observed_at > NOW()
     OR p_present_stores IS NULL
     OR p_present_store_event_ids IS NULL
     OR jsonb_typeof(p_present_store_event_ids) <> 'object'
  THEN
    RETURN QUERY SELECT FALSE, 'invalid_snapshot';
    RETURN;
  END IF;

  SELECT COALESCE(array_agg(listed.store_name ORDER BY listed.store_name), ARRAY[]::TEXT[])
  INTO v_canonical_present_stores
  FROM unnest(p_present_stores) AS listed(store_name);

  IF cardinality(p_present_stores) <> (
       SELECT count(DISTINCT listed.store_name)::INTEGER
       FROM unnest(p_present_stores) AS listed(store_name)
     )
     OR EXISTS (
       SELECT 1
       FROM unnest(p_present_stores) AS listed(store_name)
       WHERE listed.store_name NOT IN ('app_store', 'play_store')
          OR jsonb_typeof(p_present_store_event_ids -> listed.store_name) <> 'string'
          OR NULLIF(trim(p_present_store_event_ids ->> listed.store_name), '') IS NULL
     )
     OR EXISTS (
       SELECT 1
       FROM jsonb_object_keys(p_present_store_event_ids) AS supplied(store_name)
       WHERE NOT (supplied.store_name = ANY(p_present_stores))
     )
  THEN
    RETURN QUERY SELECT FALSE, 'invalid_snapshot';
    RETURN;
  END IF;

  PERFORM 1 FROM public.users WHERE id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, 'missing_user';
    RETURN;
  END IF;

  SELECT * INTO v_manifest
  FROM public.subscription_store_state_snapshot_manifests
  WHERE user_id = p_user_id AND snapshot_id = trim(p_snapshot_id)
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, 'snapshot_manifest_missing';
    RETURN;
  END IF;
  IF v_manifest.observed_at IS DISTINCT FROM p_observed_at
     OR v_manifest.present_stores IS DISTINCT FROM v_canonical_present_stores
     OR v_manifest.present_store_event_ids IS DISTINCT FROM p_present_store_event_ids
  THEN
    RETURN QUERY SELECT FALSE, 'snapshot_manifest_mismatch';
    RETURN;
  END IF;

  -- Verify both stores against the same immutable manifest. Both-present,
  -- one-present/one-absent, and both-absent snapshots all take this path.
  FOR v_store IN
    SELECT unnest(ARRAY['app_store', 'play_store']::TEXT[])
  LOOP
    IF v_store IN ('app_store', 'play_store')
       AND v_store = ANY(v_manifest.present_stores)
    THEN
      v_present_event_id := v_manifest.present_store_event_ids ->> v_store;
      SELECT * INTO v_proof_state
      FROM public.subscription_store_states AS state
      WHERE state.user_id = p_user_id
        AND state.store = v_store
        AND state.event_id = v_present_event_id
        AND state.verification_status = 'verified'
        AND state.revenuecat_environment IS NOT DISTINCT FROM v_manifest.revenuecat_environment
        AND state.event_at <= v_manifest.observed_at
      FOR UPDATE;
      IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'missing_present_event';
        RETURN;
      END IF;
    ELSE
      v_expected_absence_event_id := 'snapshot_absence:' || md5(
        p_user_id::TEXT || '|' || v_store || '|' || trim(p_snapshot_id) || '|' ||
        extract(epoch FROM v_manifest.observed_at)::TEXT || '|' ||
        COALESCE(array_to_string(v_manifest.present_stores, ','), '') || '|' ||
        v_manifest.present_store_event_ids::TEXT
      );
      IF NOT EXISTS (
        SELECT 1
        FROM public.subscription_store_state_snapshot_absences AS absence
        WHERE absence.user_id = p_user_id
          AND absence.store = v_store
          AND absence.snapshot_id = trim(p_snapshot_id)
          AND absence.observed_at = v_manifest.observed_at
          AND absence.present_stores = v_manifest.present_stores
          AND absence.present_store_event_ids = v_manifest.present_store_event_ids
          AND absence.absence_event_id = v_expected_absence_event_id
          AND absence.revenuecat_environment IS NOT DISTINCT FROM v_manifest.revenuecat_environment
      ) THEN
        RETURN QUERY SELECT FALSE, 'missing_snapshot_absence';
        RETURN;
      END IF;
      SELECT * INTO v_proof_state
      FROM public.subscription_store_states AS state
      WHERE state.user_id = p_user_id
        AND state.store = v_store
        AND state.event_id = v_expected_absence_event_id
        AND state.tier = 'free'
        AND state.status = 'expired'
        AND state.verification_status = 'verified'
        AND state.revenuecat_environment IS NOT DISTINCT FROM v_manifest.revenuecat_environment
        AND state.event_at = v_manifest.observed_at
      FOR UPDATE;
      IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'missing_snapshot_absence';
        RETURN;
      END IF;
    END IF;
  END LOOP;

  SELECT * INTO v_legacy
  FROM public.subscriptions
  WHERE user_id = p_user_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, 'missing_legacy_subscription';
    RETURN;
  END IF;

  IF v_legacy.started_at IS NULL
     OR (v_legacy.tier IN ('starter', 'essential')
         AND (
           v_legacy.store IS NULL
           OR v_legacy.store NOT IN ('app_store', 'play_store')
           OR NULLIF(trim(v_legacy.active_product_id), '') IS NULL
         ))
  THEN
    RETURN QUERY SELECT FALSE, 'ambiguous_legacy_store';
    RETURN;
  END IF;

  IF v_legacy.tier IN ('starter', 'essential')
     AND NOT EXISTS (
       SELECT 1
       FROM public.subscription_store_states AS covered
       WHERE covered.user_id = p_user_id
         AND covered.store = v_legacy.store
         AND covered.verification_status = 'verified'
         AND covered.event_at <= NOW()
         AND (
           covered.tier = 'free'
           OR NULLIF(trim(covered.product_id), '') IS NOT NULL
         )
     )
  THEN
    RETURN QUERY SELECT FALSE, 'coverage_not_authoritative';
    RETURN;
  END IF;

  -- Select the same read-time winner as the writer, across every verified
  -- store. If all rows are ineffective, retain the latest verified row only
  -- for provenance while the aggregate becomes free/expired.
  SELECT * INTO v_state
  FROM public.subscription_store_states
  WHERE user_id = p_user_id
    AND verification_status = 'verified'
    AND event_at <= NOW()
    AND status <> 'expired'
    AND ((expires_at IS NULL AND status = 'active') OR expires_at > NOW())
  ORDER BY
    CASE tier WHEN 'essential' THEN 2 WHEN 'starter' THEN 1 ELSE 0 END DESC,
    event_at DESC,
    store ASC
  LIMIT 1
  FOR UPDATE;
  IF NOT FOUND THEN
    SELECT * INTO v_state
    FROM public.subscription_store_states
    WHERE user_id = p_user_id
      AND verification_status = 'verified'
      AND event_at <= NOW()
    ORDER BY event_at DESC, store ASC
    LIMIT 1
    FOR UPDATE;
  END IF;
  IF NOT FOUND AND v_legacy.tier IN ('starter', 'essential') THEN
    RETURN QUERY SELECT FALSE, 'coverage_not_authoritative';
    RETURN;
  END IF;
  IF v_state.user_id IS NOT NULL
     AND v_state.tier IN ('starter', 'essential')
     AND NULLIF(trim(v_state.product_id), '') IS NULL
  THEN
    RETURN QUERY SELECT FALSE, 'ambiguous_verified_product';
    RETURN;
  END IF;

  INSERT INTO public.subscription_store_state_reconciliations (
    user_id, status, coverage, completed_at, completed_by,
    baseline_tier, baseline_status, baseline_expires_at,
    baseline_active_product_id, baseline_billing_period, baseline_store,
    baseline_revenuecat_environment, updated_at
  ) VALUES (
    p_user_id, 'complete', 'complete_revenuecat_snapshot', NOW(),
    NULLIF(trim(p_completed_by), ''), v_legacy.tier, v_legacy.status,
    v_legacy.expires_at, v_legacy.active_product_id, v_legacy.billing_period,
    v_legacy.store, v_legacy.revenuecat_environment, NOW()
  )
  ON CONFLICT (user_id) DO UPDATE
  SET status = 'complete',
      coverage = 'complete_revenuecat_snapshot',
      completed_at = NOW(),
      completed_by = EXCLUDED.completed_by,
      baseline_tier = COALESCE(
        public.subscription_store_state_reconciliations.baseline_tier,
        EXCLUDED.baseline_tier
      ),
      baseline_status = COALESCE(
        public.subscription_store_state_reconciliations.baseline_status,
        EXCLUDED.baseline_status
      ),
      baseline_expires_at = COALESCE(
        public.subscription_store_state_reconciliations.baseline_expires_at,
        EXCLUDED.baseline_expires_at
      ),
      baseline_active_product_id = COALESCE(
        public.subscription_store_state_reconciliations.baseline_active_product_id,
        EXCLUDED.baseline_active_product_id
      ),
      baseline_billing_period = COALESCE(
        public.subscription_store_state_reconciliations.baseline_billing_period,
        EXCLUDED.baseline_billing_period
      ),
      baseline_store = COALESCE(
        public.subscription_store_state_reconciliations.baseline_store,
        EXCLUDED.baseline_store
      ),
      baseline_revenuecat_environment = COALESCE(
        public.subscription_store_state_reconciliations.baseline_revenuecat_environment,
        EXCLUDED.baseline_revenuecat_environment
      ),
      updated_at = NOW();

  -- Recompute immediately under the same locks; subsequent readers also
  -- recompute at their own clock, so waiting for another webhook is unnecessary.
  UPDATE public.subscriptions
  SET tier = CASE
        WHEN v_state.user_id IS NOT NULL
             AND v_state.status <> 'expired'
             AND ((v_state.expires_at IS NULL AND v_state.status = 'active')
                  OR v_state.expires_at > NOW())
          THEN v_state.tier
        ELSE 'free'
      END,
      status = CASE
        WHEN v_state.user_id IS NOT NULL
             AND v_state.status <> 'expired'
             AND ((v_state.expires_at IS NULL AND v_state.status = 'active')
                  OR v_state.expires_at > NOW())
          THEN CASE WHEN v_state.status = 'billing_issue' THEN 'active' ELSE v_state.status END
        ELSE 'expired'
      END,
      expires_at = CASE WHEN v_state.user_id IS NULL THEN NULL ELSE v_state.expires_at END,
      active_product_id = CASE WHEN v_state.user_id IS NULL THEN NULL ELSE v_state.product_id END,
      billing_period = CASE
        WHEN v_state.user_id IS NULL THEN NULL
        ELSE public.infer_subscription_billing_period(v_state.product_id)
      END,
      store = CASE WHEN v_state.user_id IS NULL THEN NULL ELSE v_state.store END,
      revenuecat_environment = CASE WHEN v_state.user_id IS NULL THEN NULL ELSE v_state.revenuecat_environment END
  WHERE user_id = p_user_id;

  RETURN QUERY SELECT TRUE, 'complete';
END;
$$;

REVOKE ALL ON FUNCTION public.finalize_subscription_store_state_reconciliation(
  UUID, TEXT, TIMESTAMPTZ, TEXT[], JSONB, TEXT
)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_subscription_store_state_reconciliation(
  UUID, TEXT, TIMESTAMPTZ, TEXT[], JSONB, TEXT
)
  TO service_role;

CREATE OR REPLACE FUNCTION public.rollback_subscription_store_state_reconciliation(
  p_user_id UUID,
  p_reason TEXT DEFAULT 'manual_review'
)
RETURNS TABLE(rolled_back BOOLEAN, reason TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_reconciliation public.subscription_store_state_reconciliations%ROWTYPE;
BEGIN
  -- Match upsert/finalize lock order: parent user first, then reconciliation,
  -- then legacy aggregate. This prevents a rollback/finalize deadlock where
  -- one transaction holds the reconciliation row while the other holds users.
  PERFORM 1 FROM public.users WHERE id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, 'missing_user';
    RETURN;
  END IF;

  SELECT * INTO v_reconciliation
  FROM public.subscription_store_state_reconciliations
  WHERE user_id = p_user_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, 'missing_reconciliation';
    RETURN;
  END IF;
  IF v_reconciliation.baseline_tier IS NULL THEN
    RETURN QUERY SELECT FALSE, 'missing_cutover_baseline';
    RETURN;
  END IF;

  -- Restore the exact pre-cutover aggregate before dropping the marker. Store
  -- evidence is intentionally retained for later review/reconciliation.
  UPDATE public.subscriptions
  SET tier = v_reconciliation.baseline_tier,
      status = v_reconciliation.baseline_status,
      expires_at = v_reconciliation.baseline_expires_at,
      active_product_id = v_reconciliation.baseline_active_product_id,
      billing_period = v_reconciliation.baseline_billing_period,
      store = v_reconciliation.baseline_store,
      revenuecat_environment = v_reconciliation.baseline_revenuecat_environment
  WHERE user_id = p_user_id;

  UPDATE public.subscription_store_state_reconciliations
  SET status = 'pending',
      coverage = 'unknown',
      completed_at = NULL,
      completed_by = NULL,
      baseline_tier = NULL,
      baseline_status = NULL,
      baseline_expires_at = NULL,
      baseline_active_product_id = NULL,
      baseline_billing_period = NULL,
      baseline_store = NULL,
      baseline_revenuecat_environment = NULL,
      updated_at = NOW()
  WHERE user_id = p_user_id;
  RETURN QUERY SELECT TRUE, COALESCE(NULLIF(trim(p_reason), ''), 'rolled_back');
END;
$$;

REVOKE ALL ON FUNCTION public.rollback_subscription_store_state_reconciliation(UUID, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rollback_subscription_store_state_reconciliation(UUID, TEXT)
  TO service_role;

NOTIFY pgrst, 'reload schema';
