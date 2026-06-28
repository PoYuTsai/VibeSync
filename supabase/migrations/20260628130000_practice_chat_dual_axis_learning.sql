-- practice-chat dual-axis learning state
-- Adds familiarity beside the existing temperature_score, which is now treated
-- as heat. Existing beginner temperature/hint RPCs stay available; the new
-- overload and update RPC are used by the dual-axis Edge Function.

ALTER TABLE public.practice_chat_sessions
  ADD COLUMN IF NOT EXISTS familiarity_score INTEGER;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'practice_chat_sessions_familiarity_score_check'
      AND conrelid = 'public.practice_chat_sessions'::regclass
  ) THEN
    ALTER TABLE public.practice_chat_sessions
      ADD CONSTRAINT practice_chat_sessions_familiarity_score_check
      CHECK (familiarity_score IS NULL OR familiarity_score BETWEEN 0 AND 100);
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.commit_practice_chat_turn(
  p_user_id           UUID,
  p_session_id        TEXT,
  p_charge_quota      BOOLEAN,
  p_max_replies       INTEGER,
  p_practice_mode     TEXT,
  p_temperature_score INTEGER,
  p_familiarity_score INTEGER
)
RETURNS TABLE(new_ai_count INTEGER, did_charge BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row                 public.practice_chat_sessions;
  v_should_settle       BOOLEAN;
  v_mode                TEXT;
  v_initial_temp        INTEGER;
  v_initial_familiarity INTEGER;
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
  IF v_mode NOT IN ('standard', 'beginner') THEN
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

  INSERT INTO public.practice_chat_sessions (
    user_id,
    session_id,
    practice_mode,
    temperature_score,
    familiarity_score,
    temperature_updated_at
  )
  VALUES (
    p_user_id,
    p_session_id,
    v_mode,
    CASE WHEN v_mode = 'beginner' THEN v_initial_temp ELSE NULL END,
    CASE WHEN v_mode = 'beginner' THEN v_initial_familiarity ELSE NULL END,
    CASE WHEN v_mode = 'beginner' AND v_initial_temp IS NOT NULL THEN now() ELSE NULL END
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
  did_charge := v_should_settle AND p_charge_quota;

  IF did_charge THEN
    PERFORM public.increment_usage(p_user_id, 1);
  END IF;

  UPDATE public.practice_chat_sessions
  SET ai_count = ai_count + 1,
      charged = charged OR v_should_settle,
      temperature_score = CASE
        WHEN practice_mode = 'beginner' AND temperature_score IS NULL THEN v_initial_temp
        ELSE temperature_score
      END,
      familiarity_score = CASE
        WHEN practice_mode = 'beginner' AND familiarity_score IS NULL THEN v_initial_familiarity
        ELSE familiarity_score
      END,
      temperature_updated_at = CASE
        WHEN practice_mode = 'beginner' AND temperature_score IS NULL AND v_initial_temp IS NOT NULL THEN now()
        ELSE temperature_updated_at
      END,
      updated_at = now()
  WHERE user_id = p_user_id AND session_id = p_session_id
  RETURNING ai_count INTO new_ai_count;

  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.assert_practice_learning_ready(
  p_user_id    UUID,
  p_session_id TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'assert_practice_learning_ready: p_user_id is required';
  END IF;
  IF p_session_id IS NULL OR length(p_session_id) = 0 OR length(p_session_id) > 64 THEN
    RAISE EXCEPTION 'assert_practice_learning_ready: invalid p_session_id';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'practice_chat_sessions'
      AND column_name = 'familiarity_score'
  ) THEN
    RAISE EXCEPTION 'PRACTICE_LEARNING_NOT_READY: missing familiarity_score';
  END IF;

  IF to_regprocedure('public.commit_practice_chat_turn(uuid,text,boolean,integer,text,integer,integer)') IS NULL THEN
    RAISE EXCEPTION 'PRACTICE_LEARNING_NOT_READY: missing dual-axis commit RPC';
  END IF;

  IF to_regprocedure('public.update_practice_learning_state(uuid,text,integer,integer,integer,integer)') IS NULL THEN
    RAISE EXCEPTION 'PRACTICE_LEARNING_NOT_READY: missing learning state RPC';
  END IF;

  RETURN true;
END;
$$;

DROP FUNCTION IF EXISTS public.update_practice_learning_state(UUID, TEXT, INTEGER, INTEGER);
DROP FUNCTION IF EXISTS public.update_practice_learning_state(UUID, TEXT, INTEGER, INTEGER, INTEGER, INTEGER);

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

  UPDATE public.practice_chat_sessions
  SET temperature_score = v_new_temperature,
      familiarity_score = v_new_familiarity,
      temperature_updated_at = now(),
      updated_at = now()
  WHERE user_id = p_user_id
    AND session_id = p_session_id
    AND practice_mode = 'beginner'
    AND temperature_score = v_expected_temperature
    AND familiarity_score = v_expected_familiarity;

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

REVOKE EXECUTE ON FUNCTION public.assert_practice_learning_ready(UUID, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.assert_practice_learning_ready(UUID, TEXT)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.commit_practice_chat_turn(UUID, TEXT, BOOLEAN, INTEGER, TEXT, INTEGER, INTEGER)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.commit_practice_chat_turn(UUID, TEXT, BOOLEAN, INTEGER, TEXT, INTEGER, INTEGER)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.update_practice_learning_state(UUID, TEXT, INTEGER, INTEGER, INTEGER, INTEGER)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_practice_learning_state(UUID, TEXT, INTEGER, INTEGER, INTEGER, INTEGER)
  TO service_role;

NOTIFY pgrst, 'reload schema';
