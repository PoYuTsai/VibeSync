-- practice-chat debrief requestId 冪等回放（2026-07-10）
--
-- 網路逾時時 Edge 可能已 claim debrief_count、甚至已完成生成，但 client 沒收到
-- response。若使用者重按，舊流程會再吃一次三次上限並重打模型。
--
-- 這裡比照 Hint 的單槽 replay：每個 session 只保留最後一次 debrief requestId
-- 與完整 response。只存生成後的拆解卡快照，不存 raw transcript；新 requestId 會
-- 覆寫舊快照。舊 Edge 不送 requestId 時仍維持原本三參數 claim 行為。

ALTER TABLE public.practice_chat_sessions
  ADD COLUMN IF NOT EXISTS last_debrief_request_id TEXT,
  ADD COLUMN IF NOT EXISTS last_debrief_result JSONB,
  ADD COLUMN IF NOT EXISTS last_debrief_started_at TIMESTAMPTZ;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'practice_chat_sessions_last_debrief_request_id_check'
      AND conrelid = 'public.practice_chat_sessions'::regclass
  ) THEN
    ALTER TABLE public.practice_chat_sessions
      ADD CONSTRAINT practice_chat_sessions_last_debrief_request_id_check
      CHECK (
        last_debrief_request_id IS NULL
        OR length(last_debrief_request_id) BETWEEN 1 AND 64
      );
  END IF;
END
$$;

COMMENT ON TABLE public.practice_chat_sessions IS
  'AI 實戰練習室 server 權威帳本；不存 raw transcript，只保留計數、學習狀態與最後一次 Hint/Debrief 冪等回放快照。';

-- Return shape 由 INTEGER 改成 replay table，必須先移除舊簽名。新函式的
-- p_request_id 有 DEFAULT NULL，舊 Edge 的三參數呼叫仍可解析。
DROP FUNCTION IF EXISTS public.claim_practice_debrief(UUID, TEXT, INTEGER);

CREATE OR REPLACE FUNCTION public.claim_practice_debrief(
  p_user_id      UUID,
  p_session_id   TEXT,
  p_max_debriefs INTEGER DEFAULT 3,
  p_request_id   TEXT DEFAULT NULL
)
RETURNS TABLE(
  current_debrief_count INTEGER,
  replay BOOLEAN,
  in_flight BOOLEAN,
  stored_result JSONB
)
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
  IF p_request_id IS NOT NULL
     AND (length(p_request_id) = 0 OR length(p_request_id) > 64) THEN
    RAISE EXCEPTION 'claim_practice_debrief: invalid p_request_id';
  END IF;

  SELECT * INTO v_row
  FROM public.practice_chat_sessions
  WHERE user_id = p_user_id AND session_id = p_session_id
  FOR UPDATE;

  IF NOT FOUND OR NOT v_row.charged OR v_row.ai_count < 1 THEN
    RAISE EXCEPTION 'PRACTICE_SESSION_NOT_STARTED';
  END IF;

  -- 完成回放：必須先於上限檢查，讓第三次已完成但 response 遺失的請求仍能取回。
  IF p_request_id IS NOT NULL
     AND v_row.last_debrief_request_id = p_request_id
     AND v_row.last_debrief_result IS NOT NULL THEN
    current_debrief_count := v_row.debrief_count;
    replay := TRUE;
    in_flight := FALSE;
    stored_result := v_row.last_debrief_result;
    RETURN NEXT;
    RETURN;
  END IF;

  -- fresh latch：同一 request 的 transport retry、或另一個併發 request，都不可
  -- 在原生成尚未完成時再打模型。45 秒蓋過 server 最壞 24 秒模型預算＋DB overhead；
  -- 超時後才允許接手，避免 worker 中斷留下永久鎖。
  IF p_request_id IS NOT NULL
     AND v_row.last_debrief_request_id IS NOT NULL
     AND v_row.last_debrief_result IS NULL
     AND v_row.last_debrief_started_at IS NOT NULL
     AND v_row.last_debrief_started_at > now() - INTERVAL '45 seconds' THEN
    current_debrief_count := v_row.debrief_count;
    replay := FALSE;
    in_flight := TRUE;
    stored_result := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  -- 同 requestId 的 stale/unfinished claim 可接手，不再遞增 debrief_count。
  IF p_request_id IS NOT NULL
     AND v_row.last_debrief_request_id = p_request_id THEN
    UPDATE public.practice_chat_sessions
    SET last_debrief_started_at = now(),
        updated_at = now()
    WHERE user_id = p_user_id AND session_id = p_session_id;
    current_debrief_count := v_row.debrief_count;
    replay := FALSE;
    in_flight := FALSE;
    stored_result := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_row.debrief_count >= p_max_debriefs THEN
    RAISE EXCEPTION 'PRACTICE_DEBRIEF_LIMIT';
  END IF;

  UPDATE public.practice_chat_sessions
  SET debrief_count = debrief_count + 1,
      last_debrief_request_id = p_request_id,
      last_debrief_result = NULL,
      last_debrief_started_at = CASE
        WHEN p_request_id IS NULL THEN NULL
        ELSE now()
      END,
      updated_at = now()
  WHERE user_id = p_user_id AND session_id = p_session_id
  RETURNING debrief_count INTO current_debrief_count;

  replay := FALSE;
  in_flight := FALSE;
  stored_result := NULL;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_practice_debrief(
  p_user_id    UUID,
  p_session_id TEXT,
  p_request_id TEXT,
  p_result     JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.practice_chat_sessions;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'record_practice_debrief: p_user_id is required';
  END IF;
  IF p_session_id IS NULL OR length(p_session_id) = 0 OR length(p_session_id) > 64 THEN
    RAISE EXCEPTION 'record_practice_debrief: invalid p_session_id';
  END IF;
  IF p_request_id IS NULL
     OR length(p_request_id) = 0
     OR length(p_request_id) > 64 THEN
    RAISE EXCEPTION 'record_practice_debrief: invalid p_request_id';
  END IF;
  IF p_result IS NULL OR jsonb_typeof(p_result) <> 'object' THEN
    RAISE EXCEPTION 'record_practice_debrief: invalid p_result';
  END IF;

  SELECT * INTO v_row
  FROM public.practice_chat_sessions
  WHERE user_id = p_user_id AND session_id = p_session_id
  FOR UPDATE;

  IF NOT FOUND OR NOT v_row.charged OR v_row.ai_count < 1 THEN
    RAISE EXCEPTION 'PRACTICE_SESSION_NOT_STARTED';
  END IF;
  IF v_row.last_debrief_request_id IS DISTINCT FROM p_request_id THEN
    RAISE EXCEPTION 'PRACTICE_DEBRIEF_REQUEST_MISMATCH';
  END IF;

  -- first writer wins：重疊 worker 晚到時不得覆寫 client 已收到／之後會 replay 的卡。
  IF v_row.last_debrief_result IS NOT NULL THEN
    RETURN v_row.last_debrief_result;
  END IF;

  UPDATE public.practice_chat_sessions
  SET last_debrief_result = p_result,
      last_debrief_started_at = NULL,
      updated_at = now()
  WHERE user_id = p_user_id AND session_id = p_session_id;

  RETURN p_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.claim_practice_debrief(UUID, TEXT, INTEGER, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_practice_debrief(UUID, TEXT, INTEGER, TEXT)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.record_practice_debrief(UUID, TEXT, TEXT, JSONB)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_practice_debrief(UUID, TEXT, TEXT, JSONB)
  TO service_role;

NOTIFY pgrst, 'reload schema';
