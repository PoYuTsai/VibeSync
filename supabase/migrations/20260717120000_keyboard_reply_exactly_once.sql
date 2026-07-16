-- AI keyboard: persist the first validated reply and quota increment in one
-- transaction. A retry with the same request id and normalized-input hash
-- receives the stored reply without another model call or quota charge.

CREATE TABLE IF NOT EXISTS public.keyboard_reply_requests (
  user_id        UUID        NOT NULL
                              REFERENCES auth.users(id) ON DELETE CASCADE,
  request_id     UUID        NOT NULL,
  input_hash     TEXT        NOT NULL
                              CHECK (input_hash ~ '^[0-9a-f]{64}$'),
  result_json    JSONB       NOT NULL
                              CHECK (
                                jsonb_typeof(result_json) = 'object'
                                AND jsonb_typeof(result_json -> 'reply') = 'string'
                                AND char_length(result_json ->> 'reply') BETWEEN 1 AND 100
                                AND NULLIF(btrim(result_json ->> 'reply'), '') IS NOT NULL
                                AND jsonb_typeof(result_json -> 'style') = 'string'
                                AND result_json ->> 'style' IN (
                                  'extend', 'resonate', 'tease', 'humor', 'coldRead'
                                )
                                -- Exact equality prevents copied input,
                                -- prompts, usage, or telemetry from entering
                                -- this short-lived replay ledger.
                                AND result_json = jsonb_build_object(
                                  'reply', result_json ->> 'reply',
                                  'style', result_json ->> 'style'
                                )
                              ),
  quota_charged  BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, request_id)
);

CREATE INDEX IF NOT EXISTS keyboard_reply_requests_created_at_idx
  ON public.keyboard_reply_requests (created_at);

ALTER TABLE public.keyboard_reply_requests ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.keyboard_reply_requests FROM PUBLIC;
REVOKE ALL ON TABLE public.keyboard_reply_requests FROM anon, authenticated;
GRANT SELECT ON TABLE public.keyboard_reply_requests TO service_role;

COMMENT ON TABLE public.keyboard_reply_requests IS
  '24-hour idempotent replay ledger for AI keyboard replies. Stores generated reply and style only; never copied source text.';

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

-- pg_cron is already required by the optimize-message result ledger. Keep a
-- dedicated job so keyboard privacy retention does not depend on user traffic.
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

CREATE OR REPLACE FUNCTION public.settle_keyboard_reply_request(
  p_user_id UUID,
  p_request_id UUID,
  p_input_hash TEXT,
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
  v_inserted INTEGER;
  v_existing public.keyboard_reply_requests%ROWTYPE;
  v_should_charge BOOLEAN := COALESCE(p_charge_quota, TRUE);
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'settle_keyboard_reply_request: p_user_id is required';
  END IF;
  IF p_request_id IS NULL THEN
    RAISE EXCEPTION 'settle_keyboard_reply_request: p_request_id is required';
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

  DELETE FROM public.keyboard_reply_requests
  WHERE created_at < now() - interval '24 hours';

  INSERT INTO public.keyboard_reply_requests (
    user_id,
    request_id,
    input_hash,
    result_json,
    quota_charged
  ) VALUES (
    p_user_id,
    p_request_id,
    p_input_hash,
    p_result_json,
    v_should_charge
  )
  ON CONFLICT (user_id, request_id) DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  IF v_inserted = 0 THEN
    SELECT * INTO v_existing
    FROM public.keyboard_reply_requests
    WHERE user_id = p_user_id
      AND request_id = p_request_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'KEYBOARD_REPLY_REQUEST_REPLAY_MISSING';
    END IF;
    IF v_existing.input_hash IS DISTINCT FROM p_input_hash THEN
      RAISE EXCEPTION 'KEYBOARD_REPLY_REQUEST_REPLAY_MISMATCH';
    END IF;

    RETURN jsonb_build_object(
      'charged', FALSE,
      'result', v_existing.result_json
    );
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

  RETURN jsonb_build_object(
    'charged', v_should_charge,
    'result', p_result_json
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.settle_keyboard_reply_request(
  UUID, UUID, TEXT, JSONB, INTEGER, INTEGER, BOOLEAN
) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.settle_keyboard_reply_request(
  UUID, UUID, TEXT, JSONB, INTEGER, INTEGER, BOOLEAN
) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.settle_keyboard_reply_request(
  UUID, UUID, TEXT, JSONB, INTEGER, INTEGER, BOOLEAN
) TO service_role;

NOTIFY pgrst, 'reload schema';
