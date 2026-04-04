-- Round 4 security hardening:
-- 1. automate observability/security log cleanup with pg_cron
-- 2. expose active security/anomaly signals for dashboard triage

CREATE EXTENSION IF NOT EXISTS pg_cron;

CREATE OR REPLACE FUNCTION public.cleanup_old_cron_job_run_details(
  retention interval DEFAULT interval '14 days'
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, cron
AS $$
DECLARE
  deleted_count integer := 0;
BEGIN
  DELETE FROM cron.job_run_details
  WHERE COALESCE(end_time, start_time) < now() - retention;

  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$;

COMMENT ON FUNCTION public.cleanup_old_cron_job_run_details(interval)
  IS 'Deletes pg_cron job_run_details rows older than the retention window. Default 14 days.';

REVOKE ALL ON FUNCTION public.cleanup_old_cron_job_run_details(interval) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_old_cron_job_run_details(interval) TO service_role;

SELECT cron.schedule(
  'vibesync-observability-retention-nightly',
  '25 18 * * *',
  $$SELECT public.cleanup_observability_logs();$$
);

SELECT cron.schedule(
  'vibesync-cron-history-retention-weekly',
  '40 18 * * 0',
  $$SELECT public.cleanup_old_cron_job_run_details();$$
);

CREATE OR REPLACE VIEW public.security_signals AS
WITH auth_recent AS (
  SELECT
    COUNT(*) AS total_events_15m,
    COUNT(*) FILTER (WHERE status = 'error') AS error_events_15m
  FROM public.auth_diagnostics
  WHERE created_at >= now() - interval '15 minutes'
),
auth_error_baseline AS (
  SELECT
    COALESCE(AVG(error_count), 0)::numeric / 4.0 AS baseline_errors_15m
  FROM (
    SELECT
      date_trunc('hour', created_at) AS hour_bucket,
      COUNT(*) FILTER (WHERE status = 'error') AS error_count
    FROM public.auth_diagnostics
    WHERE created_at >= now() - interval '7 days'
      AND created_at < now() - interval '15 minutes'
    GROUP BY 1
  ) hourly
),
auth_top_fingerprint AS (
  SELECT
    client_fingerprint,
    COUNT(*) AS event_count_10m,
    COUNT(*) FILTER (WHERE status = 'error') AS error_count_10m,
    MAX(created_at) AS latest_seen_at
  FROM public.auth_diagnostics
  WHERE created_at >= now() - interval '10 minutes'
    AND client_fingerprint IS NOT NULL
  GROUP BY client_fingerprint
  ORDER BY COUNT(*) DESC, MAX(created_at) DESC
  LIMIT 1
),
ai_recent AS (
  SELECT
    COUNT(*) AS total_requests_15m,
    COUNT(*) FILTER (WHERE status = 'failed') AS failed_requests_15m,
    ROUND(COALESCE(AVG(latency_ms), 0))::integer AS avg_latency_ms_15m
  FROM public.ai_logs
  WHERE created_at >= now() - interval '15 minutes'
),
webhook_recent AS (
  SELECT
    COUNT(*) AS events_60m
  FROM public.webhook_logs
  WHERE created_at >= now() - interval '60 minutes'
),
webhook_baseline AS (
  SELECT
    COALESCE(AVG(hourly_count), 0)::numeric AS baseline_hourly
  FROM (
    SELECT
      date_trunc('hour', created_at) AS hour_bucket,
      COUNT(*) AS hourly_count
    FROM public.webhook_logs
    WHERE created_at >= now() - interval '7 days'
      AND created_at < now() - interval '60 minutes'
    GROUP BY 1
  ) hourly
),
cron_recent_failures AS (
  SELECT
    COUNT(*) FILTER (
      WHERE lower(COALESCE(status, '')) NOT IN ('succeeded', 'success')
    ) AS failed_runs_24h
  FROM cron.job_run_details
  WHERE jobid IN (
    SELECT jobid
    FROM cron.job
    WHERE jobname IN (
      'vibesync-observability-retention-nightly',
      'vibesync-cron-history-retention-weekly'
    )
  )
    AND COALESCE(end_time, start_time) >= now() - interval '24 hours'
)
SELECT
  'auth_error_spike_15m'::text AS signal_key,
  CASE
    WHEN auth_recent.error_events_15m >= 12 THEN 'critical'
    ELSE 'warning'
  END::text AS severity,
  'Auth diagnostics error spike'::text AS title,
  'Recent auth errors are above the recent baseline and may indicate signup/reset friction or abuse.'::text AS summary,
  15::integer AS window_minutes,
  auth_recent.error_events_15m::numeric AS observed_value,
  GREATEST(5, CEIL(auth_error_baseline.baseline_errors_15m * 3.0))::numeric AS threshold_value,
  ROUND(auth_error_baseline.baseline_errors_15m, 2) AS baseline_value,
  now() AS detected_at,
  jsonb_build_object(
    'total_events_15m', auth_recent.total_events_15m,
    'error_events_15m', auth_recent.error_events_15m
  ) AS details
FROM auth_recent
CROSS JOIN auth_error_baseline
WHERE auth_recent.error_events_15m >= GREATEST(5, CEIL(auth_error_baseline.baseline_errors_15m * 3.0))

UNION ALL

SELECT
  'auth_fingerprint_spike_10m'::text,
  CASE
    WHEN auth_top_fingerprint.event_count_10m >= 20 THEN 'critical'
    ELSE 'warning'
  END::text,
  'Single client fingerprint is spiking auth traffic'::text,
  'One client fingerprint generated an unusual burst of auth diagnostics in a short window.'::text,
  10::integer,
  auth_top_fingerprint.event_count_10m::numeric,
  12::numeric,
  auth_top_fingerprint.error_count_10m::numeric,
  now(),
  jsonb_build_object(
    'client_fingerprint', auth_top_fingerprint.client_fingerprint,
    'event_count_10m', auth_top_fingerprint.event_count_10m,
    'error_count_10m', auth_top_fingerprint.error_count_10m,
    'latest_seen_at', auth_top_fingerprint.latest_seen_at
  )
FROM auth_top_fingerprint
WHERE auth_top_fingerprint.event_count_10m >= 12
   OR auth_top_fingerprint.error_count_10m >= 6

UNION ALL

SELECT
  'ai_failure_spike_15m'::text,
  CASE
    WHEN ai_recent.failed_requests_15m >= 8 THEN 'critical'
    ELSE 'warning'
  END::text,
  'AI failure spike'::text,
  'Recent AI requests show an elevated failed-request rate.'::text,
  15::integer,
  ai_recent.failed_requests_15m::numeric,
  5::numeric,
  ROUND(
    COALESCE(
      (ai_recent.failed_requests_15m::numeric / NULLIF(ai_recent.total_requests_15m, 0)) * 100,
      0
    ),
    2
  ) AS baseline_value,
  now(),
  jsonb_build_object(
    'total_requests_15m', ai_recent.total_requests_15m,
    'failed_requests_15m', ai_recent.failed_requests_15m
  )
FROM ai_recent
WHERE ai_recent.total_requests_15m >= 6
  AND (
    ai_recent.failed_requests_15m >= 5
    OR (
      ai_recent.failed_requests_15m::numeric / NULLIF(ai_recent.total_requests_15m, 0)
    ) >= 0.25
  )

UNION ALL

SELECT
  'ai_latency_degraded_15m'::text,
  CASE
    WHEN ai_recent.avg_latency_ms_15m >= 40000 THEN 'critical'
    ELSE 'warning'
  END::text,
  'AI latency degraded'::text,
  'Recent AI calls are materially slower than expected.'::text,
  15::integer,
  ai_recent.avg_latency_ms_15m::numeric,
  25000::numeric,
  NULL::numeric,
  now(),
  jsonb_build_object(
    'total_requests_15m', ai_recent.total_requests_15m,
    'avg_latency_ms_15m', ai_recent.avg_latency_ms_15m
  )
FROM ai_recent
WHERE ai_recent.total_requests_15m >= 5
  AND ai_recent.avg_latency_ms_15m >= 25000

UNION ALL

SELECT
  'webhook_volume_spike_60m'::text,
  CASE
    WHEN webhook_recent.events_60m >= GREATEST(16, CEIL(webhook_baseline.baseline_hourly * 4.0)) THEN 'critical'
    ELSE 'warning'
  END::text,
  'Webhook volume spike'::text,
  'Webhook traffic is above the recent hourly baseline and may reflect transfer churn, replay, or downstream instability.'::text,
  60::integer,
  webhook_recent.events_60m::numeric,
  GREATEST(8, CEIL(webhook_baseline.baseline_hourly * 3.0))::numeric,
  ROUND(webhook_baseline.baseline_hourly, 2),
  now(),
  jsonb_build_object(
    'events_60m', webhook_recent.events_60m
  )
FROM webhook_recent
CROSS JOIN webhook_baseline
WHERE webhook_recent.events_60m >= GREATEST(8, CEIL(webhook_baseline.baseline_hourly * 3.0))

UNION ALL

SELECT
  'security_cleanup_job_failures_24h'::text,
  'critical'::text,
  'Security cleanup cron job failures'::text,
  'One or more scheduled retention jobs failed in the last 24 hours.'::text,
  1440::integer,
  cron_recent_failures.failed_runs_24h::numeric,
  1::numeric,
  NULL::numeric,
  now(),
  jsonb_build_object(
    'failed_runs_24h', cron_recent_failures.failed_runs_24h
  )
FROM cron_recent_failures
WHERE cron_recent_failures.failed_runs_24h > 0;

COMMENT ON VIEW public.security_signals
  IS 'Active security/anomaly signals derived from auth_diagnostics, ai_logs, webhook_logs, and pg_cron job health.';

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
    'vibesync-cron-history-retention-weekly'
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

COMMENT ON VIEW public.security_automation_status
  IS 'Shows the configured security/observability pg_cron jobs plus recent run history.';
