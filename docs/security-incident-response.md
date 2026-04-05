# Security Incident Response

Last updated: 2026-04-05

This runbook is for suspected security incidents in VibeSync, especially:

- leaked or abused API keys
- suspicious Edge Function behavior
- unexpected premium tier changes
- unusual auth / password-reset activity
- suspected prompt-injection or sensitive-data leakage

## Severity

### SEV-1

Use when there is a credible risk of user-data leakage, active account takeover, or a public production exploit.

Examples:

- service-role key exposure
- malicious requests reaching a sensitive Edge Function
- premium / subscription data being escalated incorrectly at scale
- clear evidence that sensitive chat content was logged or exposed

### SEV-2

Use when there is no confirmed leak yet, but production behavior is abnormal and user trust is at risk.

Examples:

- restore / transfer behavior looks inconsistent across accounts
- auth recovery links behave unpredictably
- webhook processing is failing in a way that might leave wrong entitlements
- observability tables are being spammed

### SEV-3

Use when the issue is contained, low-volume, or mostly internal.

Examples:

- noisy logs
- one-off malformed webhook payloads
- test-environment misconfiguration

## First 15 Minutes

1. Stop the bleeding.
2. Preserve enough evidence to debug safely.
3. Rotate secrets if there is any doubt.
4. Decide whether users need to be warned immediately.

## Immediate Containment

### If an Edge Function looks compromised

1. Disable or temporarily stop calling the affected function from the app/web client.
2. If needed, hotfix the function to return a safe failure.
3. Check:
   - `Supabase -> Edge Functions -> Logs`
   - `public.ai_logs`
   - `public.auth_diagnostics`
   - `public.webhook_logs`

### If a secret may be exposed

Rotate in this order:

1. `SUPABASE_SERVICE_ROLE_KEY`
2. `CLAUDE_API_KEY`
3. `REVENUECAT_WEBHOOK_SECRET`
4. any RevenueCat server-side API key
5. GitHub Actions / Vercel env vars if they touched the same integration

After rotating:

1. update Supabase project secrets
2. update GitHub Actions secrets
3. update Vercel env vars if relevant
4. redeploy affected Edge Functions

### If subscription state looks wrong

Check all three systems before changing user data:

1. `Supabase`
   - `public.subscriptions`
   - `public.revenue_events`
   - `public.webhook_logs`
2. `RevenueCat`
   - customer profile
   - entitlement status
   - transfer history
3. `App Store Connect`
   - subscription group / product status if the problem is store-side

Do not assume Supabase alone is the source of truth for restore / transfer incidents.

## Investigation Queries

### Auth diagnostics

```sql
select
  created_at,
  event,
  status,
  email_redacted,
  error_code,
  message,
  metadata
from public.auth_diagnostics
order by created_at desc
limit 100;
```

### Recent webhook activity

```sql
select
  created_at,
  source,
  event_type,
  user_id,
  payload
from public.webhook_logs
order by created_at desc
limit 100;
```

### Recent AI failures

```sql
select
  created_at,
  user_id,
  model,
  request_type,
  status,
  error_code,
  error_message
from public.ai_logs
where status in ('failed', 'filtered')
order by created_at desc
limit 100;
```

## Recovery

After containment:

1. patch the root cause
2. redeploy affected functions
3. retest the exact failure path
4. verify the logs stop growing abnormally
5. verify a normal user flow still works
6. check whether `public.security_signals` and `public.security_alert_events` have returned to a healthy state

Minimum re-verification checklist:

- auth sign-in / sign-up still works
- password reset still works
- subscription sync still works
- premium users keep the correct tier
- OCR / analysis requests still return normally

## Communication

### Internal

Record:

- when the incident started
- who first noticed it
- what systems were involved
- what was disabled or rotated
- what user impact is confirmed vs still unknown

### User-facing

If user data may have been exposed, prepare:

- what happened
- what data may be affected
- what the user should do next
- what was already fixed

Do not overstate certainty before the root cause is confirmed.

## Post-Incident

Always create a short postmortem with:

1. symptom
2. root cause
3. blast radius
4. fix
5. prevention change

Also update:

- `docs/security-hardening-status.md`
- `AGENTS.md`
- `CLAUDE_CODE_HANDOFF_2026-03-16.md`

## Retention / Cleanup

The repo now includes helper SQL functions:

```sql
select public.cleanup_old_auth_diagnostics();
select public.cleanup_old_webhook_logs();
select public.cleanup_observability_logs();
select public.invoke_security_alerts_job();
```

Default retention:

- `auth_diagnostics`: 14 days
- `webhook_logs`: 30 days
- `ai_logs`: 30 days

These cleanup jobs are now scheduled automatically with `pg_cron`.

Security alerts are also scheduled automatically, but only work end-to-end if the following secrets are configured:

- Supabase Vault:
  - `security_alert_project_url`
  - `security_alert_anon_key`
  - `security_alert_secret`
- Edge Function secrets:
  - `SECURITY_ALERT_SECRET`
  - `TELEGRAM_BOT_TOKEN`
  - `TELEGRAM_SECURITY_CHAT_ID` (or fallback `TELEGRAM_CHAT_ID`)
  - optional second sink:
    - `SECURITY_ALERT_WEBHOOK_URL`
    - `SECURITY_ALERT_WEBHOOK_BEARER_TOKEN`

Manual checks still matter during incidents:

```sql
select * from public.security_signals;
select * from public.security_alert_events order by last_detected_at desc limit 20;
select * from public.security_automation_status order by jobname;
```

Operator setup reminders:

- the `security-alerts` cron job will only work when both sides are configured:
  - Supabase Vault secrets for invocation
  - Edge Function secrets for delivery
- if alerts stop arriving, check both:
  - `public.security_automation_status`
  - `public.security_alert_events`
