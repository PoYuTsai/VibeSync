-- opener 扣費 idempotency：ledger 綁 input hash（2026-07-03，Codex P2）。
--
-- 漏洞：20260703120000 只以 (user_id, request_id) 去重且 dedup 回 200——
-- 改造 client 付一次 3 額度後，7 天 ledger 窗口內同 request_id 換輸入可
-- 無限免費重生成。修法：ledger 存 payload hash，同 id 重放但 hash 不符
-- 直接 RAISE 擋下（OPENER_REQUEST_REPLAY_MISMATCH → Edge 映射 400）。
-- 正常 client 不會踩到：requestId 隨輸入指紋 rotate（client 同步修）。
--
-- 部署窗口相容：p_input_hash DEFAULT NULL——舊版 Edge（5 named args）在
-- migration 套用到 Edge deploy 完成之間仍可呼叫，hash 記為 ''。
-- 套用方式：Supabase MCP apply_migration，**不要** supabase db push。

ALTER TABLE public.opener_request_charges
  ADD COLUMN IF NOT EXISTS input_hash TEXT NOT NULL DEFAULT '';

-- 簽名變更（5-arg → 6-arg）：必須 DROP 再建，避免 overload 並存 ambiguity
-- （同 increment_usage 2-arg → 4-arg 教訓）。
DROP FUNCTION IF EXISTS public.increment_usage_idempotent(
  uuid, integer, integer, integer, uuid);

CREATE FUNCTION public.increment_usage_idempotent(
  p_user_id UUID,
  p_messages INTEGER,
  p_monthly_limit INTEGER,
  p_daily_limit INTEGER,
  p_request_id UUID,
  p_input_hash TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inserted INTEGER;
  v_hash TEXT := coalesce(p_input_hash, '');
  v_existing_hash TEXT;
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

  -- lazy purge：行極小（兩 uuid＋int＋ts＋hash），PK 前綴掃描便宜。
  DELETE FROM public.opener_request_charges
  WHERE user_id = p_user_id
    AND created_at < now() - interval '7 days';

  INSERT INTO public.opener_request_charges
    (user_id, request_id, cost, input_hash)
  VALUES (p_user_id, p_request_id, p_messages, v_hash)
  ON CONFLICT (user_id, request_id) DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  IF v_inserted = 0 THEN
    SELECT input_hash INTO v_existing_hash
    FROM public.opener_request_charges
    WHERE user_id = p_user_id AND request_id = p_request_id;

    -- 同 id 重放但 payload 不同＝改造 client 蹭免費生成，擋下（Codex P2）。
    IF v_existing_hash IS DISTINCT FROM v_hash THEN
      RAISE EXCEPTION 'OPENER_REQUEST_REPLAY_MISMATCH';
    END IF;

    -- 已扣過：同 request_id 同 payload 的重試，跳過扣費。
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
  public.increment_usage_idempotent(uuid, integer, integer, integer, uuid, text)
  FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION
  public.increment_usage_idempotent(uuid, integer, integer, integer, uuid, text)
  FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.increment_usage_idempotent(uuid, integer, integer, integer, uuid, text)
  TO service_role;

NOTIFY pgrst, 'reload schema';
