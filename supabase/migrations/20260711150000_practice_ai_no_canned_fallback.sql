-- practice Hint/Debrief generated-only contract (2026-07-11)
--
-- * Debrief failures release their token-fenced latch and never persist canned text.
-- * Every logical Debrief requestId remains replayable for the whole session;
--   A -> B -> A cannot recount or let a late worker overwrite either result.
-- * Applied Hint decisions are resolved from the settled, charged server snapshot.

ALTER TABLE public.practice_chat_sessions
  ADD COLUMN IF NOT EXISTS last_debrief_generation_token TEXT,
  ADD COLUMN IF NOT EXISTS debrief_request_ledger JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS hint_generation_owner_token TEXT;

-- Re-applying this still-unshipped migration after an earlier local revision
-- must first remove the old three-field validator. Existing reservations from
-- that revision were pre-counted, so they are normalized to counted=true below.
ALTER TABLE public.practice_chat_sessions
  DROP CONSTRAINT IF EXISTS practice_chat_sessions_debrief_request_ledger_check;

CREATE OR REPLACE FUNCTION public.is_valid_practice_debrief_request_ledger(
  p_ledger JSONB
)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN jsonb_typeof(p_ledger) IS DISTINCT FROM 'object' THEN FALSE
    WHEN (SELECT count(*) FROM jsonb_each(p_ledger)) > 3 THEN FALSE
    ELSE NOT EXISTS (
      SELECT 1
      FROM jsonb_each(p_ledger) AS entry(request_id, payload)
      WHERE length(entry.request_id) NOT BETWEEN 1 AND 64
        OR jsonb_typeof(entry.payload) IS DISTINCT FROM 'object'
        OR CASE
          WHEN jsonb_typeof(entry.payload) = 'object'
            THEN (SELECT count(*) FROM jsonb_each(entry.payload)) <> 4
          ELSE TRUE
        END
        OR NOT (entry.payload ?& ARRAY[
          'result',
          'started_at',
          'generation_token',
          'counted'
        ])
        OR (
          entry.payload -> 'result' = 'null'::jsonb
          OR jsonb_typeof(entry.payload -> 'result') = 'object'
        ) IS DISTINCT FROM TRUE
        OR (
          entry.payload -> 'started_at' = 'null'::jsonb
          OR jsonb_typeof(entry.payload -> 'started_at') = 'string'
        ) IS DISTINCT FROM TRUE
        OR (
          entry.payload -> 'generation_token' = 'null'::jsonb
          OR (
            jsonb_typeof(entry.payload -> 'generation_token') = 'string'
            AND length(entry.payload ->> 'generation_token') BETWEEN 1 AND 64
          )
        ) IS DISTINCT FROM TRUE
        OR jsonb_typeof(entry.payload -> 'counted') IS DISTINCT FROM 'boolean'
        OR (
          entry.payload -> 'started_at' <> 'null'::jsonb
          AND entry.payload -> 'generation_token' = 'null'::jsonb
        )
        OR (
          entry.payload -> 'result' <> 'null'::jsonb
          AND entry.payload -> 'started_at' <> 'null'::jsonb
        )
        OR (
          entry.payload -> 'result' <> 'null'::jsonb
          AND entry.payload -> 'counted' IS DISTINCT FROM 'true'::jsonb
        )
        OR (
          entry.payload -> 'counted' = 'false'::jsonb
          AND (
            entry.payload -> 'result' <> 'null'::jsonb
            OR entry.payload -> 'started_at' = 'null'::jsonb
            OR entry.payload -> 'generation_token' = 'null'::jsonb
          )
        )
    )
  END
$$;

-- The previous single-slot replay state is the only historical requestId that
-- can be recovered. Backfill it before enforcing the bounded ledger shape.
-- A legacy active row without a generation token is released, never trusted as
-- an owner, so an old null-token worker cannot resurrect a result.
UPDATE public.practice_chat_sessions AS s
SET debrief_request_ledger = s.debrief_request_ledger || jsonb_build_object(
      s.last_debrief_request_id,
      jsonb_build_object(
        'result', s.last_debrief_result,
        'started_at', CASE
          WHEN s.last_debrief_generation_token IS NULL THEN NULL
          ELSE s.last_debrief_started_at
        END,
        'generation_token', s.last_debrief_generation_token,
        'counted', TRUE
      )
    )
WHERE s.last_debrief_request_id IS NOT NULL
  AND NOT s.debrief_request_ledger ? s.last_debrief_request_id;

-- A previous local revision stored three-field entries and incremented count at
-- claim time. Mark only those legacy-shaped entries as already counted.
UPDATE public.practice_chat_sessions AS s
SET debrief_request_ledger = (
      SELECT jsonb_object_agg(
        entry.request_id,
        CASE
          WHEN jsonb_typeof(entry.payload) = 'object'
               AND NOT (entry.payload ? 'counted')
            THEN entry.payload || jsonb_build_object('counted', TRUE)
          ELSE entry.payload
        END
      )
      FROM jsonb_each(s.debrief_request_ledger) AS entry(request_id, payload)
    )
WHERE jsonb_typeof(s.debrief_request_ledger) = 'object'
  AND EXISTS (
    SELECT 1
    FROM jsonb_each(s.debrief_request_ledger) AS entry(request_id, payload)
    WHERE jsonb_typeof(entry.payload) = 'object'
      AND NOT (entry.payload ? 'counted')
  );

-- Unsafe settled Hint snapshots already consumed one hint slot. Keep that
-- reservation durable while a token-fenced worker replaces only the payload.
ALTER TABLE public.practice_hint_requests
  ADD COLUMN IF NOT EXISTS legacy_replacement_pending BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS legacy_replacement_generation_token TEXT,
  ADD COLUMN IF NOT EXISTS legacy_replacement_started_at TIMESTAMPTZ;

-- The shared Hint latch needs its own owner token because normal generation
-- rows and legacy replacement sidecars live in different state shapes. Drain
-- any pre-token legacy worker at migration time; every post-migration claim is
-- fail-closed unless it can bind a non-null token to the session latch.
UPDATE public.practice_chat_sessions AS s
SET hint_generation_owner_token = (
      SELECT r.generation_token
      FROM public.practice_hint_requests AS r
      WHERE r.user_id = s.user_id
        AND r.session_id = s.session_id
        AND r.state = 'generating'
        AND r.generation_token IS NOT NULL
      ORDER BY r.updated_at DESC
      LIMIT 1
    )
WHERE s.hint_generation_started_at IS NOT NULL;

UPDATE public.practice_chat_sessions AS s
SET hint_generation_owner_token = (
      SELECT r.legacy_replacement_generation_token
      FROM public.practice_hint_requests AS r
      WHERE r.user_id = s.user_id
        AND r.session_id = s.session_id
        AND r.legacy_replacement_pending = TRUE
        AND r.legacy_replacement_started_at IS NOT NULL
        AND r.legacy_replacement_generation_token IS NOT NULL
      ORDER BY r.updated_at DESC
      LIMIT 1
    )
WHERE s.hint_generation_started_at IS NOT NULL
  AND s.hint_generation_owner_token IS NULL;

-- Keep at most the row that owns the recovered session token. Ambiguous or
-- tokenless in-flight work is drained instead of being allowed to write late.
DELETE FROM public.practice_hint_requests AS r
USING public.practice_chat_sessions AS s
WHERE r.user_id = s.user_id
  AND r.session_id = s.session_id
  AND r.state = 'generating'
  AND (
    s.hint_generation_owner_token IS NULL
    OR r.generation_token IS DISTINCT FROM s.hint_generation_owner_token
  );

UPDATE public.practice_hint_requests AS r
SET legacy_replacement_started_at = NULL,
    updated_at = now()
FROM public.practice_chat_sessions AS s
WHERE r.user_id = s.user_id
  AND r.session_id = s.session_id
  AND r.legacy_replacement_pending = TRUE
  AND r.legacy_replacement_started_at IS NOT NULL
  AND (
    s.hint_generation_owner_token IS NULL
    OR r.legacy_replacement_generation_token IS DISTINCT FROM
      s.hint_generation_owner_token
  );

UPDATE public.practice_chat_sessions AS s
SET hint_generation_started_at = NULL,
    hint_generation_owner_token = NULL,
    updated_at = now()
WHERE s.hint_generation_started_at IS NOT NULL
  AND s.hint_generation_owner_token IS NULL;

UPDATE public.practice_chat_sessions AS s
SET hint_generation_owner_token = NULL,
    updated_at = now()
WHERE s.hint_generation_started_at IS NULL
  AND s.hint_generation_owner_token IS NOT NULL;

-- Existing normal record/release RPCs already clear the timestamp. Centralize
-- the companion token cleanup so every successful latch release preserves the
-- strict nullability invariant without touching any request owner row.
CREATE OR REPLACE FUNCTION public.clear_practice_hint_owner_token()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.hint_generation_started_at IS NULL THEN
    NEW.hint_generation_owner_token := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS clear_practice_hint_owner_token
  ON public.practice_chat_sessions;
CREATE TRIGGER clear_practice_hint_owner_token
BEFORE INSERT OR UPDATE OF hint_generation_started_at
ON public.practice_chat_sessions
FOR EACH ROW
EXECUTE FUNCTION public.clear_practice_hint_owner_token();

ALTER TABLE public.practice_chat_sessions
  DROP CONSTRAINT IF EXISTS practice_chat_sessions_hint_generation_owner_check;
ALTER TABLE public.practice_chat_sessions
  ADD CONSTRAINT practice_chat_sessions_hint_generation_owner_check
  CHECK (
    (
      hint_generation_started_at IS NULL
      AND hint_generation_owner_token IS NULL
    )
    OR (
      hint_generation_started_at IS NOT NULL
      AND hint_generation_owner_token IS NOT NULL
      AND length(hint_generation_owner_token) BETWEEN 1 AND 64
    )
  );

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'practice_chat_sessions_debrief_generation_token_check'
      AND conrelid = 'public.practice_chat_sessions'::regclass
  ) THEN
    ALTER TABLE public.practice_chat_sessions
      ADD CONSTRAINT practice_chat_sessions_debrief_generation_token_check
      CHECK (
        last_debrief_generation_token IS NULL
        OR length(last_debrief_generation_token) BETWEEN 1 AND 64
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'practice_chat_sessions_debrief_request_ledger_check'
      AND conrelid = 'public.practice_chat_sessions'::regclass
  ) THEN
    ALTER TABLE public.practice_chat_sessions
      ADD CONSTRAINT practice_chat_sessions_debrief_request_ledger_check
      CHECK (
        public.is_valid_practice_debrief_request_ledger(
          debrief_request_ledger
        )
      );
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'practice_hint_requests_legacy_replacement_check'
      AND conrelid = 'public.practice_hint_requests'::regclass
  ) THEN
    ALTER TABLE public.practice_hint_requests
      ADD CONSTRAINT practice_hint_requests_legacy_replacement_check
      CHECK (
        (
          legacy_replacement_pending = FALSE
          AND legacy_replacement_generation_token IS NULL
          AND legacy_replacement_started_at IS NULL
        )
        OR (
          legacy_replacement_pending = TRUE
          AND state = 'settled'
          AND charged = TRUE
          AND result IS NOT NULL
          AND jsonb_typeof(result) = 'object'
          AND legacy_replacement_generation_token IS NOT NULL
          AND length(legacy_replacement_generation_token) BETWEEN 1 AND 64
        )
      ) NOT VALID;
  END IF;

  -- NOT VALID preserves old snapshots for safe, on-demand replacement while
  -- enforcing generated-only payloads for every new prefetch/settlement write.
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'practice_hint_requests_generated_only_result_check'
      AND conrelid = 'public.practice_hint_requests'::regclass
  ) THEN
    ALTER TABLE public.practice_hint_requests
      ADD CONSTRAINT practice_hint_requests_generated_only_result_check
      CHECK (
        state = 'generating'
        OR legacy_replacement_pending = TRUE
        OR (
          result ->> 'generationSource' IS NOT DISTINCT FROM 'model'
          AND result -> 'fallbackUsed' IS NOT DISTINCT FROM 'false'::jsonb
        )
      ) NOT VALID;
  END IF;
END
$$;

-- Rebind normal Hint generation to the same token-fenced session latch used by
-- legacy snapshot replacement. This intentionally rejects the old NULL-token
-- Edge after the migration drain: without an owner token a late worker cannot
-- be distinguished from the current owner.
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
  IF p_generation_token IS NULL
     OR length(p_generation_token) = 0
     OR length(p_generation_token) > 64 THEN
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

  IF p_prefetch THEN
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

  -- A fresh normal or legacy-replacement owner always wins. Only after its
  -- shared latch is stale may this claimant tombstone every old owner shape.
  IF EXISTS (
    SELECT 1
    FROM public.practice_hint_requests AS r
    WHERE r.user_id = p_user_id
      AND r.session_id = p_session_id
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

  UPDATE public.practice_chat_sessions AS s
  SET hint_generation_started_at = now(),
      hint_generation_owner_token = p_generation_token,
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

-- The old no-request-id release path inferred latch ownership from the absence
-- of a normal generating row. That inference is false while a legacy
-- replacement owns the shared latch, so every release now requires the exact
-- session token before it may delete a row or clear the latch.
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
  v_rows INTEGER := 0;
  v_session_rows INTEGER := 0;
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
  IF p_generation_token IS NULL
     OR length(p_generation_token) = 0
     OR length(p_generation_token) > 64 THEN
    RAISE EXCEPTION 'release_practice_hint_generation: invalid p_generation_token';
  END IF;

  SELECT s.* INTO v_session
  FROM public.practice_chat_sessions AS s
  WHERE s.user_id = p_user_id
    AND s.session_id = p_session_id
  FOR UPDATE;

  IF NOT FOUND
     OR v_session.hint_generation_started_at IS NULL
     OR v_session.hint_generation_owner_token IS DISTINCT FROM p_generation_token THEN
    released := FALSE;
    RETURN NEXT;
    RETURN;
  END IF;

  IF p_request_id IS NOT NULL THEN
    DELETE FROM public.practice_hint_requests AS r
    WHERE r.user_id = p_user_id
      AND r.session_id = p_session_id
      AND r.request_id = p_request_id
      AND r.state = 'generating'
      AND r.generation_token = p_generation_token;
  ELSE
    DELETE FROM public.practice_hint_requests AS r
    WHERE r.user_id = p_user_id
      AND r.session_id = p_session_id
      AND r.request_id = '__legacy_inflight__'
      AND r.state = 'generating'
      AND r.generation_token = p_generation_token;
  END IF;
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows = 0 THEN
    released := FALSE;
    RETURN NEXT;
    RETURN;
  END IF;

  UPDATE public.practice_chat_sessions AS s
  SET hint_generation_started_at = NULL,
      updated_at = now()
  WHERE s.user_id = p_user_id
    AND s.session_id = p_session_id
    AND s.hint_generation_started_at IS NOT NULL
    AND s.hint_generation_owner_token = p_generation_token;
  GET DIAGNOSTICS v_session_rows = ROW_COUNT;

  IF v_session_rows <> 1 THEN
    RAISE EXCEPTION 'PRACTICE_HINT_OWNER_MISMATCH';
  END IF;

  released := TRUE;
  RETURN NEXT;
END;
$$;

DROP FUNCTION IF EXISTS public.claim_practice_debrief(UUID, TEXT, INTEGER, TEXT);
DROP FUNCTION IF EXISTS public.claim_practice_debrief(UUID, TEXT, INTEGER, TEXT, TEXT);

CREATE FUNCTION public.claim_practice_debrief(
  p_user_id         UUID,
  p_session_id      TEXT,
  p_max_debriefs    INTEGER DEFAULT 3,
  p_request_id      TEXT DEFAULT NULL,
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

  -- Exact completed replay is session-wide, not only the most recent slot.
  -- This must precede both the cap and the global generation latch.
  IF v_entry IS NOT NULL
     AND v_entry -> 'result' <> 'null'::jsonb THEN
    current_debrief_count := v_row.debrief_count;
    replay := TRUE;
    in_flight := FALSE;
    stored_result := v_entry -> 'result';
    RETURN NEXT;
    RETURN;
  END IF;

  -- One active model call per session. A different requestId cannot bypass the
  -- fresh owner merely because it has its own ledger entry.
  IF v_row.last_debrief_request_id IS NOT NULL
     AND v_row.last_debrief_result IS NULL
     AND v_row.last_debrief_started_at IS NOT NULL
     AND v_row.last_debrief_started_at > now() - INTERVAL '45 seconds' THEN
    current_debrief_count := v_row.debrief_count;
    replay := FALSE;
    in_flight := TRUE;
    stored_result := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  -- Fence a stale/released previous global owner before another logical ID
  -- takes the latch. A not-yet-counted failed attempt leaves no logical row;
  -- an old pre-counted reservation keeps a token tombstone for exact retry.
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

  -- Exact stale/released retry preserves whether the slot was already counted.
  -- Replacing token+started_at fences every older worker.
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

  -- The production contract is three Debriefs per session. Keep the physical
  -- ledger bounded even if a caller supplies a looser p_max_debriefs value.
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

DROP FUNCTION IF EXISTS public.record_practice_debrief(UUID, TEXT, TEXT, JSONB);
DROP FUNCTION IF EXISTS public.record_practice_debrief(UUID, TEXT, TEXT, JSONB, TEXT);

CREATE FUNCTION public.record_practice_debrief(
  p_user_id          UUID,
  p_session_id       TEXT,
  p_request_id       TEXT,
  p_result           JSONB,
  p_generation_token TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.practice_chat_sessions;
  v_ledger JSONB;
  v_entry JSONB;
  v_new_debrief_count INTEGER;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'record_practice_debrief: p_user_id is required';
  END IF;
  IF p_session_id IS NULL OR length(p_session_id) = 0 OR length(p_session_id) > 64 THEN
    RAISE EXCEPTION 'record_practice_debrief: invalid p_session_id';
  END IF;
  IF p_request_id IS NULL OR length(p_request_id) = 0 OR length(p_request_id) > 64 THEN
    RAISE EXCEPTION 'record_practice_debrief: invalid p_request_id';
  END IF;
  IF p_result IS NULL
     OR jsonb_typeof(p_result) <> 'object'
     OR p_result ->> 'generationSource' IS DISTINCT FROM 'model'
     OR p_result -> 'fallbackUsed' IS DISTINCT FROM 'false'::jsonb THEN
    RAISE EXCEPTION 'record_practice_debrief: invalid p_result';
  END IF;
  IF p_generation_token IS NULL
     OR length(p_generation_token) = 0
     OR length(p_generation_token) > 64 THEN
    RAISE EXCEPTION 'record_practice_debrief: invalid p_generation_token';
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
  IF v_entry IS NULL THEN
    RAISE EXCEPTION 'PRACTICE_DEBRIEF_REQUEST_MISMATCH';
  END IF;

  -- First writer wins per exact logical ID, even after another request becomes
  -- the session's last slot.
  IF v_entry -> 'result' <> 'null'::jsonb THEN
    RETURN v_entry -> 'result';
  END IF;

  IF v_entry ->> 'started_at' IS NULL
     OR v_entry ->> 'generation_token' IS DISTINCT FROM p_generation_token
     OR v_row.last_debrief_request_id IS DISTINCT FROM p_request_id
     OR v_row.last_debrief_started_at IS NULL
     OR v_row.last_debrief_generation_token IS DISTINCT FROM p_generation_token THEN
    RAISE EXCEPTION 'PRACTICE_DEBRIEF_GENERATION_MISMATCH';
  END IF;

  -- Only a successfully persisted generated card consumes the three-card cap.
  -- Old/backfilled reservations already have counted=true and must not recount.
  IF v_entry -> 'counted' = 'false'::jsonb THEN
    IF v_row.debrief_count >= 3 THEN
      RAISE EXCEPTION 'PRACTICE_DEBRIEF_LIMIT';
    END IF;
    v_new_debrief_count := v_row.debrief_count + 1;
  ELSE
    IF v_row.debrief_count < 1 THEN
      RAISE EXCEPTION 'PRACTICE_DEBRIEF_LEDGER_INVALID';
    END IF;
    v_new_debrief_count := v_row.debrief_count;
  END IF;

  v_entry := jsonb_build_object(
    'result', p_result,
    'started_at', NULL,
    'generation_token', NULL,
    'counted', TRUE
  );
  v_ledger := jsonb_set(
    v_ledger,
    ARRAY[p_request_id],
    v_entry,
    FALSE
  );

  UPDATE public.practice_chat_sessions
  SET debrief_count = v_new_debrief_count,
      debrief_request_ledger = v_ledger,
      last_debrief_result = CASE
        WHEN last_debrief_request_id = p_request_id THEN p_result
        ELSE last_debrief_result
      END,
      last_debrief_started_at = CASE
        WHEN last_debrief_request_id = p_request_id THEN NULL
        ELSE last_debrief_started_at
      END,
      last_debrief_generation_token = CASE
        WHEN last_debrief_request_id = p_request_id THEN NULL
        ELSE last_debrief_generation_token
      END,
      updated_at = now()
  WHERE user_id = p_user_id AND session_id = p_session_id;

  RETURN p_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.release_practice_debrief_generation(
  p_user_id          UUID,
  p_session_id       TEXT,
  p_request_id       TEXT,
  p_generation_token TEXT
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
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'release_practice_debrief_generation: p_user_id is required';
  END IF;
  IF p_session_id IS NULL OR length(p_session_id) = 0 OR length(p_session_id) > 64 THEN
    RAISE EXCEPTION 'release_practice_debrief_generation: invalid p_session_id';
  END IF;
  IF p_request_id IS NULL OR length(p_request_id) = 0 OR length(p_request_id) > 64 THEN
    RAISE EXCEPTION 'release_practice_debrief_generation: invalid p_request_id';
  END IF;
  IF p_generation_token IS NULL
     OR length(p_generation_token) = 0
     OR length(p_generation_token) > 64 THEN
    RAISE EXCEPTION 'release_practice_debrief_generation: invalid p_generation_token';
  END IF;

  SELECT * INTO v_session
  FROM public.practice_chat_sessions
  WHERE user_id = p_user_id AND session_id = p_session_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  v_ledger := v_session.debrief_request_ledger;
  IF NOT public.is_valid_practice_debrief_request_ledger(v_ledger) THEN
    RAISE EXCEPTION 'PRACTICE_DEBRIEF_LEDGER_INVALID';
  END IF;
  v_entry := v_ledger -> p_request_id;
  IF v_entry IS NULL
     OR v_entry -> 'result' <> 'null'::jsonb
     OR v_entry ->> 'started_at' IS NULL
     OR v_entry ->> 'generation_token' IS DISTINCT FROM p_generation_token
     OR v_session.last_debrief_request_id IS DISTINCT FROM p_request_id
     OR v_session.last_debrief_started_at IS NULL
     OR v_session.last_debrief_generation_token IS DISTINCT FROM p_generation_token THEN
    RETURN FALSE;
  END IF;

  IF v_entry -> 'counted' = 'false'::jsonb THEN
    -- Generation never produced an authoritative card, so the logical attempt
    -- disappears completely and consumes no debrief_count slot.
    v_ledger := v_ledger - p_request_id;
    UPDATE public.practice_chat_sessions
    SET debrief_request_ledger = v_ledger,
        last_debrief_request_id = NULL,
        last_debrief_result = NULL,
        last_debrief_started_at = NULL,
        last_debrief_generation_token = NULL,
        updated_at = now()
    WHERE user_id = p_user_id AND session_id = p_session_id;
  ELSE
    -- A legacy/pre-counted request keeps its token tombstone. Only an exact
    -- future claim can replace token+started_at; this worker cannot record.
    v_entry := jsonb_set(
      v_entry,
      '{started_at}',
      'null'::jsonb,
      FALSE
    );
    v_ledger := jsonb_set(
      v_ledger,
      ARRAY[p_request_id],
      v_entry,
      FALSE
    );
    UPDATE public.practice_chat_sessions
    SET debrief_request_ledger = v_ledger,
        last_debrief_started_at = NULL,
        updated_at = now()
    WHERE user_id = p_user_id AND session_id = p_session_id;
  END IF;

  RETURN TRUE;
END;
$$;

-- Remove a replayable legacy snapshot only when the new Edge has proved that
-- it cannot certify the payload as model-generated. The logical request stays
-- idempotent: Debrief keeps its already-counted request id; Hint replacement
-- preserves both count and quota provenance under its sidecar owner.
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

  -- Hint count/quota reservations must never be refunded in one transaction
  -- and reclaimed in another. New callers use the atomic replacement RPC.
  RAISE EXCEPTION 'PRACTICE_HINT_REPLACEMENT_REQUIRED';
END;
$$;

-- Atomically reserve the already-counted Hint slot while replacing an unsafe
-- settled snapshot. The old payload remains isolated in the row until a
-- generated-only first writer succeeds, so provider failure cannot lose the
-- count/quota provenance needed by a later retry.
CREATE OR REPLACE FUNCTION public.claim_legacy_practice_hint_replacement(
  p_user_id          UUID,
  p_session_id       TEXT,
  p_request_id       TEXT,
  p_generation_token TEXT,
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
  v_explicit_model BOOLEAN := FALSE;
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

  v_explicit_model := v_request.result ->> 'generationSource' = 'model'
    AND v_request.result -> 'fallbackUsed' = 'false'::jsonb;

  IF NOT v_request.legacy_replacement_pending
     AND v_explicit_model THEN
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
  -- Fresh opposite-mode ownership returned IN_FLIGHT above while the session
  -- row was locked, so these tombstones can only supersede stale work.
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

CREATE OR REPLACE FUNCTION public.record_legacy_practice_hint_replacement(
  p_user_id          UUID,
  p_session_id       TEXT,
  p_request_id       TEXT,
  p_generation_token TEXT,
  p_result           JSONB,
  p_charge_quota     BOOLEAN,
  p_monthly_limit    INTEGER,
  p_daily_limit      INTEGER,
  p_max_hints        INTEGER
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
  v_session public.practice_chat_sessions%ROWTYPE;
  v_request public.practice_hint_requests%ROWTYPE;
  v_usage RECORD;
  v_final_result JSONB;
  v_monthly_used INTEGER;
  v_daily_used INTEGER;
  v_quota_already_paid BOOLEAN;
  v_session_rows INTEGER := 0;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'record_legacy_practice_hint_replacement: p_user_id is required';
  END IF;
  IF p_session_id IS NULL OR length(p_session_id) = 0 OR length(p_session_id) > 64 THEN
    RAISE EXCEPTION 'record_legacy_practice_hint_replacement: invalid p_session_id';
  END IF;
  IF p_request_id IS NULL OR length(p_request_id) = 0 OR length(p_request_id) > 64
     OR p_request_id = '__legacy_inflight__' THEN
    RAISE EXCEPTION 'record_legacy_practice_hint_replacement: invalid p_request_id';
  END IF;
  IF p_generation_token IS NULL
     OR length(p_generation_token) = 0
     OR length(p_generation_token) > 64 THEN
    RAISE EXCEPTION 'record_legacy_practice_hint_replacement: invalid p_generation_token';
  END IF;
  IF p_result IS NULL
     OR jsonb_typeof(p_result) <> 'object'
     OR p_result ->> 'generationSource' IS DISTINCT FROM 'model'
     OR p_result -> 'fallbackUsed' IS DISTINCT FROM 'false'::jsonb THEN
    RAISE EXCEPTION 'record_legacy_practice_hint_replacement: invalid p_result';
  END IF;
  IF p_charge_quota IS NULL THEN
    RAISE EXCEPTION 'record_legacy_practice_hint_replacement: invalid p_charge_quota';
  END IF;
  IF p_monthly_limit IS NULL OR p_monthly_limit < 1
     OR p_daily_limit IS NULL OR p_daily_limit < 1 THEN
    RAISE EXCEPTION 'record_legacy_practice_hint_replacement: invalid quota limits';
  END IF;
  IF p_max_hints IS NULL OR p_max_hints < 1 OR p_max_hints > 5 THEN
    RAISE EXCEPTION 'record_legacy_practice_hint_replacement: invalid p_max_hints';
  END IF;

  SELECT s.* INTO v_session
  FROM public.practice_chat_sessions AS s
  WHERE s.user_id = p_user_id
    AND s.session_id = p_session_id
  FOR UPDATE;

  IF NOT FOUND OR NOT v_session.charged OR v_session.ai_count < 1 THEN
    RAISE EXCEPTION 'PRACTICE_SESSION_NOT_STARTED';
  END IF;
  IF v_session.hint_count < 1 OR v_session.hint_count > p_max_hints THEN
    RAISE EXCEPTION 'PRACTICE_HINT_LIMIT';
  END IF;

  SELECT r.* INTO v_request
  FROM public.practice_hint_requests AS r
  WHERE r.user_id = p_user_id
    AND r.session_id = p_session_id
    AND r.request_id = p_request_id
  FOR UPDATE;

  IF NOT FOUND OR v_request.state <> 'settled' OR NOT v_request.charged THEN
    RAISE EXCEPTION 'PRACTICE_HINT_REPLACEMENT_NOT_READY';
  END IF;

  -- A lost RPC response replays the first generated-only writer.
  IF NOT v_request.legacy_replacement_pending
     AND v_request.result ->> 'generationSource' = 'model'
     AND v_request.result -> 'fallbackUsed' = 'false'::jsonb THEN
    new_hint_count := v_session.hint_count;
    did_charge := FALSE;
    stored_result := v_request.result;
    stored_charged := TRUE;
    RETURN NEXT;
    RETURN;
  END IF;

  IF NOT v_request.legacy_replacement_pending
     OR v_request.legacy_replacement_started_at IS NULL
     OR v_request.legacy_replacement_generation_token IS DISTINCT FROM p_generation_token
     OR v_session.hint_generation_started_at IS NULL
     OR v_session.hint_generation_owner_token IS DISTINCT FROM p_generation_token
     OR v_request.claimed_ai_count <> v_session.ai_count THEN
    RAISE EXCEPTION 'PRACTICE_HINT_OWNER_MISMATCH';
  END IF;

  v_quota_already_paid := v_request.result -> 'costDeducted' = '1'::jsonb;
  SELECT * INTO v_usage
  FROM public.prepare_practice_subscription_usage(p_user_id);

  did_charge := p_charge_quota AND NOT v_quota_already_paid;
  IF did_charge THEN
    PERFORM public.increment_usage(
      p_user_id,
      1,
      p_monthly_limit,
      p_daily_limit
    );
  END IF;

  v_monthly_used := v_usage.monthly_messages_used + CASE WHEN did_charge THEN 1 ELSE 0 END;
  v_daily_used := v_usage.daily_messages_used + CASE WHEN did_charge THEN 1 ELSE 0 END;
  v_final_result := p_result || jsonb_build_object(
    'costDeducted', CASE
      WHEN v_quota_already_paid OR did_charge THEN 1
      ELSE 0
    END,
    'hintUsedCount', v_session.hint_count,
    'monthlyRemaining', GREATEST(0, p_monthly_limit - v_monthly_used),
    'dailyRemaining', GREATEST(0, p_daily_limit - v_daily_used)
  );

  UPDATE public.practice_hint_requests AS r
  SET result = v_final_result,
      is_prefetch = FALSE,
      legacy_replacement_pending = FALSE,
      legacy_replacement_generation_token = NULL,
      legacy_replacement_started_at = NULL,
      updated_at = now()
  WHERE r.user_id = p_user_id
    AND r.session_id = p_session_id
    AND r.request_id = p_request_id
    AND r.legacy_replacement_pending = TRUE
    AND r.legacy_replacement_started_at IS NOT NULL
    AND r.legacy_replacement_generation_token = p_generation_token;

  UPDATE public.practice_chat_sessions AS s
  SET hint_generation_started_at = NULL,
      last_hint_request_id = p_request_id,
      last_hint_result = v_final_result,
      updated_at = now()
  WHERE s.user_id = p_user_id
    AND s.session_id = p_session_id
    AND s.hint_generation_started_at IS NOT NULL
    AND s.hint_generation_owner_token = p_generation_token;
  GET DIAGNOSTICS v_session_rows = ROW_COUNT;

  -- Any impossible partial ownership mismatch aborts the transaction, rolling
  -- back the request write and quota increment together.
  IF v_session_rows <> 1 THEN
    RAISE EXCEPTION 'PRACTICE_HINT_OWNER_MISMATCH';
  END IF;

  new_hint_count := v_session.hint_count;
  stored_result := v_final_result;
  stored_charged := TRUE;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.release_legacy_practice_hint_replacement(
  p_user_id          UUID,
  p_session_id       TEXT,
  p_request_id       TEXT,
  p_generation_token TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.practice_chat_sessions%ROWTYPE;
  v_rows INTEGER := 0;
  v_session_rows INTEGER := 0;
BEGIN
  IF p_user_id IS NULL
     OR p_session_id IS NULL OR length(p_session_id) = 0 OR length(p_session_id) > 64
     OR p_request_id IS NULL OR length(p_request_id) = 0 OR length(p_request_id) > 64
     OR p_generation_token IS NULL OR length(p_generation_token) = 0 OR length(p_generation_token) > 64 THEN
    RAISE EXCEPTION 'release_legacy_practice_hint_replacement: invalid arguments';
  END IF;

  SELECT s.* INTO v_session
  FROM public.practice_chat_sessions AS s
  WHERE s.user_id = p_user_id
    AND s.session_id = p_session_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;
  IF v_session.hint_generation_started_at IS NULL
     OR v_session.hint_generation_owner_token IS DISTINCT FROM p_generation_token THEN
    RETURN FALSE;
  END IF;

  -- Keep pending=true and the token as a tombstone. Only the active timestamp
  -- is released; a later exact retry atomically replaces token+timestamp.
  UPDATE public.practice_hint_requests AS r
  SET legacy_replacement_started_at = NULL,
      updated_at = now()
  WHERE r.user_id = p_user_id
    AND r.session_id = p_session_id
    AND r.request_id = p_request_id
    AND r.state = 'settled'
    AND r.legacy_replacement_pending = TRUE
    AND r.legacy_replacement_started_at IS NOT NULL
    AND r.legacy_replacement_generation_token = p_generation_token;
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows > 0 THEN
    UPDATE public.practice_chat_sessions AS s
    SET hint_generation_started_at = NULL,
        updated_at = now()
    WHERE s.user_id = p_user_id
      AND s.session_id = p_session_id
      AND s.hint_generation_started_at IS NOT NULL
      AND s.hint_generation_owner_token = p_generation_token;
    GET DIAGNOSTICS v_session_rows = ROW_COUNT;

    IF v_session_rows <> 1 THEN
      RAISE EXCEPTION 'PRACTICE_HINT_OWNER_MISMATCH';
    END IF;
  END IF;
  RETURN v_rows > 0;
END;
$$;

-- A delayed kill-switch discard must never delete a newly token-owned worker.
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
  v_request public.practice_hint_requests%ROWTYPE;
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

  PERFORM 1
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
  IF v_request.state = 'generating'
     OR v_request.legacy_replacement_pending THEN
    RAISE EXCEPTION 'PRACTICE_HINT_IN_FLIGHT';
  END IF;
  IF v_request.state = 'settled' THEN
    discarded := FALSE;
    replay := TRUE;
    stored_result := v_request.result;
    stored_charged := TRUE;
    RETURN NEXT;
    RETURN;
  END IF;
  IF v_request.state <> 'prefetched' OR NOT v_request.is_prefetch THEN
    RAISE EXCEPTION 'PRACTICE_HINT_STATE_MISMATCH';
  END IF;

  DELETE FROM public.practice_hint_requests AS r
  WHERE r.user_id = p_user_id
    AND r.session_id = p_session_id
    AND r.request_id = p_request_id
    AND r.state = 'prefetched'
    AND r.is_prefetch = TRUE;

  discarded := TRUE;
  replay := FALSE;
  stored_result := NULL;
  stored_charged := FALSE;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_practice_hint_decision(
  p_user_id           UUID,
  p_session_id        TEXT,
  p_request_id        TEXT,
  p_hint_type         TEXT,
  p_original_hint_text TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSONB;
  v_reply JSONB;
  v_decision JSONB;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'resolve_practice_hint_decision: p_user_id is required';
  END IF;
  IF p_session_id IS NULL OR length(p_session_id) = 0 OR length(p_session_id) > 64 THEN
    RAISE EXCEPTION 'resolve_practice_hint_decision: invalid p_session_id';
  END IF;
  IF p_request_id IS NULL OR length(p_request_id) = 0 OR length(p_request_id) > 64 THEN
    RAISE EXCEPTION 'resolve_practice_hint_decision: invalid p_request_id';
  END IF;
  IF p_hint_type NOT IN ('warm_up', 'steady') THEN
    RAISE EXCEPTION 'resolve_practice_hint_decision: invalid p_hint_type';
  END IF;
  IF p_original_hint_text IS NULL
     OR length(btrim(p_original_hint_text)) = 0
     OR length(p_original_hint_text) > 500 THEN
    RAISE EXCEPTION 'resolve_practice_hint_decision: invalid p_original_hint_text';
  END IF;

  SELECT r.result INTO v_result
  FROM public.practice_hint_requests AS r
  WHERE r.user_id = p_user_id
    AND r.session_id = p_session_id
    AND r.request_id = p_request_id
    AND r.state = 'settled'
    AND r.charged = TRUE
    AND r.result ->> 'generationSource' = 'model'
    AND r.result -> 'fallbackUsed' = 'false'::jsonb;

  IF NOT FOUND OR jsonb_typeof(v_result) <> 'object' THEN
    RAISE EXCEPTION 'PRACTICE_HINT_LINEAGE_NOT_READY';
  END IF;
  SELECT reply.value INTO v_reply
  FROM jsonb_array_elements(COALESCE(v_result -> 'replies', '[]'::jsonb)) AS reply(value)
  WHERE reply.value ->> 'type' = p_hint_type
    AND btrim(reply.value ->> 'text') = btrim(p_original_hint_text)
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PRACTICE_HINT_LINEAGE_MISMATCH';
  END IF;

  v_decision := v_reply -> 'decision';
  IF jsonb_typeof(v_decision) <> 'object'
     OR COALESCE(v_decision ->> 'phase', '') = ''
     OR COALESCE(v_decision ->> 'targetVariable', '') = ''
     OR COALESCE(v_decision ->> 'move', '') = ''
     OR COALESCE(v_decision ->> 'inviteRoute', '') = ''
     OR COALESCE(v_decision ->> 'rationale', '') = '' THEN
    RAISE EXCEPTION 'PRACTICE_HINT_DECISION_NOT_READY';
  END IF;

  RETURN v_decision;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.is_valid_practice_debrief_request_ledger(JSONB)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_valid_practice_debrief_request_ledger(JSONB)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.clear_practice_hint_owner_token()
  FROM PUBLIC, anon, authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.claim_practice_hint_generation(UUID, TEXT, INTEGER, TEXT, BOOLEAN, TEXT, INTEGER)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_practice_hint_generation(UUID, TEXT, INTEGER, TEXT, BOOLEAN, TEXT, INTEGER)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.release_practice_hint_generation(UUID, TEXT, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.release_practice_hint_generation(UUID, TEXT, TEXT, TEXT)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.claim_practice_debrief(UUID, TEXT, INTEGER, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_practice_debrief(UUID, TEXT, INTEGER, TEXT, TEXT)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.record_practice_debrief(UUID, TEXT, TEXT, JSONB, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_practice_debrief(UUID, TEXT, TEXT, JSONB, TEXT)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.release_practice_debrief_generation(UUID, TEXT, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.release_practice_debrief_generation(UUID, TEXT, TEXT, TEXT)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.invalidate_legacy_practice_ai_snapshot(UUID, TEXT, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.invalidate_legacy_practice_ai_snapshot(UUID, TEXT, TEXT, TEXT)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.claim_legacy_practice_hint_replacement(UUID, TEXT, TEXT, TEXT, INTEGER)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_legacy_practice_hint_replacement(UUID, TEXT, TEXT, TEXT, INTEGER)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.record_legacy_practice_hint_replacement(UUID, TEXT, TEXT, TEXT, JSONB, BOOLEAN, INTEGER, INTEGER, INTEGER)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_legacy_practice_hint_replacement(UUID, TEXT, TEXT, TEXT, JSONB, BOOLEAN, INTEGER, INTEGER, INTEGER)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.release_legacy_practice_hint_replacement(UUID, TEXT, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.release_legacy_practice_hint_replacement(UUID, TEXT, TEXT, TEXT)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.resolve_practice_hint_decision(UUID, TEXT, TEXT, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_practice_hint_decision(UUID, TEXT, TEXT, TEXT, TEXT)
  TO service_role;

NOTIFY pgrst, 'reload schema';
