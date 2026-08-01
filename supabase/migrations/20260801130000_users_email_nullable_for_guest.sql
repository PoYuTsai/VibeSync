-- 訪客模式修復：匿名帳號 email 為 NULL，on_auth_user_created → handle_new_user 會把
-- NEW.email 插入 public.users，email NOT NULL 使整筆 /signup 交易回滾，
-- GoTrue 對匿名登入回 500「Database error saving new user」。
-- UNIQUE(email) 保留：Postgres UNIQUE 允許多個 NULL，匿名帳號互不衝突。
-- 決策（雙審 2026-08-01）：接受多個 NULL；訪客升級（manual linking）後
-- public.users.email 仍為 NULL（現況本無 email 同步機制、亦無消費者讀此欄）。
-- 不要再把此欄改回 NOT NULL 或用假 email COALESCE——會把匿名 signup 炸回 500。
ALTER TABLE public.users ALTER COLUMN email DROP NOT NULL;
