-- Round 5 security hardening:
-- 1. add external delivery for critical security signals
-- 2. persist alert state with cooldown / dedupe
-- 3. schedule alert delivery with pg_cron + pg_net

CREATE EXTENSION IF NOT EXISTS vault;
CREATE EXTENSION IF NOT EXISTS pg_net;

CREATE TABLE IF NOT EXISTS public.security_alert_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  signal_key TEXT NOT NULL,
  severity TEXT NOT NULL CHECK (severity IN ('warning', 'critical')),
  channel TEXT NOT NULL CHECK (channel IN ('telegram')),
  dedupe_key TEXT NOT NULL UNIQUE,
  title TEXT,
  signal_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
  first_detected_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_detected_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_notified_at TIMESTAMPTZ,
  notification_count INTEGER NOT NULL DEFAULT 0 CHECK (notification_count >= 0),
  last_status TEXT NOT NULL DEFAULT 'pending' CHECK (
    last_status IN ('pending', 'sent', 'suppressed', 'failed', 'skipped_no_channel')
  ),
  last_response_code INTEGER,
  last_error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_security_alert_events_signal_key
  ON public.security_alert_events(signal_key);

CREATE INDEX IF NOT EXISTS idx_security_alert_events_last_detected_at
  ON public.security_alert_events(last_detected_at DESC);

CREATE INDEX IF NOT EXISTS idx_security_alert_events_last_status
  ON public.security_alert_events(last_status);

ALTER TABLE public.security_alert_events ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON TABLE public.security_alert_events TO authenticated;
GRANT SELECT ON TABLE public.security_alert_events TO service_role;

DROP POLICY IF EXISTS "Admin can read security_alert_events" ON public.security_alert_events;
CREATE POLICY "Admin can read security_alert_events" ON public.security_alert_events
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.admin_users WHERE email = auth.jwt()->>'email')
  );

DROP POLICY IF EXISTS "Service role can manage security_alert_events" ON public.security_alert_events;
CREATE POLICY "Service role can manage security_alert_events" ON public.security_alert_events
  FOR ALL TO service_role
  USING (true)
  WITH CHECK (true);

CREATE OR REPLACE FUNCTION public.cleanup_old_security_alert_events(
  retention interval DEFAULT interval '30 days'
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  deleted_count integer := 0;
BEGIN
  DELETE FROM public.security_alert_events
  WHERE last_detected_at < now() - retention;

  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$;

COMMENT ON FUNCTION public.cleanup_old_security_alert_events(interval)
  IS 'Deletes security_alert_events rows older than the retention window. Default 30 days.';

REVOKE ALL ON FUNCTION public.cleanup_old_security_alert_events(interval) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_old_security_alert_events(interval) TO service_role;

CREATE OR REPLACE FUNCTION public.cleanup_observability_logs(
  ai_retention interval DEFAULT interval '30 days',
  auth_retention interval DEFAULT interval '14 days',
  webhook_retention interval DEFAULT interval '30 days'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  ai_deleted integer := 0;
  auth_deleted integer := 0;
  webhook_deleted integer := 0;
  alert_deleted integer := 0;
BEGIN
  DELETE FROM public.ai_logs
  WHERE created_at < now() - ai_retention;
  GET DIAGNOSTICS ai_deleted = ROW_COUNT;

  auth_deleted := public.cleanup_old_auth_diagnostics(auth_retention);
  webhook_deleted := public.cleanup_old_webhook_logs(webhook_retention);
  alert_deleted := public.cleanup_old_security_alert_events(interval '30 days');

  RETURN jsonb_build_object(
    'ai_logs', ai_deleted,
    'auth_diagnostics', auth_deleted,
    'webhook_logs', webhook_deleted,
    'security_alert_events', alert_deleted
  );
END;
$$;

COMMENT ON FUNCTION public.cleanup_observability_logs(interval, interval, interval)
  IS 'Deletes old ai_logs, auth_diagnostics, webhook_logs, and security_alert_events rows and returns per-table counts.';

REVOKE ALL ON FUNCTION public.cleanup_observability_logs(interval, interval, interval) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_observability_logs(interval, interval, interval) TO service_role;

CREATE OR REPLACE FUNCTION public.invoke_security_alerts_job()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault
AS $$
DECLARE
  project_url text;
  anon_key text;
  security_alert_secret text;
  request_id bigint;
BEGIN
  SELECT decrypted_secret
  INTO project_url
  FROM vault.decrypted_secrets
  WHERE name = 'security_alert_project_url'
  LIMIT 1;

  SELECT decrypted_secret
  INTO anon_key
  FROM vault.decrypted_secrets
  WHERE name = 'security_alert_anon_key'
  LIMIT 1;

  SELECT decrypted_secret
  INTO security_alert_secret
  FROM vault.decrypted_secrets
  WHERE name = 'security_alert_secret'
  LIMIT 1;

  IF project_url IS NULL OR anon_key IS NULL OR security_alert_secret IS NULL THEN
    RAISE EXCEPTION 'Missing Vault secret(s) for security alerts job';
  END IF;

  SELECT net.http_post(
    url := project_url || '/functions/v1/security-alerts',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || anon_key,
      'x-security-alert-secret', security_alert_secret
    ),
    body := jsonb_build_object(
      'source', 'pg_cron',
      'severity', 'critical'
    ),
    timeout_milliseconds := 5000
  )
  INTO request_id;

  RETURN jsonb_build_object(
    'ok', true,
    'request_id', request_id
  );
END;
$$;

COMMENT ON FUNCTION public.invoke_security_alerts_job()
  IS 'Invokes the security-alerts Edge Function using Vault-managed security_alert_project_url / security_alert_anon_key / security_alert_secret.';

REVOKE ALL ON FUNCTION public.invoke_security_alerts_job() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.invoke_security_alerts_job() TO service_role;

DO $$
DECLARE
  existing_job_id bigint;
BEGIN
  SELECT jobid
  INTO existing_job_id
  FROM cron.job
  WHERE jobname = 'vibesync-security-alerts-every-10m'
  LIMIT 1;

  IF existing_job_id IS NOT NULL THEN
    PERFORM cron.unschedule(existing_job_id);
  END IF;
END;
$$;

SELECT cron.schedule(
  'vibesync-security-alerts-every-10m',
  '*/10 * * * *',
  $$SELECT public.invoke_security_alerts_job();$$
);

CREATE OR REPLACE VIEW public.security_automation_status AS
WITH target_jobs AS (
  SELECT
    jobid,
    jobname,
    schedule,
    active,
    command
  FROM cron.job
  WHERE jobname IN (
    'vibesync-observability-retention-nightly',
    'vibesync-cron-history-retention-weekly',
    'vibesync-security-alerts-every-10m'
  )
),
recent_runs AS (
  SELECT
    jobid,
    MAX(COALESCE(end_time, start_time)) AS last_run_at,
    COUNT(*) FILTER (
      WHERE lower(COALESCE(status, '')) IN ('succeeded', 'success')
        AND COALESCE(end_time, start_time) >= now() - interval '7 days'
    ) AS succeeded_runs_7d,
    COUNT(*) FILTER (
      WHERE lower(COALESCE(status, '')) NOT IN ('succeeded', 'success')
        AND COALESCE(end_time, start_time) >= now() - interval '7 days'
    ) AS failed_runs_7d
  FROM cron.job_run_details
  WHERE jobid IN (SELECT jobid FROM target_jobs)
  GROUP BY jobid
)
SELECT
  target_jobs.jobname,
  target_jobs.schedule,
  target_jobs.active,
  target_jobs.command,
  recent_runs.last_run_at,
  COALESCE(recent_runs.succeeded_runs_7d, 0) AS succeeded_runs_7d,
  COALESCE(recent_runs.failed_runs_7d, 0) AS failed_runs_7d
FROM target_jobs
LEFT JOIN recent_runs USING (jobid);

GRANT SELECT ON TABLE public.security_signals TO authenticated;
GRANT SELECT ON TABLE public.security_signals TO service_role;
GRANT SELECT ON TABLE public.security_automation_status TO authenticated;
GRANT SELECT ON TABLE public.security_automation_status TO service_role;
