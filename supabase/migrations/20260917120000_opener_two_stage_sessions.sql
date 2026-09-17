-- 開場救星兩段式（先分析、再讓用戶補充、按生成才第二段）短期會話快照
--（2026-09-17，docs/… 附件《以用戶自己的想法為核心的完整實作報告》§11）。
--
-- 兩張表、六支交易 RPC，沿 ADR #22 claim/lease/settle 範本
--（20260724120000_new_topic_exactly_once.sql），參數性偏離：
--   * opener_sessions：一局＝一份對方資料＋伺服器分析快照。分析不扣費；
--     首次成功生成才扣 first_generation_cost（0 或 3，Edge 客觀判定後傳入）。
--     一局共 p_max_generations 組成功結果（Edge 傳 3），到期 expires_at 固定
--     在分析落地時＝now()+ttl，重試不延長。
--   * opener_generation_runs：一次「按生成」＝一列；同 generation_id 重試取回
--     同一組結果（不重扣、不占成功次數）；同局同時只允許一個 pending 作業。
--   * settle_opener_generation 在同一交易內：保存結果＋首次扣費＋成功數 +1＋
--     標示完成；increment_usage RAISE 令整筆回滾（絕無「扣了卻沒結果」）。
--   * 到期由 pg_cron 每小時清除（含 CASCADE 的作業列）；帳號刪除靠
--     auth.users ON DELETE CASCADE＋delete-account 的顯式清單。
--   * 兩表 RLS 開啟且不建 policy：只有 service_role 與 SECURITY DEFINER RPC
--     可碰；App 只透過 Edge 讀取自己帳號的快照。不存原始圖片。
-- 套用方式：Supabase MCP apply_migration，**不要** supabase db push。

CREATE TABLE IF NOT EXISTS public.opener_sessions (
  session_id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID        NOT NULL
                                    REFERENCES auth.users(id) ON DELETE CASCADE,
  analysis_request_id   UUID        NOT NULL,
  input_hash            TEXT        NOT NULL
                                    CHECK (input_hash ~ '^[0-9a-f]{64}$'),
  state                 TEXT        NOT NULL DEFAULT 'pending'
                                    CHECK (state IN ('pending', 'ready')),
  owner_token           UUID        NOT NULL,
  lease_expires_at      TIMESTAMPTZ NOT NULL,
  flow_version          INTEGER     NOT NULL CHECK (flow_version >= 1),
  contract_version      INTEGER     NOT NULL CHECK (contract_version >= 1),
  analysis_revision     INTEGER     NOT NULL DEFAULT 1
                                    CHECK (analysis_revision >= 1),
  analysis_json         JSONB,
  first_generation_cost INTEGER     NOT NULL DEFAULT 3
                                    CHECK (first_generation_cost >= 0),
  quota_charged         BOOLEAN     NOT NULL DEFAULT FALSE,
  charged_amount        INTEGER     NOT NULL DEFAULT 0
                                    CHECK (charged_amount >= 0),
  generations_used      INTEGER     NOT NULL DEFAULT 0
                                    CHECK (generations_used >= 0),
  expires_at            TIMESTAMPTZ,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT opener_sessions_request_unique UNIQUE (user_id, analysis_request_id),
  CONSTRAINT opener_sessions_state_consistency CHECK (
    (
      state = 'pending'
      AND analysis_json IS NULL
      AND expires_at IS NULL
      AND quota_charged = FALSE
      AND generations_used = 0
    )
    OR
    (
      state = 'ready'
      AND analysis_json IS NOT NULL
      AND jsonb_typeof(analysis_json) = 'object'
      AND expires_at IS NOT NULL
    )
  ),
  CONSTRAINT opener_sessions_charge_consistency CHECK (
    (quota_charged = FALSE AND charged_amount = 0)
    OR (quota_charged = TRUE AND charged_amount = first_generation_cost)
  )
);

CREATE INDEX IF NOT EXISTS opener_sessions_expires_at_idx
  ON public.opener_sessions (expires_at);
CREATE INDEX IF NOT EXISTS opener_sessions_user_created_idx
  ON public.opener_sessions (user_id, created_at);

ALTER TABLE public.opener_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.opener_sessions FROM PUBLIC;
REVOKE ALL ON TABLE public.opener_sessions FROM anon, authenticated;
GRANT SELECT ON TABLE public.opener_sessions TO service_role;

COMMENT ON TABLE public.opener_sessions IS
  '開場救星兩段式：一局＝一份對方資料＋伺服器分析快照（文字線索與來源位置，不存圖片）。分析不扣費；首次成功生成才扣 first_generation_cost。ready 後 expires_at 固定 24h，到期由 pg_cron 清除。';

CREATE TABLE IF NOT EXISTS public.opener_generation_runs (
  user_id               UUID        NOT NULL
                                    REFERENCES auth.users(id) ON DELETE CASCADE,
  generation_id         UUID        NOT NULL,
  session_id            UUID        NOT NULL
                                    REFERENCES public.opener_sessions(session_id)
                                    ON DELETE CASCADE,
  input_hash            TEXT        NOT NULL
                                    CHECK (input_hash ~ '^[0-9a-f]{64}$'),
  state                 TEXT        NOT NULL DEFAULT 'pending'
                                    CHECK (state IN ('pending', 'done')),
  owner_token           UUID        NOT NULL,
  lease_expires_at      TIMESTAMPTZ NOT NULL,
  contribution_json     JSONB       NOT NULL,
  result_json           JSONB,
  charged_amount        INTEGER     NOT NULL DEFAULT 0
                                    CHECK (charged_amount >= 0),
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, generation_id),
  CONSTRAINT opener_generation_runs_state_consistency CHECK (
    (state = 'pending' AND result_json IS NULL AND charged_amount = 0)
    OR (
      state = 'done'
      AND result_json IS NOT NULL
      AND jsonb_typeof(result_json) = 'object'
    )
  )
);

CREATE INDEX IF NOT EXISTS opener_generation_runs_session_idx
  ON public.opener_generation_runs (session_id, state);

ALTER TABLE public.opener_generation_runs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.opener_generation_runs FROM PUBLIC;
REVOKE ALL ON TABLE public.opener_generation_runs FROM anon, authenticated;
GRANT SELECT ON TABLE public.opener_generation_runs TO service_role;

COMMENT ON TABLE public.opener_generation_runs IS
  '開場救星兩段式第二段作業：一次「按生成」一列。同 generation_id 重試取回同組結果；contribution_json 是用戶本次選項與補充原文（隨會話 24h 到期一起清除）。result_json 只存已依 tier 投影的可交付結果。';

-- ── 清理：到期會話（含 CASCADE 作業）＋租約失效超過 1 小時的孤兒 pending 列 ──
CREATE OR REPLACE FUNCTION public.cleanup_expired_opener_sessions()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deleted INTEGER;
BEGIN
  DELETE FROM public.opener_sessions
  WHERE (state = 'ready' AND expires_at < now())
     OR (state = 'pending' AND lease_expires_at < now() - interval '1 hour');
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.cleanup_expired_opener_sessions() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cleanup_expired_opener_sessions()
  FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_expired_opener_sessions()
  TO service_role;

DO $schedule$
DECLARE
  v_job_id BIGINT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_cron') THEN
    IF current_setting('app.allow_missing_pg_cron', true) = 'pglite-contract-test' THEN
      RAISE NOTICE 'pg_cron not available; opener session cleanup job skipped (test mode)';
      RETURN;
    END IF;
    RAISE EXCEPTION 'pg_cron is required to schedule opener session cleanup';
  END IF;

  CREATE EXTENSION IF NOT EXISTS pg_cron;

  FOR v_job_id IN
    SELECT jobid FROM cron.job WHERE jobname = 'cleanup-expired-opener-sessions'
  LOOP
    PERFORM cron.unschedule(v_job_id);
  END LOOP;

  PERFORM cron.schedule(
    'cleanup-expired-opener-sessions',
    '29 * * * *',
    'SELECT public.cleanup_expired_opener_sessions();'
  );
END
$schedule$;

-- ── 第一段：分析作業 claim / release / settle ─────────────────────────────
-- 回傳 kind：claimed｜pending（他人租約仍有效）｜replay（已 ready，帶快照）｜
-- expired（已 ready 但過期）。同 analysis_request_id 換輸入 RAISE
-- OPENER_OPERATION_INPUT_MISMATCH。
CREATE OR REPLACE FUNCTION public.claim_opener_analysis(
  p_user_id UUID,
  p_analysis_request_id UUID,
  p_input_hash TEXT,
  p_owner_token UUID,
  p_flow_version INTEGER,
  p_contract_version INTEGER,
  p_lease_seconds INTEGER DEFAULT 65
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inserted INTEGER;
  v_existing public.opener_sessions%ROWTYPE;
  v_lease_expires_at TIMESTAMPTZ :=
    now() + make_interval(secs => GREATEST(1, COALESCE(p_lease_seconds, 65)));
BEGIN
  IF p_user_id IS NULL OR p_analysis_request_id IS NULL OR p_owner_token IS NULL THEN
    RAISE EXCEPTION 'claim_opener_analysis: identity is required';
  END IF;
  IF p_input_hash IS NULL OR p_input_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'claim_opener_analysis: invalid p_input_hash';
  END IF;
  IF p_flow_version IS NULL OR p_flow_version < 1
     OR p_contract_version IS NULL OR p_contract_version < 1 THEN
    RAISE EXCEPTION 'claim_opener_analysis: invalid versions';
  END IF;

  INSERT INTO public.opener_sessions (
    user_id, analysis_request_id, input_hash, state, owner_token,
    lease_expires_at, flow_version, contract_version
  ) VALUES (
    p_user_id, p_analysis_request_id, p_input_hash, 'pending', p_owner_token,
    v_lease_expires_at, p_flow_version, p_contract_version
  )
  ON CONFLICT (user_id, analysis_request_id) DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  IF v_inserted = 1 THEN
    RETURN jsonb_build_object('kind', 'claimed', 'leaseExpiresAt', v_lease_expires_at);
  END IF;

  SELECT * INTO v_existing
  FROM public.opener_sessions
  WHERE user_id = p_user_id AND analysis_request_id = p_analysis_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'OPENER_SESSION_INVALID';
  END IF;
  IF v_existing.input_hash IS DISTINCT FROM p_input_hash THEN
    RAISE EXCEPTION 'OPENER_OPERATION_INPUT_MISMATCH';
  END IF;
  IF v_existing.state = 'ready' THEN
    IF v_existing.expires_at <= now() THEN
      RETURN jsonb_build_object('kind', 'expired');
    END IF;
    RETURN jsonb_build_object(
      'kind', 'replay',
      'sessionId', v_existing.session_id,
      'analysisRevision', v_existing.analysis_revision,
      'analysisJson', v_existing.analysis_json,
      'expiresAt', v_existing.expires_at,
      'firstGenerationCost', v_existing.first_generation_cost,
      'quotaCharged', v_existing.quota_charged,
      'generationsUsed', v_existing.generations_used
    );
  END IF;
  IF v_existing.owner_token = p_owner_token THEN
    UPDATE public.opener_sessions
    SET lease_expires_at = v_lease_expires_at, updated_at = now()
    WHERE session_id = v_existing.session_id AND state = 'pending';
    RETURN jsonb_build_object('kind', 'claimed', 'leaseExpiresAt', v_lease_expires_at);
  END IF;
  IF v_existing.lease_expires_at > now() THEN
    RETURN jsonb_build_object(
      'kind', 'pending',
      'retryAfterMs', GREATEST(
        250,
        CEIL(EXTRACT(EPOCH FROM (v_existing.lease_expires_at - now())) * 1000)::INTEGER
      )
    );
  END IF;

  -- 租約過期：接手，並凍結為本 owner（舊作業晚回會在 settle 被 owner 檢查擋下）。
  UPDATE public.opener_sessions
  SET owner_token = p_owner_token,
      lease_expires_at = v_lease_expires_at,
      updated_at = now()
  WHERE session_id = v_existing.session_id;
  RETURN jsonb_build_object('kind', 'claimed', 'leaseExpiresAt', v_lease_expires_at);
END;
$$;

CREATE OR REPLACE FUNCTION public.release_opener_analysis_claim(
  p_user_id UUID,
  p_analysis_request_id UUID,
  p_owner_token UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deleted INTEGER;
BEGIN
  DELETE FROM public.opener_sessions
  WHERE user_id = p_user_id
    AND analysis_request_id = p_analysis_request_id
    AND owner_token = p_owner_token
    AND state = 'pending';
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted = 1;
END;
$$;

-- 分析快照落地：state→ready、expires_at 固定為 now()+ttl。已 ready 的重複
-- settle 直接回存檔（不改到期、不改版本）。
CREATE OR REPLACE FUNCTION public.settle_opener_analysis(
  p_user_id UUID,
  p_analysis_request_id UUID,
  p_owner_token UUID,
  p_analysis_json JSONB,
  p_first_generation_cost INTEGER,
  p_ttl_seconds INTEGER DEFAULT 86400
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing public.opener_sessions%ROWTYPE;
  v_expires_at TIMESTAMPTZ;
BEGIN
  IF p_user_id IS NULL OR p_analysis_request_id IS NULL OR p_owner_token IS NULL THEN
    RAISE EXCEPTION 'settle_opener_analysis: identity is required';
  END IF;
  IF p_analysis_json IS NULL OR jsonb_typeof(p_analysis_json) <> 'object'
     OR NOT (p_analysis_json ?& ARRAY['approach', 'cues', 'profileDigest'])
     OR jsonb_typeof(p_analysis_json -> 'approach') <> 'object'
     OR jsonb_typeof(p_analysis_json -> 'cues') <> 'array'
     OR jsonb_typeof(p_analysis_json -> 'profileDigest') <> 'string'
     OR (p_analysis_json ? 'question'
         AND jsonb_typeof(p_analysis_json -> 'question') NOT IN ('object', 'null'))
     OR p_analysis_json ? 'images' OR p_analysis_json ? 'imageData' THEN
    RAISE EXCEPTION 'settle_opener_analysis: invalid p_analysis_json';
  END IF;
  IF p_first_generation_cost IS NULL OR p_first_generation_cost < 0 THEN
    RAISE EXCEPTION 'settle_opener_analysis: invalid p_first_generation_cost';
  END IF;
  IF p_ttl_seconds IS NULL OR p_ttl_seconds <= 0 THEN
    RAISE EXCEPTION 'settle_opener_analysis: invalid p_ttl_seconds';
  END IF;

  SELECT * INTO v_existing
  FROM public.opener_sessions
  WHERE user_id = p_user_id AND analysis_request_id = p_analysis_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'OPENER_SESSION_INVALID';
  END IF;
  IF v_existing.state = 'ready' THEN
    RETURN jsonb_build_object(
      'replayed', TRUE,
      'sessionId', v_existing.session_id,
      'analysisRevision', v_existing.analysis_revision,
      'analysisJson', v_existing.analysis_json,
      'expiresAt', v_existing.expires_at,
      'firstGenerationCost', v_existing.first_generation_cost
    );
  END IF;
  IF v_existing.owner_token IS DISTINCT FROM p_owner_token THEN
    RAISE EXCEPTION 'OPENER_OPERATION_OWNER_MISMATCH';
  END IF;

  v_expires_at := now() + make_interval(secs => p_ttl_seconds);
  UPDATE public.opener_sessions
  SET state = 'ready',
      analysis_json = p_analysis_json,
      first_generation_cost = p_first_generation_cost,
      expires_at = v_expires_at,
      updated_at = now()
  WHERE session_id = v_existing.session_id;

  RETURN jsonb_build_object(
    'replayed', FALSE,
    'sessionId', v_existing.session_id,
    'analysisRevision', v_existing.analysis_revision,
    'analysisJson', p_analysis_json,
    'expiresAt', v_expires_at,
    'firstGenerationCost', p_first_generation_cost
  );
END;
$$;

-- ── 第二段：生成作業 claim / release / settle ─────────────────────────────
-- 回傳 kind：claimed（帶會話報價與已扣狀態）｜pending（同 generation_id
-- 他人租約仍有效）｜session_busy（同局另一作業執行中）｜replay（已 done）。
-- RAISE：OPENER_SESSION_INVALID／OPENER_SESSION_EXPIRED／
-- OPENER_OPERATION_INPUT_MISMATCH／OPENER_GENERATION_LIMIT_REACHED。
CREATE OR REPLACE FUNCTION public.claim_opener_generation(
  p_user_id UUID,
  p_session_id UUID,
  p_generation_id UUID,
  p_input_hash TEXT,
  p_owner_token UUID,
  p_contribution_json JSONB,
  p_max_generations INTEGER DEFAULT 3,
  p_lease_seconds INTEGER DEFAULT 65
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.opener_sessions%ROWTYPE;
  v_run public.opener_generation_runs%ROWTYPE;
  v_busy public.opener_generation_runs%ROWTYPE;
  v_lease_expires_at TIMESTAMPTZ :=
    now() + make_interval(secs => GREATEST(1, COALESCE(p_lease_seconds, 65)));
  v_session_view JSONB;
BEGIN
  IF p_user_id IS NULL OR p_session_id IS NULL OR p_generation_id IS NULL
     OR p_owner_token IS NULL THEN
    RAISE EXCEPTION 'claim_opener_generation: identity is required';
  END IF;
  IF p_input_hash IS NULL OR p_input_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'claim_opener_generation: invalid p_input_hash';
  END IF;
  IF p_contribution_json IS NULL OR jsonb_typeof(p_contribution_json) <> 'object' THEN
    RAISE EXCEPTION 'claim_opener_generation: invalid p_contribution_json';
  END IF;
  IF p_max_generations IS NULL OR p_max_generations < 1 THEN
    RAISE EXCEPTION 'claim_opener_generation: invalid p_max_generations';
  END IF;

  -- 會話鎖：同局的 claim 串行化（同局最多一個執行中作業的權威在這把鎖上）。
  SELECT * INTO v_session
  FROM public.opener_sessions
  WHERE session_id = p_session_id AND user_id = p_user_id
  FOR UPDATE;
  IF NOT FOUND OR v_session.state <> 'ready' THEN
    RAISE EXCEPTION 'OPENER_SESSION_INVALID';
  END IF;
  IF v_session.expires_at <= now() THEN
    RAISE EXCEPTION 'OPENER_SESSION_EXPIRED';
  END IF;

  v_session_view := jsonb_build_object(
    'sessionId', v_session.session_id,
    'analysisRevision', v_session.analysis_revision,
    'analysisJson', v_session.analysis_json,
    'expiresAt', v_session.expires_at,
    'firstGenerationCost', v_session.first_generation_cost,
    'quotaCharged', v_session.quota_charged,
    'chargedAmount', v_session.charged_amount,
    'generationsUsed', v_session.generations_used,
    'contractVersion', v_session.contract_version
  );

  SELECT * INTO v_run
  FROM public.opener_generation_runs
  WHERE user_id = p_user_id AND generation_id = p_generation_id
  FOR UPDATE;

  IF FOUND THEN
    IF v_run.session_id IS DISTINCT FROM p_session_id
       OR v_run.input_hash IS DISTINCT FROM p_input_hash THEN
      RAISE EXCEPTION 'OPENER_OPERATION_INPUT_MISMATCH';
    END IF;
    IF v_run.state = 'done' THEN
      RETURN jsonb_build_object(
        'kind', 'replay',
        'result', v_run.result_json,
        'session', v_session_view
      );
    END IF;
    IF v_run.owner_token = p_owner_token THEN
      UPDATE public.opener_generation_runs
      SET lease_expires_at = v_lease_expires_at, updated_at = now()
      WHERE user_id = p_user_id AND generation_id = p_generation_id;
      RETURN jsonb_build_object(
        'kind', 'claimed', 'leaseExpiresAt', v_lease_expires_at,
        'session', v_session_view
      );
    END IF;
    IF v_run.lease_expires_at > now() THEN
      RETURN jsonb_build_object(
        'kind', 'pending',
        'retryAfterMs', GREATEST(
          250,
          CEIL(EXTRACT(EPOCH FROM (v_run.lease_expires_at - now())) * 1000)::INTEGER
        )
      );
    END IF;
    UPDATE public.opener_generation_runs
    SET owner_token = p_owner_token,
        lease_expires_at = v_lease_expires_at,
        updated_at = now()
    WHERE user_id = p_user_id AND generation_id = p_generation_id;
    RETURN jsonb_build_object(
      'kind', 'claimed', 'leaseExpiresAt', v_lease_expires_at,
      'session', v_session_view
    );
  END IF;

  -- 新作業：先擋次數（模型呼叫前），再擋同局併發。
  IF v_session.generations_used >= p_max_generations THEN
    RAISE EXCEPTION 'OPENER_GENERATION_LIMIT_REACHED';
  END IF;

  SELECT * INTO v_busy
  FROM public.opener_generation_runs
  WHERE session_id = p_session_id
    AND state = 'pending'
    AND lease_expires_at > now()
  ORDER BY lease_expires_at DESC
  LIMIT 1;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'kind', 'session_busy',
      'generationId', v_busy.generation_id,
      'retryAfterMs', GREATEST(
        250,
        CEIL(EXTRACT(EPOCH FROM (v_busy.lease_expires_at - now())) * 1000)::INTEGER
      )
    );
  END IF;

  INSERT INTO public.opener_generation_runs (
    user_id, generation_id, session_id, input_hash, state, owner_token,
    lease_expires_at, contribution_json
  ) VALUES (
    p_user_id, p_generation_id, p_session_id, p_input_hash, 'pending',
    p_owner_token, v_lease_expires_at, p_contribution_json
  );
  RETURN jsonb_build_object(
    'kind', 'claimed', 'leaseExpiresAt', v_lease_expires_at,
    'session', v_session_view
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.release_opener_generation_claim(
  p_user_id UUID,
  p_generation_id UUID,
  p_owner_token UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deleted INTEGER;
BEGIN
  DELETE FROM public.opener_generation_runs
  WHERE user_id = p_user_id
    AND generation_id = p_generation_id
    AND owner_token = p_owner_token
    AND state = 'pending';
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted = 1;
END;
$$;

-- 可交付結果的深層驗證：頂層鍵白名單、openers 非空且每句 ≤180 字、
-- recommendation.pick 必須是可見卡、access.visibleTypes 與 openers 鍵一致。
CREATE OR REPLACE FUNCTION public.validate_opener_generation_result(
  p_result_json JSONB
)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_key TEXT;
  v_text TEXT;
  v_pick TEXT;
  v_count INTEGER := 0;
BEGIN
  IF p_result_json IS NULL OR jsonb_typeof(p_result_json) <> 'object'
     OR NOT (p_result_json ?& ARRAY['openers', 'recommendation', 'access', 'materialUse'])
     OR jsonb_typeof(p_result_json -> 'openers') <> 'object'
     OR jsonb_typeof(p_result_json -> 'recommendation') <> 'object'
     OR jsonb_typeof(p_result_json -> 'access') <> 'object'
     OR jsonb_typeof(p_result_json -> 'materialUse') <> 'object' THEN
    RETURN FALSE;
  END IF;
  IF (p_result_json
      - 'openers' - 'recommendation' - 'access' - 'materialUse'
      - 'cardReasons' - 'stretchLevels' - 'pioneerPlan' - 'profileAnalysis'
      - 'recommendedPick' - 'recommendedReason') <> '{}'::jsonb THEN
    RETURN FALSE;
  END IF;

  FOR v_key, v_text IN
    SELECT key, value #>> '{}'
    FROM jsonb_each(p_result_json -> 'openers')
  LOOP
    IF v_key NOT IN ('extend', 'resonate', 'tease', 'humor', 'coldRead')
       OR v_text IS NULL OR length(btrim(v_text)) = 0 OR length(v_text) > 180 THEN
      RETURN FALSE;
    END IF;
    v_count := v_count + 1;
  END LOOP;
  IF v_count = 0 THEN
    RETURN FALSE;
  END IF;

  v_pick := p_result_json -> 'recommendation' ->> 'pick';
  IF v_pick IS NULL OR NOT ((p_result_json -> 'openers') ? v_pick) THEN
    RETURN FALSE;
  END IF;
  IF NOT ((p_result_json -> 'access') ?& ARRAY['servedTier', 'visibleTypes', 'lockedTypes', 'contractVersion'])
     OR jsonb_typeof(p_result_json -> 'access' -> 'visibleTypes') <> 'array' THEN
    RETURN FALSE;
  END IF;
  RETURN TRUE;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.validate_opener_generation_result(JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.validate_opener_generation_result(JSONB)
  FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.validate_opener_generation_result(JSONB)
  TO service_role;

-- 結算：保存結果、首次扣費、成功數 +1、標示完成，同一交易。
-- 再驗：租約 owner、會話期限、次數上限；increment_usage RAISE 令整筆回滾。
-- 已 done 的重複 settle 回存檔（replayed=true、chargedNow=0）。
CREATE OR REPLACE FUNCTION public.settle_opener_generation(
  p_user_id UUID,
  p_session_id UUID,
  p_generation_id UUID,
  p_owner_token UUID,
  p_result_json JSONB,
  p_monthly_limit INTEGER,
  p_daily_limit INTEGER,
  p_charge_quota BOOLEAN DEFAULT TRUE,
  p_max_generations INTEGER DEFAULT 3
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.opener_sessions%ROWTYPE;
  v_run public.opener_generation_runs%ROWTYPE;
  v_charge_now INTEGER := 0;
  v_should_charge BOOLEAN := COALESCE(p_charge_quota, TRUE);
BEGIN
  IF p_user_id IS NULL OR p_session_id IS NULL OR p_generation_id IS NULL
     OR p_owner_token IS NULL THEN
    RAISE EXCEPTION 'settle_opener_generation: identity is required';
  END IF;
  IF NOT public.validate_opener_generation_result(p_result_json) THEN
    RAISE EXCEPTION 'settle_opener_generation: invalid p_result_json';
  END IF;
  IF p_max_generations IS NULL OR p_max_generations < 1 THEN
    RAISE EXCEPTION 'settle_opener_generation: invalid p_max_generations';
  END IF;

  SELECT * INTO v_session
  FROM public.opener_sessions
  WHERE session_id = p_session_id AND user_id = p_user_id
  FOR UPDATE;
  IF NOT FOUND OR v_session.state <> 'ready' THEN
    RAISE EXCEPTION 'OPENER_SESSION_INVALID';
  END IF;

  SELECT * INTO v_run
  FROM public.opener_generation_runs
  WHERE user_id = p_user_id AND generation_id = p_generation_id
  FOR UPDATE;
  IF NOT FOUND OR v_run.session_id IS DISTINCT FROM p_session_id THEN
    RAISE EXCEPTION 'OPENER_SESSION_INVALID';
  END IF;
  IF v_run.state = 'done' THEN
    RETURN jsonb_build_object(
      'replayed', TRUE,
      'chargedNow', 0,
      'sessionChargedTotal', v_session.charged_amount,
      'generationsUsed', v_session.generations_used,
      'generationsRemaining', GREATEST(0, p_max_generations - v_session.generations_used),
      'result', v_run.result_json
    );
  END IF;
  IF v_run.owner_token IS DISTINCT FROM p_owner_token THEN
    RAISE EXCEPTION 'OPENER_OPERATION_OWNER_MISMATCH';
  END IF;
  IF v_session.expires_at <= now() THEN
    RAISE EXCEPTION 'OPENER_SESSION_EXPIRED';
  END IF;
  IF v_session.generations_used >= p_max_generations THEN
    RAISE EXCEPTION 'OPENER_GENERATION_LIMIT_REACHED';
  END IF;

  IF v_should_charge AND NOT v_session.quota_charged
     AND v_session.first_generation_cost > 0 THEN
    IF p_monthly_limit IS NULL OR p_monthly_limit <= 0
       OR p_daily_limit IS NULL OR p_daily_limit <= 0 THEN
      RAISE EXCEPTION 'settle_opener_generation: invalid quota limits';
    END IF;
    PERFORM 1 FROM public.subscriptions WHERE user_id = p_user_id FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'OPENER_SUBSCRIPTION_MISSING';
    END IF;
    -- 超限 RAISE（QUOTA_EXCEEDED_*）→ 整筆回滾：結果不落地、成功數不動。
    PERFORM public.increment_usage(
      p_user_id, v_session.first_generation_cost, p_monthly_limit, p_daily_limit
    );
    v_charge_now := v_session.first_generation_cost;
    UPDATE public.opener_sessions
    SET quota_charged = TRUE,
        charged_amount = v_session.first_generation_cost
    WHERE session_id = p_session_id;
  END IF;

  UPDATE public.opener_sessions
  SET generations_used = generations_used + 1,
      updated_at = now()
  WHERE session_id = p_session_id;

  UPDATE public.opener_generation_runs
  SET state = 'done',
      result_json = p_result_json,
      charged_amount = v_charge_now,
      updated_at = now()
  WHERE user_id = p_user_id AND generation_id = p_generation_id;

  SELECT * INTO v_session FROM public.opener_sessions WHERE session_id = p_session_id;

  RETURN jsonb_build_object(
    'replayed', FALSE,
    'chargedNow', v_charge_now,
    'sessionChargedTotal', v_session.charged_amount,
    'generationsUsed', v_session.generations_used,
    'generationsRemaining', GREATEST(0, p_max_generations - v_session.generations_used),
    'result', p_result_json
  );
END;
$$;

DO $grants$
DECLARE
  v_sig TEXT;
BEGIN
  FOREACH v_sig IN ARRAY ARRAY[
    'public.claim_opener_analysis(uuid,uuid,text,uuid,integer,integer,integer)',
    'public.release_opener_analysis_claim(uuid,uuid,uuid)',
    'public.settle_opener_analysis(uuid,uuid,uuid,jsonb,integer,integer)',
    'public.claim_opener_generation(uuid,uuid,uuid,text,uuid,jsonb,integer,integer)',
    'public.release_opener_generation_claim(uuid,uuid,uuid)',
    'public.settle_opener_generation(uuid,uuid,uuid,uuid,jsonb,integer,integer,boolean,integer)'
  ]
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', v_sig);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon, authenticated', v_sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', v_sig);
  END LOOP;
END
$grants$;

-- Edge 讀這個 DB 端能力標記決定是否受理新局：migration 沒套齊時新版 App 會
-- 收到 OPENER_FLOW_UNAVAILABLE 並退回舊單段（只限尚未進入兩段式的局）。
CREATE OR REPLACE FUNCTION public.opener_flow_contract_version()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN to_regclass('public.opener_sessions') IS NOT NULL
      AND to_regclass('public.opener_generation_runs') IS NOT NULL
      AND to_regprocedure('public.claim_opener_analysis(uuid,uuid,text,uuid,integer,integer,integer)') IS NOT NULL
      AND to_regprocedure('public.settle_opener_analysis(uuid,uuid,uuid,jsonb,integer,integer)') IS NOT NULL
      AND to_regprocedure('public.claim_opener_generation(uuid,uuid,uuid,text,uuid,jsonb,integer,integer)') IS NOT NULL
      AND to_regprocedure('public.settle_opener_generation(uuid,uuid,uuid,uuid,jsonb,integer,integer,boolean,integer)') IS NOT NULL
      AND to_regprocedure('public.validate_opener_generation_result(jsonb)') IS NOT NULL
    THEN 'opener-two-stage-v1'::TEXT
    ELSE 'incomplete'::TEXT
  END;
$$;

REVOKE EXECUTE ON FUNCTION public.opener_flow_contract_version() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.opener_flow_contract_version()
  FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.opener_flow_contract_version() TO service_role;

NOTIFY pgrst, 'reload schema';
