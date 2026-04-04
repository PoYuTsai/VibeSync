-- Round 3 security hardening:
-- move auth diagnostics ingestion behind a dedicated edge function with
-- hashed client fingerprint + rate-limit-friendly indexing.

ALTER TABLE public.auth_diagnostics
  ADD COLUMN IF NOT EXISTS client_fingerprint TEXT;

ALTER TABLE public.auth_diagnostics
  DROP CONSTRAINT IF EXISTS auth_diagnostics_client_fingerprint_length_check;

ALTER TABLE public.auth_diagnostics
  ADD CONSTRAINT auth_diagnostics_client_fingerprint_length_check
    CHECK (
      client_fingerprint IS NULL
      OR client_fingerprint ~ '^[a-f0-9]{64}$'
    );

CREATE INDEX IF NOT EXISTS idx_auth_diagnostics_fingerprint_created_at
  ON public.auth_diagnostics(client_fingerprint, created_at DESC);

COMMENT ON COLUMN public.auth_diagnostics.client_fingerprint
  IS 'Hashed per-client fingerprint used for coarse abuse detection. Never stores raw IP or raw user-agent.';
