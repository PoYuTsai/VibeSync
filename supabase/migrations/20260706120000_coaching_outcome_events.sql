-- 案1批3：outcome loop 去識別化上傳目標表。
-- 僅由 submit-feedback Edge Function 以 service role UPSERT 寫入（kind='outcome' 分支）。
-- 白名單欄位；絕不儲存 outcomeTextPreview（對方回覆原文）或 userNote（使用者筆記）。
-- 同一 (user_id, id) 隨 outcome 演進覆寫（copy→userAction→reaction 皆同 id）。
create table if not exists public.outcome_events (
  id text not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  source text not null,
  advice_type text,
  advice_id text,
  user_action text not null,
  outcome text not null,
  suggested_move_summary text not null,
  user_tier text,
  client_created_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint outcome_events_pkey primary key (user_id, id)
);

-- Edge Function 以 service role 寫入繞過 RLS；不開放 anon/authenticated 直存取。
-- 無 policy = 預設拒絕，僅 service role 可讀寫。
alter table public.outcome_events enable row level security;

create index if not exists outcome_events_user_id_created_idx
  on public.outcome_events (user_id, created_at desc);
