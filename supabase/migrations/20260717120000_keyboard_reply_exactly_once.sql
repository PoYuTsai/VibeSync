-- AI keyboard exactly-once contract.
--
-- Claim/lease prevents concurrent requests with the same identity from all
-- calling the model. Settlement stores the validated result and increments
-- quota in one transaction. A lost-response retry replays the stored result.

CREATE TABLE IF NOT EXISTS public.keyboard_reply_requests (
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
      AND jsonb_typeof(result_json) = 'object'
      AND jsonb_typeof(result_json -> 'reply') = 'string'
      AND char_length(result_json ->> 'reply') BETWEEN 1 AND 100
      AND NULLIF(btrim(result_json ->> 'reply'), '') IS NOT NULL
      AND jsonb_typeof(result_json -> 'style') = 'string'
      AND result_json ->> 'style' IN (
        'extend', 'resonate', 'tease', 'humor', 'coldRead'
      )
      -- Exact equality prevents copied input, prompts, usage, or telemetry
      -- from entering this short-lived replay ledger.
      AND result_json = jsonb_build_object(
        'reply', result_json ->> 'reply',
        'style', result_json ->> 'style'
      )
    )
  )
);

CREATE INDEX IF NOT EXISTS keyboard_reply_requests_created_at_idx
  ON public.keyboard_reply_requests (created_at);

ALTER TABLE public.keyboard_reply_requests ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.keyboard_reply_requests FROM PUBLIC;
REVOKE ALL ON TABLE public.keyboard_reply_requests FROM anon, authenticated;
GRANT SELECT ON TABLE public.keyboard_reply_requests TO service_role;

COMMENT ON TABLE public.keyboard_reply_requests IS
  '24-hour idempotent replay ledger for AI keyboard replies. Stores generated reply and style only; never copied source text. input_hash is a server-keyed HMAC.';

CREATE OR REPLACE FUNCTION public.cleanup_expired_keyboard_reply_requests()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deleted INTEGER;
BEGIN
  DELETE FROM public.keyboard_reply_requests
  WHERE created_at < now() - interval '24 hours';
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

REVOKE EXECUTE ON FUNCTION
  public.cleanup_expired_keyboard_reply_requests() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION
  public.cleanup_expired_keyboard_reply_requests() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.cleanup_expired_keyboard_reply_requests() TO service_role;

CREATE EXTENSION IF NOT EXISTS pg_cron;

DO $schedule$
DECLARE
  v_job_id BIGINT;
BEGIN
  FOR v_job_id IN
    SELECT jobid
    FROM cron.job
    WHERE jobname = 'cleanup-expired-keyboard-reply-requests'
  LOOP
    PERFORM cron.unschedule(v_job_id);
  END LOOP;

  PERFORM cron.schedule(
    'cleanup-expired-keyboard-reply-requests',
    '31 * * * *',
    'SELECT public.cleanup_expired_keyboard_reply_requests();'
  );
END;
$schedule$;

CREATE OR REPLACE FUNCTION public.claim_keyboard_reply_request(
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
  v_existing public.keyboard_reply_requests%ROWTYPE;
  v_lease_expires_at TIMESTAMPTZ := now() + interval '45 seconds';
BEGIN
  IF p_user_id IS NULL OR p_request_id IS NULL OR p_owner_token IS NULL THEN
    RAISE EXCEPTION 'claim_keyboard_reply_request: identity is required';
  END IF;
  IF p_input_hash IS NULL OR p_input_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'claim_keyboard_reply_request: invalid p_input_hash';
  END IF;

  -- Only the colliding identity is cleaned on the interactive path. The
  -- hourly cron owns bulk retention so a user request never performs a
  -- cross-user backlog delete inside its billing transaction.
  DELETE FROM public.keyboard_reply_requests
  WHERE user_id = p_user_id
    AND request_id = p_request_id
    AND created_at < now() - interval '24 hours';

  INSERT INTO public.keyboard_reply_requests (
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
  FROM public.keyboard_reply_requests
  WHERE user_id = p_user_id
    AND request_id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'KEYBOARD_REPLY_REQUEST_CLAIM_MISSING';
  END IF;
  IF v_existing.input_hash IS DISTINCT FROM p_input_hash THEN
    RAISE EXCEPTION 'KEYBOARD_REPLY_REQUEST_REPLAY_MISMATCH';
  END IF;
  IF v_existing.state = 'done' THEN
    RETURN jsonb_build_object(
      'kind', 'replay',
      'result', v_existing.result_json
    );
  END IF;
  IF v_existing.owner_token = p_owner_token THEN
    UPDATE public.keyboard_reply_requests
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

  UPDATE public.keyboard_reply_requests
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

REVOKE EXECUTE ON FUNCTION public.claim_keyboard_reply_request(
  UUID, UUID, TEXT, UUID
) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.claim_keyboard_reply_request(
  UUID, UUID, TEXT, UUID
) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_keyboard_reply_request(
  UUID, UUID, TEXT, UUID
) TO service_role;

CREATE OR REPLACE FUNCTION public.release_keyboard_reply_claim(
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
  DELETE FROM public.keyboard_reply_requests
  WHERE user_id = p_user_id
    AND request_id = p_request_id
    AND input_hash = p_input_hash
    AND owner_token = p_owner_token
    AND state = 'pending';
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted = 1;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.release_keyboard_reply_claim(
  UUID, UUID, TEXT, UUID
) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.release_keyboard_reply_claim(
  UUID, UUID, TEXT, UUID
) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.release_keyboard_reply_claim(
  UUID, UUID, TEXT, UUID
) TO service_role;

CREATE OR REPLACE FUNCTION public.settle_keyboard_reply_request(
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
  v_existing public.keyboard_reply_requests%ROWTYPE;
  v_should_charge BOOLEAN := COALESCE(p_charge_quota, TRUE);
BEGIN
  IF p_user_id IS NULL OR p_request_id IS NULL OR p_owner_token IS NULL THEN
    RAISE EXCEPTION 'settle_keyboard_reply_request: identity is required';
  END IF;
  IF p_input_hash IS NULL OR p_input_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'settle_keyboard_reply_request: invalid p_input_hash';
  END IF;
  IF p_result_json IS NULL
     OR jsonb_typeof(p_result_json) <> 'object'
     OR jsonb_typeof(p_result_json -> 'reply') <> 'string'
     OR char_length(p_result_json ->> 'reply') NOT BETWEEN 1 AND 100
     OR NULLIF(btrim(p_result_json ->> 'reply'), '') IS NULL
     OR jsonb_typeof(p_result_json -> 'style') <> 'string'
     OR p_result_json ->> 'style' NOT IN (
       'extend', 'resonate', 'tease', 'humor', 'coldRead'
     )
     OR p_result_json <> jsonb_build_object(
       'reply', p_result_json ->> 'reply',
       'style', p_result_json ->> 'style'
     ) THEN
    RAISE EXCEPTION 'settle_keyboard_reply_request: invalid p_result_json';
  END IF;
  IF v_should_charge
     AND (
       p_monthly_limit IS NULL OR p_monthly_limit <= 0
       OR p_daily_limit IS NULL OR p_daily_limit <= 0
     ) THEN
    RAISE EXCEPTION 'settle_keyboard_reply_request: invalid quota limits';
  END IF;

  SELECT * INTO v_existing
  FROM public.keyboard_reply_requests
  WHERE user_id = p_user_id
    AND request_id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'KEYBOARD_REPLY_REQUEST_SETTLEMENT_MISSING';
  END IF;
  IF v_existing.input_hash IS DISTINCT FROM p_input_hash THEN
    RAISE EXCEPTION 'KEYBOARD_REPLY_REQUEST_REPLAY_MISMATCH';
  END IF;
  IF v_existing.state = 'done' THEN
    RETURN jsonb_build_object(
      'charged', FALSE,
      'result', v_existing.result_json
    );
  END IF;
  IF v_existing.owner_token IS DISTINCT FROM p_owner_token THEN
    RAISE EXCEPTION 'KEYBOARD_REPLY_REQUEST_OWNER_MISMATCH';
  END IF;

  IF v_should_charge THEN
    PERFORM 1
    FROM public.subscriptions
    WHERE user_id = p_user_id
    FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'KEYBOARD_REPLY_SUBSCRIPTION_MISSING';
    END IF;

    PERFORM public.increment_usage(
      p_user_id,
      1,
      p_monthly_limit,
      p_daily_limit
    );
  END IF;

  UPDATE public.keyboard_reply_requests
  SET state = 'done',
      result_json = p_result_json,
      quota_charged = v_should_charge,
      updated_at = now()
  WHERE user_id = p_user_id
    AND request_id = p_request_id;

  RETURN jsonb_build_object(
    'charged', v_should_charge,
    'result', p_result_json
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.settle_keyboard_reply_request(
  UUID, UUID, TEXT, UUID, JSONB, INTEGER, INTEGER, BOOLEAN
) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.settle_keyboard_reply_request(
  UUID, UUID, TEXT, UUID, JSONB, INTEGER, INTEGER, BOOLEAN
) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.settle_keyboard_reply_request(
  UUID, UUID, TEXT, UUID, JSONB, INTEGER, INTEGER, BOOLEAN
) TO service_role;

-- The Edge health endpoint reads this DB-owned capability marker. A new Edge
-- binary cannot self-declare readiness while the claim/settle migration is
-- missing or only partially installed.
CREATE OR REPLACE FUNCTION public.keyboard_reply_contract_version()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN to_regclass('public.keyboard_reply_requests') IS NOT NULL
      AND to_regprocedure(
        'public.claim_keyboard_reply_request(uuid,uuid,text,uuid)'
      ) IS NOT NULL
      AND to_regprocedure(
        'public.release_keyboard_reply_claim(uuid,uuid,text,uuid)'
      ) IS NOT NULL
      AND to_regprocedure(
        'public.settle_keyboard_reply_request(uuid,uuid,text,uuid,jsonb,integer,integer,boolean)'
      ) IS NOT NULL
      AND (
        SELECT count(*) = 4
        FROM pg_attribute
        WHERE attrelid = to_regclass('public.keyboard_reply_requests')
          AND attname = ANY (
            ARRAY['state', 'owner_token', 'lease_expires_at', 'updated_at']
          )
          AND NOT attisdropped
      )
    THEN 'keyboard-reply-exactly-once-v1'::TEXT
    ELSE 'incomplete'::TEXT
  END;
$$;

REVOKE EXECUTE ON FUNCTION public.keyboard_reply_contract_version() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.keyboard_reply_contract_version()
  FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.keyboard_reply_contract_version()
  TO service_role;

NOTIFY pgrst, 'reload schema';
