-- SR 限定翻牌消耗 RPC（2026-08-08，配套 20260808155202 券表）。
--
-- 流程：冪等 replay（鎖前）→ 券列 FOR UPDATE → 鎖後二次 replay → 寫抽卡事件
-- （cost=0, bonus_source='subscription_sr'）→ 標 consumed，全部同交易原子。
-- 券抽不佔每日免費額度（主 RPC 計數已排除 bonus_source，見 20260808155210）、
-- 不扣一般 quota、不驗當下 tier（拍板：已送出的券退訂不回收）。
--
-- 鎖序：只鎖 practice_sr_draw_tickets（本 RPC 專屬表）＋事件表 unique 防撞，
-- 不碰 subscriptions / practice_draw_bonuses 的鎖 → 與主 claim RPC
-- （subscriptions → bonuses）無死鎖環。
--
-- 錯誤碼：
--   PRACTICE_SR_TICKET_NOT_AVAILABLE  無券或已用（fail-closed，Edge 映 409）
--   PRACTICE_DRAW_PROFILE_CONFLICT    同窗同 profile 撞號（Edge 換一張重抽）

CREATE OR REPLACE FUNCTION public.claim_practice_sr_ticket_draw(
  p_user_id               UUID,
  p_request_id            TEXT,
  p_profile_id            TEXT,
  p_reset_window_start_at TIMESTAMPTZ,
  p_tier                  TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing public.practice_profile_draw_events;
  v_ticket   public.practice_sr_draw_tickets;
BEGIN
  -- 輸入驗證（SECURITY DEFINER 下 RLS 不擋垃圾輸入，逐項明確驗）。
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'claim_practice_sr_ticket_draw: p_user_id is required';
  END IF;
  IF p_request_id IS NULL OR length(p_request_id) = 0 OR length(p_request_id) > 64 THEN
    RAISE EXCEPTION 'claim_practice_sr_ticket_draw: invalid p_request_id';
  END IF;
  IF p_profile_id IS NULL OR length(p_profile_id) = 0 OR length(p_profile_id) > 64 THEN
    RAISE EXCEPTION 'claim_practice_sr_ticket_draw: invalid p_profile_id';
  END IF;
  IF p_reset_window_start_at IS NULL THEN
    RAISE EXCEPTION 'claim_practice_sr_ticket_draw: p_reset_window_start_at is required';
  END IF;

  -- ── 1. 冪等 replay（鎖前）：同 requestId 已抽過 → 回放，不碰券 ─────────────
  SELECT * INTO v_existing
  FROM public.practice_profile_draw_events
  WHERE user_id = p_user_id AND request_id = p_request_id;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'profile_id', v_existing.profile_id,
      'idempotent_replay', TRUE
    );
  END IF;

  -- ── 2. 鎖券列；無券或已用 → NOT_AVAILABLE（fail-closed）────────────────────
  SELECT * INTO v_ticket
  FROM public.practice_sr_draw_tickets
  WHERE user_id = p_user_id
  FOR UPDATE;
  IF NOT FOUND OR v_ticket.consumed_at IS NOT NULL THEN
    RAISE EXCEPTION 'PRACTICE_SR_TICKET_NOT_AVAILABLE';
  END IF;

  -- ── 2a. 鎖後二次 replay：併發同 requestId 的後到者從券鎖醒來時，先到者的
  --     事件可能已 commit（比照主 claim RPC 2a），不回放會把冪等重試錯打成
  --     NOT_AVAILABLE。────────────────────────────────────────────────────
  SELECT * INTO v_existing
  FROM public.practice_profile_draw_events
  WHERE user_id = p_user_id AND request_id = p_request_id;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'profile_id', v_existing.profile_id,
      'idempotent_replay', TRUE
    );
  END IF;

  -- ── 3. 寫事件（unique 防重複 request / 同窗重複 profile）───────────────────
  BEGIN
    INSERT INTO public.practice_profile_draw_events (
      user_id, request_id, profile_id, tier_at_draw,
      reset_window_start_at, cost_messages, bonus_source
    ) VALUES (
      p_user_id, p_request_id, p_profile_id, COALESCE(p_tier, 'free'),
      p_reset_window_start_at, 0, 'subscription_sr'
    );
  EXCEPTION WHEN unique_violation THEN
    SELECT * INTO v_existing
    FROM public.practice_profile_draw_events
    WHERE user_id = p_user_id AND request_id = p_request_id;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'profile_id', v_existing.profile_id,
        'idempotent_replay', TRUE
      );
    END IF;
    -- 同窗同 profile 撞號 → 要求 Edge 換一張重抽。
    RAISE EXCEPTION 'PRACTICE_DRAW_PROFILE_CONFLICT';
  END;

  -- ── 4. 標 consumed（與事件同交易；任何 RAISE 整體 rollback，券不會白扣）────
  UPDATE public.practice_sr_draw_tickets
  SET consumed_at = now(), consumed_request_id = p_request_id
  WHERE user_id = p_user_id;

  RETURN jsonb_build_object(
    'profile_id', p_profile_id,
    'idempotent_replay', FALSE
  );
END;
$$;

-- service_role only（client 一律經 Edge）。
REVOKE ALL ON FUNCTION public.claim_practice_sr_ticket_draw(UUID, TEXT, TEXT, TIMESTAMPTZ, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_practice_sr_ticket_draw(UUID, TEXT, TEXT, TIMESTAMPTZ, TEXT) FROM anon;
REVOKE ALL ON FUNCTION public.claim_practice_sr_ticket_draw(UUID, TEXT, TEXT, TIMESTAMPTZ, TEXT) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.claim_practice_sr_ticket_draw(UUID, TEXT, TEXT, TIMESTAMPTZ, TEXT) TO service_role;

NOTIFY pgrst, 'reload schema';
