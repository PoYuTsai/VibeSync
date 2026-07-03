-- 全面模型呼叫 per-user 限流（2026-07-03，docs/plans/2026-07-03-model-rate-limit-design.md）。
--
-- 上架前收掉「成本濫用」整類問題：opener、analyze、coach-chat、coach-follow-up、
-- practice turn、practice hint 六個會打模型的入口統一鋪分鐘窗＋日窗節流。
-- 同案收斂 opener P2-2（並發同 id storm 在扣費去重點前燒模型成本——分鐘限流
-- 直接封頂燒錢上界）。Eric 拍板：一張通用表＋scope 鍵；既有 ocr_rate_limits
-- 已上線不動、不遷入。
--
-- 語義照抄 increment_ocr_usage（20260702130000）：
--   - 交易內 INSERT ON CONFLICT DO NOTHING → SELECT FOR UPDATE → 窗口重置 →
--     上限檢查 → UPDATE。並發串行化、絕無 lost update。
--   - 超限 RAISE（MODEL_RATE_LIMITED_MINUTE / MODEL_RATE_LIMITED_DAILY），Edge
--     以 message.includes 偵測映射 429。
--   - 限流值一律由 Edge 傳入（_shared/model_rate_limit.ts），SQL 不寫死。
--   - 分鐘窗＝fixed window anchored at first request；日窗＝UTC 日翻轉重置
--     （台北早上 8 點恢復）。
--   - scope 隔離：(user_id, scope) 複合 PK，各面計數互不影響。
--
-- 套用方式：Supabase MCP apply_migration，**不要** supabase db push（本機/遠端
-- migration 版本號已知分歧）。套完把帳本 version 對齊本檔名。

-- ── 計數表 ──────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.model_call_rate_limits (
  user_id             UUID        NOT NULL
                                  REFERENCES auth.users(id) ON DELETE CASCADE,
  scope               TEXT        NOT NULL
                                  CHECK (char_length(scope) BETWEEN 1 AND 32),
  minute_window_start TIMESTAMPTZ NOT NULL,
  minute_count        INTEGER     NOT NULL DEFAULT 0 CHECK (minute_count >= 0),
  day_window_start    TIMESTAMPTZ NOT NULL,
  day_count           INTEGER     NOT NULL DEFAULT 0 CHECK (day_count >= 0),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, scope)
);

-- service_role only（同 ocr_rate_limits 策略）：RLS 開啟且不建任何 policy →
-- 只有 service_role（bypass RLS）與 SECURITY DEFINER RPC 可碰。
ALTER TABLE public.model_call_rate_limits ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.model_call_rate_limits IS
  '模型呼叫入口節流計數：分鐘窗＋UTC 日窗，(user_id, scope) 一 row。'
  '與訂閱額度（subscriptions）完全獨立；OCR 限流另在 ocr_rate_limits。';

-- ── 原子計數 RPC ─────────────────────────────────────────────────────────────
-- Edge 在 !accountIsTest 時、打模型之前呼叫。計 attempt 不計 success
-- （限的是成本不是產出）。超限 RAISE 令整筆交易 rollback（含首次請求的
-- INSERT），計數絕無污染。
CREATE OR REPLACE FUNCTION public.increment_model_usage(
  p_user_id UUID,
  p_scope TEXT,
  p_minute_limit INTEGER,
  p_daily_limit INTEGER
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.model_call_rate_limits%ROWTYPE;
  v_now TIMESTAMPTZ := now();
  v_minute_count INTEGER;
  v_minute_window_start TIMESTAMPTZ;
  v_day_count INTEGER;
  v_day_window_start TIMESTAMPTZ;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'increment_model_usage: p_user_id is required';
  END IF;
  IF p_scope IS NULL OR char_length(p_scope) NOT BETWEEN 1 AND 32 THEN
    RAISE EXCEPTION 'increment_model_usage: invalid p_scope';
  END IF;
  IF p_minute_limit IS NULL OR p_minute_limit <= 0 THEN
    RAISE EXCEPTION 'increment_model_usage: invalid p_minute_limit';
  END IF;
  IF p_daily_limit IS NULL OR p_daily_limit <= 0 THEN
    RAISE EXCEPTION 'increment_model_usage: invalid p_daily_limit';
  END IF;

  -- 先插後鎖回讀：避免「SELECT 無 row → INSERT 撞 23505」競態。
  INSERT INTO public.model_call_rate_limits
    (user_id, scope, minute_window_start, minute_count,
     day_window_start, day_count)
  VALUES (p_user_id, p_scope, v_now, 0, v_now, 0)
  ON CONFLICT (user_id, scope) DO NOTHING;

  SELECT * INTO v_row
  FROM public.model_call_rate_limits
  WHERE user_id = p_user_id AND scope = p_scope
  FOR UPDATE;

  -- 分鐘窗：滿 60 秒即重置歸零。
  IF v_now - v_row.minute_window_start >= interval '60 seconds' THEN
    v_minute_window_start := v_now;
    v_minute_count := 0;
  ELSE
    v_minute_window_start := v_row.minute_window_start;
    v_minute_count := v_row.minute_count;
  END IF;

  -- 日窗：UTC 日翻轉即重置（與主額度 sameUtcDay 同語義）。
  IF date_trunc('day', v_now AT TIME ZONE 'UTC')
     <> date_trunc('day', v_row.day_window_start AT TIME ZONE 'UTC') THEN
    v_day_window_start := v_now;
    v_day_count := 0;
  ELSE
    v_day_window_start := v_row.day_window_start;
    v_day_count := v_row.day_count;
  END IF;

  -- 分鐘先判（先擋短窗，用戶訊息較不悲觀：等一分鐘 vs 等明天）。
  IF v_minute_count + 1 > p_minute_limit THEN
    RAISE EXCEPTION 'MODEL_RATE_LIMITED_MINUTE';
  END IF;
  IF v_day_count + 1 > p_daily_limit THEN
    RAISE EXCEPTION 'MODEL_RATE_LIMITED_DAILY';
  END IF;

  UPDATE public.model_call_rate_limits
  SET minute_window_start = v_minute_window_start,
      minute_count = v_minute_count + 1,
      day_window_start = v_day_window_start,
      day_count = v_day_count + 1,
      updated_at = v_now
  WHERE user_id = p_user_id AND scope = p_scope;
END;
$$;

REVOKE EXECUTE ON FUNCTION
  public.increment_model_usage(uuid, text, integer, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION
  public.increment_model_usage(uuid, text, integer, integer)
  FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.increment_model_usage(uuid, text, integer, integer) TO service_role;

-- 新函數必須刷新 PostgREST schema cache，否則 Edge rpc() 在 cache 過期前
-- 會吃 function not found（那會落 Edge 側 fail-open）。
NOTIFY pgrst, 'reload schema';
