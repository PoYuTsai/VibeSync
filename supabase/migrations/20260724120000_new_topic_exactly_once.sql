-- New Topic（破冰腦力）exactly-once contract（ADR #22 template，mirrored from
-- 20260721120000_coach_exactly_once.sql）。
--
-- Claim/lease prevents concurrent requests with the same identity from all
-- calling the model. Settlement stores the tier-projected result and
-- increments quota (+3) in one transaction. A lost-response retry replays the
-- stored result within 24 hours.
--
-- Deliberate parameter deviations from the coach template:
--   * lease 65 seconds — new-topic generation deadline is 45s + 5s settlement
--     reserve; 65s covers the full server request deadline with margin.
--   * fixed cost 3（increment_usage p_messages = 3）。
-- Structure is otherwise unchanged.
--
-- result_json 只存已依 tier 投影的最終 topics/recommendation/access——
-- 絕不存 Partner／About Me／情境原文、prompt、provider raw output 或
-- telemetry；Free row 只存推薦那一題（鎖定四題文字不落地）。

CREATE TABLE IF NOT EXISTS public.new_topic_requests (
  user_id          UUID        NOT NULL
                                REFERENCES auth.users(id) ON DELETE CASCADE,
  request_id       UUID        NOT NULL,
  input_hash       TEXT        NOT NULL
                                CHECK (input_hash ~ '^[0-9a-f]{64}$'),
  state            TEXT        NOT NULL DEFAULT 'pending'
                                CHECK (state IN ('pending', 'done')),
  owner_token      UUID        NOT NULL,
  lease_expires_at TIMESTAMPTZ NOT NULL,
  result_json      JSONB,
  quota_charged    BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, request_id),
  CONSTRAINT new_topic_requests_result_state_consistency CHECK (
    (
      state = 'pending'
      AND result_json IS NULL
      AND quota_charged = FALSE
    )
    OR
    (
      state = 'done'
      AND result_json IS NOT NULL
      AND jsonb_typeof(result_json) = 'object'
      -- 頂層恰為三鍵：topics / recommendation / access，禁夾帶其他鍵。
      AND result_json ?& ARRAY['topics', 'recommendation', 'access']
      AND (result_json - 'topics' - 'recommendation' - 'access')
        = '{}'::jsonb
      AND jsonb_typeof(result_json -> 'topics') = 'array'
      AND jsonb_typeof(result_json -> 'recommendation') = 'object'
      AND jsonb_typeof(result_json -> 'access') = 'object'
      -- access 欄位白名單＋totalCount 恆 5。
      AND (result_json -> 'access') ?& ARRAY[
        'servedTier', 'limited', 'totalCount', 'unlockedCount', 'lockedCount'
      ]
      AND ((result_json -> 'access')
        - 'servedTier' - 'limited' - 'totalCount'
        - 'unlockedCount' - 'lockedCount') = '{}'::jsonb
      AND (result_json -> 'access' ->> 'totalCount') = '5'
      -- tier 投影一致性：Free 只存 1 題（鎖 4）、Paid 存 5 題（鎖 0）。
      AND (
        (
          (result_json -> 'access' ->> 'servedTier') = 'free'
          AND (result_json -> 'access' ->> 'limited') = 'true'
          AND (result_json -> 'access' ->> 'unlockedCount') = '1'
          AND (result_json -> 'access' ->> 'lockedCount') = '4'
          AND jsonb_array_length(result_json -> 'topics') = 1
        )
        OR
        (
          (result_json -> 'access' ->> 'servedTier')
            IN ('starter', 'essential')
          AND (result_json -> 'access' ->> 'limited') = 'false'
          AND (result_json -> 'access' ->> 'unlockedCount') = '5'
          AND (result_json -> 'access' ->> 'lockedCount') = '0'
          AND jsonb_array_length(result_json -> 'topics') = 5
        )
      )
    )
  )
);

CREATE INDEX IF NOT EXISTS new_topic_requests_created_at_idx
  ON public.new_topic_requests (created_at);

ALTER TABLE public.new_topic_requests ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.new_topic_requests FROM PUBLIC;
REVOKE ALL ON TABLE public.new_topic_requests FROM anon, authenticated;
GRANT SELECT ON TABLE public.new_topic_requests TO service_role;

COMMENT ON TABLE public.new_topic_requests IS
  '24-hour idempotent replay ledger for New Topic ideas. Stores the tier-projected topics/recommendation/access only; never prompts, partner/about-me material, or provider raw output. input_hash is a server-keyed HMAC.';

CREATE OR REPLACE FUNCTION public.cleanup_expired_new_topic_requests()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deleted INTEGER;
BEGIN
  DELETE FROM public.new_topic_requests
  WHERE created_at < now() - interval '24 hours';
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

REVOKE EXECUTE ON FUNCTION
  public.cleanup_expired_new_topic_requests() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION
  public.cleanup_expired_new_topic_requests() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.cleanup_expired_new_topic_requests() TO service_role;

CREATE EXTENSION IF NOT EXISTS pg_cron;

DO $schedule$
DECLARE
  v_job_id BIGINT;
BEGIN
  FOR v_job_id IN
    SELECT jobid
    FROM cron.job
    WHERE jobname = 'cleanup-expired-new-topic-requests'
  LOOP
    PERFORM cron.unschedule(v_job_id);
  END LOOP;

  PERFORM cron.schedule(
    'cleanup-expired-new-topic-requests',
    '43 * * * *',
    'SELECT public.cleanup_expired_new_topic_requests();'
  );
END;
$schedule$;

CREATE OR REPLACE FUNCTION public.claim_new_topic_request(
  p_user_id UUID,
  p_request_id UUID,
  p_input_hash TEXT,
  p_owner_token UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inserted INTEGER;
  v_existing public.new_topic_requests%ROWTYPE;
  v_lease_expires_at TIMESTAMPTZ := now() + interval '65 seconds';
BEGIN
  IF p_user_id IS NULL OR p_request_id IS NULL OR p_owner_token IS NULL THEN
    RAISE EXCEPTION 'claim_new_topic_request: identity is required';
  END IF;
  IF p_input_hash IS NULL OR p_input_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'claim_new_topic_request: invalid p_input_hash';
  END IF;

  -- Only the colliding identity is cleaned on the interactive path. The
  -- hourly cron owns bulk retention so a user request never performs a
  -- cross-user backlog delete inside its billing transaction.
  DELETE FROM public.new_topic_requests
  WHERE user_id = p_user_id
    AND request_id = p_request_id
    AND created_at < now() - interval '24 hours';

  INSERT INTO public.new_topic_requests (
    user_id,
    request_id,
    input_hash,
    state,
    owner_token,
    lease_expires_at
  ) VALUES (
    p_user_id,
    p_request_id,
    p_input_hash,
    'pending',
    p_owner_token,
    v_lease_expires_at
  )
  ON CONFLICT (user_id, request_id) DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  IF v_inserted = 1 THEN
    RETURN jsonb_build_object(
      'kind', 'claimed',
      'leaseExpiresAt', v_lease_expires_at
    );
  END IF;

  SELECT * INTO v_existing
  FROM public.new_topic_requests
  WHERE user_id = p_user_id
    AND request_id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NEW_TOPIC_REQUEST_CLAIM_MISSING';
  END IF;
  IF v_existing.input_hash IS DISTINCT FROM p_input_hash THEN
    RAISE EXCEPTION 'NEW_TOPIC_REQUEST_REPLAY_MISMATCH';
  END IF;
  IF v_existing.state = 'done' THEN
    RETURN jsonb_build_object(
      'kind', 'replay',
      'result', v_existing.result_json
    );
  END IF;
  IF v_existing.owner_token = p_owner_token THEN
    UPDATE public.new_topic_requests
    SET lease_expires_at = v_lease_expires_at,
        updated_at = now()
    WHERE user_id = p_user_id
      AND request_id = p_request_id
      AND state = 'pending'
      AND owner_token = p_owner_token;
    RETURN jsonb_build_object(
      'kind', 'claimed',
      'leaseExpiresAt', v_lease_expires_at
    );
  END IF;
  IF v_existing.lease_expires_at > now() THEN
    RETURN jsonb_build_object(
      'kind', 'pending',
      'retryAfterMs', GREATEST(
        250,
        CEIL(EXTRACT(EPOCH FROM (v_existing.lease_expires_at - now())) * 1000)::INTEGER
      )
    );
  END IF;

  UPDATE public.new_topic_requests
  SET owner_token = p_owner_token,
      lease_expires_at = v_lease_expires_at,
      updated_at = now()
  WHERE user_id = p_user_id
    AND request_id = p_request_id;

  RETURN jsonb_build_object(
    'kind', 'claimed',
    'leaseExpiresAt', v_lease_expires_at
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.claim_new_topic_request(
  UUID, UUID, TEXT, UUID
) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.claim_new_topic_request(
  UUID, UUID, TEXT, UUID
) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_new_topic_request(
  UUID, UUID, TEXT, UUID
) TO service_role;

CREATE OR REPLACE FUNCTION public.release_new_topic_claim(
  p_user_id UUID,
  p_request_id UUID,
  p_input_hash TEXT,
  p_owner_token UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deleted INTEGER;
BEGIN
  DELETE FROM public.new_topic_requests
  WHERE user_id = p_user_id
    AND request_id = p_request_id
    AND input_hash = p_input_hash
    AND owner_token = p_owner_token
    AND state = 'pending';
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted = 1;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.release_new_topic_claim(
  UUID, UUID, TEXT, UUID
) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.release_new_topic_claim(
  UUID, UUID, TEXT, UUID
) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.release_new_topic_claim(
  UUID, UUID, TEXT, UUID
) TO service_role;

-- 深層 result 驗證抽成 helper：settle 的 CHECK constraint 只能擋粗形狀，
-- 這裡逐題驗欄位白名單、長度 cap、nt_1~nt_5 ID、唯一性與推薦存在性。
CREATE OR REPLACE FUNCTION public.validate_new_topic_result(
  p_result_json JSONB
)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_topic JSONB;
  v_id TEXT;
  v_direction TEXT;
  v_opening TEXT;
  v_why TEXT;
  v_next TEXT;
  v_reason TEXT;
  v_rec_topic_id TEXT;
  v_seen_ids TEXT[] := '{}';
  v_rec_found BOOLEAN := FALSE;
BEGIN
  IF p_result_json IS NULL
     OR jsonb_typeof(p_result_json) <> 'object'
     OR NOT (p_result_json ?& ARRAY['topics', 'recommendation', 'access'])
     OR (p_result_json - 'topics' - 'recommendation' - 'access')
       <> '{}'::jsonb
     OR jsonb_typeof(p_result_json -> 'topics') <> 'array'
     OR jsonb_typeof(p_result_json -> 'recommendation') <> 'object'
     OR jsonb_typeof(p_result_json -> 'access') <> 'object' THEN
    RETURN FALSE;
  END IF;

  -- access 形狀（tier/counts 一致性同 table CHECK，重複驗證守 settle 入口）。
  IF NOT ((p_result_json -> 'access') ?& ARRAY[
       'servedTier', 'limited', 'totalCount', 'unlockedCount', 'lockedCount'
     ])
     OR ((p_result_json -> 'access')
       - 'servedTier' - 'limited' - 'totalCount'
       - 'unlockedCount' - 'lockedCount') <> '{}'::jsonb
     OR (p_result_json -> 'access' ->> 'totalCount') <> '5'
     OR NOT (
       (
         (p_result_json -> 'access' ->> 'servedTier') = 'free'
         AND (p_result_json -> 'access' ->> 'limited') = 'true'
         AND (p_result_json -> 'access' ->> 'unlockedCount') = '1'
         AND (p_result_json -> 'access' ->> 'lockedCount') = '4'
         AND jsonb_array_length(p_result_json -> 'topics') = 1
       )
       OR
       (
         (p_result_json -> 'access' ->> 'servedTier')
           IN ('starter', 'essential')
         AND (p_result_json -> 'access' ->> 'limited') = 'false'
         AND (p_result_json -> 'access' ->> 'unlockedCount') = '5'
         AND (p_result_json -> 'access' ->> 'lockedCount') = '0'
         AND jsonb_array_length(p_result_json -> 'topics') = 5
       )
     ) THEN
    RETURN FALSE;
  END IF;

  FOR v_topic IN SELECT * FROM jsonb_array_elements(p_result_json -> 'topics')
  LOOP
    IF jsonb_typeof(v_topic) <> 'object'
       OR NOT (v_topic ?& ARRAY[
         'id', 'direction', 'openingLine', 'whyItWorks', 'nextMove'
       ])
       OR (v_topic
         - 'id' - 'direction' - 'openingLine'
         - 'whyItWorks' - 'nextMove') <> '{}'::jsonb THEN
      RETURN FALSE;
    END IF;

    v_id := v_topic ->> 'id';
    v_direction := v_topic ->> 'direction';
    v_opening := v_topic ->> 'openingLine';
    v_why := v_topic ->> 'whyItWorks';
    v_next := v_topic ->> 'nextMove';

    IF v_id IS NULL OR v_id !~ '^nt_[1-5]$'
       OR v_id = ANY (v_seen_ids)
       OR v_direction IS NULL OR length(btrim(v_direction)) = 0
       OR length(v_direction) > 80
       OR v_opening IS NULL OR length(btrim(v_opening)) = 0
       OR length(v_opening) > 180
       OR v_why IS NULL OR length(btrim(v_why)) = 0
       OR length(v_why) > 400
       OR v_next IS NULL OR length(btrim(v_next)) = 0
       OR length(v_next) > 300 THEN
      RETURN FALSE;
    END IF;
    v_seen_ids := v_seen_ids || v_id;
  END LOOP;

  -- recommendation：topicId 必存在於 stored topics；reason 選填 ≤300。
  IF NOT ((p_result_json -> 'recommendation') ? 'topicId')
     OR ((p_result_json -> 'recommendation') - 'topicId' - 'reason')
       <> '{}'::jsonb THEN
    RETURN FALSE;
  END IF;
  v_rec_topic_id := p_result_json -> 'recommendation' ->> 'topicId';
  v_rec_found := v_rec_topic_id = ANY (v_seen_ids);
  IF NOT v_rec_found THEN
    RETURN FALSE;
  END IF;
  IF (p_result_json -> 'recommendation') ? 'reason' THEN
    v_reason := p_result_json -> 'recommendation' ->> 'reason';
    IF v_reason IS NULL OR length(btrim(v_reason)) = 0
       OR length(v_reason) > 300 THEN
      RETURN FALSE;
    END IF;
  END IF;

  RETURN TRUE;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.validate_new_topic_result(JSONB)
  FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.validate_new_topic_result(JSONB)
  FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.validate_new_topic_result(JSONB)
  TO service_role;

CREATE OR REPLACE FUNCTION public.settle_new_topic_request(
  p_user_id UUID,
  p_request_id UUID,
  p_input_hash TEXT,
  p_owner_token UUID,
  p_result_json JSONB,
  p_monthly_limit INTEGER,
  p_daily_limit INTEGER,
  p_charge_quota BOOLEAN DEFAULT TRUE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing public.new_topic_requests%ROWTYPE;
  v_should_charge BOOLEAN := COALESCE(p_charge_quota, TRUE);
  v_monthly_used INTEGER;
  v_daily_used INTEGER;
BEGIN
  IF p_user_id IS NULL OR p_request_id IS NULL OR p_owner_token IS NULL THEN
    RAISE EXCEPTION 'settle_new_topic_request: identity is required';
  END IF;
  IF p_input_hash IS NULL OR p_input_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'settle_new_topic_request: invalid p_input_hash';
  END IF;
  IF NOT public.validate_new_topic_result(p_result_json) THEN
    RAISE EXCEPTION 'settle_new_topic_request: invalid p_result_json';
  END IF;
  IF v_should_charge
     AND (
       p_monthly_limit IS NULL OR p_monthly_limit <= 0
       OR p_daily_limit IS NULL OR p_daily_limit <= 0
     ) THEN
    RAISE EXCEPTION 'settle_new_topic_request: invalid quota limits';
  END IF;

  SELECT * INTO v_existing
  FROM public.new_topic_requests
  WHERE user_id = p_user_id
    AND request_id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NEW_TOPIC_REQUEST_SETTLEMENT_MISSING';
  END IF;
  IF v_existing.input_hash IS DISTINCT FROM p_input_hash THEN
    RAISE EXCEPTION 'NEW_TOPIC_REQUEST_REPLAY_MISMATCH';
  END IF;
  IF v_existing.state = 'done' THEN
    RETURN jsonb_build_object(
      'charged', FALSE,
      'result', v_existing.result_json
    );
  END IF;
  IF v_existing.owner_token IS DISTINCT FROM p_owner_token THEN
    RAISE EXCEPTION 'NEW_TOPIC_REQUEST_OWNER_MISMATCH';
  END IF;

  IF v_should_charge THEN
    PERFORM 1
    FROM public.subscriptions
    WHERE user_id = p_user_id
    FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'NEW_TOPIC_SUBSCRIPTION_MISSING';
    END IF;

    -- 固定成本 3；限額不足時 increment_usage RAISE，本 transaction 全回滾
    --（result 不落地、counter 不動：同成同敗）。
    PERFORM public.increment_usage(
      p_user_id,
      3,
      p_monthly_limit,
      p_daily_limit
    );
  END IF;

  UPDATE public.new_topic_requests
  SET state = 'done',
      result_json = p_result_json,
      quota_charged = v_should_charge,
      updated_at = now()
  WHERE user_id = p_user_id
    AND request_id = p_request_id;

  SELECT monthly_messages_used, daily_messages_used
  INTO v_monthly_used, v_daily_used
  FROM public.subscriptions
  WHERE user_id = p_user_id;

  RETURN jsonb_build_object(
    'charged', v_should_charge,
    'result', p_result_json,
    'monthlyUsed', v_monthly_used,
    'dailyUsed', v_daily_used
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.settle_new_topic_request(
  UUID, UUID, TEXT, UUID, JSONB, INTEGER, INTEGER, BOOLEAN
) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.settle_new_topic_request(
  UUID, UUID, TEXT, UUID, JSONB, INTEGER, INTEGER, BOOLEAN
) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.settle_new_topic_request(
  UUID, UUID, TEXT, UUID, JSONB, INTEGER, INTEGER, BOOLEAN
) TO service_role;

-- The Edge health endpoint reads this DB-owned capability marker. A new Edge
-- binary cannot self-declare readiness while the claim/settle migration is
-- missing or only partially installed.
CREATE OR REPLACE FUNCTION public.new_topic_contract_version()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN to_regclass('public.new_topic_requests') IS NOT NULL
      AND to_regprocedure(
        'public.claim_new_topic_request(uuid,uuid,text,uuid)'
      ) IS NOT NULL
      AND to_regprocedure(
        'public.release_new_topic_claim(uuid,uuid,text,uuid)'
      ) IS NOT NULL
      AND to_regprocedure(
        'public.settle_new_topic_request(uuid,uuid,text,uuid,jsonb,integer,integer,boolean)'
      ) IS NOT NULL
      AND to_regprocedure(
        'public.validate_new_topic_result(jsonb)'
      ) IS NOT NULL
      AND (
        SELECT count(*) = 4
        FROM pg_attribute
        WHERE attrelid = to_regclass('public.new_topic_requests')
          AND attname = ANY (
            ARRAY['state', 'owner_token', 'lease_expires_at', 'updated_at']
          )
          AND NOT attisdropped
      )
    THEN 'new-topic-exactly-once-v1'::TEXT
    ELSE 'incomplete'::TEXT
  END;
$$;

REVOKE EXECUTE ON FUNCTION public.new_topic_contract_version() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.new_topic_contract_version()
  FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.new_topic_contract_version()
  TO service_role;

NOTIFY pgrst, 'reload schema';
