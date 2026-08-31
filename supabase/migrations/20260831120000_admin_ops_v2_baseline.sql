-- 後台營運第二版（B0）相容性基線：純 additive，不 drop、不 rename、不改既有結構。
-- 本檔僅建立空的營運契約表與 view，未接任何讀寫路徑；ADMIN_V2 旗標關閉時
-- 現有後台行為與可見輸出完全不變。時間一律存 timestamptz（UTC），
-- fresh/stale/unknown 與 Asia/Taipei 日界判斷在 admin-dashboard/lib/operations/ 做。
--
-- baseline 只能新建：CREATE 一律不做條件式建立、view 也不做取代式建立，
-- 同名物件代表環境漂移，必須在任何 ALTER/REVOKE/GRANT 之前直接失敗
-- （migration 整包在同一交易內 rollback）。所有 CREATE 因此集中在最前面。

-- 來源心跳檢查點：freshness 的唯一真相來源。沒有列＝unknown，不得冒充 healthy。
CREATE TABLE public.admin_ops_source_checkpoints (
  source       TEXT PRIMARY KEY,
  last_seen_at TIMESTAMPTZ,
  note         TEXT,
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.admin_ops_incidents (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source      TEXT NOT NULL,
  severity    TEXT NOT NULL CHECK (severity IN ('info', 'warning', 'critical')),
  status      TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'resolved')),
  title       TEXT NOT NULL,
  -- 匿名結構化摘要；禁止寫入 email、user id、對話原文或完整 payload。
  detail      JSONB NOT NULL DEFAULT '{}'::jsonb,
  opened_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX admin_ops_incidents_status_opened_at_idx
  ON public.admin_ops_incidents (status, opened_at DESC);

CREATE TABLE public.admin_ops_decision_cards (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  incident_id    UUID REFERENCES public.admin_ops_incidents (id),
  kind           TEXT NOT NULL,
  summary        TEXT NOT NULL,
  options        JSONB NOT NULL DEFAULT '[]'::jsonb,
  decided_option TEXT,
  decided_at     TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- security_invoker：view 用呼叫者權限跑，不繞過基表 RLS。
CREATE VIEW public.admin_ops_source_freshness
  WITH (security_invoker = true) AS
SELECT source, last_seen_at, updated_at
FROM public.admin_ops_source_checkpoints;

-- 不擴大存取權限：RLS 開啟且不建任何 policy（deny by default）。
ALTER TABLE public.admin_ops_source_checkpoints ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_ops_incidents          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_ops_decision_cards     ENABLE ROW LEVEL SECURITY;

-- 先把三張表與 view 的權限收光（連 service_role 一起收），
-- 避免 PUBLIC／Supabase 預設 ACL 或可更新 view 留下 DELETE、TRUNCATE 等多餘權限。
REVOKE ALL PRIVILEGES ON TABLE public.admin_ops_source_checkpoints FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON TABLE public.admin_ops_incidents          FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON TABLE public.admin_ops_decision_cards     FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON TABLE public.admin_ops_source_freshness   FROM PUBLIC, anon, authenticated, service_role;

-- 再只補 service_role 最小權限：table 僅 SELECT, INSERT, UPDATE；view 僅 SELECT。
GRANT SELECT, INSERT, UPDATE ON TABLE public.admin_ops_source_checkpoints TO service_role;
GRANT SELECT, INSERT, UPDATE ON TABLE public.admin_ops_incidents          TO service_role;
GRANT SELECT, INSERT, UPDATE ON TABLE public.admin_ops_decision_cards     TO service_role;
GRANT SELECT ON TABLE public.admin_ops_source_freshness TO service_role;
