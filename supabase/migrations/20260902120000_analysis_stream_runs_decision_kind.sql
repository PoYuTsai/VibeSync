-- Analyze Phase 1a: let a charged stream run carry a no-send decision.
--
-- Today a charged run must hold one of the five reply styles, so the three
-- no-send decisions (do_not_send / acknowledge_and_stop / need_context) are
-- illegal rows: the charged CHECK, charge_stream_analysis_run and the retry
-- lease all require selected_style. This migration is additive and backward
-- compatible: existing rows keep decision_kind NULL (treated as send), the v1
-- RPC is untouched so in-flight v1 Edge code keeps working, and Edge v2 code
-- must not ship to main before this migration is verified on production.

ALTER TABLE public.analysis_stream_runs
  ADD COLUMN IF NOT EXISTS decision_kind TEXT;

ALTER TABLE public.analysis_stream_runs
  DROP CONSTRAINT IF EXISTS analysis_stream_runs_decision_kind_check;
ALTER TABLE public.analysis_stream_runs
  ADD CONSTRAINT analysis_stream_runs_decision_kind_check
  CHECK (
    decision_kind IS NULL
    OR decision_kind IN ('send', 'do_not_send', 'acknowledge_and_stop', 'need_context')
  );

-- A no-send run never carries a reply style; otherwise a v1 resume path could
-- mistake it for a send run.
ALTER TABLE public.analysis_stream_runs
  DROP CONSTRAINT IF EXISTS analysis_stream_runs_no_send_has_no_style;
ALTER TABLE public.analysis_stream_runs
  ADD CONSTRAINT analysis_stream_runs_no_send_has_no_style
  CHECK (
    COALESCE(
      decision_kind NOT IN ('do_not_send', 'acknowledge_and_stop', 'need_context'),
      TRUE
    )
    OR selected_style IS NULL
  );

-- charged_at non-null => recommendation object AND (style OR no-send kind).
-- Existing rows (decision_kind NULL, selected_style NOT NULL) satisfy this
-- unchanged, so no backfill is needed.
ALTER TABLE public.analysis_stream_runs
  DROP CONSTRAINT IF EXISTS analysis_stream_runs_charged_has_recommendation;
ALTER TABLE public.analysis_stream_runs
  ADD CONSTRAINT analysis_stream_runs_charged_has_recommendation
  CHECK (
    charged_at IS NULL
    OR (
      recommendation_json IS NOT NULL
      AND jsonb_typeof(recommendation_json) = 'object'
      AND (
        selected_style IS NOT NULL
        -- NULL decision_kind must read as FALSE here, or a charged row with
        -- neither style nor kind would pass the CHECK through SQL NULL logic.
        OR COALESCE(
          decision_kind IN ('do_not_send', 'acknowledge_and_stop', 'need_context'),
          FALSE
        )
      )
    )
  );

COMMENT ON COLUMN public.analysis_stream_runs.decision_kind IS
  'Analyze V2 messageDecision persisted at charge time. NULL means a legacy v1 send run. no-send kinds have selected_style NULL and recommendation_json {decisionKind, action, reason, stopCondition}.';

COMMENT ON TABLE public.analysis_stream_runs IS
  'Streaming analyze runs. charged_at non-null means the recommendation was accepted into the charged lifecycle; recommendation_json plus either selected_style (send) or a no-send decision_kind must be durable for resume.';

-- v2 charge RPC. The v1 charge_stream_analysis_run is intentionally left as is.
CREATE OR REPLACE FUNCTION public.charge_stream_analysis_run_v2(
  p_run_id UUID,
  p_user_id UUID,
  p_conversation_hash TEXT,
  p_recommendation_json JSONB,
  p_decision_kind TEXT,
  p_selected_style TEXT DEFAULT NULL,
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
  is_no_send BOOLEAN;
BEGIN
  IF p_run_id IS NULL THEN
    RAISE EXCEPTION 'charge_stream_analysis_run_v2: p_run_id is required';
  END IF;

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'charge_stream_analysis_run_v2: p_user_id is required';
  END IF;

  IF p_conversation_hash IS NULL OR length(btrim(p_conversation_hash)) = 0 THEN
    RAISE EXCEPTION 'charge_stream_analysis_run_v2: p_conversation_hash is required';
  END IF;

  IF p_recommendation_json IS NULL
     OR p_recommendation_json = 'null'::jsonb
     OR jsonb_typeof(p_recommendation_json) <> 'object' THEN
    RAISE EXCEPTION 'STREAM_MALFORMED_RECOMMENDATION';
  END IF;

  IF p_decision_kind IS NULL
     OR p_decision_kind NOT IN ('send', 'do_not_send', 'acknowledge_and_stop', 'need_context') THEN
    RAISE EXCEPTION 'STREAM_INVALID_DECISION_KIND';
  END IF;

  is_no_send := p_decision_kind <> 'send';

  IF is_no_send THEN
    -- No-send charges on the decision itself, so the decision must not be an
    -- empty shell: the resume/retry path replays exactly these fields.
    IF p_selected_style IS NOT NULL THEN
      RAISE EXCEPTION 'STREAM_INVALID_SELECTED_STYLE';
    END IF;
    IF p_recommendation_json->>'decisionKind' IS DISTINCT FROM p_decision_kind
       OR COALESCE(length(btrim(p_recommendation_json->>'action')), 0) = 0
       OR COALESCE(length(btrim(p_recommendation_json->>'reason')), 0) = 0
       OR COALESCE(length(btrim(p_recommendation_json->>'stopCondition')), 0) = 0 THEN
      RAISE EXCEPTION 'STREAM_MALFORMED_RECOMMENDATION';
    END IF;
  ELSE
    IF p_selected_style IS NULL
       OR p_selected_style NOT IN ('extend', 'resonate', 'tease', 'humor', 'coldRead') THEN
      RAISE EXCEPTION 'STREAM_INVALID_SELECTED_STYLE';
    END IF;
    IF p_recommendation_json ? 'decisionKind'
       AND p_recommendation_json->>'decisionKind' <> 'send' THEN
      RAISE EXCEPTION 'STREAM_MALFORMED_RECOMMENDATION';
    END IF;
  END IF;

  IF should_charge AND (p_message_count IS NULL OR p_message_count <= 0) THEN
    RAISE EXCEPTION 'charge_stream_analysis_run_v2: p_message_count must be positive when charging';
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

  -- Exactly-once: a charged run replays its durable state, whatever the caller
  -- sends the second time.
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
         decision_kind = p_decision_kind,
         last_error_code = NULL
   WHERE id = p_run_id
  RETURNING * INTO stream_run;

  RETURN stream_run;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.charge_stream_analysis_run_v2(
  UUID, UUID, TEXT, JSONB, TEXT, TEXT, INTEGER, BOOLEAN
) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.charge_stream_analysis_run_v2(
  UUID, UUID, TEXT, JSONB, TEXT, TEXT, INTEGER, BOOLEAN
) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.charge_stream_analysis_run_v2(
  UUID, UUID, TEXT, JSONB, TEXT, TEXT, INTEGER, BOOLEAN
) TO service_role;

COMMENT ON FUNCTION public.charge_stream_analysis_run_v2(
  UUID, UUID, TEXT, JSONB, TEXT, TEXT, INTEGER, BOOLEAN
) IS 'Atomic charge-before-emit for Analyze V2. send requires a reply style; no-send kinds require a NULL style and a non-empty {decisionKind, action, reason, stopCondition} recommendation. Charged runs replay idempotently.';

-- Retry lease: same signature and semantics as 20260813003000, now also
-- leasing charged no-send runs. Old rows keep satisfying the old condition.
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
     AND (
       selected_style IS NOT NULL
       OR decision_kind IN ('do_not_send', 'acknowledge_and_stop', 'need_context')
     )
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
  UUID, UUID, TEXT, INTEGER
) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.reserve_stream_analysis_retry(
  UUID, UUID, TEXT, INTEGER
) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_stream_analysis_retry(
  UUID, UUID, TEXT, INTEGER
) TO service_role;

COMMENT ON FUNCTION public.reserve_stream_analysis_retry(UUID, UUID, TEXT, INTEGER)
IS 'Atomically leases one retry for an already-charged failed stream run (send or no-send) by moving it back to charged/in-flight; never reserves rows with a durable final result.';

NOTIFY pgrst, 'reload schema';
