-- practice-chat beginner temperature + hint ledger
-- Extends the server-side practice_chat_sessions ledger without replacing the
-- existing 4-argument commit_practice_chat_turn RPC used by current chat flow.

ALTER TABLE public.practice_chat_sessions
  ADD COLUMN IF NOT EXISTS practice_mode TEXT NOT NULL DEFAULT 'standard',
  ADD COLUMN IF NOT EXISTS temperature_score INTEGER,
  ADD COLUMN IF NOT EXISTS hint_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS temperature_updated_at TIMESTAMPTZ;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'practice_chat_sessions_practice_mode_check'
      AND conrelid = 'public.practice_chat_sessions'::regclass
  ) THEN
    ALTER TABLE public.practice_chat_sessions
      ADD CONSTRAINT practice_chat_sessions_practice_mode_check
      CHECK (practice_mode IN ('standard', 'beginner'));
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'practice_chat_sessions_temperature_score_check'
      AND conrelid = 'public.practice_chat_sessions'::regclass
  ) THEN
    ALTER TABLE public.practice_chat_sessions
      ADD CONSTRAINT practice_chat_sessions_temperature_score_check
      CHECK (temperature_score IS NULL OR temperature_score BETWEEN 0 AND 100);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'practice_chat_sessions_hint_count_check'
      AND conrelid = 'public.practice_chat_sessions'::regclass
  ) THEN
    ALTER TABLE public.practice_chat_sessions
      ADD CONSTRAINT practice_chat_sessions_hint_count_check
      CHECK (hint_count BETWEEN 0 AND 5);
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.commit_practice_chat_turn(
  p_user_id           UUID,
  p_session_id        TEXT,
  p_charge_quota      BOOLEAN,
  p_max_replies       INTEGER,
  p_practice_mode     TEXT,
  p_temperature_score INTEGER
)
RETURNS TABLE(new_ai_count INTEGER, did_charge BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row           public.practice_chat_sessions;
  v_should_settle BOOLEAN;
  v_mode          TEXT;
  v_initial_temp  INTEGER;
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

  INSERT INTO public.practice_chat_sessions (
    user_id,
    session_id,
    practice_mode,
    temperature_score,
    temperature_updated_at
  )
  VALUES (
    p_user_id,
    p_session_id,
    v_mode,
    CASE WHEN v_mode = 'beginner' THEN v_initial_temp ELSE NULL END,
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

CREATE OR REPLACE FUNCTION public.record_practice_hint(
  p_user_id      UUID,
  p_session_id   TEXT,
  p_charge_quota BOOLEAN,
  p_max_hints    INTEGER
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

  SELECT * INTO v_row
  FROM public.practice_chat_sessions
  WHERE user_id = p_user_id AND session_id = p_session_id
  FOR UPDATE;

  IF NOT FOUND OR NOT v_row.charged OR v_row.ai_count < 1 THEN
    RAISE EXCEPTION 'PRACTICE_SESSION_NOT_STARTED';
  END IF;

  IF v_row.practice_mode <> 'beginner' THEN
    RAISE EXCEPTION 'PRACTICE_HINT_BEGINNER_ONLY';
  END IF;

  IF v_row.hint_count >= p_max_hints THEN
    RAISE EXCEPTION 'PRACTICE_HINT_LIMIT';
  END IF;

  did_charge := p_charge_quota;
  IF did_charge THEN
    PERFORM public.increment_usage(p_user_id, 1);
  END IF;

  UPDATE public.practice_chat_sessions
  SET hint_count = hint_count + 1,
      updated_at = now()
  WHERE user_id = p_user_id AND session_id = p_session_id
  RETURNING hint_count INTO new_hint_count;

  RETURN NEXT;
END;
$$;

DROP FUNCTION IF EXISTS public.update_practice_temperature(UUID, TEXT, INTEGER);

CREATE OR REPLACE FUNCTION public.update_practice_temperature(
  p_user_id           UUID,
  p_session_id        TEXT,
  p_temperature_score INTEGER
)
RETURNS TABLE(updated BOOLEAN, temperature_score INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_score INTEGER;
  v_rows  INTEGER;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'update_practice_temperature: p_user_id is required';
  END IF;
  IF p_session_id IS NULL OR length(p_session_id) = 0 OR length(p_session_id) > 64 THEN
    RAISE EXCEPTION 'update_practice_temperature: invalid p_session_id';
  END IF;
  IF p_temperature_score IS NULL THEN
    RAISE EXCEPTION 'update_practice_temperature: p_temperature_score is required';
  END IF;

  v_score := CASE
    WHEN p_temperature_score < 0 THEN 0
    WHEN p_temperature_score > 100 THEN 100
    ELSE p_temperature_score
  END;

  UPDATE public.practice_chat_sessions
  SET temperature_score = v_score,
      temperature_updated_at = now(),
      updated_at = now()
  WHERE user_id = p_user_id
    AND session_id = p_session_id
    AND practice_mode = 'beginner';

  GET DIAGNOSTICS v_rows = ROW_COUNT;

  updated := v_rows > 0;
  temperature_score := v_score;
  RETURN NEXT;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.commit_practice_chat_turn(UUID, TEXT, BOOLEAN, INTEGER, TEXT, INTEGER)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.commit_practice_chat_turn(UUID, TEXT, BOOLEAN, INTEGER, TEXT, INTEGER)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.record_practice_hint(UUID, TEXT, BOOLEAN, INTEGER)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_practice_hint(UUID, TEXT, BOOLEAN, INTEGER)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.update_practice_temperature(UUID, TEXT, INTEGER)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_practice_temperature(UUID, TEXT, INTEGER)
  TO service_role;

NOTIFY pgrst, 'reload schema';
