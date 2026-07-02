-- practice-chat hint requestId 冪等（2026-07-03）
--
-- 問題：hint 流程（claim → 生成 → record 扣 1）無 requestId 冪等。回應在網路上
-- 遺失後 client 重試會再生成、再扣 1 則額度。
--
-- 修法（比照翻牌 claim_practice_profile_draw 的 requestId 回放範本）：
--   1. practice_chat_sessions 加 last_hint_request_id / last_hint_result 單槽快照。
--   2. claim_practice_hint_generation / record_practice_hint 改寫為帶
--      p_request_id TEXT DEFAULT NULL 的「單一新簽名」：先 DROP 舊簽名再 CREATE，
--      絕不留 overload（避免 PostgREST named-arg ambiguity）。
--   3. claim：p_request_id 命中 last_hint_request_id 且 last_hint_result 非空 →
--      回 replay=TRUE + stored result。回放不動 latch、不增 hint_count、不扣 quota，
--      且必須先於 hint 上限 / in-flight 檢查——上限邊緣的重試才不會被擋死。
--   4. record：成功結算時寫入 last_hint_request_id / last_hint_result；
--      hintUsedCount 由本 RPC 在鎖內以權威 new_hint_count merge 進快照，
--      Edge 不預填。
--
-- 部署順序：本 migration 對舊版 Edge 向後相容（舊 Edge 以 3/4 個 named args 呼叫，
-- 新簽名的 DEFAULT NULL 參數自動補位），故先套 migration 再 deploy 新 Edge。
-- 整檔可重放（IF NOT EXISTS / DROP IF EXISTS / CREATE OR REPLACE）。

ALTER TABLE public.practice_chat_sessions
  ADD COLUMN IF NOT EXISTS last_hint_request_id TEXT,
  ADD COLUMN IF NOT EXISTS last_hint_result JSONB;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'practice_chat_sessions_last_hint_request_id_check'
      AND conrelid = 'public.practice_chat_sessions'::regclass
  ) THEN
    ALTER TABLE public.practice_chat_sessions
      ADD CONSTRAINT practice_chat_sessions_last_hint_request_id_check
      CHECK (
        last_hint_request_id IS NULL
        OR length(last_hint_request_id) BETWEEN 1 AND 64
      );
  END IF;
END;
$$;

-- 舊簽名一律先 DROP，絕不留 overload。
DROP FUNCTION IF EXISTS public.claim_practice_hint_generation(UUID, TEXT, INTEGER);
DROP FUNCTION IF EXISTS public.record_practice_hint(UUID, TEXT, BOOLEAN, INTEGER);

CREATE OR REPLACE FUNCTION public.claim_practice_hint_generation(
  p_user_id    UUID,
  p_session_id TEXT,
  p_max_hints  INTEGER,
  p_request_id TEXT DEFAULT NULL
)
RETURNS TABLE(current_hint_count INTEGER, replay BOOLEAN, stored_result JSONB)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.practice_chat_sessions;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'claim_practice_hint_generation: p_user_id is required';
  END IF;
  IF p_session_id IS NULL OR length(p_session_id) = 0 OR length(p_session_id) > 64 THEN
    RAISE EXCEPTION 'claim_practice_hint_generation: invalid p_session_id';
  END IF;
  IF p_max_hints IS NULL OR p_max_hints <= 0 OR p_max_hints > 5 THEN
    RAISE EXCEPTION 'claim_practice_hint_generation: invalid p_max_hints';
  END IF;
  IF p_request_id IS NOT NULL
     AND (length(p_request_id) = 0 OR length(p_request_id) > 64) THEN
    RAISE EXCEPTION 'claim_practice_hint_generation: invalid p_request_id';
  END IF;

  SELECT * INTO v_row
  FROM public.practice_chat_sessions
  WHERE user_id = p_user_id AND session_id = p_session_id
  FOR UPDATE;

  IF NOT FOUND OR NOT v_row.charged OR v_row.ai_count < 1 THEN
    RAISE EXCEPTION 'PRACTICE_SESSION_NOT_STARTED';
  END IF;

  -- Replay：同 requestId 的重試直接回放已扣費的結果。必須先於 hint 上限與
  -- in-flight 檢查（上限邊緣的重試不得被擋死），且絕不動 latch、絕不扣費。
  IF p_request_id IS NOT NULL
     AND v_row.last_hint_request_id = p_request_id
     AND v_row.last_hint_result IS NOT NULL THEN
    current_hint_count := v_row.hint_count;
    replay := TRUE;
    stored_result := v_row.last_hint_result;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_row.practice_mode <> 'beginner' THEN
    RAISE EXCEPTION 'PRACTICE_HINT_BEGINNER_ONLY';
  END IF;

  IF v_row.hint_count >= p_max_hints THEN
    RAISE EXCEPTION 'PRACTICE_HINT_LIMIT';
  END IF;

  IF v_row.hint_generation_started_at IS NOT NULL
    AND v_row.hint_generation_started_at > now() - interval '2 minutes' THEN
    RAISE EXCEPTION 'PRACTICE_HINT_IN_FLIGHT';
  END IF;

  UPDATE public.practice_chat_sessions
  SET hint_generation_started_at = now(),
      updated_at = now()
  WHERE user_id = p_user_id AND session_id = p_session_id
  RETURNING hint_count INTO current_hint_count;

  replay := FALSE;
  stored_result := NULL;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_practice_hint(
  p_user_id      UUID,
  p_session_id   TEXT,
  p_charge_quota BOOLEAN,
  p_max_hints    INTEGER,
  p_request_id   TEXT DEFAULT NULL,
  p_result       JSONB DEFAULT NULL
)
RETURNS TABLE(new_hint_count INTEGER, did_charge BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.practice_chat_sessions;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'record_practice_hint: p_user_id is required';
  END IF;
  IF p_session_id IS NULL OR length(p_session_id) = 0 OR length(p_session_id) > 64 THEN
    RAISE EXCEPTION 'record_practice_hint: invalid p_session_id';
  END IF;
  IF p_max_hints IS NULL OR p_max_hints <= 0 OR p_max_hints > 5 THEN
    RAISE EXCEPTION 'record_practice_hint: invalid p_max_hints';
  END IF;
  IF p_charge_quota IS NULL THEN
    RAISE EXCEPTION 'record_practice_hint: invalid p_charge_quota';
  END IF;
  IF p_request_id IS NOT NULL
     AND (length(p_request_id) = 0 OR length(p_request_id) > 64) THEN
    RAISE EXCEPTION 'record_practice_hint: invalid p_request_id';
  END IF;

  SELECT * INTO v_row
  FROM public.practice_chat_sessions
  WHERE user_id = p_user_id AND session_id = p_session_id
  FOR UPDATE;

  IF NOT FOUND OR NOT v_row.charged OR v_row.ai_count < 1 THEN
    RAISE EXCEPTION 'PRACTICE_SESSION_NOT_STARTED';
  END IF;

  IF v_row.practice_mode <> 'beginner' THEN
    RAISE EXCEPTION 'PRACTICE_HINT_BEGINNER_ONLY';
  END IF;

  IF v_row.hint_count >= p_max_hints THEN
    RAISE EXCEPTION 'PRACTICE_HINT_LIMIT';
  END IF;

  IF v_row.hint_generation_started_at IS NULL THEN
    RAISE EXCEPTION 'PRACTICE_HINT_NOT_CLAIMED';
  END IF;

  did_charge := p_charge_quota;
  IF did_charge THEN
    PERFORM public.increment_usage(p_user_id, 1);
  END IF;

  -- last_hint_result：hintUsedCount 以鎖內權威 new hint count（hint_count + 1，
  -- RHS 讀舊值）merge 進 Edge 傳入的回應快照，回放時直接原樣回傳。
  -- 舊 client（p_request_id NULL）清空槽位，走無冪等現行為。
  UPDATE public.practice_chat_sessions
  SET hint_count = hint_count + 1,
      hint_generation_started_at = NULL,
      last_hint_request_id = p_request_id,
      last_hint_result = CASE
        WHEN p_request_id IS NULL OR p_result IS NULL THEN NULL
        ELSE p_result || jsonb_build_object('hintUsedCount', hint_count + 1)
      END,
      updated_at = now()
  WHERE user_id = p_user_id AND session_id = p_session_id
  RETURNING hint_count INTO new_hint_count;

  RETURN NEXT;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.claim_practice_hint_generation(UUID, TEXT, INTEGER, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_practice_hint_generation(UUID, TEXT, INTEGER, TEXT)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.record_practice_hint(UUID, TEXT, BOOLEAN, INTEGER, TEXT, JSONB)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_practice_hint(UUID, TEXT, BOOLEAN, INTEGER, TEXT, JSONB)
  TO service_role;

-- 簽名變更必須刷新 PostgREST schema cache，否則 Edge 帶 p_request_id 的 rpc()
-- 在 cache 過期前會吃 function not found。
NOTIFY pgrst, 'reload schema';
