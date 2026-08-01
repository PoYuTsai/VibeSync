-- 訪客模式移除（2026-08-01 Eric/Bruce 拍板）：prepare_practice_subscription_usage
-- 還原為無條件歸零版本——拿掉 20260801120000 加入的 is_anonymous 跳過分支。
--
-- 匿名登入已於同批全面下線（client 入口、Edge 匿名分支、auth 旗標一併移除，
-- 既有匿名帳號由 ops 清除），DB 端不再需要訪客總量制語意。
-- 其餘行為（row lock、fail-closed、回傳形狀、簽名）byte-for-byte 不變。

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

-- 簽名未變：既有 REVOKE/GRANT（service_role only）隨 CREATE OR REPLACE 保留。
