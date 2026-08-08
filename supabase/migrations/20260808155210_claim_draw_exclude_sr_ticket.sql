-- SR 限定翻牌券（20260808155202）配套：主 claim RPC 的 free_used 計數排除券抽。
--
-- 唯一語意變更＝4 個 free_used 計數位點（step 1 replay、2a 鎖後 replay、step 3、
-- unique_violation replay）加 `AND bonus_source IS NULL`：券抽事件也是 cost=0，
-- 不排除會偷吃 tier 每日免費額度（Starter 用券後當天只剩 2 次免費翻牌）。
-- 其餘 byte-for-byte 沿用 20260802120000_claim_draw_bonus_atomic.sql（含註解），
-- 簽名、錯誤碼、鎖順序（subscriptions → bonuses）、贈抽懶消耗語意全部不變。

CREATE OR REPLACE FUNCTION public.claim_practice_profile_draw(
  p_user_id                UUID,
  p_request_id             TEXT,
  p_profile_id             TEXT,
  p_reset_window_start_at  TIMESTAMPTZ,
  p_tier                   TEXT,
  p_free_allowance         INTEGER,
  p_extra_cost             INTEGER,
  p_allow_paid_extra       BOOLEAN,
  p_daily_limit            INTEGER,
  p_monthly_limit          INTEGER,
  p_charge_quota           BOOLEAN DEFAULT TRUE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing        public.practice_profile_draw_events;
  v_sub             public.subscriptions;
  v_free_used       INTEGER;
  v_cost            INTEGER;
  v_did_charge      BOOLEAN;
  v_free_after      INTEGER;
  v_bonus_available BOOLEAN := FALSE;
  v_allowance       INTEGER;
BEGIN
  -- 輸入驗證（SECURITY DEFINER 下 RLS 不擋垃圾輸入，逐項明確驗）。
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'claim_practice_profile_draw: p_user_id is required';
  END IF;
  IF p_request_id IS NULL OR length(p_request_id) = 0 OR length(p_request_id) > 64 THEN
    RAISE EXCEPTION 'claim_practice_profile_draw: invalid p_request_id';
  END IF;
  IF p_profile_id IS NULL OR length(p_profile_id) = 0 OR length(p_profile_id) > 64 THEN
    RAISE EXCEPTION 'claim_practice_profile_draw: invalid p_profile_id';
  END IF;
  IF p_reset_window_start_at IS NULL THEN
    RAISE EXCEPTION 'claim_practice_profile_draw: p_reset_window_start_at is required';
  END IF;
  IF p_free_allowance IS NULL OR p_free_allowance < 0 THEN
    RAISE EXCEPTION 'claim_practice_profile_draw: invalid p_free_allowance';
  END IF;
  -- 額外翻牌成本鎖死為 5（與 ledger CHECK cost_messages IN (0,5) 一致）。
  IF p_extra_cost IS NULL OR p_extra_cost <> 5 THEN
    RAISE EXCEPTION 'claim_practice_profile_draw: invalid p_extra_cost';
  END IF;

  -- ── 1. Idempotency：同 request_id 已成功抽過 → 回放，不重扣、不碰贈抽消耗 ──
  SELECT * INTO v_existing
  FROM public.practice_profile_draw_events
  WHERE user_id = p_user_id AND request_id = p_request_id;

  IF FOUND THEN
    SELECT * INTO v_sub FROM public.subscriptions WHERE user_id = p_user_id;
    SELECT count(*) INTO v_free_used
    FROM public.practice_profile_draw_events
    WHERE user_id = p_user_id
      AND reset_window_start_at = p_reset_window_start_at
      AND cost_messages = 0
      AND bonus_source IS NULL;
    -- replay 只讀不鎖：回傳的 allowance 反映現況（含未消耗贈抽），不做任何寫入。
    SELECT (b.consumed_at IS NULL) INTO v_bonus_available
    FROM public.practice_draw_bonuses AS b
    WHERE b.user_id = p_user_id;
    v_allowance := p_free_allowance +
      (CASE WHEN COALESCE(v_bonus_available, FALSE) THEN 1 ELSE 0 END);
    RETURN jsonb_build_object(
      'profile_id', v_existing.profile_id,
      'cost_messages', v_existing.cost_messages,
      'free_allowance', v_allowance,
      'free_used', v_free_used,
      'free_remaining', GREATEST(0, v_allowance - v_free_used),
      'daily_messages_used', COALESCE(v_sub.daily_messages_used, 0),
      'monthly_messages_used', COALESCE(v_sub.monthly_messages_used, 0),
      'idempotent_replay', TRUE
    );
  END IF;

  -- ── 2. 鎖訂閱列（與扣費同交易，原子）─────────────────────────────────────
  SELECT * INTO v_sub
  FROM public.subscriptions
  WHERE user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PRACTICE_DRAW_NO_SUBSCRIPTION';
  END IF;

  -- ── 2a. 鎖後二次 replay 檢查（Codex 二輪 P2：併發同 requestId 的後到者從
  --     訂閱鎖醒來時，先到者的 event 可能已 commit——不先回放，會在下方
  --     402/429 判定被錯擋，破壞冪等。回放不消耗贈抽。）────────────────────
  SELECT * INTO v_existing
  FROM public.practice_profile_draw_events
  WHERE user_id = p_user_id AND request_id = p_request_id;

  IF FOUND THEN
    SELECT count(*) INTO v_free_used
    FROM public.practice_profile_draw_events
    WHERE user_id = p_user_id
      AND reset_window_start_at = p_reset_window_start_at
      AND cost_messages = 0
      AND bonus_source IS NULL;
    SELECT (b.consumed_at IS NULL) INTO v_bonus_available
    FROM public.practice_draw_bonuses AS b
    WHERE b.user_id = p_user_id;
    v_allowance := p_free_allowance +
      (CASE WHEN COALESCE(v_bonus_available, FALSE) THEN 1 ELSE 0 END);
    RETURN jsonb_build_object(
      'profile_id', v_existing.profile_id,
      'cost_messages', v_existing.cost_messages,
      'free_allowance', v_allowance,
      'free_used', v_free_used,
      'free_remaining', GREATEST(0, v_allowance - v_free_used),
      'daily_messages_used', v_sub.daily_messages_used,
      'monthly_messages_used', v_sub.monthly_messages_used,
      'idempotent_replay', TRUE
    );
  END IF;

  -- ── 2b. 鎖贈抽列（Codex P1 根治：判定與消耗同交易串行）────────────────────
  v_bonus_available := FALSE;
  SELECT (b.consumed_at IS NULL) INTO v_bonus_available
  FROM public.practice_draw_bonuses AS b
  WHERE b.user_id = p_user_id
  FOR UPDATE;
  IF NOT FOUND THEN
    v_bonus_available := FALSE;
  END IF;
  v_allowance := p_free_allowance +
    (CASE WHEN v_bonus_available THEN 1 ELSE 0 END);

  -- ── 3. 數本 window 已用免費次數（cost=0 的事件；排除 SR 券抽）───────────
  SELECT count(*) INTO v_free_used
  FROM public.practice_profile_draw_events
  WHERE user_id = p_user_id
    AND reset_window_start_at = p_reset_window_start_at
    AND cost_messages = 0
    AND bonus_source IS NULL;

  -- ── 4. 決定本次成本（tier 額度＋贈抽合併判定）────────────────────────────
  IF v_free_used < v_allowance THEN
    v_cost := 0;
  ELSE
    IF NOT COALESCE(p_allow_paid_extra, FALSE) THEN
      -- Free：免費用完不開放額外扣點 → 導升級。不寫 event、不扣費。
      RAISE EXCEPTION 'PRACTICE_DRAW_UPGRADE_REQUIRED';
    END IF;
    v_cost := p_extra_cost;
  END IF;

  -- 測試帳號（p_charge_quota=false）：仍寫 event，但不真扣 quota。
  v_did_charge := (v_cost > 0) AND COALESCE(p_charge_quota, TRUE);

  -- ── 5. 付費額外抽：鎖內 quota headroom 複檢（防 Edge preflight 後競態）────
  --     月先於日，與 _shared/quota.ts checkQuota 一致。
  IF v_did_charge THEN
    IF p_monthly_limit IS NULL OR p_daily_limit IS NULL THEN
      RAISE EXCEPTION 'claim_practice_profile_draw: paid extra needs limits';
    END IF;
    IF v_sub.monthly_messages_used + v_cost > p_monthly_limit THEN
      RAISE EXCEPTION 'PRACTICE_DRAW_QUOTA_EXCEEDED_MONTHLY';
    END IF;
    IF v_sub.daily_messages_used + v_cost > p_daily_limit THEN
      RAISE EXCEPTION 'PRACTICE_DRAW_QUOTA_EXCEEDED_DAILY';
    END IF;
  END IF;

  -- ── 6. 寫 event（unique 防重複 profile / 重複 request）──────────────────
  BEGIN
    INSERT INTO public.practice_profile_draw_events (
      user_id, request_id, profile_id, tier_at_draw,
      reset_window_start_at, cost_messages
    ) VALUES (
      p_user_id, p_request_id, p_profile_id, COALESCE(p_tier, 'free'),
      p_reset_window_start_at, v_cost
    );
  EXCEPTION WHEN unique_violation THEN
    -- 並發同 request_id 重送 → 回放既有事件，不重扣、不消耗贈抽。
    SELECT * INTO v_existing
    FROM public.practice_profile_draw_events
    WHERE user_id = p_user_id AND request_id = p_request_id;
    IF FOUND THEN
      SELECT count(*) INTO v_free_used
      FROM public.practice_profile_draw_events
      WHERE user_id = p_user_id
        AND reset_window_start_at = p_reset_window_start_at
        AND cost_messages = 0
        AND bonus_source IS NULL;
      RETURN jsonb_build_object(
        'profile_id', v_existing.profile_id,
        'cost_messages', v_existing.cost_messages,
        'free_allowance', v_allowance,
        'free_used', v_free_used,
        'free_remaining', GREATEST(0, v_allowance - v_free_used),
        'daily_messages_used', v_sub.daily_messages_used,
        'monthly_messages_used', v_sub.monthly_messages_used,
        'idempotent_replay', TRUE
      );
    END IF;
    -- 否則為同 window 同 profile 撞號 → 要求 Edge 換一張重抽。
    RAISE EXCEPTION 'PRACTICE_DRAW_PROFILE_CONFLICT';
  END;

  -- ── 6b. 贈抽懶消耗（同交易；寫入成功才會走到這）─────────────────────────
  --     本次 cost=0 且寫入前本窗免費數已達 tier 額度＝這一抽靠贈抽成立。
  IF v_cost = 0 AND v_bonus_available AND v_free_used >= p_free_allowance THEN
    UPDATE public.practice_draw_bonuses
    SET consumed_at = now()
    WHERE user_id = p_user_id AND consumed_at IS NULL;
  END IF;

  -- ── 7. 真扣 quota（與 insert 同交易；UPDATE RAISE 則整體 rollback）────────
  --     不用 increment_usage()（避免連帶 +1 total_analyses）；列已 FOR UPDATE 鎖住。
  IF v_did_charge THEN
    UPDATE public.subscriptions
    SET monthly_messages_used = monthly_messages_used + v_cost,
        daily_messages_used   = daily_messages_used + v_cost
    WHERE user_id = p_user_id;
    v_sub.daily_messages_used   := v_sub.daily_messages_used + v_cost;
    v_sub.monthly_messages_used := v_sub.monthly_messages_used + v_cost;
  END IF;

  -- ── 8. 算回傳 free_used（付費抽不佔免費額度）─────────────────────────────
  IF v_cost = 0 THEN
    v_free_after := v_free_used + 1;
  ELSE
    v_free_after := v_free_used;
  END IF;

  RETURN jsonb_build_object(
    'profile_id', p_profile_id,
    'cost_messages', v_cost,
    'free_allowance', v_allowance,
    'free_used', v_free_after,
    'free_remaining', GREATEST(0, v_allowance - v_free_after),
    'daily_messages_used', v_sub.daily_messages_used,
    'monthly_messages_used', v_sub.monthly_messages_used,
    'idempotent_replay', FALSE
  );
END;
$$;

-- 簽名未變：既有 REVOKE/GRANT（service_role only）隨 CREATE OR REPLACE 保留。

NOTIFY pgrst, 'reload schema';
