-- 批 B 訪客模式（2026-08-01）：prepare_practice_subscription_usage 匿名帳號跳過歸零。
--
-- 設計：訪客額度＝3 則總量、不按月/日重置（monthly counter 即終身計數）。
-- TS 側各 Edge function 已用 noResetResult 跳過重置，但 practice 路徑的重置
-- 在本 RPC 內（且 settle_prefetched_practice_hint 於 SQL 內部再呼叫一次），
-- 不改這裡訪客跨窗口就會被歸零、多領 3 則。
--
-- 解法：函式內查 auth.users.is_anonymous（SECURITY DEFINER、schema-qualified），
-- 匿名帳號跳過兩段歸零 UPDATE，其餘行為（row lock、fail-closed、回傳形狀）
-- byte-for-byte 不變。簽名零改動 → 無 overload/PostgREST cache 問題，
-- SQL 內部呼叫者自動繼承。
--
-- 註：check_and_reset_usage 仍含無條件歸零，但它無 live 呼叫者
--（20260702120100 註記），不動。

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
  v_sub          public.subscriptions%ROWTYPE;
  v_now          TIMESTAMPTZ := now();
  v_month_start  TIMESTAMPTZ;
  v_day_start    TIMESTAMPTZ;
  v_is_anonymous BOOLEAN := FALSE;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'prepare_practice_subscription_usage: p_user_id is required';
  END IF;

  v_month_start := DATE_TRUNC('month', v_now AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  v_day_start := DATE_TRUNC('day', v_now AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';

  SELECT COALESCE(u.is_anonymous, FALSE) INTO v_is_anonymous
  FROM auth.users AS u
  WHERE u.id = p_user_id;

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
  -- 訪客（is_anonymous）永不歸零：總量制。
  IF NOT v_is_anonymous THEN
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
  END IF;

  tier := v_sub.tier;
  monthly_messages_used := v_sub.monthly_messages_used;
  daily_messages_used := v_sub.daily_messages_used;
  daily_reset_at := v_sub.daily_reset_at;
  monthly_reset_at := v_sub.monthly_reset_at;
  RETURN NEXT;
END;
$$;

-- 簽名未變：既有 REVOKE/GRANT（service_role only）隨 CREATE OR REPLACE 保留。
