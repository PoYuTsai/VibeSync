-- Debrief now performs generated-candidate semantic adjudication before it can
-- be recorded. Keep the DB single-flight owner alive beyond the 90s client
-- window so a second request cannot take over while the verified result is
-- still in flight.

CREATE OR REPLACE FUNCTION public.claim_practice_debrief(
  p_user_id          UUID,
  p_session_id       TEXT,
  p_max_debriefs     INTEGER DEFAULT 3,
  p_request_id       TEXT DEFAULT NULL,
  p_generation_token TEXT DEFAULT NULL
)
RETURNS TABLE(
  current_debrief_count INTEGER,
  replay BOOLEAN,
  in_flight BOOLEAN,
  stored_result JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.practice_chat_sessions;
  v_ledger JSONB;
  v_entry JSONB;
  v_previous_entry JSONB;
  v_now TIMESTAMPTZ := now();
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'claim_practice_debrief: p_user_id is required';
  END IF;
  IF p_session_id IS NULL OR length(p_session_id) = 0 OR length(p_session_id) > 64 THEN
    RAISE EXCEPTION 'claim_practice_debrief: invalid p_session_id';
  END IF;
  IF p_max_debriefs IS NULL OR p_max_debriefs <= 0 THEN
    RAISE EXCEPTION 'claim_practice_debrief: invalid p_max_debriefs';
  END IF;
  IF p_request_id IS NULL
     OR length(p_request_id) = 0
     OR length(p_request_id) > 64 THEN
    RAISE EXCEPTION 'claim_practice_debrief: invalid p_request_id';
  END IF;
  IF p_generation_token IS NULL
     OR length(p_generation_token) = 0
     OR length(p_generation_token) > 64 THEN
    RAISE EXCEPTION 'claim_practice_debrief: invalid p_generation_token';
  END IF;

  SELECT * INTO v_row
  FROM public.practice_chat_sessions
  WHERE user_id = p_user_id AND session_id = p_session_id
  FOR UPDATE;

  IF NOT FOUND OR NOT v_row.charged OR v_row.ai_count < 1 THEN
    RAISE EXCEPTION 'PRACTICE_SESSION_NOT_STARTED';
  END IF;

  v_ledger := v_row.debrief_request_ledger;
  IF NOT public.is_valid_practice_debrief_request_ledger(v_ledger) THEN
    RAISE EXCEPTION 'PRACTICE_DEBRIEF_LEDGER_INVALID';
  END IF;
  v_entry := v_ledger -> p_request_id;

  -- Exact completed replay wins before both the cap and global latch.
  IF v_entry IS NOT NULL
     AND v_entry -> 'result' <> 'null'::jsonb THEN
    current_debrief_count := v_row.debrief_count;
    replay := TRUE;
    in_flight := FALSE;
    stored_result := v_entry -> 'result';
    RETURN NEXT;
    RETURN;
  END IF;

  -- One active model/adjudication pipeline per session. This window must stay
  -- above the client timeout; Hint already uses a two-minute owner fence.
  IF v_row.last_debrief_request_id IS NOT NULL
     AND v_row.last_debrief_result IS NULL
     AND v_row.last_debrief_started_at IS NOT NULL
     AND v_row.last_debrief_started_at > now() - INTERVAL '105 seconds' THEN
    current_debrief_count := v_row.debrief_count;
    replay := FALSE;
    in_flight := TRUE;
    stored_result := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_row.last_debrief_request_id IS NOT NULL
     AND v_row.last_debrief_request_id IS DISTINCT FROM p_request_id
     AND v_row.last_debrief_result IS NULL THEN
    v_previous_entry := v_ledger -> v_row.last_debrief_request_id;
    IF jsonb_typeof(v_previous_entry) = 'object' THEN
      IF v_previous_entry -> 'counted' = 'false'::jsonb THEN
        v_ledger := v_ledger - v_row.last_debrief_request_id;
      ELSE
        v_previous_entry := jsonb_set(
          v_previous_entry,
          '{started_at}',
          'null'::jsonb,
          FALSE
        );
        v_ledger := jsonb_set(
          v_ledger,
          ARRAY[v_row.last_debrief_request_id],
          v_previous_entry,
          FALSE
        );
      END IF;
    END IF;
  END IF;

  -- Exact stale/released retry preserves the original count reservation while
  -- replacing token+started_at to fence every older worker.
  IF v_entry IS NOT NULL THEN
    v_entry := jsonb_build_object(
      'result', NULL,
      'started_at', v_now,
      'generation_token', p_generation_token,
      'counted', v_entry -> 'counted'
    );
    v_ledger := jsonb_set(
      v_ledger,
      ARRAY[p_request_id],
      v_entry,
      FALSE
    );
    UPDATE public.practice_chat_sessions
    SET debrief_request_ledger = v_ledger,
        last_debrief_request_id = p_request_id,
        last_debrief_result = NULL,
        last_debrief_started_at = v_now,
        last_debrief_generation_token = p_generation_token,
        updated_at = v_now
    WHERE user_id = p_user_id AND session_id = p_session_id;
    current_debrief_count := v_row.debrief_count;
    replay := FALSE;
    in_flight := FALSE;
    stored_result := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_row.debrief_count >= p_max_debriefs THEN
    RAISE EXCEPTION 'PRACTICE_DEBRIEF_LIMIT';
  END IF;

  IF (SELECT count(*) FROM jsonb_each(v_ledger)) >= 3 THEN
    RAISE EXCEPTION 'PRACTICE_DEBRIEF_LEDGER_INVALID';
  END IF;

  v_entry := jsonb_build_object(
    'result', NULL,
    'started_at', v_now,
    'generation_token', p_generation_token,
    'counted', FALSE
  );
  v_ledger := v_ledger || jsonb_build_object(p_request_id, v_entry);

  UPDATE public.practice_chat_sessions
  SET debrief_request_ledger = v_ledger,
      last_debrief_request_id = p_request_id,
      last_debrief_result = NULL,
      last_debrief_started_at = v_now,
      last_debrief_generation_token = p_generation_token,
      updated_at = v_now
  WHERE user_id = p_user_id AND session_id = p_session_id;

  current_debrief_count := v_row.debrief_count;
  replay := FALSE;
  in_flight := FALSE;
  stored_result := NULL;
  RETURN NEXT;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.claim_practice_debrief(UUID, TEXT, INTEGER, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_practice_debrief(UUID, TEXT, INTEGER, TEXT, TEXT)
  TO service_role;

-- Keep DB replay certification aligned with the Edge/client semantic schema.
-- Exact replacement preserves already-paid Hint quota and already-counted
-- Debrief slots; only the unsafe old snapshot is regenerated.
DO $$
DECLARE
  v_definition TEXT;
  v_updated TEXT;
BEGIN
  SELECT pg_get_functiondef(
    'public.claim_legacy_practice_hint_replacement(uuid,text,text,text,integer)'::regprocedure
  ) INTO v_definition;
  IF position('typed-facts-v1' IN v_definition) = 0 THEN
    RAISE EXCEPTION 'claim_legacy_practice_hint_replacement quality marker drifted';
  END IF;
  v_updated := replace(
    v_definition,
    'typed-facts-v1',
    'semantic-quality-v2'
  );
  EXECUTE v_updated;

  SELECT pg_get_functiondef(
    'public.invalidate_legacy_practice_ai_snapshot(uuid,text,text,text)'::regprocedure
  ) INTO v_definition;
  IF position('typed-facts-v1' IN v_definition) = 0 THEN
    RAISE EXCEPTION 'invalidate_legacy_practice_ai_snapshot quality marker drifted';
  END IF;
  v_updated := replace(
    v_definition,
    'typed-facts-v1',
    'semantic-quality-v2'
  );
  EXECUTE v_updated;
END;
$$;

NOTIFY pgrst, 'reload schema';
