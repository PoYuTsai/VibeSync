-- Single-screenshot keyboard assist exactly-once ledger.
--
-- The table keeps only a keyed input HMAC and a bounded terminal result for
-- 24-hour lost-response replay. It never stores screenshots, OCR transcripts,
-- prompts, contact names, or raw image digests.

CREATE OR REPLACE FUNCTION public.is_valid_keyboard_assist_result(
  p_result JSONB
)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_distinct_strategies INTEGER;
BEGIN
  IF p_result IS NULL OR jsonb_typeof(p_result) <> 'object' THEN
    RETURN FALSE;
  END IF;

  IF p_result ->> 'status' = 'needs_speaker_confirmation' THEN
    RETURN
      p_result ->> 'contractVersion' = 'keyboard-assist-v1'
      AND p_result ->> 'suggestedMySide' IN ('left', 'right')
      AND p_result ->> 'sideConfidence' = 'low'
      AND p_result = jsonb_build_object(
        'contractVersion', 'keyboard-assist-v1',
        'status', 'needs_speaker_confirmation',
        'suggestedMySide', p_result ->> 'suggestedMySide',
        'sideConfidence', 'low'
      );
  END IF;

  IF p_result ->> 'status' <> 'ready' THEN
    RETURN FALSE;
  END IF;
  IF p_result ->> 'contractVersion' <> 'keyboard-assist-v1' THEN
    RETURN FALSE;
  END IF;
  IF p_result <> jsonb_build_object(
    'contractVersion', 'keyboard-assist-v1',
    'status', 'ready',
    'source', p_result -> 'source',
    'turnState', p_result -> 'turnState',
    'cue', p_result -> 'cue',
    'uncertainty', p_result -> 'uncertainty',
    'options', p_result -> 'options'
  ) THEN
    RETURN FALSE;
  END IF;
  IF jsonb_typeof(p_result -> 'source') <> 'object'
     OR p_result -> 'source' <> jsonb_build_object(
       'scope', p_result #> '{source,scope}',
       'messageCount', p_result #> '{source,messageCount}',
       'confidence', p_result #> '{source,confidence}',
       'sideConfidence', p_result #> '{source,sideConfidence}'
     )
     OR p_result #>> '{source,scope}' NOT IN (
       'screenshot_only', 'screenshot_plus_global_voice'
     )
     OR jsonb_typeof(p_result #> '{source,messageCount}') <> 'number'
     OR (p_result #>> '{source,messageCount}')::NUMERIC <> trunc(
       (p_result #>> '{source,messageCount}')::NUMERIC
     )
     OR (p_result #>> '{source,messageCount}')::INTEGER NOT BETWEEN 1 AND 100
     OR p_result #>> '{source,confidence}' NOT IN ('high', 'medium', 'low')
     OR p_result #>> '{source,sideConfidence}' NOT IN ('high', 'medium', 'low')
     OR p_result ->> 'turnState' NOT IN ('reply_due', 'optional_follow_up')
     OR jsonb_typeof(p_result -> 'cue') <> 'string'
     OR char_length(p_result ->> 'cue') NOT BETWEEN 1 AND 120
     OR btrim(p_result ->> 'cue') <> p_result ->> 'cue'
     OR (
       jsonb_typeof(p_result -> 'uncertainty') NOT IN ('string', 'null')
     )
     OR (
       jsonb_typeof(p_result -> 'uncertainty') = 'string'
       AND (
         char_length(p_result ->> 'uncertainty') NOT BETWEEN 1 AND 120
         OR btrim(p_result ->> 'uncertainty') <> p_result ->> 'uncertainty'
       )
     )
     OR jsonb_typeof(p_result -> 'options') <> 'array'
     OR jsonb_array_length(p_result -> 'options') <> 3 THEN
    RETURN FALSE;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_result -> 'options') AS candidate(option)
    WHERE jsonb_typeof(option) <> 'object'
      OR option <> jsonb_build_object(
        'strategy', option -> 'strategy',
        'text', option -> 'text',
        'why', option -> 'why',
        'effect', option -> 'effect'
      )
      OR option ->> 'strategy' NOT IN (
        'keep_pace',
        'build_connection',
        'move_forward',
        'clarify',
        'deescalate'
      )
      OR jsonb_typeof(option -> 'text') <> 'string'
      OR char_length(option ->> 'text') NOT BETWEEN 1 AND 100
      OR btrim(option ->> 'text') <> option ->> 'text'
      OR jsonb_typeof(option -> 'why') <> 'string'
      OR char_length(option ->> 'why') NOT BETWEEN 1 AND 80
      OR btrim(option ->> 'why') <> option ->> 'why'
      OR jsonb_typeof(option -> 'effect') <> 'string'
      OR char_length(option ->> 'effect') NOT BETWEEN 1 AND 60
      OR btrim(option ->> 'effect') <> option ->> 'effect'
  ) THEN
    RETURN FALSE;
  END IF;

  SELECT COUNT(DISTINCT option ->> 'strategy')
  INTO v_distinct_strategies
  FROM jsonb_array_elements(p_result -> 'options') AS candidate(option);
  IF v_distinct_strategies <> 3 THEN
    RETURN FALSE;
  END IF;

  -- Narrow deterministic privacy/quality backstop. Broader semantic grounding
  -- remains in the Edge pipeline and human evaluation.
  IF p_result::TEXT ~ '```|好感度|心理診斷|依附型態|人格分析|[%％]' THEN
    RETURN FALSE;
  END IF;

  RETURN TRUE;
END;
$$;

REVOKE EXECUTE ON FUNCTION
  public.is_valid_keyboard_assist_result(JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION
  public.is_valid_keyboard_assist_result(JSONB) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.is_valid_keyboard_assist_result(JSONB) TO service_role;

CREATE TABLE IF NOT EXISTS public.keyboard_assist_requests (
  user_id          UUID        NOT NULL
                                REFERENCES auth.users(id) ON DELETE CASCADE,
  request_id       UUID        NOT NULL,
  input_hash       TEXT        NOT NULL
                                CHECK (input_hash ~ '^[0-9a-f]{64}$'),
  hmac_key_version SMALLINT    NOT NULL CHECK (hmac_key_version > 0),
  state            TEXT        NOT NULL DEFAULT 'pending'
                                CHECK (state IN ('pending', 'done')),
  owner_token      UUID        NOT NULL,
  lease_expires_at TIMESTAMPTZ NOT NULL,
  result_json      JSONB,
  quota_charged    BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, request_id),
  CHECK (
    (
      state = 'pending'
      AND result_json IS NULL
      AND quota_charged = FALSE
    )
    OR
    (
      state = 'done'
      AND result_json IS NOT NULL
      AND public.is_valid_keyboard_assist_result(result_json)
      AND (
        result_json ->> 'status' = 'ready'
        OR (
          result_json ->> 'status' = 'needs_speaker_confirmation'
          AND quota_charged = FALSE
        )
      )
    )
  )
);

CREATE INDEX IF NOT EXISTS keyboard_assist_requests_created_at_idx
  ON public.keyboard_assist_requests (created_at);

ALTER TABLE public.keyboard_assist_requests ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.keyboard_assist_requests FROM PUBLIC;
REVOKE ALL ON TABLE public.keyboard_assist_requests FROM anon, authenticated;
GRANT SELECT ON TABLE public.keyboard_assist_requests TO service_role;

COMMENT ON TABLE public.keyboard_assist_requests IS
  '24-hour private replay ledger for single-screenshot keyboard assist. Stores only a keyed input HMAC, key version, and bounded terminal result.';

CREATE OR REPLACE FUNCTION public.cleanup_expired_keyboard_assist_requests()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deleted INTEGER;
BEGIN
  DELETE FROM public.keyboard_assist_requests
  WHERE created_at < now() - interval '24 hours';
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

REVOKE EXECUTE ON FUNCTION
  public.cleanup_expired_keyboard_assist_requests() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION
  public.cleanup_expired_keyboard_assist_requests() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.cleanup_expired_keyboard_assist_requests() TO service_role;

CREATE EXTENSION IF NOT EXISTS pg_cron;

DO $schedule$
DECLARE
  v_job_id BIGINT;
BEGIN
  FOR v_job_id IN
    SELECT jobid
    FROM cron.job
    WHERE jobname = 'cleanup-expired-keyboard-assist-requests'
  LOOP
    PERFORM cron.unschedule(v_job_id);
  END LOOP;

  PERFORM cron.schedule(
    'cleanup-expired-keyboard-assist-requests',
    '37 * * * *',
    'SELECT public.cleanup_expired_keyboard_assist_requests();'
  );
END;
$schedule$;

CREATE OR REPLACE FUNCTION public.claim_keyboard_assist_request(
  p_user_id UUID,
  p_request_id UUID,
  p_input_hash TEXT,
  p_hmac_key_version SMALLINT,
  p_owner_token UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inserted INTEGER;
  v_existing public.keyboard_assist_requests%ROWTYPE;
  v_lease_expires_at TIMESTAMPTZ := now() + interval '55 seconds';
BEGIN
  IF p_user_id IS NULL OR p_request_id IS NULL OR p_owner_token IS NULL THEN
    RAISE EXCEPTION 'claim_keyboard_assist_request: identity is required';
  END IF;
  IF p_input_hash IS NULL OR p_input_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'claim_keyboard_assist_request: invalid p_input_hash';
  END IF;
  IF p_hmac_key_version IS NULL OR p_hmac_key_version <= 0 THEN
    RAISE EXCEPTION 'claim_keyboard_assist_request: invalid HMAC key version';
  END IF;

  DELETE FROM public.keyboard_assist_requests
  WHERE user_id = p_user_id
    AND request_id = p_request_id
    AND created_at < now() - interval '24 hours';

  INSERT INTO public.keyboard_assist_requests (
    user_id,
    request_id,
    input_hash,
    hmac_key_version,
    state,
    owner_token,
    lease_expires_at
  ) VALUES (
    p_user_id,
    p_request_id,
    p_input_hash,
    p_hmac_key_version,
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
  FROM public.keyboard_assist_requests
  WHERE user_id = p_user_id
    AND request_id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'KEYBOARD_ASSIST_CLAIM_MISSING';
  END IF;
  IF v_existing.input_hash IS DISTINCT FROM p_input_hash
     OR v_existing.hmac_key_version IS DISTINCT FROM p_hmac_key_version THEN
    RAISE EXCEPTION 'KEYBOARD_ASSIST_REPLAY_MISMATCH';
  END IF;
  IF v_existing.state = 'done' THEN
    RETURN jsonb_build_object(
      'kind', 'replay',
      'result', v_existing.result_json
    );
  END IF;
  IF v_existing.owner_token = p_owner_token THEN
    UPDATE public.keyboard_assist_requests
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
        CEIL(EXTRACT(EPOCH FROM (
          v_existing.lease_expires_at - now()
        )) * 1000)::INTEGER
      )
    );
  END IF;

  UPDATE public.keyboard_assist_requests
  SET owner_token = p_owner_token,
      lease_expires_at = v_lease_expires_at,
      updated_at = now()
  WHERE user_id = p_user_id
    AND request_id = p_request_id
    AND state = 'pending';

  RETURN jsonb_build_object(
    'kind', 'claimed',
    'leaseExpiresAt', v_lease_expires_at
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.claim_keyboard_assist_request(
  UUID, UUID, TEXT, SMALLINT, UUID
) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.claim_keyboard_assist_request(
  UUID, UUID, TEXT, SMALLINT, UUID
) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_keyboard_assist_request(
  UUID, UUID, TEXT, SMALLINT, UUID
) TO service_role;

CREATE OR REPLACE FUNCTION public.renew_keyboard_assist_claim(
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
  v_updated INTEGER;
BEGIN
  UPDATE public.keyboard_assist_requests
  SET lease_expires_at = now() + interval '55 seconds',
      updated_at = now()
  WHERE user_id = p_user_id
    AND request_id = p_request_id
    AND input_hash = p_input_hash
    AND owner_token = p_owner_token
    AND state = 'pending';
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated = 1;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.renew_keyboard_assist_claim(
  UUID, UUID, TEXT, UUID
) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.renew_keyboard_assist_claim(
  UUID, UUID, TEXT, UUID
) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.renew_keyboard_assist_claim(
  UUID, UUID, TEXT, UUID
) TO service_role;

CREATE OR REPLACE FUNCTION public.release_keyboard_assist_claim(
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
  DELETE FROM public.keyboard_assist_requests
  WHERE user_id = p_user_id
    AND request_id = p_request_id
    AND input_hash = p_input_hash
    AND owner_token = p_owner_token
    AND state = 'pending';
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted = 1;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.release_keyboard_assist_claim(
  UUID, UUID, TEXT, UUID
) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.release_keyboard_assist_claim(
  UUID, UUID, TEXT, UUID
) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.release_keyboard_assist_claim(
  UUID, UUID, TEXT, UUID
) TO service_role;

CREATE OR REPLACE FUNCTION public.settle_keyboard_assist_request(
  p_user_id UUID,
  p_request_id UUID,
  p_input_hash TEXT,
  p_owner_token UUID,
  p_result_json JSONB,
  p_monthly_limit INTEGER,
  p_daily_limit INTEGER,
  p_charge_quota BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing public.keyboard_assist_requests%ROWTYPE;
  v_should_charge BOOLEAN := COALESCE(p_charge_quota, TRUE);
BEGIN
  IF NOT public.is_valid_keyboard_assist_result(p_result_json) THEN
    RAISE EXCEPTION 'settle_keyboard_assist_request: invalid p_result_json';
  END IF;
  IF p_result_json ->> 'status' = 'needs_speaker_confirmation'
     AND v_should_charge THEN
    RAISE EXCEPTION 'settle_keyboard_assist_request: confirmation cannot charge';
  END IF;
  IF v_should_charge AND (
    p_monthly_limit IS NULL OR p_monthly_limit <= 0
    OR p_daily_limit IS NULL OR p_daily_limit <= 0
  ) THEN
    RAISE EXCEPTION 'settle_keyboard_assist_request: invalid quota limits';
  END IF;

  SELECT * INTO v_existing
  FROM public.keyboard_assist_requests
  WHERE user_id = p_user_id
    AND request_id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'KEYBOARD_ASSIST_SETTLEMENT_MISSING';
  END IF;
  IF v_existing.input_hash IS DISTINCT FROM p_input_hash THEN
    RAISE EXCEPTION 'KEYBOARD_ASSIST_REPLAY_MISMATCH';
  END IF;
  IF v_existing.state = 'done' THEN
    RETURN jsonb_build_object(
      'charged', FALSE,
      'result', v_existing.result_json
    );
  END IF;
  IF v_existing.owner_token IS DISTINCT FROM p_owner_token THEN
    RAISE EXCEPTION 'KEYBOARD_ASSIST_OWNER_MISMATCH';
  END IF;

  IF v_should_charge THEN
    PERFORM 1
    FROM public.subscriptions
    WHERE user_id = p_user_id
    FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'KEYBOARD_ASSIST_SUBSCRIPTION_MISSING';
    END IF;

    PERFORM public.increment_usage(
      p_user_id,
      1,
      p_monthly_limit,
      p_daily_limit
    );
  END IF;

  UPDATE public.keyboard_assist_requests
  SET state = 'done',
      result_json = p_result_json,
      quota_charged = v_should_charge,
      updated_at = now()
  WHERE user_id = p_user_id
    AND request_id = p_request_id
    AND input_hash = p_input_hash
    AND owner_token = p_owner_token
    AND state = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'KEYBOARD_ASSIST_OWNER_MISMATCH';
  END IF;

  RETURN jsonb_build_object(
    'charged', v_should_charge,
    'result', p_result_json
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.settle_keyboard_assist_request(
  UUID, UUID, TEXT, UUID, JSONB, INTEGER, INTEGER, BOOLEAN
) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.settle_keyboard_assist_request(
  UUID, UUID, TEXT, UUID, JSONB, INTEGER, INTEGER, BOOLEAN
) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.settle_keyboard_assist_request(
  UUID, UUID, TEXT, UUID, JSONB, INTEGER, INTEGER, BOOLEAN
) TO service_role;

-- GET status uses this only after an authenticated owner-scoped lookup found a
-- pending row whose lease has expired. The condition prevents a status race
-- from deleting a renewed or completed request.
CREATE OR REPLACE FUNCTION public.expire_keyboard_assist_request(
  p_user_id UUID,
  p_request_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deleted INTEGER;
BEGIN
  DELETE FROM public.keyboard_assist_requests
  WHERE user_id = p_user_id
    AND request_id = p_request_id
    AND state = 'pending'
    AND lease_expires_at <= now();
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted = 1;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.expire_keyboard_assist_request(
  UUID, UUID
) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.expire_keyboard_assist_request(
  UUID, UUID
) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expire_keyboard_assist_request(
  UUID, UUID
) TO service_role;

-- Hourly cleanup can leave a row just under 25 hours old even though replay
-- eligibility is 24 hours. Edge health therefore requires every key version
-- referenced across the full possible physical row lifetime.
CREATE OR REPLACE FUNCTION public.keyboard_assist_hmac_key_versions()
RETURNS SMALLINT[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    array_agg(DISTINCT hmac_key_version ORDER BY hmac_key_version),
    ARRAY[]::SMALLINT[]
  )
  FROM public.keyboard_assist_requests
  WHERE created_at >= now() - interval '25 hours';
$$;

REVOKE EXECUTE ON FUNCTION
  public.keyboard_assist_hmac_key_versions() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION
  public.keyboard_assist_hmac_key_versions() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.keyboard_assist_hmac_key_versions() TO service_role;

CREATE OR REPLACE FUNCTION public.keyboard_assist_contract_version()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN to_regclass('public.keyboard_assist_requests') IS NOT NULL
      AND to_regprocedure(
        'public.claim_keyboard_assist_request(uuid,uuid,text,smallint,uuid)'
      ) IS NOT NULL
      AND to_regprocedure(
        'public.renew_keyboard_assist_claim(uuid,uuid,text,uuid)'
      ) IS NOT NULL
      AND to_regprocedure(
        'public.release_keyboard_assist_claim(uuid,uuid,text,uuid)'
      ) IS NOT NULL
      AND to_regprocedure(
        'public.settle_keyboard_assist_request(uuid,uuid,text,uuid,jsonb,integer,integer,boolean)'
      ) IS NOT NULL
      AND to_regprocedure(
        'public.expire_keyboard_assist_request(uuid,uuid)'
      ) IS NOT NULL
      AND to_regprocedure(
        'public.keyboard_assist_hmac_key_versions()'
      ) IS NOT NULL
    THEN 'keyboard-assist-v1'::TEXT
    ELSE 'incomplete'::TEXT
  END;
$$;

REVOKE EXECUTE ON FUNCTION public.keyboard_assist_contract_version()
  FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.keyboard_assist_contract_version()
  FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.keyboard_assist_contract_version()
  TO service_role;

NOTIFY pgrst, 'reload schema';
