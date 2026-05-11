-- Keep unauthenticated auth diagnostics useful, but cap payload size so the anon
-- insert policy cannot be abused as an unbounded log sink.

UPDATE public.auth_diagnostics
SET
  event = left(event, 80),
  email_redacted = CASE
    WHEN email_redacted IS NULL THEN NULL
    ELSE left(email_redacted, 120)
  END,
  platform = CASE
    WHEN platform IS NULL THEN NULL
    ELSE left(platform, 40)
  END,
  app_version = CASE
    WHEN app_version IS NULL THEN NULL
    ELSE left(app_version, 40)
  END,
  build_number = CASE
    WHEN build_number IS NULL THEN NULL
    ELSE left(build_number, 40)
  END,
  error_code = CASE
    WHEN error_code IS NULL THEN NULL
    ELSE left(error_code, 80)
  END,
  message = CASE
    WHEN message IS NULL THEN NULL
    ELSE left(message, 300)
  END,
  metadata = CASE
    WHEN pg_column_size(metadata) > 4096 THEN jsonb_build_object('truncated', true)
    ELSE metadata
  END;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.auth_diagnostics'::regclass
      AND conname = 'auth_diagnostics_event_length'
  ) THEN
    ALTER TABLE public.auth_diagnostics
      ADD CONSTRAINT auth_diagnostics_event_length
      CHECK (char_length(event) <= 80);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.auth_diagnostics'::regclass
      AND conname = 'auth_diagnostics_email_redacted_length'
  ) THEN
    ALTER TABLE public.auth_diagnostics
      ADD CONSTRAINT auth_diagnostics_email_redacted_length
      CHECK (email_redacted IS NULL OR char_length(email_redacted) <= 120);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.auth_diagnostics'::regclass
      AND conname = 'auth_diagnostics_platform_length'
  ) THEN
    ALTER TABLE public.auth_diagnostics
      ADD CONSTRAINT auth_diagnostics_platform_length
      CHECK (platform IS NULL OR char_length(platform) <= 40);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.auth_diagnostics'::regclass
      AND conname = 'auth_diagnostics_app_version_length'
  ) THEN
    ALTER TABLE public.auth_diagnostics
      ADD CONSTRAINT auth_diagnostics_app_version_length
      CHECK (app_version IS NULL OR char_length(app_version) <= 40);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.auth_diagnostics'::regclass
      AND conname = 'auth_diagnostics_build_number_length'
  ) THEN
    ALTER TABLE public.auth_diagnostics
      ADD CONSTRAINT auth_diagnostics_build_number_length
      CHECK (build_number IS NULL OR char_length(build_number) <= 40);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.auth_diagnostics'::regclass
      AND conname = 'auth_diagnostics_error_code_length'
  ) THEN
    ALTER TABLE public.auth_diagnostics
      ADD CONSTRAINT auth_diagnostics_error_code_length
      CHECK (error_code IS NULL OR char_length(error_code) <= 80);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.auth_diagnostics'::regclass
      AND conname = 'auth_diagnostics_message_length'
  ) THEN
    ALTER TABLE public.auth_diagnostics
      ADD CONSTRAINT auth_diagnostics_message_length
      CHECK (message IS NULL OR char_length(message) <= 300);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.auth_diagnostics'::regclass
      AND conname = 'auth_diagnostics_metadata_size'
  ) THEN
    ALTER TABLE public.auth_diagnostics
      ADD CONSTRAINT auth_diagnostics_metadata_size
      CHECK (pg_column_size(metadata) <= 4096);
  END IF;
END $$;
