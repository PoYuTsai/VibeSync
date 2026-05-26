-- Seed Google admin whitelist for Eric and Bruce.
-- Passwords stay in Supabase Auth / Google, never in repo.

INSERT INTO public.admin_users (email, name)
VALUES
  ('eric19921204@gmail.com', 'Eric'),
  ('chiang688041@gmail.com', 'Bruce')
ON CONFLICT (email) DO UPDATE
SET name = COALESCE(public.admin_users.name, EXCLUDED.name);
