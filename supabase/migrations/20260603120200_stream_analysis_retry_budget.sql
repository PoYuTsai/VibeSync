-- Add a bounded retry lifecycle for already-charged streaming analyze runs.

ALTER TABLE public.analysis_stream_runs
  ADD COLUMN IF NOT EXISTS retry_count INTEGER NOT NULL DEFAULT 0
  CHECK (retry_count >= 0);

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
         last_error_code = NULL
   WHERE id = p_run_id
     AND user_id = p_user_id
     AND conversation_hash = p_conversation_hash
     AND status = 'failed'
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

NOTIFY pgrst, 'reload schema';
