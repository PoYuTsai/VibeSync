-- Reserve a stream retry as an in-flight lease.
--
-- Previously the RPC incremented retry_count but left status='failed'. A
-- reconnect during that retry could therefore reserve another slot and launch
-- a concurrent model generation for the same already-charged run. Reusing the
-- existing 'charged' state makes reservation atomic and remains compatible
-- with both the current and recovering Edge handlers.

CREATE OR REPLACE FUNCTION public.reserve_stream_analysis_retry(
  p_run_id UUID,
  p_user_id UUID,
  p_conversation_hash TEXT,
  p_max_retries INTEGER DEFAULT 2
)
RETURNS public.analysis_stream_runs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  stream_run public.analysis_stream_runs;
BEGIN
  IF p_run_id IS NULL THEN
    RAISE EXCEPTION 'reserve_stream_analysis_retry: p_run_id is required';
  END IF;

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'reserve_stream_analysis_retry: p_user_id is required';
  END IF;

  IF p_conversation_hash IS NULL OR length(btrim(p_conversation_hash)) = 0 THEN
    RAISE EXCEPTION 'reserve_stream_analysis_retry: p_conversation_hash is required';
  END IF;

  IF p_max_retries IS NULL OR p_max_retries <= 0 THEN
    RAISE EXCEPTION 'reserve_stream_analysis_retry: p_max_retries must be positive';
  END IF;

  UPDATE public.analysis_stream_runs
     SET retry_count = retry_count + 1,
         status = 'charged',
         last_error_code = NULL
   WHERE id = p_run_id
     AND user_id = p_user_id
     AND conversation_hash = p_conversation_hash
     AND status = 'failed'
     AND final_result_json IS NULL
     AND charged_at IS NOT NULL
     AND recommendation_json IS NOT NULL
     AND selected_style IS NOT NULL
     AND expires_at > now()
     AND retry_count < p_max_retries
   RETURNING * INTO stream_run;

  IF stream_run.id IS NULL THEN
    RAISE EXCEPTION 'STREAM_RETRY_NOT_AVAILABLE'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN stream_run;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.reserve_stream_analysis_retry(
  UUID,
  UUID,
  TEXT,
  INTEGER
) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.reserve_stream_analysis_retry(
  UUID,
  UUID,
  TEXT,
  INTEGER
) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_stream_analysis_retry(
  UUID,
  UUID,
  TEXT,
  INTEGER
) TO service_role;

COMMENT ON FUNCTION public.reserve_stream_analysis_retry(UUID, UUID, TEXT, INTEGER)
IS 'Atomically leases one retry for an already-charged failed stream run by moving it back to charged/in-flight; never reserves rows with a durable final result.';

NOTIFY pgrst, 'reload schema';
