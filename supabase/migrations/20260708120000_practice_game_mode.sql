-- practice-chat Game Mode allowlist (2026-07-08)
-- Expands practice_mode to standard/beginner/game. Game uses the existing
-- beginner learning/hint ledger in Batch A; SR-only authority stays in Edge.

ALTER TABLE public.practice_chat_sessions
  DROP CONSTRAINT IF EXISTS practice_chat_sessions_practice_mode_check;

ALTER TABLE public.practice_chat_sessions
  ADD CONSTRAINT practice_chat_sessions_practice_mode_check
  CHECK (practice_mode IN ('standard', 'beginner', 'game'));

CREATE OR REPLACE FUNCTION public.commit_practice_chat_turn(
  p_user_id               UUID,
  p_session_id            TEXT,
  p_charge_quota          BOOLEAN,
  p_max_replies           INTEGER,
  p_practice_mode         TEXT,
  p_temperature_score     INTEGER,
  p_familiarity_score     INTEGER,
  p_partner_mood          TEXT,
  p_partner_inner_thought TEXT
)
RETURNS TABLE(new_ai_count INTEGER, did_charge BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row                   public.practice_chat_sessions;
  v_should_settle         BOOLEAN;
  v_mode                  TEXT;
  v_initial_temp          INTEGER;
  v_initial_familiarity   INTEGER;
  v_partner_mood          TEXT;
  v_partner_inner_thought TEXT;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'commit_practice_chat_turn: p_user_id is required';
  END IF;
  IF p_session_id IS NULL OR length(p_session_id) = 0 OR length(p_session_id) > 64 THEN
    RAISE EXCEPTION 'commit_practice_chat_turn: invalid p_session_id';
  END IF;
  IF p_max_replies IS NULL OR p_max_replies <= 0 THEN
    RAISE EXCEPTION 'commit_practice_chat_turn: invalid p_max_replies';
  END IF;
  IF p_charge_quota IS NULL THEN
    RAISE EXCEPTION 'commit_practice_chat_turn: invalid p_charge_quota';
  END IF;

  v_mode := COALESCE(NULLIF(btrim(p_practice_mode), ''), 'standard');
  IF v_mode NOT IN ('standard', 'beginner', 'game') THEN
    RAISE EXCEPTION 'PRACTICE_INVALID_MODE';
  END IF;

  v_initial_temp := CASE
    WHEN p_temperature_score IS NULL THEN NULL
    WHEN p_temperature_score < 0 THEN 0
    WHEN p_temperature_score > 100 THEN 100
    ELSE p_temperature_score
  END;

  v_initial_familiarity := CASE
    WHEN p_familiarity_score IS NULL THEN 0
    WHEN p_familiarity_score < 0 THEN 0
    WHEN p_familiarity_score > 100 THEN 100
    ELSE p_familiarity_score
  END;

  v_partner_mood := NULLIF(btrim(p_partner_mood), '');
  IF v_partner_mood IS NOT NULL AND v_partner_mood NOT IN (
    'neutral', 'curious', 'amused', 'comfortable', 'guarded', 'annoyed'
  ) THEN
    RAISE EXCEPTION 'commit_practice_chat_turn: invalid p_partner_mood';
  END IF;
  v_partner_inner_thought := NULLIF(left(btrim(COALESCE(p_partner_inner_thought, '')), 80), '');

  INSERT INTO public.practice_chat_sessions (
    user_id,
    session_id,
    practice_mode,
    temperature_score,
    familiarity_score,
    partner_mood,
    partner_inner_thought,
    partner_state_updated_at,
    temperature_updated_at
  )
  VALUES (
    p_user_id,
    p_session_id,
    v_mode,
    CASE WHEN v_mode IN ('beginner', 'game') THEN v_initial_temp ELSE NULL END,
    CASE WHEN v_mode IN ('beginner', 'game') THEN v_initial_familiarity ELSE NULL END,
    CASE WHEN v_mode IN ('beginner', 'game') THEN v_partner_mood ELSE NULL END,
    CASE WHEN v_mode IN ('beginner', 'game') THEN v_partner_inner_thought ELSE NULL END,
    CASE WHEN v_mode IN ('beginner', 'game') AND (v_partner_mood IS NOT NULL OR v_partner_inner_thought IS NOT NULL) THEN now() ELSE NULL END,
    CASE WHEN v_mode IN ('beginner', 'game') AND v_initial_temp IS NOT NULL THEN now() ELSE NULL END
  )
  ON CONFLICT (user_id, session_id) DO NOTHING;

  SELECT * INTO v_row
  FROM public.practice_chat_sessions
  WHERE user_id = p_user_id AND session_id = p_session_id
  FOR UPDATE;

  IF v_row.ai_count >= p_max_replies THEN
    RAISE EXCEPTION 'PRACTICE_SESSION_COMPLETE';
  END IF;

  IF v_row.practice_mode <> v_mode THEN
    RAISE EXCEPTION 'PRACTICE_MODE_LOCKED';
  END IF;

  v_should_settle := NOT v_row.charged;
  did_charge := v_should_settle AND p_charge_quota IS TRUE;

  IF did_charge THEN
    PERFORM public.increment_usage(p_user_id, 1);
  END IF;

  UPDATE public.practice_chat_sessions
  SET ai_count = ai_count + 1,
      charged = charged OR v_should_settle,
      temperature_score = CASE
        WHEN practice_mode IN ('beginner', 'game') AND temperature_score IS NULL THEN v_initial_temp
        ELSE temperature_score
      END,
      familiarity_score = CASE
        WHEN practice_mode IN ('beginner', 'game') AND familiarity_score IS NULL THEN v_initial_familiarity
        ELSE familiarity_score
      END,
      partner_mood = CASE
        WHEN practice_mode IN ('beginner', 'game') AND partner_mood IS NULL THEN v_partner_mood
        ELSE partner_mood
      END,
      partner_inner_thought = CASE
        WHEN practice_mode IN ('beginner', 'game') AND partner_inner_thought IS NULL THEN v_partner_inner_thought
        ELSE partner_inner_thought
      END,
      partner_state_updated_at = CASE
        WHEN practice_mode IN ('beginner', 'game')
          AND partner_mood IS NULL
          AND (v_partner_mood IS NOT NULL OR v_partner_inner_thought IS NOT NULL)
        THEN now()
        ELSE partner_state_updated_at
      END,
      temperature_updated_at = CASE
        WHEN practice_mode IN ('beginner', 'game') AND temperature_score IS NULL AND v_initial_temp IS NOT NULL THEN now()
        ELSE temperature_updated_at
      END,
      updated_at = now()
  WHERE user_id = p_user_id AND session_id = p_session_id
  RETURNING ai_count INTO new_ai_count;

  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_practice_hint_generation(
  p_user_id    UUID,
  p_session_id TEXT,
  p_max_hints  INTEGER,
  p_request_id TEXT DEFAULT NULL
)
RETURNS TABLE(current_hint_count INTEGER, replay BOOLEAN, stored_result JSONB)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.practice_chat_sessions;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'claim_practice_hint_generation: p_user_id is required';
  END IF;
  IF p_session_id IS NULL OR length(p_session_id) = 0 OR length(p_session_id) > 64 THEN
    RAISE EXCEPTION 'claim_practice_hint_generation: invalid p_session_id';
  END IF;
  IF p_max_hints IS NULL OR p_max_hints <= 0 OR p_max_hints > 5 THEN
    RAISE EXCEPTION 'claim_practice_hint_generation: invalid p_max_hints';
  END IF;
  IF p_request_id IS NOT NULL
     AND (length(p_request_id) = 0 OR length(p_request_id) > 64) THEN
    RAISE EXCEPTION 'claim_practice_hint_generation: invalid p_request_id';
  END IF;

  SELECT * INTO v_row
  FROM public.practice_chat_sessions
  WHERE user_id = p_user_id AND session_id = p_session_id
  FOR UPDATE;

  IF NOT FOUND OR NOT v_row.charged OR v_row.ai_count < 1 THEN
    RAISE EXCEPTION 'PRACTICE_SESSION_NOT_STARTED';
  END IF;

  IF p_request_id IS NOT NULL
     AND v_row.last_hint_request_id = p_request_id
     AND v_row.last_hint_result IS NOT NULL THEN
    current_hint_count := v_row.hint_count;
    replay := TRUE;
    stored_result := v_row.last_hint_result;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_row.practice_mode NOT IN ('beginner', 'game') THEN
    RAISE EXCEPTION 'PRACTICE_HINT_BEGINNER_ONLY';
  END IF;

  IF v_row.hint_count >= p_max_hints THEN
    RAISE EXCEPTION 'PRACTICE_HINT_LIMIT';
  END IF;

  IF v_row.hint_generation_started_at IS NOT NULL
    AND v_row.hint_generation_started_at > now() - interval '2 minutes' THEN
    RAISE EXCEPTION 'PRACTICE_HINT_IN_FLIGHT';
  END IF;

  UPDATE public.practice_chat_sessions
  SET hint_generation_started_at = now(),
      updated_at = now()
  WHERE user_id = p_user_id AND session_id = p_session_id
  RETURNING hint_count INTO current_hint_count;

  replay := FALSE;
  stored_result := NULL;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_practice_hint(
  p_user_id      UUID,
  p_session_id   TEXT,
  p_charge_quota BOOLEAN,
  p_max_hints    INTEGER,
  p_request_id   TEXT DEFAULT NULL,
  p_result       JSONB DEFAULT NULL
)
RETURNS TABLE(new_hint_count INTEGER, did_charge BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.practice_chat_sessions;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'record_practice_hint: p_user_id is required';
  END IF;
  IF p_session_id IS NULL OR length(p_session_id) = 0 OR length(p_session_id) > 64 THEN
    RAISE EXCEPTION 'record_practice_hint: invalid p_session_id';
  END IF;
  IF p_max_hints IS NULL OR p_max_hints <= 0 OR p_max_hints > 5 THEN
    RAISE EXCEPTION 'record_practice_hint: invalid p_max_hints';
  END IF;
  IF p_charge_quota IS NULL THEN
    RAISE EXCEPTION 'record_practice_hint: invalid p_charge_quota';
  END IF;
  IF p_request_id IS NOT NULL
     AND (length(p_request_id) = 0 OR length(p_request_id) > 64) THEN
    RAISE EXCEPTION 'record_practice_hint: invalid p_request_id';
  END IF;

  SELECT * INTO v_row
  FROM public.practice_chat_sessions
  WHERE user_id = p_user_id AND session_id = p_session_id
  FOR UPDATE;

  IF NOT FOUND OR NOT v_row.charged OR v_row.ai_count < 1 THEN
    RAISE EXCEPTION 'PRACTICE_SESSION_NOT_STARTED';
  END IF;

  IF v_row.practice_mode NOT IN ('beginner', 'game') THEN
    RAISE EXCEPTION 'PRACTICE_HINT_BEGINNER_ONLY';
  END IF;

  IF v_row.hint_count >= p_max_hints THEN
    RAISE EXCEPTION 'PRACTICE_HINT_LIMIT';
  END IF;

  IF v_row.hint_generation_started_at IS NULL THEN
    RAISE EXCEPTION 'PRACTICE_HINT_NOT_CLAIMED';
  END IF;

  did_charge := p_charge_quota;
  IF did_charge THEN
    PERFORM public.increment_usage(p_user_id, 1);
  END IF;

  UPDATE public.practice_chat_sessions
  SET hint_count = hint_count + 1,
      hint_generation_started_at = NULL,
      last_hint_request_id = p_request_id,
      last_hint_result = CASE
        WHEN p_request_id IS NULL OR p_result IS NULL THEN NULL
        ELSE p_result || jsonb_build_object('hintUsedCount', hint_count + 1)
      END,
      updated_at = now()
  WHERE user_id = p_user_id AND session_id = p_session_id
  RETURNING hint_count INTO new_hint_count;

  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_practice_learning_state(
  p_user_id                    UUID,
  p_session_id                 TEXT,
  p_expected_temperature_score INTEGER,
  p_expected_familiarity_score INTEGER,
  p_temperature_delta          INTEGER,
  p_familiarity_delta          INTEGER,
  p_partner_mood               TEXT,
  p_partner_inner_thought      TEXT
)
RETURNS TABLE(updated BOOLEAN, temperature_score INTEGER, familiarity_score INTEGER, partner_mood TEXT, partner_inner_thought TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_expected_temperature   INTEGER;
  v_expected_familiarity   INTEGER;
  v_temperature_delta      INTEGER;
  v_familiarity_delta      INTEGER;
  v_new_temperature        INTEGER;
  v_new_familiarity        INTEGER;
  v_partner_mood           TEXT;
  v_partner_inner_thought  TEXT;
  v_rows                   INTEGER;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'update_practice_learning_state: p_user_id is required';
  END IF;
  IF p_session_id IS NULL OR length(p_session_id) = 0 OR length(p_session_id) > 64 THEN
    RAISE EXCEPTION 'update_practice_learning_state: invalid p_session_id';
  END IF;
  IF p_expected_temperature_score IS NULL THEN
    RAISE EXCEPTION 'update_practice_learning_state: p_expected_temperature_score is required';
  END IF;
  IF p_expected_familiarity_score IS NULL THEN
    RAISE EXCEPTION 'update_practice_learning_state: p_expected_familiarity_score is required';
  END IF;
  IF p_temperature_delta IS NULL THEN
    RAISE EXCEPTION 'update_practice_learning_state: p_temperature_delta is required';
  END IF;
  IF p_familiarity_delta IS NULL THEN
    RAISE EXCEPTION 'update_practice_learning_state: p_familiarity_delta is required';
  END IF;

  v_expected_temperature := CASE
    WHEN p_expected_temperature_score < 0 THEN 0
    WHEN p_expected_temperature_score > 100 THEN 100
    ELSE p_expected_temperature_score
  END;

  v_expected_familiarity := CASE
    WHEN p_expected_familiarity_score < 0 THEN 0
    WHEN p_expected_familiarity_score > 100 THEN 100
    ELSE p_expected_familiarity_score
  END;

  v_partner_mood := COALESCE(NULLIF(btrim(p_partner_mood), ''), 'neutral');
  IF v_partner_mood NOT IN (
    'neutral', 'curious', 'amused', 'comfortable', 'guarded', 'annoyed'
  ) THEN
    RAISE EXCEPTION 'update_practice_learning_state: invalid p_partner_mood';
  END IF;
  v_partner_inner_thought := NULLIF(left(btrim(COALESCE(p_partner_inner_thought, '')), 80), '');

  v_temperature_delta := GREATEST(-12, LEAST(12, p_temperature_delta));
  v_familiarity_delta := GREATEST(-12, LEAST(12, p_familiarity_delta));
  v_new_temperature := GREATEST(0, LEAST(100, v_expected_temperature + v_temperature_delta));
  v_new_familiarity := GREATEST(0, LEAST(100, v_expected_familiarity + v_familiarity_delta));

  UPDATE public.practice_chat_sessions AS s
  SET temperature_score = v_new_temperature,
      familiarity_score = v_new_familiarity,
      partner_mood = v_partner_mood,
      partner_inner_thought = v_partner_inner_thought,
      partner_state_updated_at = now(),
      temperature_updated_at = now(),
      updated_at = now()
  WHERE s.user_id = p_user_id
    AND s.session_id = p_session_id
    AND s.practice_mode IN ('beginner', 'game')
    AND s.temperature_score = v_expected_temperature
    AND s.familiarity_score = v_expected_familiarity;

  GET DIAGNOSTICS v_rows = ROW_COUNT;

  updated := v_rows > 0;
  IF updated THEN
    temperature_score := v_new_temperature;
    familiarity_score := v_new_familiarity;
    partner_mood := v_partner_mood;
    partner_inner_thought := v_partner_inner_thought;
  ELSE
    SELECT s.temperature_score, s.familiarity_score, s.partner_mood, s.partner_inner_thought
      INTO temperature_score, familiarity_score, partner_mood, partner_inner_thought
    FROM public.practice_chat_sessions s
    WHERE s.user_id = p_user_id
      AND s.session_id = p_session_id
      AND s.practice_mode IN ('beginner', 'game');
  END IF;
  RETURN NEXT;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.commit_practice_chat_turn(UUID, TEXT, BOOLEAN, INTEGER, TEXT, INTEGER, INTEGER, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.commit_practice_chat_turn(UUID, TEXT, BOOLEAN, INTEGER, TEXT, INTEGER, INTEGER, TEXT, TEXT)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.claim_practice_hint_generation(UUID, TEXT, INTEGER, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_practice_hint_generation(UUID, TEXT, INTEGER, TEXT)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.record_practice_hint(UUID, TEXT, BOOLEAN, INTEGER, TEXT, JSONB)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_practice_hint(UUID, TEXT, BOOLEAN, INTEGER, TEXT, JSONB)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.update_practice_learning_state(UUID, TEXT, INTEGER, INTEGER, INTEGER, INTEGER, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_practice_learning_state(UUID, TEXT, INTEGER, INTEGER, INTEGER, INTEGER, TEXT, TEXT)
  TO service_role;

NOTIFY pgrst, 'reload schema';
