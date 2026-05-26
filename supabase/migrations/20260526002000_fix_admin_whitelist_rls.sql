-- Fix admin whitelist checks so app sessions can verify admins without
-- recursive admin_users RLS reads.

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

DROP POLICY IF EXISTS "Admin can read admin_users" ON public.admin_users;
CREATE POLICY "Admin can read admin_users" ON public.admin_users
  FOR SELECT TO authenticated
  USING (public.is_admin_user());

INSERT INTO public.admin_users (email, name)
VALUES
  ('eric19921204@gmail.com', 'Eric'),
  ('chiang688041@gmail.com', 'Bruce')
ON CONFLICT (email) DO UPDATE
SET name = COALESCE(public.admin_users.name, EXCLUDED.name);
