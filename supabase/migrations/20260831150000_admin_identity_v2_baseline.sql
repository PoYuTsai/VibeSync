-- 後台 B1 管理員身分、安全與稽核基線：純 additive，不 drop、不 rename、不改既有結構。
-- 新版授權真相是 Supabase Auth user_id（不再以 email 判權）；ADMIN_V2 旗標關閉時
-- 這些物件不接任何讀寫路徑，現有後台行為與可見輸出完全不變。
-- 不 seed 任何真實 user UUID、憑證或秘密；正式帳號綁定留待啟用批次另行處理。
--
-- 守則沿用 B0：CREATE 一律不做條件式建立（同名物件＝環境漂移，整包交易 rollback）；
-- 先把權限收光（含 service_role），再補最小 grant；SECURITY DEFINER 一律固定 search_path。

-- 管理員帳號：user_id 為唯一真相，PRIMARY KEY 保證一人一帳號（不可共用）。
-- session_version 供整批撤銷：版本一加，舊 session 全數失效。
CREATE TABLE public.admin_accounts_v2 (
  user_id         UUID PRIMARY KEY,
  role            TEXT NOT NULL CHECK (role IN ('owner', 'founder_admin')),
  is_active       BOOLEAN NOT NULL DEFAULT true,
  session_version INTEGER NOT NULL DEFAULT 1 CHECK (session_version >= 1),
  disabled_at     TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 管理員 session 契約：以 Supabase JWT 的 session_id 為鍵。
-- created_at＝絕對期限錨點（12h）、last_seen_at＝idle 錨點（30m）、
-- last_reauth_at＝敏感操作 reauth 錨點、session_version＝建立當下的帳號版本快照。
-- 逾時判斷由 admin-dashboard/lib/operations/admin-gate.ts 單一契約執行。
CREATE TABLE public.admin_sessions_v2 (
  session_id      UUID PRIMARY KEY,
  user_id         UUID NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_reauth_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  session_version INTEGER NOT NULL,
  revoked_at      TIMESTAMPTZ
);

CREATE INDEX admin_sessions_v2_user_id_idx ON public.admin_sessions_v2 (user_id);

-- Append-only audit 基線：欄位即 allowlist，只有 actor/action/target_ref/reason/
-- result/approver/request/time。CHECK 直接拒絕 email（@）、JWT 樣式（eyJ）與超長字串，
-- 原文、PII、secret、完整 payload 在 schema 層就進不來。
CREATE TABLE public.admin_audit_events_v2 (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_user_id    UUID NOT NULL,
  action           TEXT NOT NULL CHECK (action ~ '^[a-z0-9][a-z0-9_.:-]{0,99}$'),
  target_ref       TEXT CHECK (char_length(target_ref) <= 200 AND target_ref !~ '[@\n]' AND position('eyJ' in target_ref) = 0),
  reason           TEXT CHECK (char_length(reason) <= 500 AND reason !~ '[@\n]' AND position('eyJ' in reason) = 0),
  result           TEXT NOT NULL CHECK (result IN ('success', 'denied', 'failure')),
  approver_user_id UUID,
  request_id       TEXT CHECK (request_id ~ '^[A-Za-z0-9._:-]{1,100}$'),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX admin_audit_events_v2_actor_created_at_idx
  ON public.admin_audit_events_v2 (actor_user_id, created_at DESC);

-- Append-only 由 trigger 強制：UPDATE/DELETE/TRUNCATE 一律例外，連 service_role 也擋。
CREATE FUNCTION public.admin_audit_events_v2_block_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION 'admin_audit_events_v2 is append-only';
END;
$$;

CREATE TRIGGER admin_audit_events_v2_append_only
  BEFORE UPDATE OR DELETE ON public.admin_audit_events_v2
  FOR EACH ROW EXECUTE FUNCTION public.admin_audit_events_v2_block_mutation();

CREATE TRIGGER admin_audit_events_v2_no_truncate
  BEFORE TRUNCATE ON public.admin_audit_events_v2
  FOR EACH STATEMENT EXECUTE FUNCTION public.admin_audit_events_v2_block_mutation();

-- 讀取＋觸碰 session：呼叫者只能看到／碰到自己的帳號與當前 session。
-- 非管理員回 0 列（不 raise，避免用錯誤訊息洩漏身分判斷）；停用帳號不建新 session 列。
-- 先回傳「觸碰前」的 last_seen_at 當 idle 錨點，再更新 last_seen_at——
-- idle 是否逾時由 TS 契約用 prev_seen_at 判斷，逾時者會被 revoke，不會因觸碰復活。
CREATE FUNCTION public.admin_v2_touch_session()
RETURNS TABLE (
  role                    TEXT,
  is_active               BOOLEAN,
  account_session_version INTEGER,
  session_created_at      TIMESTAMPTZ,
  prev_seen_at            TIMESTAMPTZ,
  last_reauth_at          TIMESTAMPTZ,
  session_version         INTEGER,
  revoked_at              TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid     UUID := auth.uid();
  v_sid     UUID;
  v_account public.admin_accounts_v2;
  v_session public.admin_sessions_v2;
BEGIN
  IF v_uid IS NULL THEN
    RETURN;
  END IF;
  v_sid := NULLIF(auth.jwt() ->> 'session_id', '')::uuid;
  IF v_sid IS NULL THEN
    RETURN;
  END IF;
  SELECT * INTO v_account FROM public.admin_accounts_v2 a WHERE a.user_id = v_uid;
  IF NOT FOUND THEN
    RETURN;
  END IF;
  SELECT * INTO v_session
    FROM public.admin_sessions_v2 s
    WHERE s.session_id = v_sid AND s.user_id = v_uid;
  IF NOT FOUND THEN
    IF NOT v_account.is_active THEN
      RETURN QUERY SELECT v_account.role, v_account.is_active, v_account.session_version,
        NULL::timestamptz, NULL::timestamptz, NULL::timestamptz, NULL::integer, NULL::timestamptz;
      RETURN;
    END IF;
    INSERT INTO public.admin_sessions_v2 (session_id, user_id, session_version)
      VALUES (v_sid, v_uid, v_account.session_version)
      RETURNING * INTO v_session;
  END IF;
  RETURN QUERY SELECT v_account.role, v_account.is_active, v_account.session_version,
    v_session.created_at, v_session.last_seen_at, v_session.last_reauth_at,
    v_session.session_version, v_session.revoked_at;
  UPDATE public.admin_sessions_v2 s SET last_seen_at = now() WHERE s.session_id = v_sid;
END;
$$;

-- 撤銷呼叫者自己的當前 session（登出、gate 判定逾時／版本失效時使用）。
CREATE FUNCTION public.admin_v2_revoke_my_session()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  UPDATE public.admin_sessions_v2 s
    SET revoked_at = COALESCE(s.revoked_at, now())
    WHERE s.user_id = auth.uid()
      AND s.session_id = NULLIF(auth.jwt() ->> 'session_id', '')::uuid;
$$;

-- Audit 寫入口：只有啟用中的管理員能寫，欄位固定、CHECK 把關內容；不可更新、不可刪除。
CREATE FUNCTION public.admin_v2_append_audit(
  p_action     TEXT,
  p_result     TEXT,
  p_target_ref TEXT DEFAULT NULL,
  p_reason     TEXT DEFAULT NULL,
  p_approver   UUID DEFAULT NULL,
  p_request_id TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_id  UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authorized';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_accounts_v2 a WHERE a.user_id = v_uid AND a.is_active
  ) THEN
    RAISE EXCEPTION 'not authorized';
  END IF;
  INSERT INTO public.admin_audit_events_v2
      (actor_user_id, action, target_ref, reason, result, approver_user_id, request_id)
    VALUES (v_uid, p_action, p_target_ref, p_reason, p_result, p_approver, p_request_id)
    RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- 不擴大存取權限：RLS 開啟且不建任何 policy（deny by default）。
ALTER TABLE public.admin_accounts_v2     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_sessions_v2     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_audit_events_v2 ENABLE ROW LEVEL SECURITY;

-- 先把表權限收光（連 service_role 一起收），避免預設 ACL 留下多餘權限。
REVOKE ALL PRIVILEGES ON TABLE public.admin_accounts_v2     FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON TABLE public.admin_sessions_v2     FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON TABLE public.admin_audit_events_v2 FROM PUBLIC, anon, authenticated, service_role;

-- 再補最小權限：帳號管理與 session 撤銷之後由受控營運流程走 service_role；
-- audit 即使是 service_role 也只有 SELECT, INSERT（append-only）。任何 GRANT 不得含 DELETE/TRUNCATE。
GRANT SELECT, INSERT, UPDATE ON TABLE public.admin_accounts_v2 TO service_role;
GRANT SELECT, UPDATE ON TABLE public.admin_sessions_v2 TO service_role;
GRANT SELECT, INSERT ON TABLE public.admin_audit_events_v2 TO service_role;

-- 函式權限：先收光（CREATE FUNCTION 預設 grant EXECUTE 給 PUBLIC），再只開給 authenticated。
-- trigger 函式不開給任何角色（由表的 trigger 以擁有者身分執行）。
REVOKE ALL ON FUNCTION public.admin_audit_events_v2_block_mutation() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_v2_touch_session()     FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_v2_revoke_my_session() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_v2_append_audit(TEXT, TEXT, TEXT, TEXT, UUID, TEXT) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.admin_v2_touch_session()     TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_v2_revoke_my_session() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_v2_append_audit(TEXT, TEXT, TEXT, TEXT, UUID, TEXT) TO authenticated;
