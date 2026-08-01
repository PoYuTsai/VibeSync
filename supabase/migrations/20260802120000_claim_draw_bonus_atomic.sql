-- 審修（Codex BLOCKED P1/P2，2026-08-02）：起步贈抽的判定與消耗搬進
-- claim_practice_profile_draw 同一交易，Edge 不再先讀後傳動態 allowance。
--
-- P1 根治：贈抽列 FOR UPDATE——跨台北中午窗邊界的兩個併發 draw 會在 bonus 列
-- 上串行，後者必然看見前者 commit 的 consumed_at，同一顆贈抽不可能發出兩次
-- cost=0（原 Edge 先讀後傳的寫法在兩窗各自的免費計數下可雙花）。
-- P2 根治：idempotent replay 兩條路徑都在寫入前 return，永不觸碰消耗邏輯；
-- replay 只順帶讀（不鎖）bonus 讓回傳的 free_allowance 與現況一致。
--
-- 語意不變處：簽名、錯誤碼、鎖順序（subscriptions → bonuses，全 repo 唯一鎖
-- bonuses 的路徑）、free_remaining 計算、測試帳號 p_charge_quota 行為。
-- p_free_allowance 回歸「純 tier 額度」（Edge 傳 drawAllowanceForTier(tier)）。
--
-- 消耗條件（懶消耗）：本次 cost=0 且寫入前本窗免費數 >= tier 額度＝這一抽是
-- 靠贈抽才成立，標 consumed_at；tier 額度內的免費抽不動贈抽（對用戶最有利）。

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
      AND cost_messages = 0;
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

  -- ── 3. 數本 window 已用免費次數（cost=0 的事件）─────────────────────────
  SELECT count(*) INTO v_free_used
  FROM public.practice_profile_draw_events
  WHERE user_id = p_user_id
    AND reset_window_start_at = p_reset_window_start_at
    AND cost_messages = 0;

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
        AND cost_messages = 0;
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
