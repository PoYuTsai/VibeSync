-- practice-chat Game Mode delta clamp (2026-07-08)
-- Beginner keeps the original +/-12 learning delta clamp.
-- Game uses +/-18 so SR speed-invite training has visibly stronger feedback.

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
  v_delta_limit            INTEGER;
  v_practice_mode          TEXT;
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

  SELECT s.practice_mode
    INTO v_practice_mode
  FROM public.practice_chat_sessions s
  WHERE s.user_id = p_user_id
    AND s.session_id = p_session_id;

  v_delta_limit := CASE WHEN v_practice_mode = 'game' THEN 18 ELSE 12 END;
  v_temperature_delta := GREATEST(-v_delta_limit, LEAST(v_delta_limit, p_temperature_delta));
  v_familiarity_delta := GREATEST(-v_delta_limit, LEAST(v_delta_limit, p_familiarity_delta));
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

REVOKE EXECUTE ON FUNCTION public.update_practice_learning_state(UUID, TEXT, INTEGER, INTEGER, INTEGER, INTEGER, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_practice_learning_state(UUID, TEXT, INTEGER, INTEGER, INTEGER, INTEGER, TEXT, TEXT)
  TO service_role;

NOTIFY pgrst, 'reload schema';
