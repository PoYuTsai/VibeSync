-- Batch C#4（2026-07-02 paywall 加固）：check_and_reset_usage 補 row lock 除 TOCTOU。
--
-- 現版（20260509_fix_check_and_reset_usage_limits.sql）SELECT 無鎖，讀到的
-- v_sub 與後續 UPDATE ... = 0 之間有競態：跨日/月邊界時可覆寫並發請求剛扣
-- 的額度。補 FOR UPDATE 讓讀取即權威（與 increment_usage v2、
-- claim_practice_profile_draw 同款），其餘行為不變。
--
-- 註：本函式無 live 呼叫者（20260316 起 REVOKE 出 client、Edge 亦不呼叫），
-- 保留是為舊環境相容；順手除競態、不刪除。tier CASE hardcode 是既有 legacy，
-- 上限權威在 Edge `_shared/quota.ts`，此處不動。

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
  SELECT * INTO v_sub FROM public.subscriptions
  WHERE user_id = p_user_id
  FOR UPDATE;

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
