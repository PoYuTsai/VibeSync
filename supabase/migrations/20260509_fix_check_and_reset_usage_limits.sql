-- Keep legacy DB quota helper aligned with the current pricing table.
-- Edge Functions perform authoritative checks today, but this function still
-- exists in older databases and fresh local environments.

CREATE OR REPLACE FUNCTION public.check_and_reset_usage(p_user_id UUID)
RETURNS TABLE(
  can_use BOOLEAN,
  messages_remaining INTEGER,
  daily_remaining INTEGER
) AS $$
DECLARE
  v_sub RECORD;
  v_monthly_limit INTEGER;
  v_daily_limit INTEGER;
BEGIN
  SELECT * INTO v_sub FROM public.subscriptions WHERE user_id = p_user_id;

  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, 0, 0;
    RETURN;
  END IF;

  CASE v_sub.tier
    WHEN 'free' THEN
      v_monthly_limit := 30;
      v_daily_limit := 15;
    WHEN 'starter' THEN
      v_monthly_limit := 300;
      v_daily_limit := 50;
    WHEN 'essential' THEN
      v_monthly_limit := 800;
      v_daily_limit := 120;
    ELSE
      v_monthly_limit := 30;
      v_daily_limit := 15;
  END CASE;

  IF v_sub.monthly_reset_at < DATE_TRUNC('month', NOW()) THEN
    UPDATE public.subscriptions
    SET monthly_messages_used = 0,
        monthly_reset_at = DATE_TRUNC('month', NOW())
    WHERE user_id = p_user_id;
    v_sub.monthly_messages_used := 0;
  END IF;

  IF v_sub.daily_reset_at < DATE_TRUNC('day', NOW()) THEN
    UPDATE public.subscriptions
    SET daily_messages_used = 0,
        daily_reset_at = DATE_TRUNC('day', NOW())
    WHERE user_id = p_user_id;
    v_sub.daily_messages_used := 0;
  END IF;

  RETURN QUERY SELECT
    (
      v_sub.monthly_messages_used < v_monthly_limit
      AND v_sub.daily_messages_used < v_daily_limit
    ),
    (v_monthly_limit - v_sub.monthly_messages_used),
    (v_daily_limit - v_sub.daily_messages_used);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
