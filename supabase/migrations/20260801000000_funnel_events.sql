-- Tier 2 批 1.5：去識別化漏斗埋點目標表（docs/integrations/funnel-events-v1.md）。
-- 僅由 submit-feedback Edge Function 以 service role INSERT 寫入（kind='funnel' 分支）。
-- properties 只收字典白名單鍵；絕不儲存對話內容、對象名或自由文字。
create table if not exists public.funnel_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  event text not null,
  properties jsonb not null default '{}'::jsonb,
  client_ts timestamptz,
  created_at timestamptz not null default now(),
  -- 縱深防禦：Edge 已做 enum 白名單，這裡再擋長度異常。
  constraint funnel_events_event_length check (char_length(event) <= 64)
);

-- Edge Function 以 service role 寫入繞過 RLS；不開放 anon/authenticated 直存取。
-- 無 policy = 預設拒絕，查詢走 Management API。
alter table public.funnel_events enable row level security;

create index if not exists funnel_events_user_event_idx
  on public.funnel_events (user_id, event, created_at desc);
