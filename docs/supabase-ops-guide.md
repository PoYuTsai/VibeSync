# Supabase Ops Guide

Last updated: 2026-04-05

This is the main operations guide for VibeSync.

Use this file when you need to:

- inspect users
- inspect tiers
- inspect auth flows
- inspect AI usage / cost
- inspect revenue summaries
- run SQL for support or operations

## Backend Split

Use the right backend for the right question:

- `Supabase`
  - main operations backend
  - users, tiers, auth diagnostics, AI logs, SQL, revenue/cost views
- `RevenueCat`
  - subscription truth
  - entitlement, restore, transfer, same Apple ID behavior
- `App Store Connect`
  - iOS product setup
  - subscription groups
  - upgrade / downgrade timing
  - App Store privacy disclosure

Short version:

- operations and SQL -> `Supabase`
- subscription truth -> `RevenueCat`
- iOS store rules -> `App Store Connect`

## Most Important Tables / Views

| Name | Type | What it is for |
| --- | --- | --- |
| `auth.users` | auth table | canonical user records |
| `public.users` | table | app-side profile records |
| `public.subscriptions` | table | current app tier and usage counters |
| `public.ai_logs` | table | AI request logs, latency, tokens, status |
| `public.feedback` | table | user thumbs up / down feedback |
| `public.webhook_logs` | table | reduced RevenueCat webhook summaries |
| `public.revenue_events` | table | normalized purchase / renewal / cancellation events |
| `public.token_usage` | table | token-level cost tracking |
| `public.auth_diagnostics` | table | signup / resend / forgot password / deep-link diagnostics |
| `public.real_subscriptions` | view | paid subscriptions excluding test-account noise |
| `public.monthly_revenue` | view | monthly subscription revenue summary |
| `public.monthly_profit` | view | monthly revenue minus AI/token cost |
| `public.security_signals` | view | active auth / AI / webhook / cron anomalies |
| `public.security_automation_status` | view | cleanup / alert cron-job status |
| `public.security_alert_events` | table | external alert delivery history |

Important notes:

- `public.rate_limits` is not the daily or monthly quota source of truth. It is only short-window throttling.
- `public.webhook_logs` does not have a `status` column.
- `public.webhook_logs.payload` now stores a reduced summary, not the full raw RevenueCat payload.
- internal test-account quota bypasses now come from the `TEST_ACCOUNT_EMAILS` Edge Function env, not a repo hardcoded email list.
- `public.monthly_profit` is not accounting-grade net profit. It is currently:
  - subscription revenue
  - minus AI / token cost
  - it does not subtract Apple fees, RevenueCat fees, infra, or other business costs

## Common Support Checks

### Check one user's auth state

```sql
select
  id,
  email,
  created_at,
  last_sign_in_at,
  email_confirmed_at
from auth.users
where email = 'user@example.com';
```

Use this when someone says:

- "I signed up but cannot log in"
- "Did my verification work?"
- "Did reset password actually finish?"

### Check one user's tier / quota

```sql
select
  u.id as user_id,
  u.email,
  s.tier,
  s.status,
  s.started_at,
  s.expires_at,
  s.daily_messages_used,
  s.monthly_messages_used,
  s.daily_reset_at,
  s.monthly_reset_at
from auth.users u
left join public.subscriptions s on u.id = s.user_id
where u.email = 'user@example.com';
```

Use this when someone says:

- "I bought Essential but still look Free"
- "Why does the app say my quota is used up?"

### Check one user's AI request history

```sql
select
  created_at,
  model,
  request_type,
  input_tokens,
  output_tokens,
  cost_usd,
  latency_ms,
  status,
  error_code,
  error_message,
  fallback_used,
  retry_count
from public.ai_logs
where user_id = (
  select id from auth.users where email = 'user@example.com'
)
order by created_at desc
limit 20;
```

Use this when someone says:

- "Analysis failed"
- "OCR feels slow"
- "Why did I get a weird empty result?"

### Check recent auth diagnostics

```sql
select
  created_at,
  event,
  status,
  email_redacted,
  client_fingerprint,
  platform,
  app_version,
  build_number,
  error_code,
  message,
  metadata
from public.auth_diagnostics
order by created_at desc
limit 100;
```

Use this when someone says:

- "signup confirmation never arrived"
- "forgot password link is weird"
- "reset password opened the app but nothing happened"

### Check recent RevenueCat webhooks

```sql
select
  created_at,
  source,
  event_type,
  user_id,
  payload
from public.webhook_logs
where source = 'revenuecat'
order by created_at desc
limit 50;
```

Use this when someone says:

- "purchase succeeded but tier did not update"
- "restore behaved strangely"
- "why did another account become premium?"

## Revenue / Cost SQL

### Paid users by tier

```sql
select
  tier,
  count(*) as users
from public.real_subscriptions
group by tier
order by users desc;
```

### Paid user list

```sql
select
  u.email,
  s.tier,
  s.status,
  s.started_at,
  s.expires_at
from auth.users u
join public.subscriptions s on u.id = s.user_id
where s.tier != 'free'
order by s.started_at desc;
```

### Monthly revenue

```sql
select *
from public.monthly_revenue
order by month desc;
```

### Monthly profit proxy

```sql
select *
from public.monthly_profit
order by month desc;
```

### Revenue events

```sql
select
  event_timestamp,
  created_at,
  user_id,
  event_type,
  product_id,
  price_usd,
  currency,
  transaction_id
from public.revenue_events
order by event_timestamp desc
limit 50;
```

### AI cost summary

```sql
select
  date(created_at) as date,
  count(*) as calls,
  coalesce(sum(cost_usd), 0) as total_cost_usd
from public.ai_logs
group by date(created_at)
order by date desc
limit 30;
```

## Safe Manual Fixes

Always double-check the target email first.

### Reset daily quota

```sql
update public.subscriptions
set
  daily_messages_used = 0,
  daily_reset_at = now()
where user_id = (
  select id from auth.users where email = 'user@example.com'
);
```

### Reset monthly quota

```sql
update public.subscriptions
set
  monthly_messages_used = 0,
  monthly_reset_at = now()
where user_id = (
  select id from auth.users where email = 'user@example.com'
);
```

### Reset both quota windows

```sql
update public.subscriptions
set
  daily_messages_used = 0,
  monthly_messages_used = 0,
  daily_reset_at = now(),
  monthly_reset_at = now()
where user_id = (
  select id from auth.users where email = 'user@example.com'
);
```

### Force a tier only if you know exactly why

```sql
update public.subscriptions
set
  tier = 'essential',
  status = 'active'
where user_id = (
  select id from auth.users where email = 'user@example.com'
);
```

Do this only for manual repair.
For subscription truth, always cross-check RevenueCat first.

## Security / Retention Operations

### Check active security signals

```sql
select *
from public.security_signals
order by
  case severity
    when 'critical' then 0
    when 'warning' then 1
    else 2
  end,
  detected_at desc;
```

### Check security automation status

```sql
select *
from public.security_automation_status
order by jobname;
```

### Check recent alert delivery history

```sql
select *
from public.security_alert_events
order by last_detected_at desc
limit 20;
```

### Manual cleanup helpers

```sql
select public.cleanup_old_auth_diagnostics();
select public.cleanup_old_webhook_logs();
select public.cleanup_observability_logs();
```

Current default retention:

- `auth_diagnostics`: 14 days
- `webhook_logs`: 30 days
- `ai_logs`: 30 days
- `security_alert_events`: 30 days

Current external alert delivery paths:

- Telegram
- optional generic webhook sink

## Common Mistakes To Avoid

- Do not treat `Supabase` alone as subscription truth.
- Do not treat `restore` under the same Apple ID as an automatic bug.
- Do not edit `public.subscriptions` first and ask questions later.
- Do not use `public.rate_limits` as if it were the subscription quota table.
- Do not expect `public.monthly_profit` to equal real accounting profit.

## Related Docs

- [RevenueCat Ops Guide](./revenuecat-ops-guide.md)
- [Security Hardening Status](./security-hardening-status.md)
- [Security Incident Response](./security-incident-response.md)
- [Security Alerting Setup](./security-alerting-setup.md)
- [App Review Final Checklist](./app-review-final-checklist.md)
- [Current Test Status](./current-test-status-2026-04-03.md)
