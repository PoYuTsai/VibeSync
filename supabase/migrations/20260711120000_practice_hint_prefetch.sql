-- Hint prefetch：bounded per-request ledger + consume-time settlement (2026-07-11)
--
-- Product invariants:
--   * successful prefetch stores an unconsumed snapshot and charges nothing;
--   * only a formal consume increments quota / hint_count;
--   * the exact request id settles at most once, even after newer requests exist;
--   * failed prefetch never stores fallback text;
--   * Game and Beginner share this ledger and the same RPCs.
--
-- Privacy boundary: this table stores request metadata and the existing Hint
-- response snapshot only. It does not store transcript, prompt, or raw provider errors.

CREATE TABLE IF NOT EXISTS public.practice_hint_requests (
  user_id          UUID        NOT NULL,
  session_id       TEXT        NOT NULL,
  request_id       TEXT        NOT NULL,
  generation_token TEXT,
  claimed_ai_count INTEGER,
  is_prefetch      BOOLEAN     NOT NULL,
  state            TEXT        NOT NULL,
  result           JSONB,
  charged          BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, session_id, request_id),
  CONSTRAINT practice_hint_requests_session_fk
    FOREIGN KEY (user_id, session_id)
    REFERENCES public.practice_chat_sessions (user_id, session_id)
    ON DELETE CASCADE,
  CONSTRAINT practice_hint_requests_request_id_len_check
    CHECK (length(request_id) BETWEEN 1 AND 64),
  CONSTRAINT practice_hint_requests_generation_token_len_check
    CHECK (
      generation_token IS NULL
      OR length(generation_token) BETWEEN 1 AND 64
    ),
  CONSTRAINT practice_hint_requests_state_check
    CHECK (state IN ('generating', 'prefetched', 'settled')),
  CONSTRAINT practice_hint_requests_claimed_ai_count_check
    CHECK (
      (
        claimed_ai_count IS NOT NULL
        AND claimed_ai_count BETWEEN 1 AND 20
      )
      OR (
        claimed_ai_count IS NULL
        AND state = 'settled'
        AND charged = TRUE
      )
    ),
  CONSTRAINT practice_hint_requests_state_payload_check
    CHECK (
      (
        state = 'generating'
        AND result IS NULL
        AND charged = FALSE
      )
      OR (
        state = 'prefetched'
        AND result IS NOT NULL
        AND jsonb_typeof(result) = 'object'
        AND charged = FALSE
        AND is_prefetch = TRUE
      )
      OR (
        state = 'settled'
        AND result IS NOT NULL
        AND jsonb_typeof(result) = 'object'
        AND charged = TRUE
      )
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS practice_hint_requests_one_prefetched_per_session
  ON public.practice_hint_requests (user_id, session_id)
  WHERE state = 'prefetched';

-- The session latch has no owner id. This index plus the claim/release fencing
-- below makes the exact generating row the owner, so a late worker cannot clear
-- a newer worker's latch.
CREATE UNIQUE INDEX IF NOT EXISTS practice_hint_requests_one_generating_per_session
  ON public.practice_hint_requests (user_id, session_id)
  WHERE state = 'generating';

CREATE INDEX IF NOT EXISTS practice_hint_requests_session_created_idx
  ON public.practice_hint_requests (user_id, session_id, created_at DESC);

ALTER TABLE public.practice_hint_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.practice_hint_requests
  FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.practice_hint_requests
  TO service_role;

COMMENT ON TABLE public.practice_hint_requests IS
  'Bounded Hint request ledger. Stores request metadata and a Hint response snapshot only; does not store transcript, prompt, or raw provider errors.';
COMMENT ON COLUMN public.practice_hint_requests.charged IS
  'Means formally consumed/settled (and hint_count recorded), not necessarily physical quota charge.';

-- Existing single-slot snapshots may include paid, test-account, or fallback
-- results. All of them were already counted, so backfill as settled/charged.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.practice_chat_sessions
    WHERE last_hint_request_id IS NOT NULL
      AND last_hint_result IS NOT NULL
      AND jsonb_typeof(last_hint_result) <> 'object'
  ) THEN
    RAISE EXCEPTION 'practice_hint_prefetch: legacy last_hint_result must be an object';
  END IF;
END;
$$;

INSERT INTO public.practice_hint_requests (
  user_id,
  session_id,
  request_id,
  generation_token,
  claimed_ai_count,
  is_prefetch,
  state,
  result,
  charged,
  created_at,
  updated_at
)
SELECT
  user_id,
  session_id,
  last_hint_request_id,
  NULL,
  NULL,
  FALSE,
  'settled',
  last_hint_result,
  TRUE,
  updated_at,
  updated_at
FROM public.practice_chat_sessions
WHERE last_hint_request_id IS NOT NULL
  AND last_hint_result IS NOT NULL
ON CONFLICT (user_id, session_id, request_id) DO NOTHING;

-- A migration can land while the old Edge is between claim and record. Give
-- that in-flight latch an internal owner. The compatibility record path may
-- exchange this placeholder for the real request id exactly once. New claims
-- delete stale owners before taking the latch, fencing a late legacy worker.
INSERT INTO public.practice_hint_requests (
  user_id,
  session_id,
  request_id,
  generation_token,
  claimed_ai_count,
  is_prefetch,
  state,
  result,
  charged,
  created_at,
  updated_at
)
SELECT
  s.user_id,
  s.session_id,
  '__legacy_inflight__',
  NULL,
  s.ai_count,
  FALSE,
  'generating',
  NULL,
  FALSE,
  s.hint_generation_started_at,
  s.updated_at
FROM public.practice_chat_sessions AS s
WHERE s.hint_generation_started_at IS NOT NULL
  AND s.ai_count BETWEEN 1 AND 20
  AND NOT EXISTS (
    SELECT 1
    FROM public.practice_hint_requests AS r
    WHERE r.user_id = s.user_id
      AND r.session_id = s.session_id
      AND r.state = 'generating'
  )
ON CONFLICT (user_id, session_id, request_id) DO NOTHING;

-- Remove the old overloads first. Defaults on the new signatures would make
-- PostgREST calls ambiguous if the old functions remained.
DROP FUNCTION IF EXISTS public.claim_practice_hint_generation(UUID, TEXT, INTEGER, TEXT);
DROP FUNCTION IF EXISTS public.claim_practice_hint_generation(UUID, TEXT, INTEGER, TEXT, BOOLEAN);
DROP FUNCTION IF EXISTS public.claim_practice_hint_generation(UUID, TEXT, INTEGER, TEXT, BOOLEAN, TEXT);
DROP FUNCTION IF EXISTS public.claim_practice_hint_generation(UUID, TEXT, INTEGER, TEXT, BOOLEAN, TEXT, INTEGER);
DROP FUNCTION IF EXISTS public.record_practice_hint(UUID, TEXT, BOOLEAN, INTEGER, TEXT, JSONB);
DROP FUNCTION IF EXISTS public.record_practice_hint(UUID, TEXT, BOOLEAN, INTEGER, TEXT, JSONB, BOOLEAN, INTEGER, INTEGER, INTEGER);
DROP FUNCTION IF EXISTS public.record_practice_hint(UUID, TEXT, BOOLEAN, INTEGER, TEXT, JSONB, BOOLEAN, INTEGER, INTEGER, INTEGER, TEXT);
DROP FUNCTION IF EXISTS public.settle_prefetched_practice_hint(UUID, TEXT, TEXT, BOOLEAN, INTEGER, INTEGER, INTEGER, INTEGER);
DROP FUNCTION IF EXISTS public.settle_prefetched_practice_hint(UUID, TEXT, TEXT, BOOLEAN, INTEGER, INTEGER, INTEGER, INTEGER, INTEGER);
DROP FUNCTION IF EXISTS public.discard_prefetched_practice_hint(UUID, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.release_practice_hint_generation(UUID, TEXT);
DROP FUNCTION IF EXISTS public.release_practice_hint_generation(UUID, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.release_practice_hint_generation(UUID, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.prepare_practice_subscription_usage(UUID);

-- Reset usage only while holding the subscription row lock. A caller can then
-- call increment_usage in the same outer transaction; the lock remains held
-- until that outer transaction commits, so a stale Edge reset cannot erase it.
CREATE OR REPLACE FUNCTION public.prepare_practice_subscription_usage(
  p_user_id UUID
)
RETURNS TABLE(
  tier TEXT,
  monthly_messages_used INTEGER,
  daily_messages_used INTEGER,
  daily_reset_at TIMESTAMPTZ,
  monthly_reset_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub         public.subscriptions%ROWTYPE;
  v_now         TIMESTAMPTZ := now();
  v_month_start TIMESTAMPTZ;
  v_day_start   TIMESTAMPTZ;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'prepare_practice_subscription_usage: p_user_id is required';
  END IF;

  v_month_start := DATE_TRUNC('month', v_now AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  v_day_start := DATE_TRUNC('day', v_now AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';

  SELECT s.* INTO v_sub
  FROM public.subscriptions AS s
  WHERE s.user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    -- increment_usage historically no-ops on a missing row. Billing settlement
    -- must instead fail closed so it never reports did_charge=true without a row.
    RAISE EXCEPTION 'PRACTICE_SUBSCRIPTION_NOT_FOUND';
  END IF;

  -- Nullable reset timestamps are legacy-valid. Match the existing Edge
  -- semantics: NULL means the window has never been reset.
  IF v_sub.monthly_reset_at IS NULL
     OR v_sub.monthly_reset_at < v_month_start THEN
    UPDATE public.subscriptions AS s
    SET monthly_messages_used = 0,
        monthly_reset_at = v_month_start
    WHERE s.user_id = p_user_id;
    v_sub.monthly_messages_used := 0;
    v_sub.monthly_reset_at := v_month_start;
  END IF;

  IF v_sub.daily_reset_at IS NULL
     OR v_sub.daily_reset_at < v_day_start THEN
    UPDATE public.subscriptions AS s
    SET daily_messages_used = 0,
        daily_reset_at = v_day_start
    WHERE s.user_id = p_user_id;
    v_sub.daily_messages_used := 0;
    v_sub.daily_reset_at := v_day_start;
  END IF;

  tier := v_sub.tier;
  monthly_messages_used := v_sub.monthly_messages_used;
  daily_messages_used := v_sub.daily_messages_used;
  daily_reset_at := v_sub.daily_reset_at;
  monthly_reset_at := v_sub.monthly_reset_at;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_practice_hint_generation(
  p_user_id    UUID,
  p_session_id TEXT,
  p_max_hints  INTEGER,
  p_request_id TEXT DEFAULT NULL,
  p_prefetch   BOOLEAN DEFAULT FALSE,
  p_generation_token TEXT DEFAULT NULL,
  p_expected_ai_count INTEGER DEFAULT NULL
)
RETURNS TABLE(
  current_hint_count INTEGER,
  replay BOOLEAN,
  stored_result JSONB,
  stored_charged BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.practice_chat_sessions%ROWTYPE;
  v_request public.practice_hint_requests%ROWTYPE;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'claim_practice_hint_generation: p_user_id is required';
  END IF;
  IF p_session_id IS NULL OR length(p_session_id) = 0 OR length(p_session_id) > 64 THEN
    RAISE EXCEPTION 'claim_practice_hint_generation: invalid p_session_id';
  END IF;
  IF p_max_hints IS NULL OR p_max_hints < 1 OR p_max_hints > 5 THEN
    RAISE EXCEPTION 'claim_practice_hint_generation: invalid p_max_hints';
  END IF;
  IF p_prefetch IS NULL THEN
    RAISE EXCEPTION 'claim_practice_hint_generation: invalid p_prefetch';
  END IF;
  IF p_request_id IS NOT NULL
     AND (length(p_request_id) = 0 OR length(p_request_id) > 64) THEN
    RAISE EXCEPTION 'claim_practice_hint_generation: invalid p_request_id';
  END IF;
  IF p_request_id = '__legacy_inflight__' THEN
    RAISE EXCEPTION 'claim_practice_hint_generation: invalid p_request_id';
  END IF;
  IF p_generation_token IS NOT NULL
     AND (length(p_generation_token) = 0 OR length(p_generation_token) > 64) THEN
    RAISE EXCEPTION 'claim_practice_hint_generation: invalid p_generation_token';
  END IF;
  IF p_expected_ai_count IS NOT NULL
     AND (p_expected_ai_count < 1 OR p_expected_ai_count > 20) THEN
    RAISE EXCEPTION 'claim_practice_hint_generation: invalid p_expected_ai_count';
  END IF;
  IF p_prefetch AND p_request_id IS NULL THEN
    RAISE EXCEPTION 'claim_practice_hint_generation: prefetch requires p_request_id';
  END IF;

  SELECT s.* INTO v_session
  FROM public.practice_chat_sessions AS s
  WHERE s.user_id = p_user_id
    AND s.session_id = p_session_id
  FOR UPDATE;

  IF NOT FOUND OR NOT v_session.charged OR v_session.ai_count < 1 THEN
    RAISE EXCEPTION 'PRACTICE_SESSION_NOT_STARTED';
  END IF;

  -- Exact completed snapshots are immutable and replay before mutable gates.
  IF p_request_id IS NOT NULL THEN
    SELECT r.* INTO v_request
    FROM public.practice_hint_requests AS r
    WHERE r.user_id = p_user_id
      AND r.session_id = p_session_id
      AND r.request_id = p_request_id
    FOR UPDATE;

    IF FOUND AND v_request.state IN ('prefetched', 'settled') THEN
      current_hint_count := v_session.hint_count;
      replay := TRUE;
      stored_result := v_request.result;
      stored_charged := v_request.charged;
      RETURN NEXT;
      RETURN;
    END IF;

    IF FOUND
       AND v_request.state = 'generating'
       AND v_session.hint_generation_started_at IS NOT NULL
       AND v_session.hint_generation_started_at > now() - interval '2 minutes' THEN
      RAISE EXCEPTION 'PRACTICE_HINT_IN_FLIGHT';
    END IF;
  END IF;

  -- Completed exact-request replay wins above. A fresh generation must bind
  -- the client transcript version while the authoritative session row is
  -- locked, closing check/claim races and lifecycle loss of client fences.
  IF p_expected_ai_count IS NOT NULL
     AND p_expected_ai_count <> v_session.ai_count THEN
    RAISE EXCEPTION 'PRACTICE_HINT_STALE';
  END IF;

  IF v_session.practice_mode NOT IN ('beginner', 'game') THEN
    RAISE EXCEPTION 'PRACTICE_HINT_BEGINNER_ONLY';
  END IF;
  IF v_session.hint_count >= p_max_hints THEN
    RAISE EXCEPTION 'PRACTICE_HINT_LIMIT';
  END IF;

  -- A legacy Edge sends no generation token, so it cannot safely fence a
  -- stale worker. During migration -> Edge rollout it waits rather than taking
  -- over. The token-aware Edge may take over and makes late legacy writes fail.
  IF p_generation_token IS NULL AND EXISTS (
    SELECT 1
    FROM public.practice_hint_requests AS r
    WHERE r.user_id = p_user_id
      AND r.session_id = p_session_id
      AND r.state = 'generating'
  ) THEN
    RAISE EXCEPTION 'PRACTICE_HINT_IN_FLIGHT';
  END IF;

  IF p_prefetch THEN
    -- An old turn's unconsumed snapshot can never be valid for this turn.
    DELETE FROM public.practice_hint_requests AS r
    WHERE r.user_id = p_user_id
      AND r.session_id = p_session_id
      AND r.state = 'prefetched'
      AND r.claimed_ai_count < v_session.ai_count;

    IF EXISTS (
      SELECT 1
      FROM public.practice_hint_requests AS r
      WHERE r.user_id = p_user_id
        AND r.session_id = p_session_id
        AND r.state = 'prefetched'
    ) THEN
      RAISE EXCEPTION 'PRACTICE_HINT_PREFETCH_PENDING';
    END IF;
  END IF;

  IF v_session.hint_generation_started_at IS NOT NULL
     AND v_session.hint_generation_started_at > now() - interval '2 minutes' THEN
    RAISE EXCEPTION 'PRACTICE_HINT_IN_FLIGHT';
  END IF;

  -- Fence any stale owner (including the migration placeholder) before taking
  -- the global latch. Late workers then fail exact-row ownership at record time.
  DELETE FROM public.practice_hint_requests AS r
  WHERE r.user_id = p_user_id
    AND r.session_id = p_session_id
    AND r.state = 'generating';

  UPDATE public.practice_chat_sessions AS s
  SET hint_generation_started_at = now(),
      updated_at = now()
  WHERE s.user_id = p_user_id
    AND s.session_id = p_session_id;

  IF p_request_id IS NOT NULL THEN
    INSERT INTO public.practice_hint_requests (
      user_id,
      session_id,
      request_id,
      generation_token,
      claimed_ai_count,
      is_prefetch,
      state,
      result,
      charged,
      created_at,
      updated_at
    ) VALUES (
      p_user_id,
      p_session_id,
      p_request_id,
      p_generation_token,
      v_session.ai_count,
      p_prefetch,
      'generating',
      NULL,
      FALSE,
      now(),
      now()
    )
    ON CONFLICT (user_id, session_id, request_id) DO UPDATE
    SET generation_token = p_generation_token,
        claimed_ai_count = v_session.ai_count,
        is_prefetch = p_prefetch,
        state = 'generating',
        result = NULL,
        charged = FALSE,
        updated_at = now();
  ELSE
    INSERT INTO public.practice_hint_requests (
      user_id,
      session_id,
      request_id,
      generation_token,
      claimed_ai_count,
      is_prefetch,
      state,
      result,
      charged,
      created_at,
      updated_at
    ) VALUES (
      p_user_id,
      p_session_id,
      '__legacy_inflight__',
      p_generation_token,
      v_session.ai_count,
      FALSE,
      'generating',
      NULL,
      FALSE,
      now(),
      now()
    )
    ON CONFLICT (user_id, session_id, request_id) DO UPDATE
    SET generation_token = p_generation_token,
        claimed_ai_count = v_session.ai_count,
        is_prefetch = FALSE,
        state = 'generating',
        result = NULL,
        charged = FALSE,
        updated_at = now();
  END IF;

  current_hint_count := v_session.hint_count;
  replay := FALSE;
  stored_result := NULL;
  stored_charged := NULL;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_practice_hint(
  p_user_id       UUID,
  p_session_id    TEXT,
  p_charge_quota  BOOLEAN,
  p_max_hints     INTEGER,
  p_request_id    TEXT DEFAULT NULL,
  p_result        JSONB DEFAULT NULL,
  p_charged       BOOLEAN DEFAULT TRUE,
  p_monthly_limit INTEGER DEFAULT NULL,
  p_daily_limit   INTEGER DEFAULT NULL,
  p_max_replies   INTEGER DEFAULT NULL,
  p_generation_token TEXT DEFAULT NULL
)
RETURNS TABLE(
  new_hint_count INTEGER,
  did_charge BOOLEAN,
  stored_result JSONB,
  stored_charged BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session          public.practice_chat_sessions%ROWTYPE;
  v_request          public.practice_hint_requests%ROWTYPE;
  v_usage            RECORD;
  v_has_owned_worker BOOLEAN := FALSE;
  v_legacy_claimed_ai_count INTEGER;
  v_next_hint_count  INTEGER;
  v_final_result     JSONB;
  v_monthly_used     INTEGER;
  v_daily_used       INTEGER;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'record_practice_hint: p_user_id is required';
  END IF;
  IF p_session_id IS NULL OR length(p_session_id) = 0 OR length(p_session_id) > 64 THEN
    RAISE EXCEPTION 'record_practice_hint: invalid p_session_id';
  END IF;
  IF p_charge_quota IS NULL OR p_charged IS NULL THEN
    RAISE EXCEPTION 'record_practice_hint: invalid charge flags';
  END IF;
  IF p_charge_quota = TRUE AND p_charged = FALSE THEN
    RAISE EXCEPTION 'record_practice_hint: unconsumed prefetch cannot charge quota';
  END IF;
  IF p_max_hints IS NULL OR p_max_hints < 1 OR p_max_hints > 5 THEN
    RAISE EXCEPTION 'record_practice_hint: invalid p_max_hints';
  END IF;
  IF p_max_replies IS NOT NULL AND (p_max_replies < 1 OR p_max_replies > 20) THEN
    RAISE EXCEPTION 'record_practice_hint: invalid p_max_replies';
  END IF;
  IF (p_monthly_limit IS NULL) <> (p_daily_limit IS NULL)
     OR p_monthly_limit IS NOT NULL AND p_monthly_limit < 1
     OR p_daily_limit IS NOT NULL AND p_daily_limit < 1 THEN
    RAISE EXCEPTION 'record_practice_hint: invalid quota limits';
  END IF;
  IF p_request_id IS NOT NULL
     AND (length(p_request_id) = 0 OR length(p_request_id) > 64) THEN
    RAISE EXCEPTION 'record_practice_hint: invalid p_request_id';
  END IF;
  IF p_request_id = '__legacy_inflight__' THEN
    RAISE EXCEPTION 'record_practice_hint: invalid p_request_id';
  END IF;
  IF p_generation_token IS NOT NULL
     AND (length(p_generation_token) = 0 OR length(p_generation_token) > 64) THEN
    RAISE EXCEPTION 'record_practice_hint: invalid p_generation_token';
  END IF;
  IF p_charged = FALSE AND (
    p_request_id IS NULL
    OR p_result IS NULL
    OR jsonb_typeof(p_result) <> 'object'
  ) THEN
    RAISE EXCEPTION 'record_practice_hint: prefetch requires request and result';
  END IF;
  IF p_charged = TRUE
     AND p_request_id IS NOT NULL
     AND (p_result IS NULL OR jsonb_typeof(p_result) <> 'object') THEN
    RAISE EXCEPTION 'record_practice_hint: formal request requires result';
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

  IF p_request_id IS NOT NULL THEN
    SELECT r.* INTO v_request
    FROM public.practice_hint_requests AS r
    WHERE r.user_id = p_user_id
      AND r.session_id = p_session_id
      AND r.request_id = p_request_id
    FOR UPDATE;

    -- A late worker may share the logical request id after a stale takeover.
    -- Fence it before even the duplicate-return branches; otherwise an old
    -- Edge could ignore stored_result and expose its losing provider output.
    IF FOUND
       AND v_request.generation_token IS DISTINCT FROM p_generation_token THEN
      RAISE EXCEPTION 'PRACTICE_HINT_OWNER_MISMATCH';
    END IF;

    -- Duplicate workers return the first authoritative snapshot before caps or
    -- quota. A prefetched row is duplicate only for another prefetch record;
    -- formal consumption must use settle_prefetched_practice_hint.
    IF FOUND AND v_request.state = 'settled' THEN
      new_hint_count := v_session.hint_count;
      did_charge := FALSE;
      stored_result := v_request.result;
      stored_charged := TRUE;
      RETURN NEXT;
      RETURN;
    END IF;
    IF FOUND AND v_request.state = 'prefetched' AND p_charged = FALSE THEN
      new_hint_count := v_session.hint_count;
      did_charge := FALSE;
      stored_result := v_request.result;
      stored_charged := FALSE;
      RETURN NEXT;
      RETURN;
    END IF;
    IF FOUND AND v_request.state = 'prefetched' AND p_charged = TRUE THEN
      RAISE EXCEPTION 'PRACTICE_HINT_STATE_MISMATCH';
    END IF;

    IF NOT FOUND THEN
      -- Only a worker already in flight when this migration landed may lack an
      -- exact row. Exchange the internal placeholder for its formal request.
      IF p_charged = FALSE THEN
        RAISE EXCEPTION 'PRACTICE_HINT_NOT_CLAIMED';
      END IF;
      IF p_generation_token IS NOT NULL THEN
        RAISE EXCEPTION 'PRACTICE_HINT_NOT_CLAIMED';
      END IF;

      DELETE FROM public.practice_hint_requests AS r
      WHERE r.user_id = p_user_id
        AND r.session_id = p_session_id
        AND r.request_id = '__legacy_inflight__'
        AND r.state = 'generating'
        AND r.generation_token IS NULL
      RETURNING r.claimed_ai_count INTO v_legacy_claimed_ai_count;

      IF v_legacy_claimed_ai_count IS NULL THEN
        RAISE EXCEPTION 'PRACTICE_HINT_NOT_CLAIMED';
      END IF;
      IF v_legacy_claimed_ai_count <> v_session.ai_count THEN
        RAISE EXCEPTION 'PRACTICE_HINT_STALE';
      END IF;

      INSERT INTO public.practice_hint_requests (
        user_id,
        session_id,
        request_id,
        generation_token,
        claimed_ai_count,
        is_prefetch,
        state,
        result,
        charged
      ) VALUES (
        p_user_id,
        p_session_id,
        p_request_id,
        NULL,
        v_legacy_claimed_ai_count,
        FALSE,
        'generating',
        NULL,
        FALSE
      )
      RETURNING * INTO v_request;
    END IF;

    IF v_request.state <> 'generating' THEN
      RAISE EXCEPTION 'PRACTICE_HINT_STATE_MISMATCH';
    END IF;
    IF v_request.is_prefetch IS DISTINCT FROM (NOT p_charged) THEN
      RAISE EXCEPTION 'PRACTICE_HINT_STATE_MISMATCH';
    END IF;
    IF v_request.claimed_ai_count <> v_session.ai_count THEN
      RAISE EXCEPTION 'PRACTICE_HINT_STALE';
    END IF;
  ELSE
    -- Legacy no-request-id path: never clear a latch owned by a newer exact row.
    IF p_charged = FALSE THEN
      RAISE EXCEPTION 'PRACTICE_HINT_NOT_CLAIMED';
    END IF;
    SELECT EXISTS (
      SELECT 1
      FROM public.practice_hint_requests AS r
      WHERE r.user_id = p_user_id
        AND r.session_id = p_session_id
        AND r.state = 'generating'
        AND r.request_id <> '__legacy_inflight__'
    ) INTO v_has_owned_worker;
    IF v_has_owned_worker OR v_session.hint_generation_started_at IS NULL THEN
      RAISE EXCEPTION 'PRACTICE_HINT_NOT_CLAIMED';
    END IF;

    SELECT r.claimed_ai_count INTO v_legacy_claimed_ai_count
    FROM public.practice_hint_requests AS r
    WHERE r.user_id = p_user_id
      AND r.session_id = p_session_id
      AND r.request_id = '__legacy_inflight__'
      AND r.state = 'generating'
      AND r.generation_token IS NOT DISTINCT FROM p_generation_token
    FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'PRACTICE_HINT_NOT_CLAIMED';
    END IF;
    IF v_legacy_claimed_ai_count <> v_session.ai_count THEN
      RAISE EXCEPTION 'PRACTICE_HINT_STALE';
    END IF;
  END IF;

  IF v_session.hint_count >= p_max_hints THEN
    RAISE EXCEPTION 'PRACTICE_HINT_LIMIT';
  END IF;
  IF p_max_replies IS NOT NULL AND v_session.ai_count >= p_max_replies THEN
    RAISE EXCEPTION 'PRACTICE_SESSION_COMPLETE';
  END IF;

  IF p_charged = FALSE THEN
    UPDATE public.practice_hint_requests AS r
    SET state = 'prefetched',
        result = p_result,
        charged = FALSE,
        updated_at = now()
    WHERE r.user_id = p_user_id
      AND r.session_id = p_session_id
      AND r.request_id = p_request_id
      AND r.state = 'generating';

    UPDATE public.practice_chat_sessions AS s
    SET hint_generation_started_at = NULL,
        updated_at = now()
    WHERE s.user_id = p_user_id
      AND s.session_id = p_session_id;

    new_hint_count := v_session.hint_count;
    did_charge := FALSE;
    stored_result := p_result;
    stored_charged := FALSE;
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT * INTO v_usage
  FROM public.prepare_practice_subscription_usage(p_user_id);

  did_charge := p_charge_quota;
  IF did_charge THEN
    PERFORM public.increment_usage(
      p_user_id,
      1,
      p_monthly_limit,
      p_daily_limit
    );
  END IF;

  v_next_hint_count := v_session.hint_count + 1;
  v_monthly_used := v_usage.monthly_messages_used + CASE WHEN did_charge THEN 1 ELSE 0 END;
  v_daily_used := v_usage.daily_messages_used + CASE WHEN did_charge THEN 1 ELSE 0 END;
  v_final_result := COALESCE(p_result, '{}'::jsonb) || jsonb_build_object(
    'costDeducted', CASE WHEN did_charge THEN 1 ELSE 0 END,
    'hintUsedCount', v_next_hint_count
  );
  IF p_monthly_limit IS NOT NULL THEN
    v_final_result := v_final_result || jsonb_build_object(
      'monthlyRemaining', GREATEST(0, p_monthly_limit - v_monthly_used),
      'dailyRemaining', GREATEST(0, p_daily_limit - v_daily_used)
    );
  END IF;

  IF p_request_id IS NOT NULL THEN
    UPDATE public.practice_hint_requests AS r
    SET state = 'settled',
        result = v_final_result,
        charged = TRUE,
        updated_at = now()
    WHERE r.user_id = p_user_id
      AND r.session_id = p_session_id
      AND r.request_id = p_request_id
      AND r.state = 'generating';
  ELSE
    DELETE FROM public.practice_hint_requests AS r
    WHERE r.user_id = p_user_id
      AND r.session_id = p_session_id
      AND r.request_id = '__legacy_inflight__'
      AND r.state = 'generating';
  END IF;

  UPDATE public.practice_chat_sessions AS s
  SET hint_count = v_next_hint_count,
      hint_generation_started_at = NULL,
      last_hint_request_id = p_request_id,
      last_hint_result = CASE
        WHEN p_request_id IS NULL THEN NULL
        ELSE v_final_result
      END,
      updated_at = now()
  WHERE s.user_id = p_user_id
    AND s.session_id = p_session_id;

  new_hint_count := v_next_hint_count;
  stored_result := CASE WHEN p_request_id IS NULL THEN NULL ELSE v_final_result END;
  stored_charged := TRUE;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.settle_prefetched_practice_hint(
  p_user_id       UUID,
  p_session_id    TEXT,
  p_request_id    TEXT,
  p_charge_quota  BOOLEAN,
  p_max_hints     INTEGER,
  p_max_replies   INTEGER,
  p_monthly_limit INTEGER,
  p_daily_limit   INTEGER,
  p_expected_ai_count INTEGER DEFAULT NULL
)
RETURNS TABLE(
  new_hint_count INTEGER,
  did_charge BOOLEAN,
  stored_result JSONB,
  stored_charged BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session         public.practice_chat_sessions%ROWTYPE;
  v_request         public.practice_hint_requests%ROWTYPE;
  v_usage           RECORD;
  v_next_hint_count INTEGER;
  v_final_result    JSONB;
  v_monthly_used    INTEGER;
  v_daily_used      INTEGER;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'settle_prefetched_practice_hint: p_user_id is required';
  END IF;
  IF p_session_id IS NULL OR length(p_session_id) = 0 OR length(p_session_id) > 64 THEN
    RAISE EXCEPTION 'settle_prefetched_practice_hint: invalid p_session_id';
  END IF;
  IF p_request_id IS NULL OR length(p_request_id) = 0 OR length(p_request_id) > 64
     OR p_request_id = '__legacy_inflight__' THEN
    RAISE EXCEPTION 'settle_prefetched_practice_hint: invalid p_request_id';
  END IF;
  IF p_charge_quota IS NULL THEN
    RAISE EXCEPTION 'settle_prefetched_practice_hint: invalid p_charge_quota';
  END IF;
  IF p_max_hints IS NULL OR p_max_hints < 1 OR p_max_hints > 5 THEN
    RAISE EXCEPTION 'settle_prefetched_practice_hint: invalid p_max_hints';
  END IF;
  IF p_max_replies IS NULL OR p_max_replies < 1 OR p_max_replies > 20 THEN
    RAISE EXCEPTION 'settle_prefetched_practice_hint: invalid p_max_replies';
  END IF;
  IF p_monthly_limit IS NULL OR p_monthly_limit < 1
     OR p_daily_limit IS NULL OR p_daily_limit < 1 THEN
    RAISE EXCEPTION 'settle_prefetched_practice_hint: invalid quota limits';
  END IF;
  IF p_expected_ai_count IS NOT NULL
     AND (p_expected_ai_count < 1 OR p_expected_ai_count > 20) THEN
    RAISE EXCEPTION 'settle_prefetched_practice_hint: invalid p_expected_ai_count';
  END IF;

  SELECT s.* INTO v_session
  FROM public.practice_chat_sessions AS s
  WHERE s.user_id = p_user_id
    AND s.session_id = p_session_id
  FOR UPDATE;

  IF NOT FOUND OR NOT v_session.charged OR v_session.ai_count < 1 THEN
    RAISE EXCEPTION 'PRACTICE_SESSION_NOT_STARTED';
  END IF;

  SELECT r.* INTO v_request
  FROM public.practice_hint_requests AS r
  WHERE r.user_id = p_user_id
    AND r.session_id = p_session_id
    AND r.request_id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PRACTICE_HINT_PREFETCH_NOT_FOUND';
  END IF;

  -- Retry replay must win even if mutable caps/quota changed after settlement.
  IF v_request.state = 'settled' THEN
    new_hint_count := v_session.hint_count;
    did_charge := FALSE;
    stored_result := v_request.result;
    stored_charged := TRUE;
    RETURN NEXT;
    RETURN;
  END IF;

  IF p_expected_ai_count IS NOT NULL
     AND p_expected_ai_count <> v_session.ai_count THEN
    RAISE EXCEPTION 'PRACTICE_HINT_STALE';
  END IF;

  IF v_request.state <> 'prefetched'
     OR NOT v_request.is_prefetch
     OR v_request.charged
     OR v_request.result IS NULL
     OR jsonb_typeof(v_request.result) <> 'object' THEN
    RAISE EXCEPTION 'PRACTICE_HINT_STATE_MISMATCH';
  END IF;
  IF v_request.claimed_ai_count <> v_session.ai_count THEN
    RAISE EXCEPTION 'PRACTICE_HINT_STALE';
  END IF;
  IF v_session.practice_mode NOT IN ('beginner', 'game') THEN
    RAISE EXCEPTION 'PRACTICE_HINT_BEGINNER_ONLY';
  END IF;
  IF v_session.hint_count >= p_max_hints THEN
    RAISE EXCEPTION 'PRACTICE_HINT_LIMIT';
  END IF;
  IF v_session.ai_count >= p_max_replies THEN
    RAISE EXCEPTION 'PRACTICE_SESSION_COMPLETE';
  END IF;

  SELECT * INTO v_usage
  FROM public.prepare_practice_subscription_usage(p_user_id);

  did_charge := p_charge_quota;
  IF did_charge THEN
    PERFORM public.increment_usage(
      p_user_id,
      1,
      p_monthly_limit,
      p_daily_limit
    );
  END IF;

  v_next_hint_count := v_session.hint_count + 1;
  v_monthly_used := v_usage.monthly_messages_used + CASE WHEN did_charge THEN 1 ELSE 0 END;
  v_daily_used := v_usage.daily_messages_used + CASE WHEN did_charge THEN 1 ELSE 0 END;
  v_final_result := v_request.result || jsonb_build_object(
    'costDeducted', CASE WHEN did_charge THEN 1 ELSE 0 END,
    'hintUsedCount', v_next_hint_count,
    'monthlyRemaining', GREATEST(0, p_monthly_limit - v_monthly_used),
    'dailyRemaining', GREATEST(0, p_daily_limit - v_daily_used)
  );

  UPDATE public.practice_hint_requests AS r
  SET state = 'settled',
      result = v_final_result,
      charged = TRUE,
      updated_at = now()
  WHERE r.user_id = p_user_id
    AND r.session_id = p_session_id
    AND r.request_id = p_request_id
    AND r.state = 'prefetched';

  UPDATE public.practice_chat_sessions AS s
  SET hint_count = v_next_hint_count,
      last_hint_request_id = p_request_id,
      last_hint_result = v_final_result,
      updated_at = now()
  WHERE s.user_id = p_user_id
    AND s.session_id = p_session_id;

  new_hint_count := v_next_hint_count;
  stored_result := v_final_result;
  stored_charged := TRUE;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.discard_prefetched_practice_hint(
  p_user_id    UUID,
  p_session_id TEXT,
  p_request_id TEXT
)
RETURNS TABLE(
  discarded BOOLEAN,
  replay BOOLEAN,
  stored_result JSONB,
  stored_charged BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.practice_chat_sessions%ROWTYPE;
  v_request public.practice_hint_requests%ROWTYPE;
  v_rows    INTEGER := 0;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'discard_prefetched_practice_hint: p_user_id is required';
  END IF;
  IF p_session_id IS NULL OR length(p_session_id) = 0 OR length(p_session_id) > 64 THEN
    RAISE EXCEPTION 'discard_prefetched_practice_hint: invalid p_session_id';
  END IF;
  IF p_request_id IS NULL OR length(p_request_id) = 0 OR length(p_request_id) > 64
     OR p_request_id = '__legacy_inflight__' THEN
    RAISE EXCEPTION 'discard_prefetched_practice_hint: invalid p_request_id';
  END IF;

  SELECT s.* INTO v_session
  FROM public.practice_chat_sessions AS s
  WHERE s.user_id = p_user_id
    AND s.session_id = p_session_id
  FOR UPDATE;

  IF NOT FOUND THEN
    discarded := FALSE;
    replay := FALSE;
    stored_result := NULL;
    stored_charged := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT r.* INTO v_request
  FROM public.practice_hint_requests AS r
  WHERE r.user_id = p_user_id
    AND r.session_id = p_session_id
    AND r.request_id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    discarded := FALSE;
    replay := FALSE;
    stored_result := NULL;
    stored_charged := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_request.state = 'settled' THEN
    discarded := FALSE;
    replay := TRUE;
    stored_result := v_request.result;
    stored_charged := TRUE;
    RETURN NEXT;
    RETURN;
  END IF;

  DELETE FROM public.practice_hint_requests AS r
  WHERE r.user_id = p_user_id
    AND r.session_id = p_session_id
    AND r.request_id = p_request_id
    AND r.is_prefetch = TRUE
    AND r.state IN ('generating', 'prefetched');
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows > 0 AND v_request.state = 'generating' THEN
    UPDATE public.practice_chat_sessions AS s
    SET hint_generation_started_at = NULL,
        updated_at = now()
    WHERE s.user_id = p_user_id
      AND s.session_id = p_session_id;
  END IF;

  discarded := v_rows > 0;
  replay := FALSE;
  stored_result := NULL;
  stored_charged := FALSE;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.release_practice_hint_generation(
  p_user_id    UUID,
  p_session_id TEXT,
  p_request_id TEXT DEFAULT NULL,
  p_generation_token TEXT DEFAULT NULL
)
RETURNS TABLE(released BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.practice_chat_sessions%ROWTYPE;
  v_rows    INTEGER := 0;
  v_had_latch BOOLEAN := FALSE;
  v_owner_remains BOOLEAN := FALSE;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'release_practice_hint_generation: p_user_id is required';
  END IF;
  IF p_session_id IS NULL OR length(p_session_id) = 0 OR length(p_session_id) > 64 THEN
    RAISE EXCEPTION 'release_practice_hint_generation: invalid p_session_id';
  END IF;
  IF p_request_id IS NOT NULL
     AND (length(p_request_id) = 0 OR length(p_request_id) > 64) THEN
    RAISE EXCEPTION 'release_practice_hint_generation: invalid p_request_id';
  END IF;
  IF p_request_id = '__legacy_inflight__' THEN
    RAISE EXCEPTION 'release_practice_hint_generation: invalid p_request_id';
  END IF;
  IF p_generation_token IS NOT NULL
     AND (length(p_generation_token) = 0 OR length(p_generation_token) > 64) THEN
    RAISE EXCEPTION 'release_practice_hint_generation: invalid p_generation_token';
  END IF;

  SELECT s.* INTO v_session
  FROM public.practice_chat_sessions AS s
  WHERE s.user_id = p_user_id
    AND s.session_id = p_session_id
  FOR UPDATE;

  IF NOT FOUND THEN
    released := FALSE;
    RETURN NEXT;
    RETURN;
  END IF;
  v_had_latch := v_session.hint_generation_started_at IS NOT NULL;

  IF p_request_id IS NOT NULL THEN
    DELETE FROM public.practice_hint_requests AS r
    WHERE r.user_id = p_user_id
      AND r.session_id = p_session_id
      AND r.request_id = p_request_id
      AND r.state = 'generating'
      AND r.generation_token IS NOT DISTINCT FROM p_generation_token;
    GET DIAGNOSTICS v_rows = ROW_COUNT;

    -- An old request that no longer owns a generating row must not clear the
    -- latch of a newer request.
    IF v_rows > 0 THEN
      UPDATE public.practice_chat_sessions AS s
      SET hint_generation_started_at = NULL,
          updated_at = now()
      WHERE s.user_id = p_user_id
        AND s.session_id = p_session_id;
    END IF;
    released := v_rows > 0;
    RETURN NEXT;
    RETURN;
  END IF;

  -- A legacy two-argument Edge has a NULL token and may delete only a NULL-token
  -- owner. After token-aware takeover its late release matches nothing and
  -- therefore cannot clear the new latch. A token-aware no-request-id path uses
  -- the same internal marker with its non-NULL token.
  DELETE FROM public.practice_hint_requests AS r
  WHERE r.user_id = p_user_id
    AND r.session_id = p_session_id
    AND r.state = 'generating'
    AND r.generation_token IS NOT DISTINCT FROM p_generation_token;
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  SELECT EXISTS (
    SELECT 1
    FROM public.practice_hint_requests AS r
    WHERE r.user_id = p_user_id
      AND r.session_id = p_session_id
      AND r.state = 'generating'
  ) INTO v_owner_remains;

  IF v_rows > 0 OR (v_had_latch AND NOT v_owner_remains) THEN
    UPDATE public.practice_chat_sessions AS s
    SET hint_generation_started_at = NULL,
        updated_at = now()
    WHERE s.user_id = p_user_id
      AND s.session_id = p_session_id;
  END IF;

  released := v_rows > 0 OR (v_had_latch AND NOT v_owner_remains);
  RETURN NEXT;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.prepare_practice_subscription_usage(UUID)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_practice_subscription_usage(UUID)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.claim_practice_hint_generation(UUID, TEXT, INTEGER, TEXT, BOOLEAN, TEXT, INTEGER)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_practice_hint_generation(UUID, TEXT, INTEGER, TEXT, BOOLEAN, TEXT, INTEGER)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.record_practice_hint(UUID, TEXT, BOOLEAN, INTEGER, TEXT, JSONB, BOOLEAN, INTEGER, INTEGER, INTEGER, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_practice_hint(UUID, TEXT, BOOLEAN, INTEGER, TEXT, JSONB, BOOLEAN, INTEGER, INTEGER, INTEGER, TEXT)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.settle_prefetched_practice_hint(UUID, TEXT, TEXT, BOOLEAN, INTEGER, INTEGER, INTEGER, INTEGER, INTEGER)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.settle_prefetched_practice_hint(UUID, TEXT, TEXT, BOOLEAN, INTEGER, INTEGER, INTEGER, INTEGER, INTEGER)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.discard_prefetched_practice_hint(UUID, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.discard_prefetched_practice_hint(UUID, TEXT, TEXT)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.release_practice_hint_generation(UUID, TEXT, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.release_practice_hint_generation(UUID, TEXT, TEXT, TEXT)
  TO service_role;

NOTIFY pgrst, 'reload schema';
