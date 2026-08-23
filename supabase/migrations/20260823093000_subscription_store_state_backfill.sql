-- M3 BILL-07 branch-only backfill and reconciliation helpers.
--
-- These functions are deliberately service_role-only. The backfill never
-- guesses a missing store or timestamp, records legacy evidence as
-- unverified, and can be rerun safely with the same deterministic event id.
-- Production execution remains pending an explicit runbook/reconciliation
-- review; this migration must not be used as a production command by itself.

CREATE OR REPLACE FUNCTION public.backfill_subscription_store_state_from_legacy(
  p_user_id UUID DEFAULT NULL
)
RETURNS TABLE(
  backfill_user_id UUID,
  store TEXT,
  event_id TEXT,
  accepted BOOLEAN,
  reason TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_legacy public.subscriptions%ROWTYPE;
  v_store TEXT;
  v_event_at TIMESTAMPTZ;
  v_event_id TEXT;
  v_base_plan_id TEXT;
  v_environment TEXT;
  v_accepted BOOLEAN;
  v_reason TEXT;
BEGIN
  FOR v_legacy IN
    SELECT *
    FROM public.subscriptions AS s
    WHERE p_user_id IS NULL OR s.user_id = p_user_id
    ORDER BY s.user_id
  LOOP
    v_store := NULLIF(lower(trim(COALESCE(v_legacy.store, ''))), '');

    IF v_store IS NULL OR v_store NOT IN ('app_store', 'play_store') THEN
      RETURN QUERY SELECT
        v_legacy.user_id,
        v_store,
        NULL::TEXT,
        FALSE,
        'ambiguous_legacy_store'::TEXT;
      CONTINUE;
    END IF;

    IF v_legacy.started_at IS NULL THEN
      RETURN QUERY SELECT
        v_legacy.user_id,
        v_store,
        NULL::TEXT,
        FALSE,
        'missing_legacy_event_at'::TEXT;
      CONTINUE;
    END IF;

    IF v_legacy.tier IN ('starter', 'essential')
       AND NULLIF(trim(v_legacy.active_product_id), '') IS NULL THEN
      RETURN QUERY SELECT
        v_legacy.user_id,
        v_store,
        NULL::TEXT,
        FALSE,
        'ambiguous_legacy_product'::TEXT;
      CONTINUE;
    END IF;

    v_event_at := v_legacy.started_at;
    v_base_plan_id := CASE
      WHEN v_store = 'play_store'
       AND position(':' IN COALESCE(v_legacy.active_product_id, '')) > 0
      THEN NULLIF(regexp_replace(v_legacy.active_product_id, '^.*:', ''), '')
      ELSE NULL
    END;
    v_environment := CASE
      WHEN v_legacy.revenuecat_environment IN ('sandbox', 'production')
      THEN v_legacy.revenuecat_environment
      ELSE NULL
    END;
    v_event_id := 'legacy_backfill:' || md5(concat_ws(
      '|',
      v_legacy.user_id::TEXT,
      v_store,
      COALESCE(v_legacy.active_product_id, '<null>'),
      COALESCE(v_base_plan_id, '<null>'),
      v_legacy.tier,
      v_legacy.status,
      COALESCE(v_legacy.expires_at::TEXT, '<null>'),
      v_event_at AT TIME ZONE 'UTC'
    ));

    SELECT u.accepted, u.reason
    INTO v_accepted, v_reason
    FROM public.upsert_subscription_store_state(
      p_user_id => v_legacy.user_id,
      p_store => v_store,
      p_product_id => v_legacy.active_product_id,
      p_base_plan_id => v_base_plan_id,
      p_tier => v_legacy.tier,
      p_status => v_legacy.status,
      p_expires_at => v_legacy.expires_at,
      p_event_at => v_event_at,
      p_event_id => v_event_id,
      p_verification_source => 'legacy_backfill',
      p_verification_status => 'unverified',
      p_revenuecat_environment => v_environment,
      p_reset_usage => FALSE
    ) AS u;

    RETURN QUERY SELECT
      v_legacy.user_id,
      v_store,
      v_event_id,
      v_accepted,
      v_reason;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.backfill_subscription_store_state_from_legacy(UUID)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.backfill_subscription_store_state_from_legacy(UUID)
  TO service_role;

CREATE OR REPLACE FUNCTION public.reconcile_subscription_store_state_diff(
  p_user_id UUID DEFAULT NULL
)
RETURNS TABLE(
  user_id UUID,
  legacy_tier TEXT,
  legacy_status TEXT,
  legacy_product_id TEXT,
  legacy_expires_at TIMESTAMPTZ,
  effective_store TEXT,
  effective_tier TEXT,
  effective_status TEXT,
  effective_product_id TEXT,
  effective_expires_at TIMESTAMPTZ,
  effective_revenuecat_environment TEXT,
  has_verified_source BOOLEAN,
  differs BOOLEAN,
  reason TEXT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
WITH verified_summary AS (
  SELECT
    user_id,
    TRUE AS has_verified_source
  FROM public.subscription_store_states
  WHERE verification_status = 'verified'
    AND event_at <= NOW()
  GROUP BY user_id
),
effective_candidates AS (
  SELECT
    ss.*,
    ROW_NUMBER() OVER (
      PARTITION BY ss.user_id
      ORDER BY
        CASE ss.tier
          WHEN 'essential' THEN 2
          WHEN 'starter' THEN 1
          ELSE 0
        END DESC,
        ss.event_at DESC,
        ss.store ASC
    ) AS winner_rank
  FROM public.subscription_store_states AS ss
  WHERE ss.verification_status = 'verified'
    AND ss.event_at <= NOW()
    AND status <> 'expired'
    AND ((expires_at IS NULL AND status = 'active') OR expires_at > NOW())
),
effective AS (
  SELECT *
  FROM effective_candidates
  WHERE winner_rank = 1
),
latest_verified_candidates AS (
  SELECT
    ss.*,
    ROW_NUMBER() OVER (
      PARTITION BY ss.user_id
      ORDER BY ss.event_at DESC, ss.store ASC
    ) AS latest_rank
  FROM public.subscription_store_states AS ss
  WHERE ss.verification_status = 'verified'
    AND ss.event_at <= NOW()
),
latest_verified AS (
  SELECT *
  FROM latest_verified_candidates
  WHERE latest_rank = 1
),
source_projection AS (
  SELECT
    s.user_id,
    s.tier AS legacy_tier,
    s.status AS legacy_status,
    s.active_product_id AS legacy_product_id,
    s.expires_at AS legacy_expires_at,
    s.store AS legacy_store,
    s.revenuecat_environment AS legacy_revenuecat_environment,
    COALESCE(v.has_verified_source, FALSE) AS has_verified_source,
    e.user_id AS effective_user_id,
    CASE WHEN e.user_id IS NULL THEN l.store ELSE e.store END AS source_store,
    CASE WHEN e.user_id IS NULL THEN l.product_id ELSE e.product_id END
      AS source_product_id,
    CASE WHEN e.user_id IS NULL THEN l.expires_at ELSE e.expires_at END
      AS source_expires_at,
    CASE
      WHEN e.user_id IS NULL THEN l.revenuecat_environment
      ELSE e.revenuecat_environment
    END AS source_revenuecat_environment,
    CASE WHEN e.user_id IS NULL THEN 'free' ELSE e.tier END AS expected_tier,
    CASE
      WHEN e.user_id IS NULL THEN 'expired'
      WHEN e.status = 'billing_issue' THEN 'active'
      ELSE e.status
    END AS expected_status
  FROM public.subscriptions AS s
  LEFT JOIN verified_summary AS v ON v.user_id = s.user_id
  LEFT JOIN effective AS e ON e.user_id = s.user_id
  LEFT JOIN latest_verified AS l ON l.user_id = s.user_id
  WHERE p_user_id IS NULL OR s.user_id = p_user_id
)
SELECT
  p.user_id,
  p.legacy_tier,
  p.legacy_status,
  p.legacy_product_id,
  p.legacy_expires_at,
  p.source_store AS effective_store,
  p.expected_tier AS effective_tier,
  p.expected_status AS effective_status,
  p.source_product_id AS effective_product_id,
  p.source_expires_at AS effective_expires_at,
  p.source_revenuecat_environment AS effective_revenuecat_environment,
  p.has_verified_source,
  CASE
    WHEN NOT p.has_verified_source THEN NULL
    ELSE NOT (
      p.legacy_tier IS NOT DISTINCT FROM p.expected_tier
      AND p.legacy_status IS NOT DISTINCT FROM p.expected_status
      AND p.legacy_product_id IS NOT DISTINCT FROM p.source_product_id
      AND p.legacy_expires_at IS NOT DISTINCT FROM p.source_expires_at
      AND p.legacy_store IS NOT DISTINCT FROM p.source_store
      AND p.legacy_revenuecat_environment IS NOT DISTINCT FROM p.source_revenuecat_environment
    )
  END AS differs,
  CASE
    WHEN NOT p.has_verified_source THEN 'no_verified_source'
    WHEN (
      p.legacy_tier IS NOT DISTINCT FROM p.expected_tier
      AND p.legacy_status IS NOT DISTINCT FROM p.expected_status
      AND p.legacy_product_id IS NOT DISTINCT FROM p.source_product_id
      AND p.legacy_expires_at IS NOT DISTINCT FROM p.source_expires_at
      AND p.legacy_store IS NOT DISTINCT FROM p.source_store
      AND p.legacy_revenuecat_environment IS NOT DISTINCT FROM p.source_revenuecat_environment
    ) THEN 'match'
    WHEN p.effective_user_id IS NULL THEN 'verified_sources_not_effective'
    ELSE 'aggregate_mismatch'
  END AS reason
FROM source_projection AS p;
$$;

REVOKE ALL ON FUNCTION public.reconcile_subscription_store_state_diff(UUID)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_subscription_store_state_diff(UUID)
  TO service_role;

NOTIFY pgrst, 'reload schema';
