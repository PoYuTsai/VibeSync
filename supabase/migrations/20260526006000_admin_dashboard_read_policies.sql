-- Ensure admin dashboard reads real operational data through authenticated
-- admin server routes instead of browser-side anon queries.

DROP POLICY IF EXISTS "Admins can read ai_logs" ON public.ai_logs;
CREATE POLICY "Admins can read ai_logs" ON public.ai_logs
  FOR SELECT TO authenticated
  USING (public.is_admin_user());

DROP POLICY IF EXISTS "Admins can read token_usage" ON public.token_usage;
CREATE POLICY "Admins can read token_usage" ON public.token_usage
  FOR SELECT TO authenticated
  USING (public.is_admin_user());

DROP POLICY IF EXISTS "Admin can read revenue_events" ON public.revenue_events;
DROP POLICY IF EXISTS "Admins can read revenue_events" ON public.revenue_events;
CREATE POLICY "Admins can read revenue_events" ON public.revenue_events
  FOR SELECT TO authenticated
  USING (public.is_admin_user());

DROP POLICY IF EXISTS "Admin can read auth_diagnostics" ON public.auth_diagnostics;
DROP POLICY IF EXISTS "Admins can read auth_diagnostics" ON public.auth_diagnostics;
CREATE POLICY "Admins can read auth_diagnostics" ON public.auth_diagnostics
  FOR SELECT TO authenticated
  USING (public.is_admin_user());

DROP POLICY IF EXISTS "Admins can read webhook_logs" ON public.webhook_logs;
CREATE POLICY "Admins can read webhook_logs" ON public.webhook_logs
  FOR SELECT TO authenticated
  USING (public.is_admin_user());

NOTIFY pgrst, 'reload schema';
