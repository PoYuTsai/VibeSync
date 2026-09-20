-- 與 opener_two_stage_migration_postgres_test.ts 的 createDatabase() 相同的前置物件（真 Postgres 版）。
CREATE SCHEMA auth;
CREATE TABLE auth.users (id UUID PRIMARY KEY);
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE ROLE service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;
CREATE TABLE public.users (id UUID PRIMARY KEY, total_analyses INTEGER NOT NULL DEFAULT 0);
CREATE TABLE public.subscriptions (
  user_id UUID PRIMARY KEY,
  monthly_messages_used INTEGER NOT NULL DEFAULT 0,
  daily_messages_used INTEGER NOT NULL DEFAULT 0
);
CREATE FUNCTION public.increment_usage(p_user_id UUID, p_messages INTEGER DEFAULT 1)
RETURNS void LANGUAGE sql AS $$ SELECT 1; $$;
