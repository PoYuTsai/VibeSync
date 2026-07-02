-- opener 扣費 idempotency：dedup replay 上限（2026-07-03，Codex R2 P2a）。
--
-- 漏洞：同 request_id 同 payload 的 dedup 回 false → Edge 照常重新生成回
-- 200——改造 client 付一次 3 額度後可無限刷新產出（不雙扣但白拿結果＋燒
-- AI 成本）。修法：ledger 加 replay_count，dedup 每次 +1，超過 Edge 傳入
-- 的 p_replay_limit 即 RAISE OPENER_REQUEST_REPLAY_EXHAUSTED（Edge 映射
-- 400）。合法傳輸層重試一兩次就夠，上限 3（權威在 Edge，SQL 不寫死）。
--
-- 部署窗口相容：p_replay_limit DEFAULT NULL＝不設限——現部署 Edge（6 named
-- args）在 migration 套用到 Edge deploy 完成之間行為不變。
-- 套用方式：Supabase MCP apply_migration，**不要** supabase db push。

ALTER TABLE public.opener_request_charges
  ADD COLUMN IF NOT EXISTS replay_count INTEGER NOT NULL DEFAULT 0
  CHECK (replay_count >= 0);

DROP FUNCTION IF EXISTS public.increment_usage_idempotent(
  uuid, integer, integer, integer, uuid, text);

CREATE FUNCTION public.increment_usage_idempotent(
  p_user_id UUID,
  p_messages INTEGER,
  p_monthly_limit INTEGER,
  p_daily_limit INTEGER,
  p_request_id UUID,
  p_input_hash TEXT DEFAULT NULL,
  p_replay_limit INTEGER DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inserted INTEGER;
  v_hash TEXT := coalesce(p_input_hash, '');
  v_existing public.opener_request_charges%ROWTYPE;
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

  -- lazy purge：行極小，PK 前綴掃描便宜。
  DELETE FROM public.opener_request_charges
  WHERE user_id = p_user_id
    AND created_at < now() - interval '7 days';

  INSERT INTO public.opener_request_charges
    (user_id, request_id, cost, input_hash)
  VALUES (p_user_id, p_request_id, p_messages, v_hash)
  ON CONFLICT (user_id, request_id) DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  IF v_inserted = 0 THEN
    -- FOR UPDATE：並發 replay 風暴串行化，count 不丟更新。
    SELECT * INTO v_existing
    FROM public.opener_request_charges
    WHERE user_id = p_user_id AND request_id = p_request_id
    FOR UPDATE;

    -- 同 id 重放但 payload 不同＝改造 client 蹭生成，擋下（Codex P2）。
    IF v_existing.input_hash IS DISTINCT FROM v_hash THEN
      RAISE EXCEPTION 'OPENER_REQUEST_REPLAY_MISMATCH';
    END IF;

    -- 同 payload dedup 重試超過預算＝付一次刷無限產出，擋下（R2 P2a）。
    IF p_replay_limit IS NOT NULL
       AND v_existing.replay_count + 1 > p_replay_limit THEN
      RAISE EXCEPTION 'OPENER_REQUEST_REPLAY_EXHAUSTED';
    END IF;

    UPDATE public.opener_request_charges
    SET replay_count = replay_count + 1
    WHERE user_id = p_user_id AND request_id = p_request_id;

    -- 已扣過：同 request_id 同 payload 的預算內重試，跳過扣費。
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
  public.increment_usage_idempotent(
    uuid, integer, integer, integer, uuid, text, integer)
  FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION
  public.increment_usage_idempotent(
    uuid, integer, integer, integer, uuid, text, integer)
  FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.increment_usage_idempotent(
    uuid, integer, integer, integer, uuid, text, integer)
  TO service_role;

NOTIFY pgrst, 'reload schema';
