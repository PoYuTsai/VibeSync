-- 圖鑑額度列 v2：唯讀翻牌額度狀態 RPC（get_practice_draw_status）。
--
-- 動機：v1 額度列只能顯示本 session draw 回應已知值（跨 session 空白）。
-- 本 RPC 讓 Edge 的 draw_status 唯讀路由拿到本窗權威計數——「窗內用量」
-- 計算收在 SQL、與 claim 同語意，client/Edge 不得在 TS 重算計數。
--
-- 鐵律：與 claim_practice_profile_draw（20260808155210）的 free_used 謂詞
-- 保持 byte-for-byte 同語意——cost_messages = 0 AND bonus_source IS NULL
-- （排除 SR 券抽）＋未消耗起步贈抽 +1 進 allowance。改 claim 的計數謂詞
-- 必同批改這裡，否則額度列會跟扣費真相漂移。
--
-- 唯讀：不 reset、不 FOR UPDATE、不寫任何列。窗起點由 Edge 以
-- taipeiNoonResetWindow（與 claim 呼叫同一個 TS 函式）算好傳入，全系統
-- 窗實作維持單一份。

CREATE OR REPLACE FUNCTION public.get_practice_draw_status(
  p_user_id                UUID,
  p_reset_window_start_at  TIMESTAMPTZ,
  p_free_allowance         INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_free_used       INTEGER;
  v_bonus_available BOOLEAN := FALSE;
  v_allowance       INTEGER;
BEGIN
  -- 輸入驗證（SECURITY DEFINER 下 RLS 不擋垃圾輸入，逐項明確驗）。
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'get_practice_draw_status: p_user_id is required';
  END IF;
  IF p_reset_window_start_at IS NULL THEN
    RAISE EXCEPTION 'get_practice_draw_status: p_reset_window_start_at is required';
  END IF;
  IF p_free_allowance IS NULL OR p_free_allowance < 0 THEN
    RAISE EXCEPTION 'get_practice_draw_status: invalid p_free_allowance';
  END IF;

  -- 本窗已用免費次數：謂詞同 claim step 3（cost=0、排除 SR 券抽）。
  SELECT count(*) INTO v_free_used
  FROM public.practice_profile_draw_events
  WHERE user_id = p_user_id
    AND reset_window_start_at = p_reset_window_start_at
    AND cost_messages = 0
    AND bonus_source IS NULL;

  -- 未消耗起步贈抽 +1 進 allowance：同 claim replay 分支（只讀不鎖）。
  SELECT (b.consumed_at IS NULL) INTO v_bonus_available
  FROM public.practice_draw_bonuses AS b
  WHERE b.user_id = p_user_id;
  v_allowance := p_free_allowance +
    (CASE WHEN COALESCE(v_bonus_available, FALSE) THEN 1 ELSE 0 END);

  RETURN jsonb_build_object(
    'free_allowance', v_allowance,
    'free_used', v_free_used,
    'free_remaining', GREATEST(0, v_allowance - v_free_used)
  );
END;
$$;

-- service_role only（client 一律經 Edge）。
REVOKE ALL ON FUNCTION public.get_practice_draw_status(UUID, TIMESTAMPTZ, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_practice_draw_status(UUID, TIMESTAMPTZ, INTEGER) FROM anon;
REVOKE ALL ON FUNCTION public.get_practice_draw_status(UUID, TIMESTAMPTZ, INTEGER) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_practice_draw_status(UUID, TIMESTAMPTZ, INTEGER) TO service_role;

NOTIFY pgrst, 'reload schema';
