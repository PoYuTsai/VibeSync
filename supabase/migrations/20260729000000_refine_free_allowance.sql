-- Reply refinement ("再調一下") daily free allowance.
--
-- One row per user, rolled forward in place by day_utc. The table never grows
-- with time and stores no instruction text, draft text, or model output --
-- only a counter. The daily limit itself is NOT stored here: the Edge Function
-- passes it in, so the product can change the number without a migration.
--
-- Day boundary is UTC, matching every other daily window in this project
-- (increment_model_usage, OCR rate limit, practice hint quota).

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

-- Atomically claim one free refinement for today.
--
-- Returns {granted, used, remaining}. granted=false is NOT an error: the caller
-- falls back to charging one message through the existing optimize_message
-- ledger. The row lock is what stops two concurrent requests from both taking
-- the last free slot; without it a double-tap would spend one slot twice.
CREATE OR REPLACE FUNCTION public.consume_refine_free_allowance(
  p_user_id     UUID,
  p_daily_limit INTEGER
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today DATE := (now() AT TIME ZONE 'utc')::date;
  v_used  INTEGER;
  v_day   DATE;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'consume_refine_free_allowance: p_user_id is required';
  END IF;
  IF p_daily_limit IS NULL OR p_daily_limit < 0 THEN
    RAISE EXCEPTION 'consume_refine_free_allowance: invalid p_daily_limit';
  END IF;

  INSERT INTO public.refine_free_allowance (user_id, day_utc, used_count)
  VALUES (p_user_id, v_today, 0)
  ON CONFLICT (user_id) DO NOTHING;

  -- FOR UPDATE serialises concurrent callers for this user. A second caller
  -- blocks here until the first has committed its increment, so it observes
  -- the updated count rather than the stale one it would have read.
  SELECT used_count, day_utc INTO v_used, v_day
  FROM public.refine_free_allowance
  WHERE user_id = p_user_id
  FOR UPDATE;

  -- Only reachable if the row vanished between the insert and the lock, i.e.
  -- the account was deleted mid-request. Fail loudly rather than returning a
  -- grant computed from NULL.
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

  IF v_used >= p_daily_limit THEN
    RETURN jsonb_build_object(
      'granted', false, 'used', v_used, 'remaining', 0
    );
  END IF;

  UPDATE public.refine_free_allowance
  SET used_count = v_used + 1, updated_at = now()
  WHERE user_id = p_user_id;

  RETURN jsonb_build_object(
    'granted', true,
    'used', v_used + 1,
    'remaining', p_daily_limit - v_used - 1
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.consume_refine_free_allowance(UUID, INTEGER)
  FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.consume_refine_free_allowance(UUID, INTEGER)
  FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_refine_free_allowance(UUID, INTEGER)
  TO service_role;
