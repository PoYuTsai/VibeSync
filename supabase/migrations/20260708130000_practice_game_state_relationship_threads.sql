-- Practice Game state + relationship thread continuity.
-- Additive only; deploy after the Edge Function that fail-opens these RPCs.

ALTER TABLE public.practice_chat_sessions
  ADD COLUMN IF NOT EXISTS game_state JSONB;

DO $$
BEGIN
  ALTER TABLE public.practice_chat_sessions
    ADD CONSTRAINT practice_chat_sessions_game_state_object_check
    CHECK (game_state IS NULL OR jsonb_typeof(game_state) = 'object');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE OR REPLACE FUNCTION public.update_practice_game_state(
  p_user_id UUID,
  p_session_id TEXT,
  p_game_state JSONB
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rows INTEGER := 0;
BEGIN
  IF p_game_state IS NOT NULL AND jsonb_typeof(p_game_state) <> 'object' THEN
    RAISE EXCEPTION 'update_practice_game_state: invalid game_state';
  END IF;

  UPDATE public.practice_chat_sessions SET
    game_state = p_game_state,
    updated_at = now()
  WHERE user_id = p_user_id
    AND session_id = p_session_id
    AND practice_mode = 'game';

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows > 0;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.update_practice_game_state(UUID, TEXT, JSONB)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_practice_game_state(UUID, TEXT, JSONB)
  TO service_role;

CREATE TABLE IF NOT EXISTS public.practice_relationship_threads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  visible_thread_id TEXT NOT NULL,
  profile_id TEXT,
  practice_mode TEXT NOT NULL DEFAULT 'standard',
  relationship_score INTEGER CHECK (
    relationship_score IS NULL OR relationship_score BETWEEN 0 AND 100
  ),
  temperature_score INTEGER CHECK (
    temperature_score IS NULL OR temperature_score BETWEEN 0 AND 100
  ),
  familiarity_score INTEGER CHECK (
    familiarity_score IS NULL OR familiarity_score BETWEEN 0 AND 100
  ),
  partner_mood TEXT CHECK (
    partner_mood IS NULL OR partner_mood IN (
      'neutral',
      'curious',
      'amused',
      'comfortable',
      'guarded',
      'annoyed'
    )
  ),
  partner_inner_thought TEXT CHECK (
    partner_inner_thought IS NULL OR char_length(partner_inner_thought) <= 80
  ),
  invite_stage TEXT CHECK (
    invite_stage IS NULL OR invite_stage IN (
      'not_ready',
      'soft_invite_ready',
      'direct_invite_ready',
      'partner_window',
      'high_intimacy'
    )
  ),
  memory_summary TEXT CHECK (
    memory_summary IS NULL OR char_length(memory_summary) <= 1000
  ),
  recent_facts JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (
    jsonb_typeof(recent_facts) = 'object'
  ),
  last_interaction_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  archived_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, visible_thread_id)
);

ALTER TABLE public.practice_relationship_threads ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS practice_relationship_threads_select_own
  ON public.practice_relationship_threads;
DROP POLICY IF EXISTS practice_relationship_threads_insert_own
  ON public.practice_relationship_threads;
DROP POLICY IF EXISTS practice_relationship_threads_update_own
  ON public.practice_relationship_threads;

REVOKE ALL ON TABLE public.practice_relationship_threads
  FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.practice_relationship_threads
  TO service_role;

CREATE INDEX IF NOT EXISTS practice_relationship_threads_user_updated_idx
  ON public.practice_relationship_threads(user_id, updated_at DESC);

CREATE OR REPLACE FUNCTION public.upsert_practice_relationship_thread(
  p_user_id UUID,
  p_visible_thread_id TEXT,
  p_profile_id TEXT DEFAULT NULL,
  p_practice_mode TEXT DEFAULT 'standard',
  p_relationship_score INTEGER DEFAULT NULL,
  p_temperature_score INTEGER DEFAULT NULL,
  p_familiarity_score INTEGER DEFAULT NULL,
  p_partner_mood TEXT DEFAULT NULL,
  p_partner_inner_thought TEXT DEFAULT NULL,
  p_invite_stage TEXT DEFAULT NULL,
  p_memory_summary TEXT DEFAULT NULL,
  p_recent_facts JSONB DEFAULT '{}'::jsonb
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mode TEXT := COALESCE(NULLIF(btrim(p_practice_mode), ''), 'standard');
  v_recent_facts JSONB := COALESCE(p_recent_facts, '{}'::jsonb);
BEGIN
  IF p_visible_thread_id IS NULL OR btrim(p_visible_thread_id) = '' THEN
    RAISE EXCEPTION 'upsert_practice_relationship_thread: invalid thread id';
  END IF;

  IF v_mode NOT IN ('standard', 'beginner', 'game') THEN
    RAISE EXCEPTION 'upsert_practice_relationship_thread: invalid mode';
  END IF;

  IF p_recent_facts IS NOT NULL AND jsonb_typeof(p_recent_facts) <> 'object' THEN
    RAISE EXCEPTION 'upsert_practice_relationship_thread: invalid recent_facts';
  END IF;

  IF p_memory_summary IS NOT NULL AND char_length(p_memory_summary) > 1000 THEN
    RAISE EXCEPTION 'upsert_practice_relationship_thread: memory_summary too long';
  END IF;

  INSERT INTO public.practice_relationship_threads (
    user_id,
    visible_thread_id,
    profile_id,
    practice_mode,
    relationship_score,
    temperature_score,
    familiarity_score,
    partner_mood,
    partner_inner_thought,
    invite_stage,
    memory_summary,
    recent_facts,
    last_interaction_at,
    updated_at
  )
  VALUES (
    p_user_id,
    btrim(p_visible_thread_id),
    NULLIF(btrim(COALESCE(p_profile_id, '')), ''),
    v_mode,
    LEAST(100, GREATEST(0, p_relationship_score)),
    LEAST(100, GREATEST(0, p_temperature_score)),
    LEAST(100, GREATEST(0, p_familiarity_score)),
    NULLIF(btrim(COALESCE(p_partner_mood, '')), ''),
    NULLIF(left(COALESCE(p_partner_inner_thought, ''), 80), ''),
    NULLIF(btrim(COALESCE(p_invite_stage, '')), ''),
    NULLIF(left(COALESCE(p_memory_summary, ''), 1000), ''),
    v_recent_facts,
    now(),
    now()
  )
  ON CONFLICT (user_id, visible_thread_id) DO UPDATE SET
    profile_id = COALESCE(EXCLUDED.profile_id, public.practice_relationship_threads.profile_id),
    practice_mode = EXCLUDED.practice_mode,
    relationship_score = EXCLUDED.relationship_score,
    temperature_score = EXCLUDED.temperature_score,
    familiarity_score = EXCLUDED.familiarity_score,
    partner_mood = COALESCE(EXCLUDED.partner_mood, public.practice_relationship_threads.partner_mood),
    partner_inner_thought = COALESCE(
      EXCLUDED.partner_inner_thought,
      public.practice_relationship_threads.partner_inner_thought
    ),
    invite_stage = COALESCE(EXCLUDED.invite_stage, public.practice_relationship_threads.invite_stage),
    memory_summary = COALESCE(EXCLUDED.memory_summary, public.practice_relationship_threads.memory_summary),
    recent_facts = EXCLUDED.recent_facts,
    last_interaction_at = now(),
    updated_at = now();

  RETURN TRUE;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.upsert_practice_relationship_thread(UUID, TEXT, TEXT, TEXT, INTEGER, INTEGER, INTEGER, TEXT, TEXT, TEXT, TEXT, JSONB)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_practice_relationship_thread(UUID, TEXT, TEXT, TEXT, INTEGER, INTEGER, INTEGER, TEXT, TEXT, TEXT, TEXT, JSONB)
  TO service_role;

NOTIFY pgrst, 'reload schema';
