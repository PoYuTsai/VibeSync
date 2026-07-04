-- practice-chat server-side session ledger（Codex 2026-06-24 BLOCKER 修復）。
--
-- 為什麼需要這張表：
--   原 practice-chat 完全信任 client 送的 `turns` 來決定「扣不扣點」與「10 則
--   上限」。漏洞：①偽造首則 role:"ai"→整場免費 ②重送 sessionId→重複扣點
--   ③偽造 turns 狂打 debrief→無限免費 DeepSeek 成本 ④少報 ai turns→繞過上限。
--   扣費/上限的權威狀態必須跨 Edge isolate、跨請求成立 → 只能落在 Postgres，
--   以 (user_id, session_id) 為 PK 的列做原子判定。
--
-- 隱私（Eric 2026-06-24 拍板 Option A）：
--   本表「只存計數」——ai_count / charged / debrief_count，**不存任何對話內容**。
--   練習對話維持 Hive local-only（最近 5 場）。漏洞⑤（偽造 assistant 訊息越獄）
--   改由 prompt 硬化（transcript-as-data + 人設鎖）防，不靠 server 重建歷史。
--
-- 失敗方向（與 ADR #19 user-safe 哲學一致）：
--   charge 與 ai_count 遞增在同一交易內，要嘛都成立要嘛都 rollback；競態下重複
--   commit→第二次見 charged=true 不重扣（往便宜方向）。絕無「先扣再退」髒狀態。
--
-- 部署順序：此 migration 必須先於 practice-chat Edge 新碼上線（Edge push 即
--   auto-deploy）。新碼會呼叫下面兩個 RPC，RPC 不存在會 500。舊版 practice-chat
--   不呼叫這些 RPC，故先套表不影響既有行為。

CREATE TABLE public.practice_chat_sessions (
  user_id       UUID        NOT NULL,
  session_id    TEXT        NOT NULL,
  ai_count      INTEGER     NOT NULL DEFAULT 0,   -- server 權威：本場已成功生成的 AI 回覆數
  charged       BOOLEAN     NOT NULL DEFAULT FALSE, -- 本場第一則是否已結算（扣費或測試帳號豁免）
  debrief_count INTEGER     NOT NULL DEFAULT 0,   -- 本場已產生的拆解卡張數
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, session_id),
  CONSTRAINT practice_session_id_len CHECK (length(session_id) BETWEEN 1 AND 64)
);

-- service_role only（與 analysis_runs / billing_overcharge_confirmations 同策略）：
-- RLS 開啟且不建任何 policy → 只有 service_role（bypass RLS）與 SECURITY DEFINER
-- RPC 可碰。client 永遠摸不到這張表。
ALTER TABLE public.practice_chat_sessions ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.practice_chat_sessions IS
  'AI 實戰練習室 server 端 session 計數帳本（只存計數、不存對話）。扣費/上限權威來源。';

-- ── chat 回合 commit：原子「結算扣費 + ai_count 遞增」───────────────────
-- 在 DeepSeek 成功生成後呼叫。先以 FOR UPDATE 鎖列重判上限（防 preflight 後競態），
-- 第一則未結算才扣 1（idempotent），ai_count 遞增。
-- 回傳：new_ai_count（遞增後）、did_charge（本次是否真的扣了 quota）。
CREATE OR REPLACE FUNCTION public.commit_practice_chat_turn(
  p_user_id      UUID,
  p_session_id   TEXT,
  p_charge_quota BOOLEAN DEFAULT TRUE,
  p_max_replies  INTEGER DEFAULT 10
)
RETURNS TABLE(new_ai_count INTEGER, did_charge BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row           public.practice_chat_sessions;
  v_should_settle BOOLEAN;
BEGIN
  -- SECURITY DEFINER 下不能靠 RLS 擋垃圾輸入，逐項明確驗證。
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'commit_practice_chat_turn: p_user_id is required';
  END IF;
  IF p_session_id IS NULL OR length(p_session_id) = 0 OR length(p_session_id) > 64 THEN
    RAISE EXCEPTION 'commit_practice_chat_turn: invalid p_session_id';
  END IF;
  IF p_max_replies IS NULL OR p_max_replies <= 0 THEN
    RAISE EXCEPTION 'commit_practice_chat_turn: invalid p_max_replies';
  END IF;

  -- 確保列存在（第一則時建立），再鎖列。
  INSERT INTO public.practice_chat_sessions (user_id, session_id)
  VALUES (p_user_id, p_session_id)
  ON CONFLICT (user_id, session_id) DO NOTHING;

  SELECT * INTO v_row
  FROM public.practice_chat_sessions
  WHERE user_id = p_user_id AND session_id = p_session_id
  FOR UPDATE;

  -- 權威上限：以 server ai_count 為準（堵 client 少報 turns 繞過 10）。
  IF v_row.ai_count >= p_max_replies THEN
    RAISE EXCEPTION 'PRACTICE_SESSION_COMPLETE';
  END IF;

  -- 第一則（尚未結算）才結算。charged 單調 false→true，一生只結算一次。
  v_should_settle := NOT v_row.charged;
  did_charge := v_should_settle AND COALESCE(p_charge_quota, TRUE);

  -- 只有「該結算且非測試帳號」才真的扣 quota；increment_usage 在同交易內，
  -- 若它 RAISE 則整個 commit rollback（ai_count 不會動、不會半扣）。
  IF did_charge THEN
    PERFORM public.increment_usage(p_user_id, 1);
  END IF;

  UPDATE public.practice_chat_sessions
  SET ai_count   = ai_count + 1,
      charged    = charged OR v_should_settle, -- 測試帳號也標 charged（已建立），讓 debrief 可用
      updated_at = now()
  WHERE user_id = p_user_id AND session_id = p_session_id
  RETURNING ai_count INTO new_ai_count;

  RETURN NEXT;
END;
$$;

-- ── debrief claim：驗證已扣費 session + 上限，原子遞增 debrief_count ─────
-- 在 DeepSeek 拆解卡成功後呼叫。永不扣 quota。
CREATE OR REPLACE FUNCTION public.claim_practice_debrief(
  p_user_id      UUID,
  p_session_id   TEXT,
  p_max_debriefs INTEGER DEFAULT 3
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.practice_chat_sessions;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'claim_practice_debrief: p_user_id is required';
  END IF;
  IF p_session_id IS NULL OR length(p_session_id) = 0 OR length(p_session_id) > 64 THEN
    RAISE EXCEPTION 'claim_practice_debrief: invalid p_session_id';
  END IF;
  IF p_max_debriefs IS NULL OR p_max_debriefs <= 0 THEN
    RAISE EXCEPTION 'claim_practice_debrief: invalid p_max_debriefs';
  END IF;

  SELECT * INTO v_row
  FROM public.practice_chat_sessions
  WHERE user_id = p_user_id AND session_id = p_session_id
  FOR UPDATE;

  -- 只有已正式建立（扣費或豁免）且有 AI 回覆的 session 才能拆解。
  -- 堵：偽造 turns 對不存在/未扣費的 session 免費打 debrief。
  IF NOT FOUND OR NOT v_row.charged OR v_row.ai_count < 1 THEN
    RAISE EXCEPTION 'PRACTICE_SESSION_NOT_STARTED';
  END IF;

  -- 堵：單一付費 session 無限拆解放大 DeepSeek 成本。
  IF v_row.debrief_count >= p_max_debriefs THEN
    RAISE EXCEPTION 'PRACTICE_DEBRIEF_LIMIT';
  END IF;

  UPDATE public.practice_chat_sessions
  SET debrief_count = debrief_count + 1,
      updated_at    = now()
  WHERE user_id = p_user_id AND session_id = p_session_id
  RETURNING debrief_count INTO v_row.debrief_count;

  RETURN v_row.debrief_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.commit_practice_chat_turn(UUID, TEXT, BOOLEAN, INTEGER)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.commit_practice_chat_turn(UUID, TEXT, BOOLEAN, INTEGER)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.claim_practice_debrief(UUID, TEXT, INTEGER)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_practice_debrief(UUID, TEXT, INTEGER)
  TO service_role;

NOTIFY pgrst, 'reload schema';
