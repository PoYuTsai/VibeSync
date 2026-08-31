-- 後台 B2 隱私安全通知、回報與受控診斷底座：additive 為主，唯一的既有物件變更是
-- 擴充 admin_audit_events_v2 的 action enum CHECK（加入 breakglass.* 六個 action）。
-- ADMIN_V2 旗標關閉時這些物件不接任何讀寫路徑；submit-feedback 與後台 legacy
-- 可見行為完全不變。本批不投遞 Discord/email、不排程、不啟用正式環境。
--
-- 守則沿用 B0/B1：CREATE 一律不做條件式建立（同名物件＝環境漂移，整包交易
-- rollback）；先把權限收光（含 service_role），再補最小 grant；SECURITY DEFINER
-- 一律固定 search_path；deny-by-default RLS。
--
-- 隱私規則（欄位即 allowlist）：notification／feedback／delivery／audit 全部
-- 只收固定 enum、不可逆 sha256 參照與受 CHECK 約束的短 metadata；email、對話
-- 片段、Prompt、截圖、AI 原文、secret、Sentry raw 或任意自由文字 payload 在
-- schema 層就進不來。break-glass 內容只收 authenticated-encryption envelope 的
-- ciphertext；plaintext 與金鑰不進 DB（key_ref 只是外部金鑰的參照名）。

-- ============================================================
-- 通知 outbox：durable、可去重（dedupe_key UNIQUE）、可重試（重試撞 UNIQUE 只
-- 更新 occurrence 計數，不會重複建立外部事件）。red＝立即通知、yellow＝09:00
-- brief（15 分鐘持續／3 次重複的升級門檻是 B4 worker 的固定契約常數，不是
-- 每列資料）。沒有任何自由文字欄位。
CREATE TABLE public.admin_notification_outbox_v2 (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template         TEXT NOT NULL CHECK (template IN ('red', 'yellow')),
  delivery_class   TEXT NOT NULL CHECK (delivery_class IN ('immediate', 'daily_brief')),
  reason_code      TEXT NOT NULL CHECK (reason_code IN ('feedback_received', 'breakglass_extended', 'edge_error_spike', 'quota_exhausted_spike', 'payment_webhook_failure', 'cost_spike')),
  incident_id      UUID REFERENCES public.admin_ops_incidents (id),
  user_ref         TEXT CHECK (user_ref ~ '^user:sha256:[0-9a-f]{64}$'),
  dedupe_key       TEXT NOT NULL UNIQUE CHECK (dedupe_key ~ '^[a-z][a-z0-9_.]{0,63}:sha256:[0-9a-f]{64}$'),
  status           TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'failed')),
  occurrence_count INTEGER NOT NULL DEFAULT 1 CHECK (occurrence_count >= 1),
  first_seen_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK ((template = 'red' AND delivery_class = 'immediate')
      OR (template = 'yellow' AND delivery_class = 'daily_brief'))
);

-- 投遞嘗試 metadata：只建模 Discord 正常通道與 Discord 失敗後的窄 email
-- fallback（順序契約由 B4 worker 執行）。無收件位址、無 URL、無自由文字；
-- error_code 只收短 snake_case 代碼。UNIQUE 讓重試不重複記帳。
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

-- Metadata-only feedback inbox：只有 category、短描述、request ref 與 safe
-- metadata。user_ref 是不可逆 sha256 參照；summary 上限 200 字且結構上拒
-- email（@）與 JWT/base64-JSON（eyJ）樣式；category enum 與 submit-feedback
-- 的 VALID_CATEGORIES 逐字同源（測試比對）。request_ref UNIQUE＝重試冪等。
CREATE TABLE public.admin_feedback_inbox_v2 (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_ref    TEXT NOT NULL CHECK (user_ref ~ '^user:sha256:[0-9a-f]{64}$'),
  request_ref TEXT NOT NULL UNIQUE CHECK (request_ref ~ '^request:sha256:[0-9a-f]{64}$'),
  rating      TEXT NOT NULL CHECK (rating IN ('positive', 'negative')),
  category    TEXT CHECK (category IN ('too_direct', 'too_long', 'unnatural', 'wrong_style', 'other')),
  summary     TEXT CHECK (char_length(summary) <= 200 AND summary NOT LIKE '%@%' AND summary NOT LIKE '%eyJ%'),
  user_tier   TEXT CHECK (user_tier ~ '^[a-z][a-z0-9_]{0,49}$'),
  model_used  TEXT CHECK (model_used ~ '^[A-Za-z0-9][A-Za-z0-9_.:/-]{0,119}$'),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Break-glass grant：只有 owner 能啟用（RPC 驗證），範圍固定一位 user＋一項
-- function；初始有效期 30 分鐘（CHECK 封頂）或 3 個「啟用後的未來請求」
-- （captures_max 固定 3，計數在 record_capture 以單一原子 UPDATE 遞增，併發
-- 也不會超過 3）。founder_admin 只能檢視被明確指派（assigned_viewer_user_id）
-- 的單一事件。reason enum 與 audit reason enum 同源。
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

-- Break-glass capture receipt＋authenticated-encryption envelope。內容 72 小時
-- 自動到期（record_capture 寫入 captured_at + 72h），extend 最多一次、總生命
-- 週期 CHECK 封頂 7 天。purge 後 ciphertext/nonce 必為 NULL（CHECK 互斥保證
-- 「未 purge 必有內容、已 purge 必無內容」）。ciphertext 只收 base64 且拒
-- 'eyJ' 開頭——那是 base64(JSON) 明文的特徵；真隨機密文撞上的機率約 1/26 萬，
-- 撞上時整筆 RPC rollback（capture 名額也退回），呼叫端換 nonce 重試即可。
CREATE TABLE public.admin_breakglass_captures_v2 (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  grant_id         UUID NOT NULL REFERENCES public.admin_breakglass_grants_v2 (id),
  request_ref      TEXT NOT NULL CHECK (request_ref ~ '^request:sha256:[0-9a-f]{64}$'),
  cipher           TEXT NOT NULL CHECK (cipher IN ('aes-256-gcm')),
  key_ref          TEXT NOT NULL CHECK (key_ref ~ '^key:[a-z0-9_.-]{1,64}$'),
  nonce_hex        TEXT CHECK (nonce_hex ~ '^[0-9a-f]{24}$'),
  ciphertext_b64   TEXT CHECK (ciphertext_b64 ~ '^[A-Za-z0-9+/]+={0,2}$' AND ciphertext_b64 !~ '^eyJ'),
  plaintext_sha256 TEXT NOT NULL CHECK (plaintext_sha256 ~ '^[0-9a-f]{64}$'),
  captured_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at       TIMESTAMPTZ NOT NULL,
  extension_count  INTEGER NOT NULL DEFAULT 0 CHECK (extension_count IN (0, 1)),
  purged_at        TIMESTAMPTZ,
  CHECK (expires_at > captured_at AND expires_at <= captured_at + INTERVAL '7 days'),
  CHECK ((purged_at IS NULL AND ciphertext_b64 IS NOT NULL AND nonce_hex IS NOT NULL)
      OR (purged_at IS NOT NULL AND ciphertext_b64 IS NULL AND nonce_hex IS NULL))
);

-- ============================================================
-- V2 管理員身分判定（供 RLS policy 與 metadata view 使用）。
-- SECURITY DEFINER：admin_accounts_v2 是 deny-by-default，policy 的子查詢用
-- 呼叫者權限會恆回 0 列而失效，必須經 definer 函式查。只回「呼叫者自己是否
-- 為啟用中 V2 管理員」的布林，無其他資訊可洩。
CREATE FUNCTION public.admin_v2_is_active_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_accounts_v2 a
    WHERE a.user_id = auth.uid() AND a.is_active
  );
$$;

-- ai_logs 的 metadata-only view：不含 request_body／response_body／
-- error_message（raw 內容可能夾帶對話原文或 Sentry raw）。這裡刻意用
-- 「owner 權限」的 view（非 security_invoker）＋security_barrier：owner 不受
-- 下方 restrictive policy 影響，view 自帶的 admin_v2_is_active_admin() 守門
-- 是唯一入口條件——啟用中的 V2 管理員只能從這裡拿 metadata。
CREATE VIEW public.admin_ai_logs_meta_v2
  WITH (security_barrier = true) AS
SELECT id, user_id, model, request_type, input_tokens, output_tokens, cost_usd,
       latency_ms, status, error_code, fallback_used, retry_count, created_at
FROM public.ai_logs
WHERE public.admin_v2_is_active_admin();

-- ============================================================
-- 通知 enqueue：operation-specific、無自由文字參數；欄位值由表上 CHECK 驗證。
-- 冪等／去重：同 dedupe_key 重送只更新 occurrence 計數與 last_seen_at，不新增
-- 列、不改 status——已送出的外部事件不會被重複建立。
CREATE FUNCTION public.admin_v2_enqueue_notification(
  p_template    TEXT,
  p_reason_code TEXT,
  p_dedupe_key  TEXT,
  p_incident_id UUID DEFAULT NULL,
  p_user_ref    TEXT DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO public.admin_notification_outbox_v2
    (template, delivery_class, reason_code, dedupe_key, incident_id, user_ref)
  VALUES (
    p_template,
    CASE WHEN p_template = 'red' THEN 'immediate' ELSE 'daily_brief' END,
    p_reason_code, p_dedupe_key, p_incident_id, p_user_ref
  )
  ON CONFLICT (dedupe_key) DO UPDATE
    SET occurrence_count = public.admin_notification_outbox_v2.occurrence_count + 1,
        last_seen_at = now()
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- V2 feedback 寫入口：metadata-only、request_ref 冪等（重試不重複入列、不重複
-- 通知）。inbox 與 outbox 同一交易，失敗共同 rollback。
CREATE FUNCTION public.admin_v2_submit_feedback(
  p_user_ref    TEXT,
  p_request_ref TEXT,
  p_rating      TEXT,
  p_category    TEXT DEFAULT NULL,
  p_summary     TEXT DEFAULT NULL,
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
BEGIN
  INSERT INTO public.admin_feedback_inbox_v2
    (user_ref, request_ref, rating, category, summary, user_tier, model_used)
  VALUES (p_user_ref, p_request_ref, p_rating, p_category, p_summary, p_user_tier, p_model_used)
  ON CONFLICT (request_ref) DO NOTHING
  RETURNING id INTO v_id;
  IF v_id IS NOT NULL THEN
    PERFORM public.admin_v2_enqueue_notification(
      'yellow', 'feedback_received',
      'feedback:sha256:' || right(p_request_ref, 64), NULL, p_user_ref);
  END IF;
END;
$$;

-- ============================================================
-- Break-glass 啟用：只有啟用中的 owner＋近期 reauth（10 分鐘，與 admin-gate.ts
-- 的 ADMIN_REAUTH_FRESH_MS 同值）才可啟用；範圍固定一位 user＋一項 function；
-- 有效期 now()+30 分鐘。audit 同一交易寫入（過表上 provenance 守門）。
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
  v_uid     UUID := auth.uid();
  v_sid     UUID;
  v_session public.admin_sessions_v2;
  v_id      UUID;
BEGIN
  IF v_uid IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.admin_accounts_v2 a
    WHERE a.user_id = v_uid AND a.is_active AND a.role = 'owner'
  ) THEN
    RAISE EXCEPTION 'breakglass denied';
  END IF;
  v_sid := NULLIF(auth.jwt() ->> 'session_id', '')::uuid;
  IF v_sid IS NULL THEN
    RAISE EXCEPTION 'breakglass denied';
  END IF;
  SELECT * INTO v_session
    FROM public.admin_sessions_v2 s
    WHERE s.session_id = v_sid AND s.user_id = v_uid AND s.revoked_at IS NULL;
  -- 未來時間戳（時鐘漂移或偽造）也不算新鮮，與 TS isReauthFresh 同規則。
  IF NOT FOUND
     OR v_session.last_reauth_at < now() - INTERVAL '10 minutes'
     OR v_session.last_reauth_at > now() THEN
    RAISE EXCEPTION 'breakglass reauth required';
  END IF;
  IF p_assigned_viewer_user_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.admin_accounts_v2 a
    WHERE a.user_id = p_assigned_viewer_user_id AND a.is_active
  ) THEN
    RAISE EXCEPTION 'breakglass assigned viewer must be an active admin';
  END IF;
  INSERT INTO public.admin_breakglass_grants_v2
    (activated_by, scope_user_id, scope_function, reason, assigned_viewer_user_id, expires_at)
  VALUES (v_uid, p_scope_user_id, p_scope_function, p_reason, p_assigned_viewer_user_id,
          now() + INTERVAL '30 minutes')
  RETURNING id INTO v_id;
  INSERT INTO public.admin_audit_events_v2 (actor_user_id, action, target_ref, reason, result)
  VALUES (v_uid, 'breakglass.activate',
          'breakglass_grant:sha256:' || encode(sha256(convert_to(v_id::text, 'UTF8')), 'hex'),
          p_reason, 'success');
  RETURN v_id;
END;
$$;

-- Capture 記錄（server-only）：只收「現在發生」的未來請求 envelope，沒有任何
-- 回撈歷史資料的入口。名額用單一原子 UPDATE 遞增——row lock 讓併發 capture
-- 串行化，30 分鐘窗口與 3 次上限先到者為準，超過就整筆拒絕。內容 72 小時後
-- 自動到期。capture 列本身即 receipt；service 無管理員 actor，不寫 audit
-- （audit 只收 activation/view/export/extension/close/purge 六種管理員操作）。
CREATE FUNCTION public.admin_v2_breakglass_record_capture(
  p_grant_id         UUID,
  p_request_ref      TEXT,
  p_cipher           TEXT,
  p_key_ref          TEXT,
  p_nonce_hex        TEXT,
  p_ciphertext_b64   TEXT,
  p_plaintext_sha256 TEXT
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_gid UUID;
  v_id  UUID;
BEGIN
  UPDATE public.admin_breakglass_grants_v2 g
    SET captures_used = g.captures_used + 1
    WHERE g.id = p_grant_id
      AND g.closed_at IS NULL
      AND now() < g.expires_at
      AND g.captures_used < g.captures_max
    RETURNING g.id INTO v_gid;
  IF v_gid IS NULL THEN
    RAISE EXCEPTION 'breakglass grant not capturable';
  END IF;
  INSERT INTO public.admin_breakglass_captures_v2
    (grant_id, request_ref, cipher, key_ref, nonce_hex, ciphertext_b64, plaintext_sha256, expires_at)
  VALUES (p_grant_id, p_request_ref, p_cipher, p_key_ref, p_nonce_hex, p_ciphertext_b64,
          p_plaintext_sha256, now() + INTERVAL '72 hours')
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- 內容存取共用守門：owner 可看；founder_admin 只能看被明確指派的 grant 的
-- capture；到期或已 purge 一律拒絕。回傳 capture 列供 view/export 使用。
CREATE FUNCTION public.admin_v2_breakglass_content_gate(
  p_capture_id UUID,
  p_owner_only BOOLEAN
)
RETURNS public.admin_breakglass_captures_v2
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid   UUID := auth.uid();
  v_role  TEXT;
  v_cap   public.admin_breakglass_captures_v2;
  v_grant public.admin_breakglass_grants_v2;
BEGIN
  SELECT a.role INTO v_role
    FROM public.admin_accounts_v2 a
    WHERE a.user_id = v_uid AND a.is_active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'breakglass denied';
  END IF;
  SELECT * INTO v_cap FROM public.admin_breakglass_captures_v2 c WHERE c.id = p_capture_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'breakglass denied';
  END IF;
  SELECT * INTO v_grant FROM public.admin_breakglass_grants_v2 g WHERE g.id = v_cap.grant_id;
  IF v_role <> 'owner' THEN
    IF p_owner_only OR v_role <> 'founder_admin'
       OR v_grant.assigned_viewer_user_id IS DISTINCT FROM v_uid THEN
      RAISE EXCEPTION 'breakglass denied';
    END IF;
  END IF;
  IF v_cap.purged_at IS NOT NULL OR now() >= v_cap.expires_at THEN
    RAISE EXCEPTION 'breakglass capture expired';
  END IF;
  RETURN v_cap;
END;
$$;

-- 檢視：過 content gate（owner 或被指派的 founder_admin）＋同交易 audit。
CREATE FUNCTION public.admin_v2_breakglass_view(p_capture_id UUID)
RETURNS TABLE (
  cipher           TEXT,
  key_ref          TEXT,
  nonce_hex        TEXT,
  ciphertext_b64   TEXT,
  plaintext_sha256 TEXT,
  captured_at      TIMESTAMPTZ,
  expires_at       TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_cap public.admin_breakglass_captures_v2;
BEGIN
  v_cap := public.admin_v2_breakglass_content_gate(p_capture_id, false);
  INSERT INTO public.admin_audit_events_v2 (actor_user_id, action, target_ref, result)
  VALUES (auth.uid(), 'breakglass.view',
          'breakglass_capture:sha256:' || encode(sha256(convert_to(v_cap.id::text, 'UTF8')), 'hex'),
          'success');
  RETURN QUERY SELECT v_cap.cipher, v_cap.key_ref, v_cap.nonce_hex, v_cap.ciphertext_b64,
    v_cap.plaintext_sha256, v_cap.captured_at, v_cap.expires_at;
END;
$$;

-- 匯出：owner 專屬（founder_admin 只能檢視，不能匯出）＋同交易 audit。
CREATE FUNCTION public.admin_v2_breakglass_export(p_capture_id UUID)
RETURNS TABLE (
  cipher           TEXT,
  key_ref          TEXT,
  nonce_hex        TEXT,
  ciphertext_b64   TEXT,
  plaintext_sha256 TEXT,
  captured_at      TIMESTAMPTZ,
  expires_at       TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_cap public.admin_breakglass_captures_v2;
BEGIN
  v_cap := public.admin_v2_breakglass_content_gate(p_capture_id, true);
  INSERT INTO public.admin_audit_events_v2 (actor_user_id, action, target_ref, result)
  VALUES (auth.uid(), 'breakglass.export',
          'breakglass_capture:sha256:' || encode(sha256(convert_to(v_cap.id::text, 'UTF8')), 'hex'),
          'success');
  RETURN QUERY SELECT v_cap.cipher, v_cap.key_ref, v_cap.nonce_hex, v_cap.ciphertext_b64,
    v_cap.plaintext_sha256, v_cap.captured_at, v_cap.expires_at;
END;
$$;

-- 延長：owner＋重新驗證（與啟用同一 reauth 規則）；最多一次、總生命週期
-- 7 天封頂（LEAST＋表上 CHECK 雙保險）。同一交易寫 audit 並 enqueue red 通知
-- （「留下通知與 audit」）。
CREATE FUNCTION public.admin_v2_breakglass_extend(p_capture_id UUID)
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid     UUID := auth.uid();
  v_sid     UUID;
  v_session public.admin_sessions_v2;
  v_cap     public.admin_breakglass_captures_v2;
  v_new     TIMESTAMPTZ;
BEGIN
  IF v_uid IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.admin_accounts_v2 a
    WHERE a.user_id = v_uid AND a.is_active AND a.role = 'owner'
  ) THEN
    RAISE EXCEPTION 'breakglass denied';
  END IF;
  v_sid := NULLIF(auth.jwt() ->> 'session_id', '')::uuid;
  IF v_sid IS NULL THEN
    RAISE EXCEPTION 'breakglass denied';
  END IF;
  SELECT * INTO v_session
    FROM public.admin_sessions_v2 s
    WHERE s.session_id = v_sid AND s.user_id = v_uid AND s.revoked_at IS NULL;
  IF NOT FOUND
     OR v_session.last_reauth_at < now() - INTERVAL '10 minutes'
     OR v_session.last_reauth_at > now() THEN
    RAISE EXCEPTION 'breakglass reauth required';
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
  v_new := LEAST(v_cap.expires_at + INTERVAL '72 hours', v_cap.captured_at + INTERVAL '7 days');
  UPDATE public.admin_breakglass_captures_v2 c
    SET expires_at = v_new, extension_count = 1
    WHERE c.id = p_capture_id;
  PERFORM public.admin_v2_enqueue_notification(
    'red', 'breakglass_extended',
    'breakglass_extend:sha256:' || encode(sha256(convert_to(v_cap.id::text, 'UTF8')), 'hex'),
    NULL, NULL);
  INSERT INTO public.admin_audit_events_v2 (actor_user_id, action, target_ref, result)
  VALUES (v_uid, 'breakglass.extend',
          'breakglass_capture:sha256:' || encode(sha256(convert_to(v_cap.id::text, 'UTF8')), 'hex'),
          'success');
  RETURN v_new;
END;
$$;

-- 提前關閉 grant：owner 專屬（降風險操作，不要求 reauth）＋同交易 audit。
CREATE FUNCTION public.admin_v2_breakglass_close(p_grant_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_id  UUID;
BEGIN
  IF v_uid IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.admin_accounts_v2 a
    WHERE a.user_id = v_uid AND a.is_active AND a.role = 'owner'
  ) THEN
    RAISE EXCEPTION 'breakglass denied';
  END IF;
  UPDATE public.admin_breakglass_grants_v2 g
    SET closed_at = now(), closed_by = v_uid
    WHERE g.id = p_grant_id AND g.closed_at IS NULL
    RETURNING g.id INTO v_id;
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'breakglass grant not open';
  END IF;
  INSERT INTO public.admin_audit_events_v2 (actor_user_id, action, target_ref, result)
  VALUES (v_uid, 'breakglass.close',
          'breakglass_grant:sha256:' || encode(sha256(convert_to(v_id::text, 'UTF8')), 'hex'),
          'success');
END;
$$;

-- Purge 到期內容：owner 專屬；只清 ciphertext/nonce 並蓋 purged_at，receipt
-- 與 audit 保留。每筆 purge 都在同一交易寫 audit。本批只建立操作、不排程
-- （B4 才有 housekeeping）。
CREATE FUNCTION public.admin_v2_breakglass_purge_expired()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_cap RECORD;
  v_n   INTEGER := 0;
BEGIN
  IF v_uid IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.admin_accounts_v2 a
    WHERE a.user_id = v_uid AND a.is_active AND a.role = 'owner'
  ) THEN
    RAISE EXCEPTION 'breakglass denied';
  END IF;
  FOR v_cap IN
    SELECT c.id FROM public.admin_breakglass_captures_v2 c
    WHERE c.purged_at IS NULL AND c.expires_at <= now()
    FOR UPDATE
  LOOP
    UPDATE public.admin_breakglass_captures_v2 c
      SET ciphertext_b64 = NULL, nonce_hex = NULL, purged_at = now()
      WHERE c.id = v_cap.id;
    INSERT INTO public.admin_audit_events_v2 (actor_user_id, action, target_ref, result)
    VALUES (v_uid, 'breakglass.purge',
            'breakglass_capture:sha256:' || encode(sha256(convert_to(v_cap.id::text, 'UTF8')), 'hex'),
            'success');
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;

-- ============================================================
-- 唯一的既有物件變更：audit action enum 擴充 breakglass.* 六個 action。
-- 前五個與 B1（及 admin-gate.ts 的 AUDIT_ACTIONS）逐字同序；完整清單與
-- notify-contract.ts 的 AUDIT_ACTIONS_WITH_BREAKGLASS 逐字同源（測試比對）。
ALTER TABLE public.admin_audit_events_v2 DROP CONSTRAINT admin_audit_events_v2_action_check;
ALTER TABLE public.admin_audit_events_v2 ADD CONSTRAINT admin_audit_events_v2_action_check
  CHECK (action IN ('admin.login', 'admin.logout', 'admin.session.revoke', 'admin.account.activate', 'admin.account.deactivate', 'breakglass.activate', 'breakglass.view', 'breakglass.export', 'breakglass.extend', 'breakglass.close', 'breakglass.purge'));

-- ============================================================
-- 關閉 V2 管理員的 raw telemetry：restrictive policy 與既有 permissive policy
-- 取 AND——啟用中的 V2 管理員直接 SELECT ai_logs 一律 0 列（含 request_body／
-- response_body），只能改走上面的 metadata-only view。不在 admin_accounts_v2
-- 的 legacy 管理員完全不受影響（本批不 seed 任何帳號，pre-V2 行為不變；
-- service_role 寫入路徑 BYPASSRLS 也不受影響）。
CREATE POLICY admin_ai_logs_block_raw_for_v2_admins ON public.ai_logs
  AS RESTRICTIVE
  FOR SELECT
  TO authenticated
  USING (NOT public.admin_v2_is_active_admin());

-- ============================================================
-- 不擴大存取權限：RLS 開啟且不建任何 policy（deny by default）。
ALTER TABLE public.admin_notification_outbox_v2     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_notification_deliveries_v2 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_feedback_inbox_v2          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_breakglass_grants_v2       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_breakglass_captures_v2     ENABLE ROW LEVEL SECURITY;

-- 先把表與 view 權限收光（含 service_role），避免預設 ACL 留下多餘權限。
REVOKE ALL PRIVILEGES ON TABLE public.admin_notification_outbox_v2     FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON TABLE public.admin_notification_deliveries_v2 FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON TABLE public.admin_feedback_inbox_v2          FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON TABLE public.admin_breakglass_grants_v2       FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON TABLE public.admin_breakglass_captures_v2     FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON TABLE public.admin_ai_logs_meta_v2            FROM PUBLIC, anon, authenticated, service_role;

-- 再補最小權限：寫入一律走上面的 operation-specific SECURITY DEFINER RPC，
-- 沒有任何角色拿得到 INSERT/UPDATE/DELETE。service_role 只留營運讀取；
-- captures 表完全不 grant——內容存取只有 view/export RPC 這兩個受 audit 的
-- 入口，一般 agent（含 service_role）沒有常駐內容存取權。
GRANT SELECT ON TABLE public.admin_notification_outbox_v2     TO service_role;
GRANT SELECT ON TABLE public.admin_notification_deliveries_v2 TO service_role;
GRANT SELECT ON TABLE public.admin_feedback_inbox_v2          TO service_role;
GRANT SELECT ON TABLE public.admin_breakglass_grants_v2       TO service_role;
GRANT SELECT ON TABLE public.admin_ai_logs_meta_v2 TO authenticated;

-- 函式權限：先收光（CREATE FUNCTION 預設 grant EXECUTE 給 PUBLIC），再補最小
-- 執行權。server-only 的三個 RPC 開給 service_role（B1 預告的 operation-specific
-- 受控函式）；break-glass 管理員操作開給 authenticated（函式內自驗 owner／
-- founder_admin）；content gate 是內部共用件，不開給任何角色。
REVOKE ALL ON FUNCTION public.admin_v2_is_active_admin()          FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_v2_enqueue_notification(TEXT, TEXT, TEXT, UUID, TEXT) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_v2_submit_feedback(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_v2_breakglass_activate(UUID, TEXT, TEXT, UUID) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_v2_breakglass_record_capture(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_v2_breakglass_content_gate(UUID, BOOLEAN) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_v2_breakglass_view(UUID)      FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_v2_breakglass_export(UUID)    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_v2_breakglass_extend(UUID)    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_v2_breakglass_close(UUID)     FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_v2_breakglass_purge_expired() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.admin_v2_is_active_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_v2_enqueue_notification(TEXT, TEXT, TEXT, UUID, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_v2_submit_feedback(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_v2_breakglass_record_capture(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_v2_breakglass_activate(UUID, TEXT, TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_v2_breakglass_view(UUID)      TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_v2_breakglass_export(UUID)    TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_v2_breakglass_extend(UUID)    TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_v2_breakglass_close(UUID)     TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_v2_breakglass_purge_expired() TO authenticated;
