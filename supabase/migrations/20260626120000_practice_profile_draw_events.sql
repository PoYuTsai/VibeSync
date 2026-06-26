-- AI 實戰練習室「每日翻牌」ledger 與原子扣費 RPC（2026-06-26）。
--
-- 為什麼需要這張表：
--   每日翻牌的「免費次數」與「額外翻牌扣 5 則」必須跨 Edge isolate、跨請求權威
--   成立。client 計數可被偽造（多送/重送/少報），所以「今天已抽幾次、這次免費
--   還是扣 5、是否寫入」只能落在 Postgres，以單一交易原子判定。
--
-- 產品規則（見 docs/superpowers/specs/2026-06-26-practice-card-draw-design.md）：
--   每日免費翻牌：Free 1 / Starter 3 / Essential 5。
--   每日重置點：Asia/Taipei 中午 12:00（reset_window_start_at 由 Edge 計算後傳入）。
--   免費次數用完：
--     Free          → 不開放額外扣點，導升級（不寫 event、不扣費）。
--     Starter/Essential → 額外每次扣 5 則一般訊息 quota（atomic）。
--   續玩同一位 / 切難度 → 不翻牌、不進此表（由 client/Edge 控制，不呼叫本 RPC）。
--
-- 隱私 / 範圍：
--   本表只存「抽牌事件」(profile_id + 成本 + 視窗)，不存任何對話內容或人設文字。
--   聊天扣費仍走既有 practice_chat_sessions ledger，與本表互不影響。
--
-- 失敗方向（與 ADR #19 / practice_chat_sessions 的 user-safe 哲學一致）：
--   扣 quota 與寫 event 在同一交易內，要嘛都成立要嘛都 rollback；競態下同 request
--   重送 → 回放既有事件不重扣（往便宜方向）。絕無「先扣再退」髒狀態。
--
-- 部署順序（DB Migration Deploy Rule）：
--   此 migration 必須先於 practice-chat Edge 新碼上線（Edge push 即 auto-deploy）。
--   新碼會呼叫下面的 claim_practice_profile_draw RPC，RPC 不存在會 500。舊版
--   practice-chat 不呼叫此 RPC，故先套表不影響既有 chat/debrief 行為。
--   套用方式：Supabase MCP apply_migration，**不要** supabase db push（本機/遠端
--   migration 版本號已知分歧）。套完把帳本 version 對齊本檔名。

-- ── Ledger 表 ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.practice_profile_draw_events (
  id                     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  request_id             TEXT        NOT NULL,
  profile_id             TEXT        NOT NULL,
  tier_at_draw           TEXT        NOT NULL,
  reset_window_start_at  TIMESTAMPTZ NOT NULL,
  cost_messages          INTEGER     NOT NULL CHECK (cost_messages IN (0, 5)),
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT practice_draw_request_id_len CHECK (length(request_id) BETWEEN 1 AND 64),
  CONSTRAINT practice_draw_profile_id_len CHECK (length(profile_id) BETWEEN 1 AND 64),
  -- 同 request_id 重送 → idempotent，不重複寫入/扣費。
  UNIQUE (user_id, request_id),
  -- 同一 reset window 內盡量不抽到同一張（每窗最大抽數 << 60，正常永不觸發）。
  UNIQUE (user_id, reset_window_start_at, profile_id)
);

CREATE INDEX IF NOT EXISTS practice_profile_draw_events_user_window_idx
  ON public.practice_profile_draw_events (user_id, reset_window_start_at, created_at DESC);

-- service_role only（與 practice_chat_sessions / analysis_runs 同策略）：
-- RLS 開啟且不建任何 policy → 只有 service_role（bypass RLS）與 SECURITY DEFINER
-- RPC 可碰。client 永遠摸不到這張表。
ALTER TABLE public.practice_profile_draw_events ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.practice_profile_draw_events IS
  'AI 實戰練習室每日翻牌帳本（只存抽牌事件，不存對話）。免費次數/額外扣費權威來源。';

-- ── 原子扣費 RPC ───────────────────────────────────────────────────────────
-- 在「Edge 已選好候選 profile、算好 reset window 與 tier 對應額度」後呼叫。
-- 一次交易內完成：數本窗免費次數 → 決定免費/付費/導升級 → (付費)鎖內複檢 quota
-- → 寫 event → (付費)扣 quota。回傳最新 draw receipt + usage 給 client 同步顯示。
--
-- 設計刻意把「tier→免費額度/是否可付費額外/限額」算在 Edge（_shared/quota.ts 為單
-- 一真實來源），RPC 只收結果（p_free_allowance / p_allow_paid_extra / p_*_limit），
-- 避免 DB 與 Edge 兩處 tier 數字漂移。p_tier 僅作 audit 欄位。
--
-- 扣 quota 不複用 increment_usage()：那支會連帶 +1 users.total_analyses（翻牌不是
-- 分析），故此處在鎖內直接 UPDATE subscriptions 計數，精準且無副作用。
--
-- 錯誤以 RAISE 訊息回報（與 commit_practice_chat_turn 同慣例，Edge 依訊息對應 HTTP）：
--   PRACTICE_DRAW_UPGRADE_REQUIRED        → Free 免費用完，導付費牆（402）。
--   PRACTICE_DRAW_QUOTA_EXCEEDED_MONTHLY  → 付費額外抽但月額不足（429）。
--   PRACTICE_DRAW_QUOTA_EXCEEDED_DAILY    → 付費額外抽但日額不足（429）。
--   PRACTICE_DRAW_PROFILE_CONFLICT        → 同窗同 profile 撞號，Edge 換一張重抽。
--   PRACTICE_DRAW_NO_SUBSCRIPTION         → 查無訂閱列，fail-closed（不抽、不扣）。
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
  v_existing   public.practice_profile_draw_events;
  v_sub        public.subscriptions;
  v_free_used  INTEGER;
  v_cost       INTEGER;
  v_did_charge BOOLEAN;
  v_free_after INTEGER;
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

  -- ── 1. Idempotency：同 request_id 已成功抽過 → 回放，不重扣 ────────────────
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
    RETURN jsonb_build_object(
      'profile_id', v_existing.profile_id,
      'cost_messages', v_existing.cost_messages,
      'free_allowance', p_free_allowance,
      'free_used', v_free_used,
      'free_remaining', GREATEST(0, p_free_allowance - v_free_used),
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

  -- ── 3. 數本 window 已用免費次數（cost=0 的事件）─────────────────────────
  SELECT count(*) INTO v_free_used
  FROM public.practice_profile_draw_events
  WHERE user_id = p_user_id
    AND reset_window_start_at = p_reset_window_start_at
    AND cost_messages = 0;

  -- ── 4. 決定本次成本 ─────────────────────────────────────────────────────
  IF v_free_used < p_free_allowance THEN
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
    -- 並發同 request_id 重送 → 回放既有事件，不重扣。
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
        'free_allowance', p_free_allowance,
        'free_used', v_free_used,
        'free_remaining', GREATEST(0, p_free_allowance - v_free_used),
        'daily_messages_used', v_sub.daily_messages_used,
        'monthly_messages_used', v_sub.monthly_messages_used,
        'idempotent_replay', TRUE
      );
    END IF;
    -- 否則為同 window 同 profile 撞號 → 要求 Edge 換一張重抽。
    RAISE EXCEPTION 'PRACTICE_DRAW_PROFILE_CONFLICT';
  END;

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
    'free_allowance', p_free_allowance,
    'free_used', v_free_after,
    'free_remaining', GREATEST(0, p_free_allowance - v_free_after),
    'daily_messages_used', v_sub.daily_messages_used,
    'monthly_messages_used', v_sub.monthly_messages_used,
    'idempotent_replay', FALSE
  );
END;
$$;

-- service_role only（與 commit_practice_chat_turn 同策略）。
REVOKE EXECUTE ON FUNCTION public.claim_practice_profile_draw(
  UUID, TEXT, TEXT, TIMESTAMPTZ, TEXT, INTEGER, INTEGER, BOOLEAN, INTEGER, INTEGER, BOOLEAN
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_practice_profile_draw(
  UUID, TEXT, TEXT, TIMESTAMPTZ, TEXT, INTEGER, INTEGER, BOOLEAN, INTEGER, INTEGER, BOOLEAN
) TO service_role;

NOTIFY pgrst, 'reload schema';
