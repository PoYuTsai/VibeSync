# Security Alerting Setup

Last updated: 2026-04-05

This guide covers the new security alerting path for VibeSync.

## What It Does

Critical security signals are no longer dashboard-only.

The current path is:

1. `public.security_signals`
2. `pg_cron` job `vibesync-security-alerts-every-10m`
3. `public.invoke_security_alerts_job()`
4. Edge Function `security-alerts`
5. `public.security_alert_events`
6. external delivery

## Required Setup

### Supabase Vault

Create these Vault secrets:

- `security_alert_project_url`
- `security_alert_anon_key`
- `security_alert_secret`

Expected values:

- `security_alert_project_url`
  - your Supabase project URL
- `security_alert_anon_key`
  - your Supabase anon key
- `security_alert_secret`
  - a strong shared secret used only for the `security-alerts` function

### Edge Function Secrets

Set these secrets for the `security-alerts` function:

- `SECURITY_ALERT_SECRET`
- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_SECURITY_CHAT_ID`

Optional second sink:

- `SECURITY_ALERT_WEBHOOK_URL`
- `SECURITY_ALERT_WEBHOOK_BEARER_TOKEN`
- `SECURITY_ALERT_WEBHOOK_TIMEOUT_MS`

Optional fallback:

- `TELEGRAM_CHAT_ID`

## Quick Checks

### Signals

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

### Automation Status

```sql
select *
from public.security_automation_status
order by jobname;
```

### Recent Deliveries

```sql
select *
from public.security_alert_events
order by last_detected_at desc
limit 20;
```

## Manual Trigger

```sql
select public.invoke_security_alerts_job();
```

## Healthy State

You should see:

- `security_signals`
  - usually empty, or only occasional warnings
- `security_automation_status`
  - all expected jobs present
  - `active = true`
  - recent successful runs
- `security_alert_events`
  - recent `sent`, `suppressed`, or `skipped_no_channel` rows depending on setup

## Common Failure Modes

### No alert rows appear at all

Check:

- migration applied
- `pg_cron` enabled
- `vibesync-security-alerts-every-10m` exists in `public.security_automation_status`

### Cron job exists but delivery never happens

Check:

- Vault secrets exist and are spelled correctly
- `invoke_security_alerts_job()` can run successfully

### Alert rows exist but status is `skipped_no_channel`

Check:

- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_SECURITY_CHAT_ID`

### Telegram works but the second sink never fires

Check:

- `SECURITY_ALERT_WEBHOOK_URL`
- `SECURITY_ALERT_WEBHOOK_BEARER_TOKEN` if your endpoint requires auth
- whether the receiving endpoint accepts JSON `POST`
- whether the endpoint is timing out before `SECURITY_ALERT_WEBHOOK_TIMEOUT_MS`

### Alert rows exist but status is `failed`

Check:

- Telegram token/chat pair
- function logs for `security-alerts`
- whether the cooldown is hiding repeats after a first failed or sent event

## Related Docs

- [security-hardening-status.md](/C:/Users/eric1/OneDrive/Desktop/VibeSync/docs/security-hardening-status.md)
- [security-incident-response.md](/C:/Users/eric1/OneDrive/Desktop/VibeSync/docs/security-incident-response.md)
- [supabase-ops-guide.md](/C:/Users/eric1/OneDrive/Desktop/VibeSync/docs/supabase-ops-guide.md)
