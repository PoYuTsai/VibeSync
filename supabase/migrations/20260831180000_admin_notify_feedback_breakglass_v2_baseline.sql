-- 後台 B2 隱私安全通知、回報與受控診斷底座。純 additive；唯一既有物件變更是
-- admin_audit_events_v2 的 action CHECK 擴充。ADMIN_V2 與 DB cutover 都關閉
-- 時，既有後台／feedback 行為完全不變。本 migration 不投遞、不排程、不啟用。
--
-- 所有資料表採 allowlist：不得保存 email、對話、prompt、截圖、AI 原文、
-- Sentry raw、secret 或其他任意自由文字。所有 SECURITY DEFINER 函式固定
-- 空 search_path；所有直接資料表存取 deny-by-default。

-- ============================================================
-- Durable notification outbox：external_event_ref 是外部事件的唯一身分，
-- incident_id 是事故身分；同一 external event 重試只更新 occurrence，不會
-- 建立第二個外部事件。delivery 表記錄固定 channel 的每一次嘗試與 retry。
CREATE TABLE public.admin_notification_outbox_v2 (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template           TEXT NOT NULL CHECK (template IN ('red', 'yellow')),
  delivery_class     TEXT NOT NULL CHECK (delivery_class IN ('immediate', 'daily_brief')),
  reason_code        TEXT NOT NULL CHECK (reason_code IN ('feedback_received', 'breakglass_extended', 'edge_error_spike', 'quota_exhausted_spike', 'payment_webhook_failure', 'cost_spike')),
  incident_id        UUID REFERENCES public.admin_ops_incidents (id),
  external_event_ref TEXT NOT NULL UNIQUE CHECK (external_event_ref ~ '^[a-z][a-z0-9_.]{0,63}:sha256:[0-9a-f]{64}$'),
  user_ref           TEXT CHECK (user_ref ~ '^user:sha256:[0-9a-f]{64}$'),
  status             TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'failed')),
  occurrence_count   INTEGER NOT NULL DEFAULT 1 CHECK (occurrence_count >= 1),
  retry_count        INTEGER NOT NULL DEFAULT 0 CHECK (retry_count >= 0),
  next_retry_at      TIMESTAMPTZ,
  last_attempt_at    TIMESTAMPTZ,
  first_seen_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK ((template = 'red' AND delivery_class = 'immediate')
      OR (template = 'yellow' AND delivery_class = 'daily_brief'))
);

CREATE TABLE public.admin_notification_deliveries_v2 (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  outbox_id    UUID NOT NULL REFERENCES public.admin_notification_outbox_v2 (id),
  channel      TEXT NOT NULL CHECK (channel IN ('discord', 'email_fallback')),
  attempt_no   INTEGER NOT NULL CHECK (attempt_no >= 1),
  result       TEXT NOT NULL CHECK (result IN ('success', 'failure')),
  error_code   TEXT CHECK (error_code ~ '^[a-z][a-z0-9_]{0,63}$'),
  attempted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (outbox_id, channel, attempt_no),
  CHECK (result = 'failure' OR error_code IS NULL)
);

-- Metadata-only feedback inbox：request_ref 只衍生自 user + client 明確給的
-- opaque idempotency key；不接受 summary、留言、對話或 AI 內容。
CREATE TABLE public.admin_feedback_inbox_v2 (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- request-bound opaque ref：同一 retry 穩定、不同 client key 不可跨提交關聯。
  user_ref    TEXT NOT NULL CHECK (user_ref ~ '^feedback-user:v1:[0-9a-f]{32}$'),
  request_ref TEXT NOT NULL UNIQUE CHECK (request_ref ~ '^request:sha256:[0-9a-f]{64}$'),
  rating      TEXT NOT NULL CHECK (rating IN ('positive', 'negative')),
  category    TEXT CHECK (category IN ('too_direct', 'too_long', 'unnatural', 'wrong_style', 'other', 'too_beta', 'should_not_send', 'too_generic', 'invented_detail', 'wrong_judgment', 'too_many_questions', 'missed_context')),
  user_tier   TEXT CHECK (user_tier IN ('free', 'starter', 'essential', 'premium', 'other')),
  model_used  TEXT CHECK (model_used IN ('anthropic', 'deepseek', 'zai', 'other')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 一個 grant 嚴格鎖定一位 user、單一 function。captures_max 固定為三次。
CREATE TABLE public.admin_breakglass_grants_v2 (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  activated_by            UUID NOT NULL,
  scope_user_id           UUID NOT NULL,
  scope_function          TEXT NOT NULL CHECK (scope_function IN ('analyze-chat', 'coach-chat', 'coach-follow-up', 'keyboard-assist', 'keyboard-reply', 'practice-chat', 'submit-feedback', 'sync-subscription', 'delete-account', 'revenuecat-webhook')),
  reason                  TEXT NOT NULL CHECK (reason IN ('incident_response', 'support_request', 'billing_review', 'security_review', 'scheduled_maintenance', 'data_correction', 'legal_request', 'dual_control_approval')),
  assigned_viewer_user_id UUID,
  activated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at              TIMESTAMPTZ NOT NULL,
  captures_max            INTEGER NOT NULL DEFAULT 3 CHECK (captures_max = 3),
  captures_used           INTEGER NOT NULL DEFAULT 0,
  closed_at               TIMESTAMPTZ,
  closed_by               UUID,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (captures_used >= 0 AND captures_used <= captures_max),
  CHECK (expires_at > activated_at AND expires_at <= activated_at + INTERVAL '30 minutes')
);

-- 一個 scope 同時間只能有一個 open grant。activate 會先在同交易關閉已過期
-- 的 open grant；這個 partial unique index 再處理兩個 owner 同時啟用的競態。
CREATE UNIQUE INDEX admin_breakglass_grants_v2_one_open_scope_idx
  ON public.admin_breakglass_grants_v2 (scope_user_id, scope_function)
  WHERE closed_at IS NULL;

-- 由 Edge runtime（service_role）在實際請求發生時寫入的 immutable receipt。
-- 管理端 JWT 沒有此表的表權限或 RPC execute，因此不能自稱 request_ref、scope
-- 或 occurred_at。occurred_at 永遠由資料庫 now() 產生，不能由 caller 傳入。
CREATE TABLE public.admin_breakglass_request_occurrences_v2 (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_ref     TEXT NOT NULL UNIQUE CHECK (request_ref ~ '^request:sha256:[0-9a-f]{64}$'),
  scope_user_id   UUID NOT NULL,
  scope_function  TEXT NOT NULL CHECK (scope_function IN ('analyze-chat', 'coach-chat', 'coach-follow-up', 'keyboard-assist', 'keyboard-reply', 'practice-chat', 'submit-feedback', 'sync-subscription', 'delete-account', 'revenuecat-webhook')),
  occurred_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  provenance      TEXT NOT NULL DEFAULT 'edge_runtime' CHECK (provenance = 'edge_runtime'),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Capture 只存 authenticated-encryption envelope。nonce 是每一 key 的唯一值，
-- 即使 ciphertext 已 purge 仍保留 nonce/key receipt，防止日後重用 nonce。
CREATE TABLE public.admin_breakglass_captures_v2 (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  grant_id       UUID NOT NULL REFERENCES public.admin_breakglass_grants_v2 (id),
  request_ref    TEXT NOT NULL CHECK (request_ref ~ '^request:sha256:[0-9a-f]{64}$'),
  cipher         TEXT NOT NULL CHECK (cipher IN ('aes-256-gcm')),
  key_ref        TEXT NOT NULL CHECK (key_ref ~ '^key:[a-z0-9_.-]{1,64}$'),
  nonce_hex      TEXT NOT NULL CHECK (nonce_hex ~ '^[0-9a-f]{24}$'),
  ciphertext_b64 TEXT CHECK (ciphertext_b64 ~ '^[A-Za-z0-9+/]+={0,2}$' AND ciphertext_b64 !~ '^eyJ'),
  captured_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at     TIMESTAMPTZ NOT NULL,
  extension_count INTEGER NOT NULL DEFAULT 0 CHECK (extension_count IN (0, 1)),
  purged_at      TIMESTAMPTZ,
  UNIQUE (grant_id, request_ref),
  UNIQUE (key_ref, nonce_hex),
  CHECK (expires_at > captured_at AND expires_at <= captured_at + INTERVAL '7 days'),
  CHECK ((purged_at IS NULL AND ciphertext_b64 IS NOT NULL)
      OR (purged_at IS NOT NULL AND ciphertext_b64 IS NULL))
);

-- ============================================================
-- V2 身分與 DB cutover。active B1/V2 account 本身不會封鎖 legacy raw
-- ai_logs；只有這個顯式 switch 打開後才會套用 restrictive raw policy。
CREATE FUNCTION public.admin_v2_is_active_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.admin_accounts_v2 a
    WHERE a.user_id = auth.uid()
      AND a.is_active
      AND a.role IN ('owner', 'founder_admin')
  );
$$;

CREATE TABLE public.admin_v2_settings (
  singleton                  BOOLEAN PRIMARY KEY DEFAULT true CHECK (singleton),
  ai_logs_cutover_enabled    BOOLEAN NOT NULL DEFAULT false,
  updated_at                 TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO public.admin_v2_settings (singleton, ai_logs_cutover_enabled)
VALUES (true, false);

CREATE FUNCTION public.admin_v2_ai_logs_cutover_enabled()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COALESCE((
    SELECT s.ai_logs_cutover_enabled
    FROM public.admin_v2_settings s
    WHERE s.singleton
  ), false);
$$;

-- V2 errors 不建立可由 authenticated 直接 SELECT 的 view/table。metadata-only
-- RPC 定義在下方完整 B1 session gate 後，且只回 dashboard 需要的 allowlist 欄位。
-- Cutover 固定順序：先部署此 RPC 與 ADMIN_V2 route，再開 DB raw-log cutover；
-- 回退時先關 DB cutover，最後才關 ADMIN_V2 route，兩個開關不能任意交錯。

-- ============================================================
-- V2 feedback：唯一對 service_role 開放的 feedback operation RPC。inbox 與
-- outbox 同一交易；同 request_ref 的 retry 不會新增 inbox 或 external event。
CREATE FUNCTION public.admin_v2_submit_feedback(
  p_user_ref    TEXT,
  p_request_ref TEXT,
  p_rating      TEXT,
  p_category    TEXT DEFAULT NULL,
  p_user_tier   TEXT DEFAULT NULL,
  p_model_used  TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_id UUID;
  v_external_event_ref TEXT := 'feedback:sha256:' || right(p_request_ref, 64);
BEGIN
  INSERT INTO public.admin_feedback_inbox_v2
    (user_ref, request_ref, rating, category, user_tier, model_used)
  VALUES (p_user_ref, p_request_ref, p_rating, p_category, p_user_tier, p_model_used)
  ON CONFLICT (request_ref) DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NOT NULL THEN
    INSERT INTO public.admin_notification_outbox_v2
      (template, delivery_class, reason_code, incident_id, external_event_ref, user_ref)
    VALUES
      -- feedback 的 request-bound user_ref 只留在 inbox，不進 notification outbox。
      ('yellow', 'daily_brief', 'feedback_received', NULL, v_external_event_ref, NULL)
    ON CONFLICT (external_event_ref) DO UPDATE
      SET occurrence_count = public.admin_notification_outbox_v2.occurrence_count + 1,
          last_seen_at = now();
  END IF;
END;
$$;

-- ============================================================
-- 所有 authenticated V2 operation RPC 的共同完整 B1 session gate。它驗證
-- AAL2、active account/role、JWT session id、撤銷、version、12h absolute/30m
-- idle；activate/extend 再以 Supabase 已驗簽 JWT 的最新 AMR MFA timestamp
-- 加 10m fresh reauth。普通 token_refresh 與 client timestamp 都不能更新它。
CREATE FUNCTION public.admin_v2_authenticated_session_gate(
  p_require_reauth BOOLEAN DEFAULT false
)
RETURNS TABLE (
  actor_user_id UUID,
  actor_role    TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid      UUID := auth.uid();
  v_sid_text TEXT := NULLIF(auth.jwt() ->> 'session_id', '');
  v_sid      UUID;
  v_account  public.admin_accounts_v2;
  v_session  public.admin_sessions_v2;
  v_amr      JSONB := COALESCE(auth.jwt() -> 'amr', '[]'::jsonb);
  v_amr_method TEXT;
  v_amr_timestamp TEXT;
  v_mfa_at   TIMESTAMPTZ;
BEGIN
  IF v_uid IS NULL
     OR COALESCE(auth.jwt() ->> 'aal', '') <> 'aal2'
     OR v_sid_text IS NULL
     OR v_sid_text !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
    RAISE EXCEPTION 'breakglass denied';
  END IF;
  v_sid := v_sid_text::UUID;

  SELECT * INTO v_account
  FROM public.admin_accounts_v2 a
  WHERE a.user_id = v_uid
    AND a.is_active
    AND a.role IN ('owner', 'founder_admin');
  IF NOT FOUND THEN
    RAISE EXCEPTION 'breakglass denied';
  END IF;

  SELECT * INTO v_session
  FROM public.admin_sessions_v2 s
  WHERE s.session_id = v_sid
    AND s.user_id = v_uid;
  IF NOT FOUND
     OR v_session.revoked_at IS NOT NULL
     OR v_session.session_version <> v_account.session_version
     OR v_session.created_at > now()
     OR v_session.last_seen_at > now()
     OR now() - v_session.created_at > INTERVAL '12 hours'
     OR now() - v_session.last_seen_at > INTERVAL '30 minutes' THEN
    RAISE EXCEPTION 'breakglass denied';
  END IF;

  IF p_require_reauth THEN
    -- Supabase AMR 最新驗證方法在 index 0，timestamp 是受簽章保護的 Unix
    -- seconds。只接受第二因子方法；token_refresh 不能把舊 MFA 變成 fresh。
    IF jsonb_typeof(v_amr) <> 'array'
       OR jsonb_array_length(v_amr) = 0
       OR jsonb_typeof(v_amr -> 0) <> 'object' THEN
      RAISE EXCEPTION 'breakglass denied';
    END IF;
    v_amr_method := lower(COALESCE(v_amr #>> '{0,method}', ''));
    v_amr_timestamp := v_amr #>> '{0,timestamp}';
    IF v_amr_method NOT IN ('totp', 'phone', 'webauthn', 'mfa')
       OR v_amr_timestamp IS NULL
       OR v_amr_timestamp !~ '^[0-9]{10}(\.[0-9]{1,6})?$' THEN
      RAISE EXCEPTION 'breakglass denied';
    END IF;
    v_mfa_at := to_timestamp(v_amr_timestamp::double precision);
    IF v_mfa_at > now()
       OR now() - v_mfa_at > INTERVAL '10 minutes' THEN
      RAISE EXCEPTION 'breakglass denied';
    END IF;
  END IF;

  RETURN QUERY SELECT v_uid, v_account.role;
END;
$$;

-- V2 errors 唯一讀取入口：完整 B1 session gate 成功後才讀 ai_logs，且回傳欄位
-- 是 route 的最小 allowlist。沒有 authenticated SELECT grant 到任何 metadata view。
CREATE FUNCTION public.admin_v2_list_error_metadata()
RETURNS TABLE (
  id           UUID,
  created_at   TIMESTAMPTZ,
  error_code   TEXT,
  request_type TEXT,
  user_id      UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM 1 FROM public.admin_v2_authenticated_session_gate(false);
  RETURN QUERY
  SELECT l.id, l.created_at, l.error_code, l.request_type, l.user_id
  FROM public.ai_logs l
  WHERE l.status = 'failed'
  ORDER BY l.created_at DESC
  LIMIT 200;
END;
$$;

-- 啟用：只有 owner + fresh reauth。scope 固定一 user/function，首次窗口 30m。
CREATE FUNCTION public.admin_v2_breakglass_activate(
  p_scope_user_id           UUID,
  p_scope_function          TEXT,
  p_reason                  TEXT,
  p_assigned_viewer_user_id UUID DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor RECORD;
  v_id UUID;
BEGIN
  SELECT * INTO v_actor
  FROM public.admin_v2_authenticated_session_gate(true);
  IF v_actor.actor_role <> 'owner' THEN
    RAISE EXCEPTION 'breakglass denied';
  END IF;
  IF p_assigned_viewer_user_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.admin_accounts_v2 a
    WHERE a.user_id = p_assigned_viewer_user_id
      AND a.is_active
      AND a.role IN ('owner', 'founder_admin')
  ) THEN
    RAISE EXCEPTION 'breakglass assigned viewer must be an active admin';
  END IF;

  -- 同 scope 的已過期 open grant 先在本交易安全收斂，避免 partial unique
  -- index 永久卡住下一次合法啟用。未過期的 open grant 必須明確拒絕，不能累加
  -- 出 3N captures；index 再處理兩個 owner 同時執行 activate 的競態。
  UPDATE public.admin_breakglass_grants_v2 g
  SET closed_at = now(), closed_by = v_actor.actor_user_id
  WHERE g.scope_user_id = p_scope_user_id
    AND g.scope_function = p_scope_function
    AND g.closed_at IS NULL
    AND g.expires_at <= now();

  PERFORM 1
  FROM public.admin_breakglass_grants_v2 g
  WHERE g.scope_user_id = p_scope_user_id
    AND g.scope_function = p_scope_function
    AND g.closed_at IS NULL
    AND g.expires_at > now()
  FOR UPDATE;
  IF FOUND THEN
    RAISE EXCEPTION 'breakglass grant already active for scope';
  END IF;

  INSERT INTO public.admin_breakglass_grants_v2
    (activated_by, scope_user_id, scope_function, reason, assigned_viewer_user_id, expires_at)
  VALUES (
    v_actor.actor_user_id,
    p_scope_user_id,
    p_scope_function,
    p_reason,
    p_assigned_viewer_user_id,
    now() + INTERVAL '30 minutes'
  )
  ON CONFLICT (scope_user_id, scope_function) WHERE closed_at IS NULL DO NOTHING
  RETURNING id INTO v_id;
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'breakglass grant already active for scope';
  END IF;

  INSERT INTO public.admin_audit_events_v2 (actor_user_id, action, target_ref, reason, result)
  VALUES (
    v_actor.actor_user_id,
    'breakglass.activate',
    'breakglass_grant:sha256:' || encode(sha256(convert_to(v_id::text, 'UTF8')), 'hex'),
    p_reason,
    'success'
  );
  RETURN v_id;
END;
$$;

-- 實際 Edge runtime request 的 immutable occurrence。僅 service_role 可執行，
-- 管理端 JWT 沒有此 entry point；時點由 DB 寫入而非 caller 自稱。相同
-- request_ref 的 retry 只能回到相同 scope receipt，不能改寫 provenance。
CREATE FUNCTION public.admin_v2_record_breakglass_runtime_occurrence(
  p_request_ref    TEXT,
  p_scope_user_id  UUID,
  p_scope_function TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_id       UUID;
  v_existing public.admin_breakglass_request_occurrences_v2;
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'breakglass runtime denied';
  END IF;

  INSERT INTO public.admin_breakglass_request_occurrences_v2
    (request_ref, scope_user_id, scope_function)
  VALUES (p_request_ref, p_scope_user_id, p_scope_function)
  ON CONFLICT (request_ref) DO NOTHING
  RETURNING id INTO v_id;
  IF v_id IS NOT NULL THEN
    RETURN v_id;
  END IF;

  SELECT * INTO v_existing
  FROM public.admin_breakglass_request_occurrences_v2 o
  WHERE o.request_ref = p_request_ref;
  IF NOT FOUND
     OR v_existing.scope_user_id IS DISTINCT FROM p_scope_user_id
     OR v_existing.scope_function IS DISTINCT FROM p_scope_function
     OR v_existing.provenance <> 'edge_runtime' THEN
    RAISE EXCEPTION 'breakglass runtime occurrence denied';
  END IF;
  RETURN v_existing.id;
END;
$$;

-- Capture 只能消耗已存在、由 service-role runtime 寫入的 occurrence。函式不收
-- caller 宣稱的 scope 或 occurred_at；grant/occurrence exact match、啟用後 future
-- occurrence、同 request retry、row lock 下三次 cap 與 key/nonce uniqueness 都在
-- 這個 transaction 內完成。authenticated 不具 execute，dashboard 不能自行 capture。
CREATE FUNCTION public.admin_v2_breakglass_capture_trusted_runtime_request(
  p_grant_id       UUID,
  p_request_ref    TEXT,
  p_cipher         TEXT,
  p_key_ref        TEXT,
  p_nonce_hex      TEXT,
  p_ciphertext_b64 TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_grant public.admin_breakglass_grants_v2;
  v_occurrence public.admin_breakglass_request_occurrences_v2;
  v_id UUID;
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'breakglass runtime denied';
  END IF;

  -- 完全相同 pair 的 retry 不消耗 cap，也不重複寫 audit。
  SELECT c.id INTO v_id
  FROM public.admin_breakglass_captures_v2 c
  WHERE c.grant_id = p_grant_id
    AND c.request_ref = p_request_ref;
  IF v_id IS NOT NULL THEN
    RETURN v_id;
  END IF;

  SELECT * INTO v_grant
  FROM public.admin_breakglass_grants_v2 g
  WHERE g.id = p_grant_id
  FOR UPDATE;
  IF NOT FOUND
     OR v_grant.closed_at IS NOT NULL
     OR now() >= v_grant.expires_at THEN
    RAISE EXCEPTION 'breakglass grant not capturable';
  END IF;

  SELECT * INTO v_occurrence
  FROM public.admin_breakglass_request_occurrences_v2 o
  WHERE o.request_ref = p_request_ref;
  IF NOT FOUND
     OR v_occurrence.provenance <> 'edge_runtime'
     OR v_occurrence.scope_user_id IS DISTINCT FROM v_grant.scope_user_id
     OR v_occurrence.scope_function IS DISTINCT FROM v_grant.scope_function
     OR v_occurrence.occurred_at < v_grant.activated_at
     OR v_occurrence.occurred_at >= v_grant.expires_at
     OR v_occurrence.occurred_at > now() THEN
    RAISE EXCEPTION 'breakglass runtime occurrence denied';
  END IF;

  -- 等待 grant row lock 的同 request 競態，在這個第二次讀取會回既有 capture。
  SELECT c.id INTO v_id
  FROM public.admin_breakglass_captures_v2 c
  WHERE c.grant_id = p_grant_id
    AND c.request_ref = p_request_ref;
  IF v_id IS NOT NULL THEN
    RETURN v_id;
  END IF;
  IF v_grant.captures_used >= v_grant.captures_max THEN
    RAISE EXCEPTION 'breakglass capture cap reached';
  END IF;

  UPDATE public.admin_breakglass_grants_v2 g
  SET captures_used = g.captures_used + 1
  WHERE g.id = v_grant.id
    AND g.captures_used < g.captures_max;

  INSERT INTO public.admin_breakglass_captures_v2
    (grant_id, request_ref, cipher, key_ref, nonce_hex, ciphertext_b64, expires_at)
  VALUES (
    p_grant_id,
    p_request_ref,
    p_cipher,
    p_key_ref,
    p_nonce_hex,
    p_ciphertext_b64,
    now() + INTERVAL '72 hours'
  )
  ON CONFLICT (grant_id, request_ref) DO NOTHING
  RETURNING id INTO v_id;
  IF v_id IS NULL THEN
    SELECT c.id INTO v_id
    FROM public.admin_breakglass_captures_v2 c
    WHERE c.grant_id = p_grant_id
      AND c.request_ref = p_request_ref;
    IF v_id IS NOT NULL THEN
      RETURN v_id;
    END IF;
    RAISE EXCEPTION 'breakglass capture conflict';
  END IF;

  INSERT INTO public.admin_audit_events_v2 (actor_user_id, action, target_ref, result)
  VALUES (
    v_grant.activated_by,
    'breakglass.capture',
    'breakglass_capture:sha256:' || encode(sha256(convert_to(v_id::text, 'UTF8')), 'hex'),
    'success'
  );
  RETURN v_id;
END;
$$;

-- 內容存取共用件不是外部 RPC：view/export 先經完整 session gate，再把已驗證
-- actor 帶進來。owner 可 view/export；founder_admin 僅可 view 被指派的 grant。
CREATE FUNCTION public.admin_v2_breakglass_content_gate(
  p_capture_id  UUID,
  p_actor_user_id UUID,
  p_actor_role  TEXT,
  p_owner_only  BOOLEAN
)
RETURNS public.admin_breakglass_captures_v2
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_cap   public.admin_breakglass_captures_v2;
  v_grant public.admin_breakglass_grants_v2;
BEGIN
  SELECT * INTO v_cap
  FROM public.admin_breakglass_captures_v2 c
  WHERE c.id = p_capture_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'breakglass denied';
  END IF;
  SELECT * INTO v_grant
  FROM public.admin_breakglass_grants_v2 g
  WHERE g.id = v_cap.grant_id;
  IF p_actor_role <> 'owner' THEN
    IF p_owner_only
       OR p_actor_role <> 'founder_admin'
       OR v_grant.assigned_viewer_user_id IS DISTINCT FROM p_actor_user_id THEN
      RAISE EXCEPTION 'breakglass denied';
    END IF;
  END IF;
  IF v_cap.purged_at IS NOT NULL OR now() >= v_cap.expires_at THEN
    RAISE EXCEPTION 'breakglass capture expired';
  END IF;
  RETURN v_cap;
END;
$$;

CREATE FUNCTION public.admin_v2_breakglass_view(p_capture_id UUID)
RETURNS TABLE (
  cipher         TEXT,
  key_ref        TEXT,
  nonce_hex      TEXT,
  ciphertext_b64 TEXT,
  captured_at    TIMESTAMPTZ,
  expires_at     TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor RECORD;
  v_cap public.admin_breakglass_captures_v2;
BEGIN
  SELECT * INTO v_actor
  FROM public.admin_v2_authenticated_session_gate(false);
  v_cap := public.admin_v2_breakglass_content_gate(
    p_capture_id,
    v_actor.actor_user_id,
    v_actor.actor_role,
    false
  );
  INSERT INTO public.admin_audit_events_v2 (actor_user_id, action, target_ref, result)
  VALUES (
    v_actor.actor_user_id,
    'breakglass.view',
    'breakglass_capture:sha256:' || encode(sha256(convert_to(v_cap.id::text, 'UTF8')), 'hex'),
    'success'
  );
  RETURN QUERY
  SELECT v_cap.cipher, v_cap.key_ref, v_cap.nonce_hex, v_cap.ciphertext_b64,
         v_cap.captured_at, v_cap.expires_at;
END;
$$;

CREATE FUNCTION public.admin_v2_breakglass_export(p_capture_id UUID)
RETURNS TABLE (
  cipher         TEXT,
  key_ref        TEXT,
  nonce_hex      TEXT,
  ciphertext_b64 TEXT,
  captured_at    TIMESTAMPTZ,
  expires_at     TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor RECORD;
  v_cap public.admin_breakglass_captures_v2;
BEGIN
  SELECT * INTO v_actor
  FROM public.admin_v2_authenticated_session_gate(false);
  v_cap := public.admin_v2_breakglass_content_gate(
    p_capture_id,
    v_actor.actor_user_id,
    v_actor.actor_role,
    true
  );
  INSERT INTO public.admin_audit_events_v2 (actor_user_id, action, target_ref, result)
  VALUES (
    v_actor.actor_user_id,
    'breakglass.export',
    'breakglass_capture:sha256:' || encode(sha256(convert_to(v_cap.id::text, 'UTF8')), 'hex'),
    'success'
  );
  RETURN QUERY
  SELECT v_cap.cipher, v_cap.key_ref, v_cap.nonce_hex, v_cap.ciphertext_b64,
         v_cap.captured_at, v_cap.expires_at;
END;
$$;

CREATE FUNCTION public.admin_v2_breakglass_extend(p_capture_id UUID)
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor RECORD;
  v_cap   public.admin_breakglass_captures_v2;
  v_new   TIMESTAMPTZ;
  v_external_event_ref TEXT;
BEGIN
  SELECT * INTO v_actor
  FROM public.admin_v2_authenticated_session_gate(true);
  IF v_actor.actor_role <> 'owner' THEN
    RAISE EXCEPTION 'breakglass denied';
  END IF;

  SELECT * INTO v_cap
  FROM public.admin_breakglass_captures_v2 c
  WHERE c.id = p_capture_id
  FOR UPDATE;
  IF NOT FOUND OR v_cap.purged_at IS NOT NULL OR now() >= v_cap.expires_at THEN
    RAISE EXCEPTION 'breakglass capture expired';
  END IF;
  IF v_cap.extension_count >= 1 THEN
    RAISE EXCEPTION 'breakglass capture already extended';
  END IF;

  v_new := LEAST(
    v_cap.expires_at + INTERVAL '72 hours',
    v_cap.captured_at + INTERVAL '7 days'
  );
  UPDATE public.admin_breakglass_captures_v2 c
  SET expires_at = v_new, extension_count = 1
  WHERE c.id = p_capture_id;

  v_external_event_ref := 'breakglass_extend:sha256:' ||
    encode(sha256(convert_to(v_cap.id::text, 'UTF8')), 'hex');
  INSERT INTO public.admin_notification_outbox_v2
    (template, delivery_class, reason_code, incident_id, external_event_ref, user_ref)
  VALUES (
    'red',
    'immediate',
    'breakglass_extended',
    NULL,
    v_external_event_ref,
    NULL
  )
  ON CONFLICT (external_event_ref) DO UPDATE
    SET occurrence_count = public.admin_notification_outbox_v2.occurrence_count + 1,
        last_seen_at = now();

  INSERT INTO public.admin_audit_events_v2 (actor_user_id, action, target_ref, result)
  VALUES (
    v_actor.actor_user_id,
    'breakglass.extend',
    'breakglass_capture:sha256:' || encode(sha256(convert_to(v_cap.id::text, 'UTF8')), 'hex'),
    'success'
  );
  RETURN v_new;
END;
$$;

CREATE FUNCTION public.admin_v2_breakglass_close(p_grant_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor RECORD;
  v_id UUID;
BEGIN
  SELECT * INTO v_actor
  FROM public.admin_v2_authenticated_session_gate(false);
  IF v_actor.actor_role <> 'owner' THEN
    RAISE EXCEPTION 'breakglass denied';
  END IF;
  UPDATE public.admin_breakglass_grants_v2 g
  SET closed_at = now(), closed_by = v_actor.actor_user_id
  WHERE g.id = p_grant_id
    AND g.closed_at IS NULL
  RETURNING g.id INTO v_id;
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'breakglass grant not open';
  END IF;
  INSERT INTO public.admin_audit_events_v2 (actor_user_id, action, target_ref, result)
  VALUES (
    v_actor.actor_user_id,
    'breakglass.close',
    'breakglass_grant:sha256:' || encode(sha256(convert_to(v_id::text, 'UTF8')), 'hex'),
    'success'
  );
END;
$$;

CREATE FUNCTION public.admin_v2_breakglass_purge_expired()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor RECORD;
  v_cap   RECORD;
  v_n     INTEGER := 0;
BEGIN
  SELECT * INTO v_actor
  FROM public.admin_v2_authenticated_session_gate(false);
  IF v_actor.actor_role <> 'owner' THEN
    RAISE EXCEPTION 'breakglass denied';
  END IF;
  FOR v_cap IN
    SELECT c.id
    FROM public.admin_breakglass_captures_v2 c
    WHERE c.purged_at IS NULL
      AND c.expires_at <= now()
    FOR UPDATE
  LOOP
    UPDATE public.admin_breakglass_captures_v2 c
    SET ciphertext_b64 = NULL, purged_at = now()
    WHERE c.id = v_cap.id;
    INSERT INTO public.admin_audit_events_v2 (actor_user_id, action, target_ref, result)
    VALUES (
      v_actor.actor_user_id,
      'breakglass.purge',
      'breakglass_capture:sha256:' || encode(sha256(convert_to(v_cap.id::text, 'UTF8')), 'hex'),
      'success'
    );
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;

-- ============================================================
-- audit allowlist 的唯一既有物件變更。
ALTER TABLE public.admin_audit_events_v2 DROP CONSTRAINT admin_audit_events_v2_action_check;
ALTER TABLE public.admin_audit_events_v2 ADD CONSTRAINT admin_audit_events_v2_action_check
  CHECK (action IN ('admin.login', 'admin.logout', 'admin.session.revoke', 'admin.account.activate', 'admin.account.deactivate', 'breakglass.activate', 'breakglass.capture', 'breakglass.view', 'breakglass.export', 'breakglass.extend', 'breakglass.close', 'breakglass.purge'));

-- 顯式 cutover 關閉時，active B1/V2 admin 的 raw ai_logs access 不受影響。
-- 切換開啟後，active V2 admin 只能透過上方 metadata-only RPC 讀取 errors。
-- 操作順序固定：先部署 route/RPC → 再開 DB cutover；回退先關 DB cutover →
-- 最後關 ADMIN_V2 route，不能把兩個 flag 當成可任意切換的獨立開關。
CREATE POLICY admin_ai_logs_block_raw_for_v2_admins ON public.ai_logs
  AS RESTRICTIVE
  FOR SELECT
  TO authenticated
  USING (
    NOT (
      public.admin_v2_ai_logs_cutover_enabled()
      AND public.admin_v2_is_active_admin()
    )
  );

-- ============================================================
-- deny-by-default RLS/ACL。
ALTER TABLE public.admin_notification_outbox_v2     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_notification_deliveries_v2 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_feedback_inbox_v2          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_breakglass_grants_v2       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_breakglass_request_occurrences_v2 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_breakglass_captures_v2     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_v2_settings                ENABLE ROW LEVEL SECURITY;

REVOKE ALL PRIVILEGES ON TABLE public.admin_notification_outbox_v2     FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON TABLE public.admin_notification_deliveries_v2 FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON TABLE public.admin_feedback_inbox_v2          FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON TABLE public.admin_breakglass_grants_v2       FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON TABLE public.admin_breakglass_request_occurrences_v2 FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON TABLE public.admin_breakglass_captures_v2     FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON TABLE public.admin_v2_settings                FROM PUBLIC, anon, authenticated, service_role;

-- 內容表與 setting 沒有常駐 grant。service_role 只能讀 worker 所需 outbox/
-- inbox metadata，不能執行任意 enqueue 或讀 break-glass envelope。
GRANT SELECT ON TABLE public.admin_notification_outbox_v2     TO service_role;
GRANT SELECT ON TABLE public.admin_notification_deliveries_v2 TO service_role;
GRANT SELECT ON TABLE public.admin_feedback_inbox_v2          TO service_role;
GRANT SELECT ON TABLE public.admin_breakglass_grants_v2       TO service_role;

-- 所有函式先移除預設 PUBLIC execute；只有固定 operation RPC 可從外部呼叫。
REVOKE ALL ON FUNCTION public.admin_v2_is_active_admin() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_v2_ai_logs_cutover_enabled() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_v2_list_error_metadata() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_v2_submit_feedback(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_v2_authenticated_session_gate(BOOLEAN) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_v2_breakglass_activate(UUID, TEXT, TEXT, UUID) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_v2_record_breakglass_runtime_occurrence(TEXT, UUID, TEXT) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_v2_breakglass_capture_trusted_runtime_request(UUID, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_v2_breakglass_content_gate(UUID, UUID, TEXT, BOOLEAN) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_v2_breakglass_view(UUID) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_v2_breakglass_export(UUID) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_v2_breakglass_extend(UUID) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_v2_breakglass_close(UUID) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_v2_breakglass_purge_expired() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.admin_v2_is_active_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_v2_ai_logs_cutover_enabled() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_v2_list_error_metadata() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_v2_submit_feedback(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_v2_breakglass_activate(UUID, TEXT, TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_v2_record_breakglass_runtime_occurrence(TEXT, UUID, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_v2_breakglass_capture_trusted_runtime_request(UUID, TEXT, TEXT, TEXT, TEXT, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_v2_breakglass_view(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_v2_breakglass_export(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_v2_breakglass_extend(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_v2_breakglass_close(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_v2_breakglass_purge_expired() TO authenticated;
