-- Round 6 security hardening:
-- 1. remove direct client writes to auth_diagnostics
-- 2. stop exposing security views/tables to authenticated browser clients

REVOKE INSERT ON TABLE public.auth_diagnostics FROM anon, authenticated;
GRANT INSERT ON TABLE public.auth_diagnostics TO service_role;
GRANT SELECT ON TABLE public.auth_diagnostics TO service_role;

DROP POLICY IF EXISTS "Anon and authenticated can insert auth_diagnostics"
  ON public.auth_diagnostics;

DROP POLICY IF EXISTS "Service role can insert auth_diagnostics"
  ON public.auth_diagnostics;

CREATE POLICY "Service role can insert auth_diagnostics"
  ON public.auth_diagnostics
  FOR INSERT TO service_role
  WITH CHECK (true);

REVOKE SELECT ON TABLE public.auth_diagnostics FROM authenticated;

REVOKE SELECT ON TABLE public.security_signals FROM anon, authenticated;
REVOKE SELECT ON TABLE public.security_automation_status FROM anon, authenticated;
REVOKE SELECT ON TABLE public.security_alert_events FROM anon, authenticated;

GRANT SELECT ON TABLE public.security_signals TO service_role;
GRANT SELECT ON TABLE public.security_automation_status TO service_role;
GRANT SELECT ON TABLE public.security_alert_events TO service_role;
