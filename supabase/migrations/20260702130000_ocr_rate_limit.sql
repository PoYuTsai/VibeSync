-- recognizeOnly OCR 限流（2026-07-02，docs/plans/2026-07-02-ocr-rate-limit-design.md）。
--
-- recognizeOnly 是免費 Sonnet vision 入口，原本零限流＝成本暴露面（Bruce 掃描
-- 第二輪唯一未修 P1）。Eric 拍板：每用戶 6 次/分鐘、60 次/天。
--
-- 設計沿 Batch C increment_usage 慣例：
--   - 交易內 INSERT ON CONFLICT DO NOTHING → SELECT FOR UPDATE → 窗口重置 →
--     上限檢查 → UPDATE。並發串行化、絕無 lost update（I2）。
--   - 超限 RAISE（OCR_RATE_LIMITED_MINUTE / OCR_RATE_LIMITED_DAILY），Edge 以
--     message.includes 偵測映射 429（同 QUOTA_EXCEEDED_* / PRACTICE_DRAW_* 慣例）。
--   - 限流值一律由 Edge 傳入，SQL 不寫死（I7，同「pricing 權威在 code」原則）。
--   - 與 subscriptions / increment_usage 零交集（I3）：獨立表、獨立 RPC。
--
-- 窗口語義：
--   - 分鐘窗＝fixed window anchored at first request（now - window_start >= 60s
--     即歸零重計）。最壞突發 12 次/滑動分鐘，換單 row per user、零清理 job。
--   - 日窗＝UTC 日翻轉重置（與主額度 daily reset 同語義＝台北早上 8 點恢復）。
--
-- 套用方式：Supabase MCP apply_migration，**不要** supabase db push（本機/遠端
-- migration 版本號已知分歧）。套完把帳本 version 對齊本檔名。

-- ── 計數表 ──────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ocr_rate_limits (
  user_id             UUID        PRIMARY KEY
                                  REFERENCES auth.users(id) ON DELETE CASCADE,
  minute_window_start TIMESTAMPTZ NOT NULL,
  minute_count        INTEGER     NOT NULL DEFAULT 0 CHECK (minute_count >= 0),
  day_window_start    TIMESTAMPTZ NOT NULL,
  day_count           INTEGER     NOT NULL DEFAULT 0 CHECK (day_count >= 0),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- service_role only（與 practice_profile_draw_events / analysis_runs 同策略）：
-- RLS 開啟且不建任何 policy → 只有 service_role（bypass RLS）與 SECURITY DEFINER
-- RPC 可碰。client 永遠摸不到這張表。
ALTER TABLE public.ocr_rate_limits ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.ocr_rate_limits IS
  'recognizeOnly（免費 OCR）節流計數：分鐘窗＋UTC 日窗，單 row per user。'
  '與訂閱額度（subscriptions）完全獨立。';

-- ── 原子計數 RPC ─────────────────────────────────────────────────────────────
-- Edge 在 recognizeOnly && !accountIsTest 時、打 Claude vision 之前呼叫。
-- 計 attempt 不計 success（限的是成本不是產出）。超限 RAISE 令整筆交易
-- rollback（含首次請求的 INSERT），計數絕無污染。
CREATE OR REPLACE FUNCTION public.increment_ocr_usage(
  p_user_id UUID,
  p_minute_limit INTEGER,
  p_daily_limit INTEGER
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.ocr_rate_limits%ROWTYPE;
  v_now TIMESTAMPTZ := now();
  v_minute_count INTEGER;
  v_minute_window_start TIMESTAMPTZ;
  v_day_count INTEGER;
  v_day_window_start TIMESTAMPTZ;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'increment_ocr_usage: p_user_id is required';
  END IF;
  IF p_minute_limit IS NULL OR p_minute_limit <= 0 THEN
    RAISE EXCEPTION 'increment_ocr_usage: invalid p_minute_limit';
  END IF;
  IF p_daily_limit IS NULL OR p_daily_limit <= 0 THEN
    RAISE EXCEPTION 'increment_ocr_usage: invalid p_daily_limit';
  END IF;

  -- 先插後鎖回讀：避免「SELECT 無 row → INSERT 撞 23505」競態
  -- （coach-chat selfHeal 同型教訓）。已存在則 DO NOTHING，回讀必得 row。
  INSERT INTO public.ocr_rate_limits
    (user_id, minute_window_start, minute_count, day_window_start, day_count)
  VALUES (p_user_id, v_now, 0, v_now, 0)
  ON CONFLICT (user_id) DO NOTHING;

  SELECT * INTO v_row
  FROM public.ocr_rate_limits
  WHERE user_id = p_user_id
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
    RAISE EXCEPTION 'OCR_RATE_LIMITED_MINUTE';
  END IF;
  IF v_day_count + 1 > p_daily_limit THEN
    RAISE EXCEPTION 'OCR_RATE_LIMITED_DAILY';
  END IF;

  UPDATE public.ocr_rate_limits
  SET minute_window_start = v_minute_window_start,
      minute_count = v_minute_count + 1,
      day_window_start = v_day_window_start,
      day_count = v_day_count + 1,
      updated_at = v_now
  WHERE user_id = p_user_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION
  public.increment_ocr_usage(uuid, integer, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION
  public.increment_ocr_usage(uuid, integer, integer)
  FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.increment_ocr_usage(uuid, integer, integer) TO service_role;

-- 新函數必須刷新 PostgREST schema cache，否則 Edge rpc() 在 cache 過期前
-- 會吃 function not found（Batch C P2 同教訓；那會落 Edge 側 fail-open）。
NOTIFY pgrst, 'reload schema';
