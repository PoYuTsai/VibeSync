-- Corrective migration for production environments that already recorded
-- 20260822120000 before the per-user model-usage gate was added.
--
-- Fresh databases receive the 12-argument function from the original migration;
-- production needs this new ledger version because an applied migration is never
-- replayed after its checked-in SQL changes.  The old 8-argument overload has no
-- per-user accounting and must not remain callable by service_role.

-- Fail closed before touching either expected overload.  Production should have
-- the legacy 8-argument shape; a freshly rebuilt database already has the new
-- 12-argument shape.  Any third shape means catalog drift, and a signature-
-- specific DROP would otherwise no-op while leaving an unmetered RPC callable.
DO $$
DECLARE
  v_unexpected TEXT;
BEGIN
  SELECT string_agg(p.oid::regprocedure::TEXT, ', ' ORDER BY p.oid::regprocedure::TEXT)
  INTO v_unexpected
  FROM pg_proc AS p
  JOIN pg_namespace AS n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'reserve_practice_moment_slot'
    AND p.oid NOT IN (
      COALESCE(to_regprocedure(
        'public.reserve_practice_moment_slot(text,date,integer,text,text,text,integer,integer)'
      )::OID, 0::OID),
      COALESCE(to_regprocedure(
        'public.reserve_practice_moment_slot(text,date,integer,text,text,text,uuid,integer,integer,boolean,integer,integer)'
      )::OID, 0::OID)
    );

  IF v_unexpected IS NOT NULL THEN
    RAISE EXCEPTION
      'reserve_practice_moment_slot: unexpected overload(s): %',
      v_unexpected;
  END IF;
END;
$$;

DROP FUNCTION IF EXISTS public.reserve_practice_moment_slot(
  TEXT, DATE, INTEGER, TEXT, TEXT, TEXT, INTEGER, INTEGER
);

CREATE OR REPLACE FUNCTION public.reserve_practice_moment_slot(
  p_profile_id       TEXT,
  p_post_date        DATE,
  p_slot             INTEGER,
  p_day_part         TEXT,
  p_theme_id         TEXT,
  p_generation_token TEXT,
  p_user_id          UUID,
  p_minute_limit     INTEGER,
  p_daily_limit      INTEGER,
  p_count_user_usage BOOLEAN,
  p_max_attempts     INTEGER DEFAULT 3,
  p_lease_seconds    INTEGER DEFAULT 120
)
RETURNS TABLE(claimed BOOLEAN, token TEXT, attempt_count SMALLINT)
LANGUAGE plpgsql
-- Safe for statement-by-statement migration runners: PUBLIC may receive the
-- default EXECUTE privilege at CREATE time, so keep caller privileges until the
-- REVOKE/GRANT block has completed.  The final ALTER below enables definer mode.
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_row      public.practice_moment_posts%ROWTYPE;
  v_inserted INTEGER := 0;
  v_attempts SMALLINT;
BEGIN
  IF p_profile_id IS NULL
     OR char_length(p_profile_id) = 0
     OR char_length(p_profile_id) > 64 THEN
    RAISE EXCEPTION 'reserve_practice_moment_slot: invalid p_profile_id';
  END IF;
  IF p_post_date IS NULL THEN
    RAISE EXCEPTION 'reserve_practice_moment_slot: p_post_date is required';
  END IF;
  IF p_slot IS NULL OR p_slot < 0 OR p_slot > 1 THEN
    RAISE EXCEPTION 'reserve_practice_moment_slot: invalid p_slot';
  END IF;
  IF p_day_part IS NULL
     OR char_length(p_day_part) = 0
     OR char_length(p_day_part) > 32 THEN
    RAISE EXCEPTION 'reserve_practice_moment_slot: invalid p_day_part';
  END IF;
  IF p_theme_id IS NULL
     OR char_length(p_theme_id) = 0
     OR char_length(p_theme_id) > 64 THEN
    RAISE EXCEPTION 'reserve_practice_moment_slot: invalid p_theme_id';
  END IF;
  IF p_generation_token IS NULL
     OR char_length(p_generation_token) = 0
     OR char_length(p_generation_token) > 64 THEN
    RAISE EXCEPTION 'reserve_practice_moment_slot: invalid p_generation_token';
  END IF;
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'reserve_practice_moment_slot: p_user_id is required';
  END IF;
  IF p_minute_limit IS NULL OR p_minute_limit <= 0 THEN
    RAISE EXCEPTION 'reserve_practice_moment_slot: invalid p_minute_limit';
  END IF;
  IF p_daily_limit IS NULL OR p_daily_limit <= 0 THEN
    RAISE EXCEPTION 'reserve_practice_moment_slot: invalid p_daily_limit';
  END IF;
  IF p_count_user_usage IS NULL THEN
    RAISE EXCEPTION 'reserve_practice_moment_slot: p_count_user_usage is required';
  END IF;
  IF p_max_attempts IS NULL OR p_max_attempts <= 0 OR p_max_attempts > 3 THEN
    RAISE EXCEPTION 'reserve_practice_moment_slot: invalid p_max_attempts';
  END IF;
  IF p_lease_seconds IS NULL OR p_lease_seconds <= 0 THEN
    RAISE EXCEPTION 'reserve_practice_moment_slot: invalid p_lease_seconds';
  END IF;

  INSERT INTO public.practice_moment_posts AS mp (
    profile_id, post_date, slot, day_part, theme_id,
    status, attempts, generation_token, reserved_at, created_at, updated_at
  ) VALUES (
    p_profile_id, p_post_date, p_slot::SMALLINT, p_day_part, p_theme_id,
    'reserved', 1, p_generation_token, now(), now(), now()
  )
  ON CONFLICT (profile_id, post_date, slot) DO NOTHING;
  GET DIAGNOSTICS v_inserted = ROW_COUNT;

  IF v_inserted = 1 THEN
    IF p_count_user_usage THEN
      PERFORM public.increment_model_usage(
        p_user_id, 'practice_moment', p_minute_limit, p_daily_limit
      );
    END IF;
    claimed := TRUE;
    token := p_generation_token;
    attempt_count := 1::SMALLINT;
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT mp.* INTO v_row
  FROM public.practice_moment_posts AS mp
  WHERE mp.profile_id = p_profile_id
    AND mp.post_date = p_post_date
    AND mp.slot = p_slot::SMALLINT
  FOR UPDATE;

  IF NOT FOUND THEN
    claimed := FALSE;
    token := NULL;
    attempt_count := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_row.status <> 'reserved' THEN
    claimed := FALSE;
    token := NULL;
    attempt_count := v_row.attempts;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_row.generation_token IS NOT NULL
     AND v_row.reserved_at > now() - make_interval(secs => p_lease_seconds) THEN
    claimed := FALSE;
    token := NULL;
    attempt_count := v_row.attempts;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_row.attempts >= p_max_attempts THEN
    UPDATE public.practice_moment_posts AS mp
    SET status = 'exhausted',
        generation_token = NULL,
        updated_at = now()
    WHERE mp.profile_id = p_profile_id
      AND mp.post_date = p_post_date
      AND mp.slot = p_slot::SMALLINT;

    claimed := FALSE;
    token := NULL;
    attempt_count := v_row.attempts;
    RETURN NEXT;
    RETURN;
  END IF;

  IF p_count_user_usage THEN
    PERFORM public.increment_model_usage(
      p_user_id, 'practice_moment', p_minute_limit, p_daily_limit
    );
  END IF;
  UPDATE public.practice_moment_posts AS mp
  SET attempts = v_row.attempts + 1,
      generation_token = p_generation_token,
      reserved_at = now(),
      day_part = p_day_part,
      theme_id = p_theme_id,
      updated_at = now()
  WHERE mp.profile_id = p_profile_id
    AND mp.post_date = p_post_date
    AND mp.slot = p_slot::SMALLINT
  RETURNING mp.attempts INTO v_attempts;

  claimed := TRUE;
  token := p_generation_token;
  attempt_count := v_attempts;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.reserve_practice_moment_slot(
  TEXT, DATE, INTEGER, TEXT, TEXT, TEXT, UUID, INTEGER, INTEGER, BOOLEAN,
  INTEGER, INTEGER
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reserve_practice_moment_slot(
  TEXT, DATE, INTEGER, TEXT, TEXT, TEXT, UUID, INTEGER, INTEGER, BOOLEAN,
  INTEGER, INTEGER
) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_practice_moment_slot(
  TEXT, DATE, INTEGER, TEXT, TEXT, TEXT, UUID, INTEGER, INTEGER, BOOLEAN,
  INTEGER, INTEGER
) TO service_role;
ALTER FUNCTION public.reserve_practice_moment_slot(
  TEXT, DATE, INTEGER, TEXT, TEXT, TEXT, UUID, INTEGER, INTEGER, BOOLEAN,
  INTEGER, INTEGER
) SECURITY DEFINER;

COMMENT ON FUNCTION public.reserve_practice_moment_slot(
  TEXT, DATE, INTEGER, TEXT, TEXT, TEXT, UUID, INTEGER, INTEGER, BOOLEAN,
  INTEGER, INTEGER
)
IS 'Atomically leases one moment slot and, only for a successful claim, increments both attempts and per-user model usage in the same transaction. A rate-limit exception rolls the entire claim back.';

NOTIFY pgrst, 'reload schema';
