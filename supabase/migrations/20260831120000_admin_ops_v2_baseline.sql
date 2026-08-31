-- 後台營運第二版（B0）相容性基線：純 additive，不 drop、不 rename、不改既有結構。
-- 本檔僅建立空的營運契約表與 view，未接任何讀寫路徑；ADMIN_V2 旗標關閉時
-- 現有後台行為與可見輸出完全不變。時間一律存 timestamptz（UTC），
-- fresh/stale/unknown 與 Asia/Taipei 日界判斷在 admin-dashboard/lib/operations/ 做。

-- 來源心跳檢查點：freshness 的唯一真相來源。沒有列＝unknown，不得冒充 healthy。
CREATE TABLE IF NOT EXISTS public.admin_ops_source_checkpoints (
  source       TEXT PRIMARY KEY,
  last_seen_at TIMESTAMPTZ,
  note         TEXT,
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.admin_ops_incidents (
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

CREATE INDEX IF NOT EXISTS admin_ops_incidents_status_opened_at_idx
  ON public.admin_ops_incidents (status, opened_at DESC);

CREATE TABLE IF NOT EXISTS public.admin_ops_decision_cards (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  incident_id    UUID REFERENCES public.admin_ops_incidents (id),
  kind           TEXT NOT NULL,
  summary        TEXT NOT NULL,
  options        JSONB NOT NULL DEFAULT '[]'::jsonb,
  decided_option TEXT,
  decided_at     TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 不擴大存取權限：RLS 開啟且不建任何 policy（deny by default），
-- 並收回 Supabase 對 public schema 的預設 grant；只有 service role 可讀寫。
ALTER TABLE public.admin_ops_source_checkpoints ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_ops_incidents          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_ops_decision_cards     ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.admin_ops_source_checkpoints FROM anon, authenticated;
REVOKE ALL ON public.admin_ops_incidents          FROM anon, authenticated;
REVOKE ALL ON public.admin_ops_decision_cards     FROM anon, authenticated;

-- security_invoker：view 用呼叫者權限跑，不繞過基表 RLS。
CREATE OR REPLACE VIEW public.admin_ops_source_freshness
  WITH (security_invoker = true) AS
SELECT source, last_seen_at, updated_at
FROM public.admin_ops_source_checkpoints;

REVOKE ALL ON public.admin_ops_source_freshness FROM anon, authenticated;
