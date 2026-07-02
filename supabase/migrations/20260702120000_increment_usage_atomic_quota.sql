-- Batch C#1（2026-07-02 paywall 加固）：increment_usage 扣費原子化。
--
-- 現版（20260316_z_fix_service_role_policies.sql）只擋非正數，無鎖、無上限
-- 檢查：並發請求全數通過 Edge preflight 後各自 UPDATE，counters 可衝破 tier
-- 上限（多付 AI 成本）。本版：
--   1. 交易內 SELECT ... FOR UPDATE 鎖 subscriptions row，並發扣費串行化。
--   2. 新增 p_monthly_limit / p_daily_limit（DEFAULT NULL）。非 NULL 時在鎖內
--      複檢「月先於日」（與 _shared/quota.ts checkQuota 一致），超限 RAISE：
--        QUOTA_EXCEEDED_MONTHLY / QUOTA_EXCEEDED_DAILY
--      Edge 以 message.includes 偵測（同 practice draw 慣例）。RAISE 令整筆
--      交易 rollback（含 wrapper RPC 的 run insert），絕無半扣。
--   3. 上限值一律由 Edge 傳入（pricing 權威在 _shared/quota.ts），SQL 不
--      複製 pricing 表。
--
-- 向後相容：
--   - 必須 DROP 舊 2-arg 版本再建 4-arg 版本。只 CREATE 會產生新舊 overload
--     並存，既有 2-arg 呼叫（create_charged_analysis_run /
--     charge_stream_analysis_run / practice settle RPC）會 ambiguity 報錯。
--   - 4-arg 版本對 2-arg 呼叫（limits 落 DEFAULT NULL）行為＝現版＋row lock，
--     無上限檢查——wrapper RPC 路徑維持 preflight-only 防護（設計定稿記載的
--     已知殘餘，改簽名另案）。
--   - subscription row 不存在時保留現版 silent no-op（現版 UPDATE 0 rows
--     同義；所有 Edge 呼叫點前面都有 self-heal insert）。

DROP FUNCTION IF EXISTS public.increment_usage(uuid, integer);

CREATE FUNCTION public.increment_usage(
  p_user_id UUID,
  p_messages INTEGER DEFAULT 1,
  p_monthly_limit INTEGER DEFAULT NULL,
  p_daily_limit INTEGER DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub public.subscriptions%ROWTYPE;
BEGIN
  IF p_messages IS NULL OR p_messages <= 0 THEN
    RAISE EXCEPTION 'p_messages must be a positive integer';
  END IF;

  SELECT * INTO v_sub
  FROM public.subscriptions
  WHERE user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    -- 舊版 UPDATE 打 0 rows 的既有語義：無 row 不扣、不報錯。
    RETURN;
  END IF;

  IF p_monthly_limit IS NOT NULL
     AND v_sub.monthly_messages_used + p_messages > p_monthly_limit THEN
    RAISE EXCEPTION 'QUOTA_EXCEEDED_MONTHLY';
  END IF;

  IF p_daily_limit IS NOT NULL
     AND v_sub.daily_messages_used + p_messages > p_daily_limit THEN
    RAISE EXCEPTION 'QUOTA_EXCEEDED_DAILY';
  END IF;

  UPDATE public.subscriptions
  SET monthly_messages_used = monthly_messages_used + p_messages,
      daily_messages_used = daily_messages_used + p_messages
  WHERE user_id = p_user_id;

  UPDATE public.users
  SET total_analyses = total_analyses + 1
  WHERE id = p_user_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION
  public.increment_usage(uuid, integer, integer, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION
  public.increment_usage(uuid, integer, integer, integer)
  FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.increment_usage(uuid, integer, integer, integer) TO service_role;
