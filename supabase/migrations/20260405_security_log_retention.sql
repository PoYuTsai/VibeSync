-- Round 2 security hardening:
-- 1. tighten auth_diagnostics insert surface without breaking pre-auth flows
-- 2. define retention helpers for observability/security logs

UPDATE public.auth_diagnostics
SET
  email_redacted = CASE
    WHEN email_redacted IS NULL THEN NULL
    ELSE left(email_redacted, 255)
  END,
  platform = CASE
    WHEN platform IS NULL THEN NULL
    ELSE lower(left(platform, 16))
  END,
  app_version = CASE
    WHEN app_version IS NULL THEN NULL
    ELSE left(app_version, 32)
  END,
  build_number = CASE
    WHEN build_number IS NULL THEN NULL
    ELSE left(build_number, 32)
  END,
  error_code = CASE
    WHEN error_code IS NULL THEN NULL
    ELSE left(error_code, 80)
  END,
  message = CASE
    WHEN message IS NULL THEN NULL
    ELSE left(message, 500)
  END
WHERE true;

DELETE FROM public.auth_diagnostics
WHERE
  event !~ '^[a-z0-9_.:-]{1,64}$'
  OR (
    platform IS NOT NULL
    AND platform NOT IN ('web', 'ios', 'android', 'macos', 'windows', 'linux', 'fuchsia')
  )
  OR jsonb_typeof(metadata) <> 'object'
  OR octet_length(metadata::text) > 4096;

ALTER TABLE public.auth_diagnostics
  DROP CONSTRAINT IF EXISTS auth_diagnostics_event_format_check,
  DROP CONSTRAINT IF EXISTS auth_diagnostics_email_redacted_length_check,
  DROP CONSTRAINT IF EXISTS auth_diagnostics_platform_check,
  DROP CONSTRAINT IF EXISTS auth_diagnostics_app_version_length_check,
  DROP CONSTRAINT IF EXISTS auth_diagnostics_build_number_length_check,
  DROP CONSTRAINT IF EXISTS auth_diagnostics_error_code_length_check,
  DROP CONSTRAINT IF EXISTS auth_diagnostics_message_length_check,
  DROP CONSTRAINT IF EXISTS auth_diagnostics_metadata_shape_check;

ALTER TABLE public.auth_diagnostics
  ADD CONSTRAINT auth_diagnostics_event_format_check
    CHECK (event ~ '^[a-z0-9_.:-]{1,64}$'),
  ADD CONSTRAINT auth_diagnostics_email_redacted_length_check
    CHECK (email_redacted IS NULL OR char_length(email_redacted) <= 255),
  ADD CONSTRAINT auth_diagnostics_platform_check
    CHECK (
      platform IS NULL
      OR platform IN ('web', 'ios', 'android', 'macos', 'windows', 'linux', 'fuchsia')
    ),
  ADD CONSTRAINT auth_diagnostics_app_version_length_check
    CHECK (app_version IS NULL OR char_length(app_version) <= 32),
  ADD CONSTRAINT auth_diagnostics_build_number_length_check
    CHECK (build_number IS NULL OR char_length(build_number) <= 32),
  ADD CONSTRAINT auth_diagnostics_error_code_length_check
    CHECK (error_code IS NULL OR char_length(error_code) <= 80),
  ADD CONSTRAINT auth_diagnostics_message_length_check
    CHECK (message IS NULL OR char_length(message) <= 500),
  ADD CONSTRAINT auth_diagnostics_metadata_shape_check
    CHECK (
      jsonb_typeof(metadata) = 'object'
      AND octet_length(metadata::text) <= 4096
    );

DROP POLICY IF EXISTS "Anon and authenticated can insert auth_diagnostics"
  ON public.auth_diagnostics;

CREATE POLICY "Anon and authenticated can insert auth_diagnostics"
  ON public.auth_diagnostics
  FOR INSERT
  WITH CHECK (
    auth.role() IN ('anon', 'authenticated')
    AND event ~ '^[a-z0-9_.:-]{1,64}$'
    AND (email_redacted IS NULL OR char_length(email_redacted) <= 255)
    AND (
      platform IS NULL
      OR platform IN ('web', 'ios', 'android', 'macos', 'windows', 'linux', 'fuchsia')
    )
    AND (app_version IS NULL OR char_length(app_version) <= 32)
    AND (build_number IS NULL OR char_length(build_number) <= 32)
    AND (error_code IS NULL OR char_length(error_code) <= 80)
    AND (message IS NULL OR char_length(message) <= 500)
    AND jsonb_typeof(metadata) = 'object'
    AND octet_length(metadata::text) <= 4096
    AND created_at >= now() - interval '5 minutes'
    AND created_at <= now() + interval '5 minutes'
  );

CREATE OR REPLACE FUNCTION public.cleanup_old_auth_diagnostics(
  retention interval DEFAULT interval '14 days'
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  deleted_count integer := 0;
BEGIN
  DELETE FROM public.auth_diagnostics
  WHERE created_at < now() - retention;

  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.cleanup_old_webhook_logs(
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
  DELETE FROM public.webhook_logs
  WHERE created_at < now() - retention;

  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$;

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
BEGIN
  DELETE FROM public.ai_logs
  WHERE created_at < now() - ai_retention;
  GET DIAGNOSTICS ai_deleted = ROW_COUNT;

  auth_deleted := public.cleanup_old_auth_diagnostics(auth_retention);
  webhook_deleted := public.cleanup_old_webhook_logs(webhook_retention);

  RETURN jsonb_build_object(
    'ai_logs', ai_deleted,
    'auth_diagnostics', auth_deleted,
    'webhook_logs', webhook_deleted
  );
END;
$$;

COMMENT ON FUNCTION public.cleanup_old_auth_diagnostics(interval)
  IS 'Deletes auth_diagnostics rows older than the retention window. Default 14 days.';

COMMENT ON FUNCTION public.cleanup_old_webhook_logs(interval)
  IS 'Deletes webhook_logs rows older than the retention window. Default 30 days.';

COMMENT ON FUNCTION public.cleanup_observability_logs(interval, interval, interval)
  IS 'Deletes old ai_logs, auth_diagnostics, and webhook_logs rows and returns per-table counts.';

REVOKE ALL ON FUNCTION public.cleanup_old_ai_logs() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cleanup_old_auth_diagnostics(interval) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cleanup_old_webhook_logs(interval) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cleanup_observability_logs(interval, interval, interval) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.cleanup_old_ai_logs() TO service_role;
GRANT EXECUTE ON FUNCTION public.cleanup_old_auth_diagnostics(interval) TO service_role;
GRANT EXECUTE ON FUNCTION public.cleanup_old_webhook_logs(interval) TO service_role;
GRANT EXECUTE ON FUNCTION public.cleanup_observability_logs(interval, interval, interval) TO service_role;
