-- Fix update_practice_learning_state so PL/pgSQL output column names do not
-- shadow practice_chat_sessions columns in the guarded UPDATE predicate.

CREATE OR REPLACE FUNCTION public.update_practice_learning_state(
  p_user_id                    UUID,
  p_session_id                 TEXT,
  p_expected_temperature_score INTEGER,
  p_expected_familiarity_score INTEGER,
  p_temperature_delta          INTEGER,
  p_familiarity_delta          INTEGER
)
RETURNS TABLE(updated BOOLEAN, temperature_score INTEGER, familiarity_score INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_expected_temperature INTEGER;
  v_expected_familiarity INTEGER;
  v_temperature_delta    INTEGER;
  v_familiarity_delta    INTEGER;
  v_new_temperature      INTEGER;
  v_new_familiarity      INTEGER;
  v_rows                 INTEGER;
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

  v_temperature_delta := GREATEST(-12, LEAST(12, p_temperature_delta));
  v_familiarity_delta := GREATEST(-12, LEAST(12, p_familiarity_delta));
  v_new_temperature := GREATEST(0, LEAST(100, v_expected_temperature + v_temperature_delta));
  v_new_familiarity := GREATEST(0, LEAST(100, v_expected_familiarity + v_familiarity_delta));

  UPDATE public.practice_chat_sessions AS s
  SET temperature_score = v_new_temperature,
      familiarity_score = v_new_familiarity,
      temperature_updated_at = now(),
      updated_at = now()
  WHERE s.user_id = p_user_id
    AND s.session_id = p_session_id
    AND s.practice_mode = 'beginner'
    AND s.temperature_score = v_expected_temperature
    AND s.familiarity_score = v_expected_familiarity;

  GET DIAGNOSTICS v_rows = ROW_COUNT;

  updated := v_rows > 0;
  IF updated THEN
    temperature_score := v_new_temperature;
    familiarity_score := v_new_familiarity;
  ELSE
    SELECT s.temperature_score, s.familiarity_score
      INTO temperature_score, familiarity_score
    FROM public.practice_chat_sessions s
    WHERE s.user_id = p_user_id
      AND s.session_id = p_session_id
      AND s.practice_mode = 'beginner';
  END IF;
  RETURN NEXT;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.update_practice_learning_state(UUID, TEXT, INTEGER, INTEGER, INTEGER, INTEGER)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_practice_learning_state(UUID, TEXT, INTEGER, INTEGER, INTEGER, INTEGER)
  TO service_role;
