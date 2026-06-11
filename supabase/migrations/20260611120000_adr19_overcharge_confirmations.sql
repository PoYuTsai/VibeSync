-- ADR #19 定案 #5 — confirmed >2000 扣費的確認綁定 + idempotency。
--
-- 為什麼需要這張表：
--   2001~4000 字分析固定扣 20 則，由用戶在 client 確認後才扣。網路重送 /
--   雙送同一個確認絕不能重扣 20（Codex r3-P1-3）。idempotency 必須跨
--   Edge isolate / 跨請求成立 → 只能落在 Postgres，靠 PK 的
--   INSERT ... ON CONFLICT 原子判定「第一次 vs 重送」。
--
-- 失敗方向（與 r2 user-safe 哲學一致）：
--   claim 成功但後續扣費失敗 → 用戶重送走 replay 扣 0 → 往便宜方向錯。
--   絕無「先扣再退」髒狀態。
--
-- 部署順序：此 migration 必須在新 App（會送 confirmedOvercharge 的
-- billingProtocolVersion:3 client）上架前套用。Edge function 先部署
-- 沒問題——舊 client 永遠不送確認、走 legacy cap 10 路徑，不會打到
-- 這個 RPC；新 client 在 migration 套用前送確認會收到 503（fail closed，
-- 不扣費）。

CREATE TABLE public.billing_overcharge_confirmations (
  user_id         UUID        NOT NULL,
  confirmation_id TEXT        NOT NULL,
  payload_hash    TEXT        NOT NULL,
  billable_chars  INTEGER     NOT NULL,
  charged_units   INTEGER     NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, confirmation_id)
);

-- service_role only（與 analysis_runs 同策略）：RLS 開啟且不建任何
-- policy → 只有 service_role（bypass RLS）與 SECURITY DEFINER RPC 可碰。
ALTER TABLE public.billing_overcharge_confirmations ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.claim_overcharge_confirmation(
  p_user_id         UUID,
  p_confirmation_id TEXT,
  p_payload_hash    TEXT,
  p_billable_chars  INTEGER,
  p_charged_units   INTEGER,
  p_replay_window   INTERVAL DEFAULT INTERVAL '60 minutes'
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  existing public.billing_overcharge_confirmations;
BEGIN
  -- SECURITY DEFINER 下不能靠 RLS 擋垃圾輸入，逐項明確驗證。
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'claim_overcharge_confirmation: p_user_id is required';
  END IF;
  IF p_confirmation_id IS NULL OR length(p_confirmation_id) = 0
     OR length(p_confirmation_id) > 128 THEN
    RAISE EXCEPTION 'claim_overcharge_confirmation: invalid p_confirmation_id';
  END IF;
  IF p_payload_hash IS NULL OR p_payload_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'claim_overcharge_confirmation: invalid p_payload_hash';
  END IF;
  IF p_billable_chars IS NULL OR p_billable_chars <= 0 THEN
    RAISE EXCEPTION 'claim_overcharge_confirmation: invalid p_billable_chars';
  END IF;
  IF p_charged_units IS NULL OR p_charged_units <= 0 THEN
    RAISE EXCEPTION 'claim_overcharge_confirmation: invalid p_charged_units';
  END IF;

  -- 原子 claim：PK 衝突 = 此確認已被用過。
  INSERT INTO public.billing_overcharge_confirmations (
    user_id, confirmation_id, payload_hash, billable_chars, charged_units
  )
  VALUES (
    p_user_id, p_confirmation_id, p_payload_hash, p_billable_chars,
    p_charged_units
  )
  ON CONFLICT (user_id, confirmation_id) DO NOTHING;

  IF FOUND THEN
    RETURN 'claimed';
  END IF;

  SELECT * INTO existing
  FROM public.billing_overcharge_confirmations
  WHERE user_id = p_user_id AND confirmation_id = p_confirmation_id;

  -- 防禦：conflict 後 row 必存在（本表無刪除路徑）。萬一未來加了清理
  -- 機制產生 race，NULL 比較會靜默落到 replay（= 免費），fail loud 擋住。
  IF NOT FOUND THEN
    RAISE EXCEPTION
      'claim_overcharge_confirmation: conflict row vanished for user % id %',
      p_user_id, p_confirmation_id;
  END IF;

  -- 同 confirmationId 但內容不同 = 確認後內容又改過（或 id 被重用）。
  -- 絕不拿舊確認扣新內容 → caller 回新的 confirmation_required。
  IF existing.payload_hash <> p_payload_hash THEN
    RETURN 'mismatch';
  END IF;

  -- 同 payload 但超出 replay window：真實的網路重送發生在秒~分鐘級，
  -- 60 分鐘外的重用視為過期，要求重新確認（防舊確認永久免費重分析）。
  IF existing.created_at < now() - p_replay_window THEN
    RETURN 'expired';
  END IF;

  -- 同確認 + 同內容 + TTL 內 = 合法重送：上次已扣 20，本次扣 0。
  RETURN 'replay';
END;
$$;

REVOKE EXECUTE ON FUNCTION public.claim_overcharge_confirmation(
  UUID, TEXT, TEXT, INTEGER, INTEGER, INTERVAL
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_overcharge_confirmation(
  UUID, TEXT, TEXT, INTEGER, INTEGER, INTERVAL
) TO service_role;

NOTIFY pgrst, 'reload schema';
