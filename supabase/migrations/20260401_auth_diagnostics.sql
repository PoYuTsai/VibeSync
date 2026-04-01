CREATE TABLE IF NOT EXISTS public.auth_diagnostics (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'info' CHECK (status IN ('info', 'success', 'warning', 'error')),
  email_redacted TEXT,
  platform TEXT,
  app_version TEXT,
  build_number TEXT,
  error_code TEXT,
  message TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_auth_diagnostics_created_at
  ON public.auth_diagnostics(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_auth_diagnostics_event
  ON public.auth_diagnostics(event);

ALTER TABLE public.auth_diagnostics ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admin can read auth_diagnostics" ON public.auth_diagnostics
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.admin_users
      WHERE email = auth.jwt()->>'email'
    )
  );

CREATE POLICY "Anon and authenticated can insert auth_diagnostics" ON public.auth_diagnostics
  FOR INSERT WITH CHECK (
    auth.role() = 'anon' OR auth.role() = 'authenticated'
  );
