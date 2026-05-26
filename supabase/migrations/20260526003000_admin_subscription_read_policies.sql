-- Allow whitelisted admins to read operational user and subscription state.
-- Admin pages still require Supabase Auth + admin_users whitelist.

CREATE OR REPLACE FUNCTION public.is_admin_user()
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.admin_users
    WHERE lower(email) = lower(auth.jwt()->>'email')
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public, pg_temp;

DROP POLICY IF EXISTS "Admins can read users" ON public.users;
CREATE POLICY "Admins can read users" ON public.users
  FOR SELECT TO authenticated
  USING (public.is_admin_user());

DROP POLICY IF EXISTS "Admins can read subscriptions" ON public.subscriptions;
CREATE POLICY "Admins can read subscriptions" ON public.subscriptions
  FOR SELECT TO authenticated
  USING (public.is_admin_user());

DROP POLICY IF EXISTS "Admins can read test_users" ON public.test_users;
CREATE POLICY "Admins can read test_users" ON public.test_users
  FOR SELECT TO authenticated
  USING (public.is_admin_user());

NOTIFY pgrst, 'reload schema';
