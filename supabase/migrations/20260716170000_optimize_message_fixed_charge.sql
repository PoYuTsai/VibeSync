-- Essential 「我幫你修」：成功固定扣 1 則，且同一 request id 只能扣一次。
--
-- The first successful, validated result and quota increment commit in one
-- transaction. AI / parse / validation failures never call this RPC. A retry
-- with the same (user, request_id, input_hash) receives the stored result and
-- does not increment quota again.

-- Historical schema allowed NULL counters. NULL + 1 remains NULL and would
-- let a settlement commit its ledger without consuming the promised credit.
-- Backfill first, then make every existing and future quota path numeric.
UPDATE public.subscriptions
SET monthly_messages_used = COALESCE(monthly_messages_used, 0),
    daily_messages_used = COALESCE(daily_messages_used, 0)
WHERE monthly_messages_used IS NULL
   OR daily_messages_used IS NULL;

ALTER TABLE public.subscriptions
  ALTER COLUMN monthly_messages_used SET DEFAULT 0,
  ALTER COLUMN monthly_messages_used SET NOT NULL,
  ALTER COLUMN daily_messages_used SET DEFAULT 0,
  ALTER COLUMN daily_messages_used SET NOT NULL;

CREATE TABLE IF NOT EXISTS public.optimize_message_requests (
  user_id        UUID        NOT NULL
                              REFERENCES auth.users(id) ON DELETE CASCADE,
  request_id     UUID        NOT NULL,
  input_hash     TEXT        NOT NULL
                              CHECK (input_hash ~ '^[0-9a-f]{64}$'),
  result_json    JSONB       NOT NULL
                              CHECK (
                                jsonb_typeof(result_json) = 'object'
                                AND jsonb_typeof(
                                  result_json -> 'optimizedMessage'
                                ) = 'object'
                                AND jsonb_typeof(
                                  result_json #> '{optimizedMessage,optimized}'
                                ) = 'string'
                                AND NULLIF(
                                  btrim(
                                    result_json #>> '{optimizedMessage,optimized}'
                                  ),
                                  ''
                                ) IS NOT NULL
                                AND jsonb_typeof(
                                  result_json #> '{optimizedMessage,reason}'
                                ) = 'string'
                                -- Exact equality forbids separate raw-input,
                                -- context, usage, telemetry, or future fields.
                                -- Generated strings may still reflect input.
                                AND result_json = jsonb_build_object(
                                  'optimizedMessage',
                                  jsonb_build_object(
                                    'optimized',
                                    result_json #>> '{optimizedMessage,optimized}',
                                    'reason',
                                    result_json #>> '{optimizedMessage,reason}'
                                  )
                                )
                              ),
  quota_charged  BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, request_id)
);

CREATE INDEX IF NOT EXISTS optimize_message_requests_created_at_idx
  ON public.optimize_message_requests (created_at);

ALTER TABLE public.optimize_message_requests ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.optimize_message_requests FROM PUBLIC;
REVOKE ALL ON TABLE public.optimize_message_requests FROM anon, authenticated;
-- Edge only needs the replay preflight read. All writes stay behind the
-- SECURITY DEFINER settlement RPC so a caller cannot forge a charged ledger.
GRANT SELECT ON TABLE public.optimize_message_requests TO service_role;

COMMENT ON TABLE public.optimize_message_requests IS
  'Idempotent result ledger for Essential optimize_message. Stores only generated optimized text and reason, without separate raw-input fields; generated text may reflect input. Replay expires after 7 days; hourly cleanup bounds live-table retention.';

CREATE OR REPLACE FUNCTION public.cleanup_expired_optimize_message_requests()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deleted INTEGER;
BEGIN
  DELETE FROM public.optimize_message_requests
  WHERE created_at < now() - interval '7 days';
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

REVOKE EXECUTE ON FUNCTION
  public.cleanup_expired_optimize_message_requests() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION
  public.cleanup_expired_optimize_message_requests() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.cleanup_expired_optimize_message_requests() TO service_role;

-- A response-replay row contains generated user content, so lazy cleanup is
-- not sufficient. Fail the migration if pg_cron cannot be installed rather
-- than silently shipping an unbounded retention promise. Hourly cleanup gives
-- a live-table retention bound of roughly 7 days + 1 hour. Provider backups
-- and PITR/WAL follow their separate managed-service lifecycle.
CREATE EXTENSION IF NOT EXISTS pg_cron;

DO $schedule$
DECLARE
  v_job_id BIGINT;
BEGIN
  FOR v_job_id IN
    SELECT jobid
    FROM cron.job
    WHERE jobname = 'cleanup-expired-optimize-message-requests'
  LOOP
    PERFORM cron.unschedule(v_job_id);
  END LOOP;

  PERFORM cron.schedule(
    'cleanup-expired-optimize-message-requests',
    '17 * * * *',
    'SELECT public.cleanup_expired_optimize_message_requests();'
  );
END;
$schedule$;

CREATE OR REPLACE FUNCTION public.settle_optimize_message_request(
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
  v_existing public.optimize_message_requests%ROWTYPE;
  v_should_charge BOOLEAN := COALESCE(p_charge_quota, TRUE);
  v_monthly_used INTEGER;
  v_daily_used INTEGER;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'settle_optimize_message_request: p_user_id is required';
  END IF;
  IF p_request_id IS NULL THEN
    RAISE EXCEPTION 'settle_optimize_message_request: p_request_id is required';
  END IF;
  IF p_input_hash IS NULL OR p_input_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'settle_optimize_message_request: invalid p_input_hash';
  END IF;
  IF p_result_json IS NULL
     OR p_result_json = 'null'::jsonb
     OR jsonb_typeof(p_result_json) <> 'object'
     OR jsonb_typeof(p_result_json -> 'optimizedMessage') <> 'object'
     OR jsonb_typeof(
       p_result_json #> '{optimizedMessage,optimized}'
     ) <> 'string'
     OR NULLIF(
       btrim(p_result_json #>> '{optimizedMessage,optimized}'),
       ''
     ) IS NULL
     OR jsonb_typeof(
       p_result_json #> '{optimizedMessage,reason}'
     ) <> 'string'
     OR p_result_json <> jsonb_build_object(
       'optimizedMessage',
       jsonb_build_object(
         'optimized',
         p_result_json #>> '{optimizedMessage,optimized}',
         'reason',
         p_result_json #>> '{optimizedMessage,reason}'
       )
     ) THEN
    RAISE EXCEPTION 'settle_optimize_message_request: invalid p_result_json';
  END IF;
  IF v_should_charge
     AND (
       p_monthly_limit IS NULL OR p_monthly_limit <= 0
       OR p_daily_limit IS NULL OR p_daily_limit <= 0
     ) THEN
    RAISE EXCEPTION 'settle_optimize_message_request: invalid quota limits';
  END IF;

  -- Functional replay expires at the Edge query boundary. Any settlement also
  -- globally purges physically retained expired rows, so cleanup is no longer
  -- dependent on the original user returning.
  DELETE FROM public.optimize_message_requests
  WHERE created_at < now() - interval '7 days';

  INSERT INTO public.optimize_message_requests (
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
    FROM public.optimize_message_requests
    WHERE user_id = p_user_id
      AND request_id = p_request_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'OPTIMIZE_MESSAGE_REQUEST_REPLAY_MISSING';
    END IF;
    IF v_existing.input_hash IS DISTINCT FROM p_input_hash THEN
      RAISE EXCEPTION 'OPTIMIZE_MESSAGE_REQUEST_REPLAY_MISMATCH';
    END IF;

    SELECT monthly_messages_used, daily_messages_used
      INTO v_monthly_used, v_daily_used
    FROM public.subscriptions
    WHERE user_id = p_user_id
    FOR SHARE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'OPTIMIZE_MESSAGE_SUBSCRIPTION_MISSING';
    END IF;

    RETURN jsonb_build_object(
      'charged', FALSE,
      'result', v_existing.result_json,
      'monthlyUsed', v_monthly_used,
      'dailyUsed', v_daily_used
    );
  END IF;

  IF v_should_charge THEN
    -- increment_usage deliberately preserves a legacy silent-no-op when a
    -- subscription row is missing. This wrapper is stricter: a paid optimize
    -- success must either lock a real row and add exactly one, or roll back.
    PERFORM 1
    FROM public.subscriptions
    WHERE user_id = p_user_id
    FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'OPTIMIZE_MESSAGE_SUBSCRIPTION_MISSING';
    END IF;

    -- Fixed policy: context size does not affect this value. The surrounding
    -- transaction rolls the ledger insert back if increment_usage raises.
    PERFORM public.increment_usage(
      p_user_id,
      1,
      p_monthly_limit,
      p_daily_limit
    );
  END IF;

  SELECT monthly_messages_used, daily_messages_used
    INTO v_monthly_used, v_daily_used
  FROM public.subscriptions
  WHERE user_id = p_user_id
  FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'OPTIMIZE_MESSAGE_SUBSCRIPTION_MISSING';
  END IF;

  RETURN jsonb_build_object(
    'charged', v_should_charge,
    'result', p_result_json,
    'monthlyUsed', v_monthly_used,
    'dailyUsed', v_daily_used
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.settle_optimize_message_request(
  UUID, UUID, TEXT, JSONB, INTEGER, INTEGER, BOOLEAN
) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.settle_optimize_message_request(
  UUID, UUID, TEXT, JSONB, INTEGER, INTEGER, BOOLEAN
) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.settle_optimize_message_request(
  UUID, UUID, TEXT, JSONB, INTEGER, INTEGER, BOOLEAN
) TO service_role;

NOTIFY pgrst, 'reload schema';
