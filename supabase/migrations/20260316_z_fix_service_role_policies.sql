-- 2026-03-15: Security hardening
-- - RLS policies that were intended only for service_role must specify `TO service_role`.
-- - SECURITY DEFINER functions that mutate usage must not be executable by clients.

-- Tighten RLS policies
DROP POLICY IF EXISTS "Service role can manage rate_limits" ON public.rate_limits;
CREATE POLICY "Service role can manage rate_limits" ON public.rate_limits
  FOR ALL TO service_role
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "Service role can insert logs" ON public.ai_logs;
CREATE POLICY "Service role can insert logs" ON public.ai_logs
  FOR INSERT TO service_role
  WITH CHECK (true);

DROP POLICY IF EXISTS "Service role can insert token usage" ON public.token_usage;
CREATE POLICY "Service role can insert token usage" ON public.token_usage
  FOR INSERT TO service_role
  WITH CHECK (true);

DROP POLICY IF EXISTS "Service role can manage admin_users" ON public.admin_users;
CREATE POLICY "Service role can manage admin_users" ON public.admin_users
  FOR ALL TO service_role
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "Service role can insert revenue_events" ON public.revenue_events;
CREATE POLICY "Service role can insert revenue_events" ON public.revenue_events
  FOR INSERT TO service_role
  WITH CHECK (true);

DROP POLICY IF EXISTS "Service role can manage test_users" ON public.test_users;
CREATE POLICY "Service role can manage test_users" ON public.test_users
  FOR ALL TO service_role
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "Service role can insert webhook logs" ON public.webhook_logs;
CREATE POLICY "Service role can insert webhook logs" ON public.webhook_logs
  FOR INSERT TO service_role
  WITH CHECK (true);

DROP POLICY IF EXISTS "Service role can select webhook logs" ON public.webhook_logs;
CREATE POLICY "Service role can select webhook logs" ON public.webhook_logs
  FOR SELECT TO service_role
  USING (true);

-- Defensive: reject negative/zero increments
CREATE OR REPLACE FUNCTION public.increment_usage(p_user_id UUID, p_messages INTEGER DEFAULT 1)
RETURNS VOID AS $$
BEGIN
  IF p_messages IS NULL OR p_messages <= 0 THEN
    RAISE EXCEPTION 'p_messages must be a positive integer';
  END IF;

  UPDATE public.subscriptions
  SET monthly_messages_used = monthly_messages_used + p_messages,
      daily_messages_used = daily_messages_used + p_messages
  WHERE user_id = p_user_id;

  UPDATE public.users
  SET total_analyses = total_analyses + 1
  WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Only service_role should be able to execute these SECURITY DEFINER functions
REVOKE EXECUTE ON FUNCTION public.increment_usage(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.increment_usage(uuid, integer) TO service_role;

REVOKE EXECUTE ON FUNCTION public.check_and_reset_usage(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_and_reset_usage(uuid) TO service_role;
