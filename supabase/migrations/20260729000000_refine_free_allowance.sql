-- Reply refinement ("再調一下") daily free allowance.
--
-- One row per user, rolled forward in place by day_utc. The table never grows
-- with time and stores no instruction text, draft text, or model output --
-- only a counter. The daily limit itself is NOT stored here: the Edge Function
-- passes it in, so the product can change the number without a migration.
--
-- Day boundary is UTC, matching every other daily window in this project
-- (increment_model_usage, OCR rate limit, practice hint quota).

-- Creating a foreign key takes SHARE ROW EXCLUSIVE on auth.users, which
-- conflicts with the ROW EXCLUSIVE that ordinary INSERT/UPDATE/DELETE holds.
-- The wait is unbounded, and once this migration is queued for that lock every
-- subsequent auth write queues behind it -- a stalled sign-up/login pile-up.
-- Fail fast instead: if the lock is not free within 5s, this migration errors
-- out and gets retried at a quieter moment.
--
-- SET LOCAL, not SET: a plain SET survives COMMIT and stays on the connection,
-- so a pooled runner would hand the next migration an inherited 5s ceiling it
-- never asked for. LOCAL scopes it to this transaction, which is also the
-- scope the lock itself lives in. This file must therefore be applied inside a
-- transaction -- outside one, SET LOCAL warns and does nothing.
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS public.refine_free_allowance (
  user_id    UUID        NOT NULL PRIMARY KEY
                         REFERENCES auth.users(id) ON DELETE CASCADE,
  day_utc    DATE        NOT NULL,
  used_count INTEGER     NOT NULL DEFAULT 0 CHECK (used_count >= 0),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.refine_free_allowance IS
  '回覆微調每日免費額度。單列滾動：day_utc 換日即重置，表不隨時間長大。';

ALTER TABLE public.refine_free_allowance ENABLE ROW LEVEL SECURITY;

-- No policies on purpose: only service_role touches this table, and it does so
-- through consume_refine_free_allowance. Clients must never read or write it
-- directly -- a client-visible counter is a client-forgeable counter.
REVOKE ALL ON TABLE public.refine_free_allowance FROM PUBLIC;
REVOKE ALL ON TABLE public.refine_free_allowance FROM anon, authenticated;
GRANT SELECT ON TABLE public.refine_free_allowance TO service_role;

-- One row per settled free claim, so a retried requestId cannot spend a second
-- free slot.
--
-- The allowance counter alone is not idempotent: two concurrent requests that
-- carry the SAME requestId both pass the replay preflight (no ledger row
-- exists yet), both reach the model, and both call the consume function. The
-- optimize ledger de-duplicates the money, but nothing de-duplicated the free
-- counter -- the user silently lost a slot. This table is the missing key.
--
-- Rows are pruned on the same 7-day window as optimize_message_requests: past
-- that window the request can no longer be replayed anyway, so a claim row for
-- it can never be consulted again. Pruning happens two ways: opportunistically
-- for the calling user inside the function, and on an hourly pg_cron sweep for
-- everyone else -- a user who refines a few times and then churns would
-- otherwise keep their last rows forever, since the in-function prune only
-- ever runs for users who come back.
CREATE TABLE IF NOT EXISTS public.refine_free_claims (
  user_id    UUID        NOT NULL
                         REFERENCES auth.users(id) ON DELETE CASCADE,
  request_id UUID        NOT NULL,
  day_utc    DATE        NOT NULL,
  granted    BOOLEAN     NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, request_id)
);

CREATE INDEX IF NOT EXISTS refine_free_claims_created_at_idx
  ON public.refine_free_claims (created_at);

COMMENT ON TABLE public.refine_free_claims IS
  '回覆微調免費額度的冪等鍵。同一 requestId 重試（含並行重試）只能花掉一次免費次數。';

ALTER TABLE public.refine_free_claims ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.refine_free_claims FROM PUBLIC;
REVOKE ALL ON TABLE public.refine_free_claims FROM anon, authenticated;
GRANT SELECT ON TABLE public.refine_free_claims TO service_role;

CREATE OR REPLACE FUNCTION public.cleanup_expired_refine_free_claims()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deleted INTEGER;
BEGIN
  DELETE FROM public.refine_free_claims
  WHERE created_at < now() - interval '7 days';
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

REVOKE EXECUTE ON FUNCTION
  public.cleanup_expired_refine_free_claims() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION
  public.cleanup_expired_refine_free_claims() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.cleanup_expired_refine_free_claims() TO service_role;

-- Same hourly cadence and failure stance as the other replay-retention jobs:
-- fail the migration rather than silently shipping a retention promise that
-- nothing enforces. Minute 23 keeps it clear of the existing sweeps.
CREATE EXTENSION IF NOT EXISTS pg_cron;

DO $schedule$
DECLARE
  v_job_id BIGINT;
BEGIN
  FOR v_job_id IN
    SELECT jobid FROM cron.job
    WHERE jobname = 'cleanup-expired-refine-free-claims'
  LOOP
    PERFORM cron.unschedule(v_job_id);
  END LOOP;

  PERFORM cron.schedule(
    'cleanup-expired-refine-free-claims',
    '23 * * * *',
    'SELECT public.cleanup_expired_refine_free_claims();'
  );
END;
$schedule$;

-- Atomically claim one free refinement for today.
--
-- Returns {granted, used, remaining}. granted=false is NOT an error: the caller
-- falls back to charging one message through the existing optimize_message
-- ledger. The row lock is what stops two concurrent requests from both taking
-- the last free slot; without it a double-tap would spend one slot twice.
--
-- p_request_id is the idempotency key and is REQUIRED. It carries no default:
-- a nullable one would leave a silent path with no de-duplication at all, and
-- this function has no legacy caller to be gentle with -- it has never been
-- deployed. The Edge Function rejects a refine request without a requestId
-- before it gets here; this RAISE is the second lock on the same door.
--
-- Adding a third parameter creates a NEW overload rather than replacing the
-- two-argument version, and a two-argument call against both would fail with
-- "function is not unique" -- so drop the old signature first. No-op on a
-- database that never had it.
DROP FUNCTION IF EXISTS public.consume_refine_free_allowance(UUID, INTEGER);

CREATE OR REPLACE FUNCTION public.consume_refine_free_allowance(
  p_user_id     UUID,
  p_daily_limit INTEGER,
  p_request_id  UUID
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  -- Re-derived after the row lock; see the comment at the lock. This initial
  -- value only seeds the pre-lock INSERT of a missing row.
  v_today   DATE := (now() AT TIME ZONE 'utc')::date;
  v_used    INTEGER;
  v_day     DATE;
  v_claimed BOOLEAN;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'consume_refine_free_allowance: p_user_id is required';
  END IF;
  IF p_daily_limit IS NULL OR p_daily_limit < 0 THEN
    RAISE EXCEPTION 'consume_refine_free_allowance: invalid p_daily_limit';
  END IF;
  IF p_request_id IS NULL THEN
    RAISE EXCEPTION 'consume_refine_free_allowance: p_request_id is required';
  END IF;

  -- Take the parent row's FK lock FIRST, in the same order account deletion
  -- does (parent, then cascade to children). Without this the orders invert:
  -- we would lock the allowance child row here and only reach for the parent
  -- later, when inserting a claim triggers its FK check -- while a concurrent
  -- DELETE FROM auth.users holds the parent and waits for our child. That
  -- cycle deadlocks (40P01) and kills either the refine call or the account
  -- deletion. FOR KEY SHARE is the weakest lock that blocks the delete.
  PERFORM 1 FROM auth.users WHERE id = p_user_id FOR KEY SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION
      'consume_refine_free_allowance: no such user %', p_user_id;
  END IF;

  INSERT INTO public.refine_free_allowance (user_id, day_utc, used_count)
  VALUES (p_user_id, v_today, 0)
  ON CONFLICT (user_id) DO NOTHING;

  -- FOR UPDATE serialises concurrent callers for this user. A second caller
  -- blocks here until the first has committed its increment, so it observes
  -- the updated count rather than the stale one it would have read.
  --
  -- Taking this lock BEFORE the claim lookup is what makes the idempotency
  -- work under concurrency: the duplicate requestId waits here and therefore
  -- reads a claim row that is already committed.
  SELECT used_count, day_utc INTO v_used, v_day
  FROM public.refine_free_allowance
  WHERE user_id = p_user_id
  FOR UPDATE;

  -- Re-derive the day AFTER the lock. A caller that entered at 23:59:59 can
  -- wait on this lock until after midnight; with the entry-time value it would
  -- then see the winner's already-rolled day_utc as "wrong", roll the counter
  -- BACK to yesterday and reset used_count to 0 -- handing out a fresh ten free
  -- slots.
  --
  -- clock_timestamp(), NOT now(): now() is transaction_timestamp() and is
  -- frozen for the whole transaction, so re-reading it after a lock wait
  -- returns the same instant we entered with and fixes nothing. This is the
  -- only place in this function that needs true wall-clock time.
  v_today := (clock_timestamp() AT TIME ZONE 'utc')::date;

  -- Now that the parent row is pinned with FOR KEY SHARE, account deletion can
  -- no longer cascade this row away mid-call, so this guard only fires if
  -- something deleted the allowance row directly. Kept anyway: failing loudly
  -- beats returning a grant computed from NULL.
  IF NOT FOUND THEN
    RAISE EXCEPTION
      'consume_refine_free_allowance: allowance row missing for %', p_user_id;
  END IF;

  IF v_day <> v_today THEN
    UPDATE public.refine_free_allowance
    SET used_count = 0, day_utc = v_today, updated_at = now()
    WHERE user_id = p_user_id;
    v_used := 0;
  END IF;

  -- Scoped to this user on purpose. A table-wide sweep here would run under
  -- the per-user allowance lock and could deadlock against another user's sweep
  -- touching the same pages; per-user is already serialised by the lock we
  -- hold, and the table is at most a handful of rows per user per day (account
  -- deletion is covered by the ON DELETE CASCADE).
  DELETE FROM public.refine_free_claims
  WHERE user_id = p_user_id
    AND created_at < now() - interval '7 days';

  SELECT granted INTO v_claimed
  FROM public.refine_free_claims
  WHERE user_id = p_user_id AND request_id = p_request_id;

  -- Replay of a settled verdict. Return it verbatim without touching the
  -- counter: this requestId has already had whatever it was going to get.
  IF FOUND THEN
    RETURN jsonb_build_object(
      'granted', v_claimed,
      'used', v_used,
      'remaining', GREATEST(0, p_daily_limit - v_used)
    );
  END IF;

  IF v_used >= p_daily_limit THEN
    INSERT INTO public.refine_free_claims
      (user_id, request_id, day_utc, granted)
    VALUES (p_user_id, p_request_id, v_today, false);
    RETURN jsonb_build_object(
      'granted', false, 'used', v_used, 'remaining', 0
    );
  END IF;

  UPDATE public.refine_free_allowance
  SET used_count = v_used + 1, updated_at = now()
  WHERE user_id = p_user_id;

  INSERT INTO public.refine_free_claims
    (user_id, request_id, day_utc, granted)
  VALUES (p_user_id, p_request_id, v_today, true);

  RETURN jsonb_build_object(
    'granted', true,
    'used', v_used + 1,
    'remaining', p_daily_limit - v_used - 1
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION
  public.consume_refine_free_allowance(UUID, INTEGER, UUID)
  FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION
  public.consume_refine_free_allowance(UUID, INTEGER, UUID)
  FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.consume_refine_free_allowance(UUID, INTEGER, UUID)
  TO service_role;

NOTIFY pgrst, 'reload schema';
