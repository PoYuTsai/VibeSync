-- Two-stage analyze: server-owned run record linking quick and full phases.
-- Goal: quota charged exactly once on quick success; full validates against this row.
-- Invariants enforced here: I1 (single charge anchor), I3 (RLS), I4 (TTL), I6 (retry bound).

CREATE TABLE IF NOT EXISTS public.analysis_runs (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  conversation_hash TEXT        NOT NULL,
  charged           BOOLEAN     NOT NULL DEFAULT FALSE,
  quick_result      JSONB       NOT NULL,
  request_context   JSONB,
  retry_count       INTEGER     NOT NULL DEFAULT 0,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at        TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '30 minutes'),
  consumed_at       TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_analysis_runs_user_expires
  ON public.analysis_runs (user_id, expires_at);

ALTER TABLE public.analysis_runs ENABLE ROW LEVEL SECURITY;

-- service_role only; clients never read this table directly.
DROP POLICY IF EXISTS analysis_runs_service_role ON public.analysis_runs;
CREATE POLICY analysis_runs_service_role
  ON public.analysis_runs
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Supabase 2026-10-30 後 public 新表的 Data API 預設不再自動 GRANT；
-- 必須明確聲明 service_role 可讀寫，且 anon / authenticated 完全沒權限。
GRANT SELECT, INSERT, UPDATE, DELETE ON public.analysis_runs TO service_role;
REVOKE ALL ON public.analysis_runs FROM anon, authenticated;

-- Cleanup function for pg_cron (Phase 4 wires the schedule).
-- Keep one-hour grace beyond expires_at so in-flight retries near boundary don't
-- get RUN_EXPIRED + deleted race.
CREATE OR REPLACE FUNCTION public.cleanup_expired_analysis_runs()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  deleted INTEGER;
BEGIN
  -- 不要用 DELETE ... RETURNING ... INTO（刪多筆會 too_many_rows）。
  -- GET DIAGNOSTICS ROW_COUNT 是 plpgsql 標準的批次計數方式。
  DELETE FROM public.analysis_runs
   WHERE expires_at < now() - interval '1 hour';
  GET DIAGNOSTICS deleted = ROW_COUNT;
  RETURN deleted;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.cleanup_expired_analysis_runs() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cleanup_expired_analysis_runs() TO service_role;
