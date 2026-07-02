-- opener 扣費 idempotency（2026-07-03，docs/plans/2026-07-03-opener-idempotency-design.md）。
--
-- 問題：opener 扣費（increment_usage）commit 後，回應在 PostgREST→Edge 或
-- Edge→client 丟失 → client 重試 → 同一次生成扣兩次（Batch 4 audit #2）。
-- Eric 拍板：request-id＋輕量 ledger 只去重扣費，不存結果 replay。
--
-- 設計沿 Batch C / OCR rate limit 慣例：
--   - 同一 TX：ledger INSERT ON CONFLICT DO NOTHING → 沒插入＝已扣過 →
--     RETURN false 跳過扣費；插入成功 → 呼叫現有 increment_usage（4-arg，
--     FOR UPDATE＋超限 RAISE 原封不動，其他呼叫點零影響）→ RETURN true。
--   - 不變量 I2：超限 RAISE 令整筆 TX rollback（含 ledger 行）——額度重置後
--     同 request_id 重試仍能正常扣費，不會被死 ledger 行卡住。
--   - 清理＝lazy purge：每次呼叫順手刪該 user 7 天前的行，不依賴 pg_cron。
--   - 上限值一律由 Edge 傳入（pricing 權威在 _shared/quota.ts），SQL 不寫死。
--
-- 套用方式：Supabase MCP apply_migration，**不要** supabase db push（本機/遠端
-- migration 版本號已知分歧）。套完把帳本 version 對齊本檔名。

-- ── 扣費去重 ledger ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.opener_request_charges (
  user_id    UUID        NOT NULL
                         REFERENCES auth.users(id) ON DELETE CASCADE,
  request_id UUID        NOT NULL,
  cost       INTEGER     NOT NULL CHECK (cost > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, request_id)
);

-- service_role only（與 ocr_rate_limits / analysis_runs 同策略）：RLS 開啟且
-- 不建任何 policy → 只有 service_role 與 SECURITY DEFINER RPC 可碰。
ALTER TABLE public.opener_request_charges ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.opener_request_charges IS
  'opener 扣費去重 ledger：每 (user_id, request_id) 至多扣費一次，'
  '擋傳輸層重試雙扣。行以 lazy purge 保留 7 天。';

-- ── idempotent 扣費 RPC ─────────────────────────────────────────────────────
-- Edge 在 opener 扣費點、requestId 為合法 UUID 時呼叫。回傳：
--   true  ＝ 本次真的扣了（ledger 新行＋increment_usage 已執行）
--   false ＝ 同 request_id 已扣過（dedup），跳過扣費
-- 超限沿用 increment_usage 的 QUOTA_EXCEEDED_* RAISE（Edge 映射 429）。
CREATE OR REPLACE FUNCTION public.increment_usage_idempotent(
  p_user_id UUID,
  p_messages INTEGER,
  p_monthly_limit INTEGER,
  p_daily_limit INTEGER,
  p_request_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inserted INTEGER;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'increment_usage_idempotent: p_user_id is required';
  END IF;
  IF p_request_id IS NULL THEN
    RAISE EXCEPTION 'increment_usage_idempotent: p_request_id is required';
  END IF;
  IF p_messages IS NULL OR p_messages <= 0 THEN
    RAISE EXCEPTION 'increment_usage_idempotent: invalid p_messages';
  END IF;

  -- lazy purge：行極小（兩 uuid＋int＋ts），單 user 頻率低，PK 前綴掃描便宜。
  DELETE FROM public.opener_request_charges
  WHERE user_id = p_user_id
    AND created_at < now() - interval '7 days';

  INSERT INTO public.opener_request_charges (user_id, request_id, cost)
  VALUES (p_user_id, p_request_id, p_messages)
  ON CONFLICT (user_id, request_id) DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  IF v_inserted = 0 THEN
    -- 已扣過：同 request_id 的重試，跳過扣費。
    RETURN FALSE;
  END IF;

  -- 現有 4-arg increment_usage：FOR UPDATE 串行化＋超限 RAISE。RAISE 會令
  -- 整筆 TX rollback（含上面的 ledger INSERT）＝不變量 I2。
  PERFORM public.increment_usage(
    p_user_id,
    p_messages,
    p_monthly_limit,
    p_daily_limit
  );

  RETURN TRUE;
END;
$$;

REVOKE EXECUTE ON FUNCTION
  public.increment_usage_idempotent(uuid, integer, integer, integer, uuid)
  FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION
  public.increment_usage_idempotent(uuid, integer, integer, integer, uuid)
  FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.increment_usage_idempotent(uuid, integer, integer, integer, uuid)
  TO service_role;

-- 新函數必須刷新 PostgREST schema cache，否則 Edge rpc() 在 cache 過期前
-- 會吃 function not found（Batch C P2 同教訓）。
NOTIFY pgrst, 'reload schema';
