-- Atomic charge-before-emit for full streaming analyze.
-- charged_at, recommendation_json, selected_style, and increment_usage must
-- succeed or fail together so a charged run is always resumable.

CREATE OR REPLACE FUNCTION public.charge_stream_analysis_run(
  p_run_id UUID,
  p_user_id UUID,
  p_conversation_hash TEXT,
  p_recommendation_json JSONB,
  p_selected_style TEXT,
  p_message_count INTEGER DEFAULT 1,
  p_charge_quota BOOLEAN DEFAULT TRUE
)
RETURNS public.analysis_stream_runs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  stream_run public.analysis_stream_runs;
  should_charge BOOLEAN := COALESCE(p_charge_quota, TRUE);
BEGIN
  IF p_run_id IS NULL THEN
    RAISE EXCEPTION 'charge_stream_analysis_run: p_run_id is required';
  END IF;

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'charge_stream_analysis_run: p_user_id is required';
  END IF;

  IF p_conversation_hash IS NULL OR length(btrim(p_conversation_hash)) = 0 THEN
    RAISE EXCEPTION 'charge_stream_analysis_run: p_conversation_hash is required';
  END IF;

  IF p_recommendation_json IS NULL
     OR p_recommendation_json = 'null'::jsonb
     OR jsonb_typeof(p_recommendation_json) <> 'object' THEN
    RAISE EXCEPTION 'STREAM_MALFORMED_RECOMMENDATION';
  END IF;

  IF p_selected_style IS NULL
     OR p_selected_style NOT IN ('extend', 'resonate', 'tease', 'humor', 'coldRead') THEN
    RAISE EXCEPTION 'STREAM_INVALID_SELECTED_STYLE';
  END IF;

  IF should_charge AND (p_message_count IS NULL OR p_message_count <= 0) THEN
    RAISE EXCEPTION 'charge_stream_analysis_run: p_message_count must be positive when charging';
  END IF;

  SELECT *
    INTO stream_run
    FROM public.analysis_stream_runs
   WHERE id = p_run_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'STREAM_RUN_NOT_FOUND';
  END IF;

  IF stream_run.user_id <> p_user_id THEN
    RAISE EXCEPTION 'STREAM_RUN_OWNER_MISMATCH';
  END IF;

  IF stream_run.conversation_hash <> p_conversation_hash THEN
    RAISE EXCEPTION 'RUN_CONVERSATION_MISMATCH';
  END IF;

  IF stream_run.charged_at IS NOT NULL THEN
    RETURN stream_run;
  END IF;

  IF stream_run.status <> 'pending' THEN
    RAISE EXCEPTION 'STREAM_RUN_NOT_PENDING';
  END IF;

  IF stream_run.expires_at <= now() THEN
    RAISE EXCEPTION 'STREAM_RUN_EXPIRED';
  END IF;

  IF should_charge THEN
    PERFORM public.increment_usage(p_user_id, p_message_count);
  END IF;

  UPDATE public.analysis_stream_runs
     SET status = 'charged',
         charged_at = now(),
         recommendation_json = p_recommendation_json,
         selected_style = p_selected_style,
         last_error_code = NULL
   WHERE id = p_run_id
  RETURNING * INTO stream_run;

  RETURN stream_run;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.charge_stream_analysis_run(
  UUID, UUID, TEXT, JSONB, TEXT, INTEGER, BOOLEAN
) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.charge_stream_analysis_run(
  UUID, UUID, TEXT, JSONB, TEXT, INTEGER, BOOLEAN
) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.charge_stream_analysis_run(
  UUID, UUID, TEXT, JSONB, TEXT, INTEGER, BOOLEAN
) TO service_role;

NOTIFY pgrst, 'reload schema';
