-- Keep the database replay predicates aligned with the Edge quality guards.
--
-- Rollout order matters: this compatibility migration is safe to deploy before
-- the Edge function. Existing Edge versions still replay their own generated
-- snapshots, while the new Edge can atomically replace an already-charged
-- Hint or already-counted Debrief that predates typed-facts-v1 without
-- charging/counting it again.

CREATE OR REPLACE FUNCTION public.claim_legacy_practice_hint_replacement(
  p_user_id           UUID,
  p_session_id        TEXT,
  p_request_id        TEXT,
  p_generation_token  TEXT,
  p_expected_ai_count INTEGER
)
RETURNS TABLE(
  current_hint_count INTEGER,
  claimed BOOLEAN,
  replay BOOLEAN,
  stored_result JSONB,
  quota_already_paid BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.practice_chat_sessions%ROWTYPE;
  v_request public.practice_hint_requests%ROWTYPE;
  v_current_quality_model BOOLEAN := FALSE;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'claim_legacy_practice_hint_replacement: p_user_id is required';
  END IF;
  IF p_session_id IS NULL OR length(p_session_id) = 0 OR length(p_session_id) > 64 THEN
    RAISE EXCEPTION 'claim_legacy_practice_hint_replacement: invalid p_session_id';
  END IF;
  IF p_request_id IS NULL OR length(p_request_id) = 0 OR length(p_request_id) > 64
     OR p_request_id = '__legacy_inflight__' THEN
    RAISE EXCEPTION 'claim_legacy_practice_hint_replacement: invalid p_request_id';
  END IF;
  IF p_generation_token IS NULL
     OR length(p_generation_token) = 0
     OR length(p_generation_token) > 64 THEN
    RAISE EXCEPTION 'claim_legacy_practice_hint_replacement: invalid p_generation_token';
  END IF;
  IF p_expected_ai_count IS NULL
     OR p_expected_ai_count < 1
     OR p_expected_ai_count > 20 THEN
    RAISE EXCEPTION 'claim_legacy_practice_hint_replacement: invalid p_expected_ai_count';
  END IF;

  SELECT s.* INTO v_session
  FROM public.practice_chat_sessions AS s
  WHERE s.user_id = p_user_id
    AND s.session_id = p_session_id
  FOR UPDATE;

  IF NOT FOUND OR NOT v_session.charged OR v_session.ai_count < 1 THEN
    RAISE EXCEPTION 'PRACTICE_SESSION_NOT_STARTED';
  END IF;
  IF v_session.practice_mode NOT IN ('beginner', 'game') THEN
    RAISE EXCEPTION 'PRACTICE_HINT_BEGINNER_ONLY';
  END IF;
  IF p_expected_ai_count <> v_session.ai_count THEN
    RAISE EXCEPTION 'PRACTICE_HINT_STALE';
  END IF;

  SELECT r.* INTO v_request
  FROM public.practice_hint_requests AS r
  WHERE r.user_id = p_user_id
    AND r.session_id = p_session_id
    AND r.request_id = p_request_id
  FOR UPDATE;

  IF NOT FOUND
     OR v_request.state <> 'settled'
     OR NOT v_request.charged
     OR v_request.result IS NULL
     OR jsonb_typeof(v_request.result) <> 'object' THEN
    RAISE EXCEPTION 'PRACTICE_HINT_REPLACEMENT_NOT_READY';
  END IF;

  -- Cost provenance must be explicit before taking ownership. Treating a
  -- missing/invalid marker as unpaid could charge a consumed legacy Hint twice.
  IF v_request.result -> 'costDeducted' IS DISTINCT FROM '0'::jsonb
     AND v_request.result -> 'costDeducted' IS DISTINCT FROM '1'::jsonb THEN
    RAISE EXCEPTION 'PRACTICE_HINT_REPLACEMENT_NOT_READY';
  END IF;

  v_current_quality_model :=
    v_request.result ->> 'generationSource' = 'model'
    AND v_request.result -> 'fallbackUsed' = 'false'::jsonb
    AND v_request.result ->> 'qualitySchemaVersion' = 'typed-facts-v1';

  IF NOT v_request.legacy_replacement_pending
     AND v_current_quality_model THEN
    current_hint_count := v_session.hint_count;
    claimed := FALSE;
    replay := TRUE;
    stored_result := v_request.result;
    quota_already_paid := v_request.result -> 'costDeducted' = '1'::jsonb;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_request.claimed_ai_count IS NOT NULL
     AND v_request.claimed_ai_count <> v_session.ai_count THEN
    RAISE EXCEPTION 'PRACTICE_HINT_STALE';
  END IF;
  IF v_request.legacy_replacement_pending
     AND v_request.legacy_replacement_started_at IS NOT NULL
     AND v_request.legacy_replacement_started_at > now() - interval '2 minutes' THEN
    RAISE EXCEPTION 'PRACTICE_HINT_IN_FLIGHT';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.practice_hint_requests AS r
    WHERE r.user_id = p_user_id
      AND r.session_id = p_session_id
      AND r.request_id <> p_request_id
      AND r.legacy_replacement_pending = TRUE
      AND r.legacy_replacement_started_at IS NOT NULL
      AND r.legacy_replacement_started_at > now() - interval '2 minutes'
  ) THEN
    RAISE EXCEPTION 'PRACTICE_HINT_IN_FLIGHT';
  END IF;
  IF v_session.hint_generation_started_at IS NOT NULL
     AND v_session.hint_generation_started_at > now() - interval '2 minutes' THEN
    RAISE EXCEPTION 'PRACTICE_HINT_IN_FLIGHT';
  END IF;

  -- Fence every stale owner shape before taking the shared session latch.
  UPDATE public.practice_hint_requests AS r
  SET legacy_replacement_started_at = NULL,
      updated_at = now()
  WHERE r.user_id = p_user_id
    AND r.session_id = p_session_id
    AND r.legacy_replacement_pending = TRUE
    AND r.legacy_replacement_started_at IS NOT NULL;

  DELETE FROM public.practice_hint_requests AS r
  WHERE r.user_id = p_user_id
    AND r.session_id = p_session_id
    AND r.state = 'generating';

  UPDATE public.practice_hint_requests AS r
  SET legacy_replacement_pending = TRUE,
      legacy_replacement_generation_token = p_generation_token,
      legacy_replacement_started_at = now(),
      claimed_ai_count = v_session.ai_count,
      updated_at = now()
  WHERE r.user_id = p_user_id
    AND r.session_id = p_session_id
    AND r.request_id = p_request_id;

  UPDATE public.practice_chat_sessions AS s
  SET hint_generation_started_at = now(),
      hint_generation_owner_token = p_generation_token,
      updated_at = now()
  WHERE s.user_id = p_user_id
    AND s.session_id = p_session_id;

  current_hint_count := v_session.hint_count;
  claimed := TRUE;
  replay := FALSE;
  stored_result := NULL;
  quota_already_paid := v_request.result -> 'costDeducted' = '1'::jsonb;
  RETURN NEXT;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.claim_legacy_practice_hint_replacement(UUID, TEXT, TEXT, TEXT, INTEGER)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_legacy_practice_hint_replacement(UUID, TEXT, TEXT, TEXT, INTEGER)
  TO service_role;

-- Debrief replay must use the same quality version as the Edge parser. An old
-- model result without typed-facts-v1 is safe to invalidate because its
-- already-counted ledger entry remains in place; the next exact request claim
-- replaces only result/token ownership and record_practice_debrief does not
-- increment debrief_count twice.
CREATE OR REPLACE FUNCTION public.invalidate_legacy_practice_ai_snapshot(
  p_user_id     UUID,
  p_session_id  TEXT,
  p_request_id  TEXT,
  p_kind        TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.practice_chat_sessions%ROWTYPE;
  v_ledger JSONB;
  v_entry JSONB;
  v_result JSONB;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'invalidate_legacy_practice_ai_snapshot: p_user_id is required';
  END IF;
  IF p_session_id IS NULL OR length(p_session_id) = 0 OR length(p_session_id) > 64 THEN
    RAISE EXCEPTION 'invalidate_legacy_practice_ai_snapshot: invalid p_session_id';
  END IF;
  IF p_request_id IS NULL OR length(p_request_id) = 0 OR length(p_request_id) > 64 THEN
    RAISE EXCEPTION 'invalidate_legacy_practice_ai_snapshot: invalid p_request_id';
  END IF;
  IF p_kind NOT IN ('hint', 'debrief') THEN
    RAISE EXCEPTION 'invalidate_legacy_practice_ai_snapshot: invalid p_kind';
  END IF;

  SELECT * INTO v_session
  FROM public.practice_chat_sessions
  WHERE user_id = p_user_id AND session_id = p_session_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  IF p_kind = 'debrief' THEN
    v_ledger := v_session.debrief_request_ledger;
    IF NOT public.is_valid_practice_debrief_request_ledger(v_ledger) THEN
      RAISE EXCEPTION 'PRACTICE_DEBRIEF_LEDGER_INVALID';
    END IF;
    v_entry := v_ledger -> p_request_id;
    v_result := v_entry -> 'result';
    IF v_entry IS NULL
       OR v_result IS NULL
       OR v_result = 'null'::jsonb
       OR (
         v_result ->> 'generationSource' = 'model'
         AND v_result -> 'fallbackUsed' = 'false'::jsonb
         AND v_result ->> 'qualitySchemaVersion' = 'typed-facts-v1'
       ) THEN
      RETURN FALSE;
    END IF;

    v_entry := jsonb_set(v_entry, '{result}', 'null'::jsonb, FALSE);
    v_entry := jsonb_set(v_entry, '{started_at}', 'null'::jsonb, FALSE);
    v_ledger := jsonb_set(
      v_ledger,
      ARRAY[p_request_id],
      v_entry,
      FALSE
    );

    UPDATE public.practice_chat_sessions
    SET debrief_request_ledger = v_ledger,
        last_debrief_result = CASE
          WHEN last_debrief_request_id = p_request_id THEN NULL
          ELSE last_debrief_result
        END,
        last_debrief_started_at = CASE
          WHEN last_debrief_request_id = p_request_id THEN NULL
          ELSE last_debrief_started_at
        END,
        updated_at = now()
    WHERE user_id = p_user_id AND session_id = p_session_id;
    RETURN TRUE;
  END IF;

  -- Hint replacement remains atomic in claim_legacy_practice_hint_replacement.
  RAISE EXCEPTION 'PRACTICE_HINT_REPLACEMENT_REQUIRED';
END;
$$;

REVOKE EXECUTE ON FUNCTION public.invalidate_legacy_practice_ai_snapshot(UUID, TEXT, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.invalidate_legacy_practice_ai_snapshot(UUID, TEXT, TEXT, TEXT)
  TO service_role;

NOTIFY pgrst, 'reload schema';
