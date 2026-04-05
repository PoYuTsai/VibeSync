# Security Hardening Status

Last updated: 2026-04-05

This file tracks the current security posture of VibeSync at a practical, launch-facing level.

## Current Rating

- Previous rough rating: `6/10`
- After round 1 hardening: `7/10`
- After round 2 hardening: `7.5/10`
- After round 3 hardening: `8/10`
- After round 4 hardening: `8.5/10`
- After round 5 hardening: `9/10`
- After round 6 hardening: `9.2/10`

This is good enough for an early public launch with active monitoring.
It is not yet the posture of a mature, high-trust privacy product.

## What Is Now Hardened

### Round 1

- User-facing Edge Functions now deploy with JWT verification by default.
- Webhook-style ingress remains explicit:
  - `revenuecat-webhook`
  - `auth-diagnostics`
- Those ingress functions are now declared in `supabase/config.toml` with `verify_jwt = false` instead of relying on ad-hoc CLI deploy flags.
- `sync-subscription` no longer has a repo-side RevenueCat key fallback.
- RevenueCat webhook logs now store a reduced payload summary instead of raw full payloads.

### Round 2

- `auth_diagnostics` now has stricter schema-level limits:
  - constrained event format
  - allowed platform values
  - bounded field lengths
  - bounded metadata size
  - bounded insert timestamps
- App-side auth diagnostics now do lightweight dedupe and metadata shrinking before insert.
- Retention helper SQL functions now exist for:
  - `auth_diagnostics`
  - `webhook_logs`
  - combined observability cleanup
- Those cleanup functions are not left open as public RPC surfaces; execute permission is revoked from `PUBLIC / anon / authenticated`.
- A formal incident-response runbook now exists:
  - [security-incident-response.md](/C:/Users/eric1/OneDrive/Desktop/VibeSync/docs/security-incident-response.md)

### Round 3

- Auth diagnostics ingestion is no longer a direct client -> table write.
- A dedicated `auth-diagnostics` Edge Function now sits in front of the table.
- That function adds:
  - server-side payload validation
  - hashed client fingerprinting
  - coarse abuse throttling over recent windows
  - service-role-owned insertion
- The client now calls that function instead of inserting into `public.auth_diagnostics` directly.

### Round 4

- Observability/security cleanup is no longer manual-only:
  - `pg_cron` now schedules nightly `cleanup_observability_logs()`
  - `pg_cron` history now has its own retention cleanup job
- A new `security_signals` view now surfaces active anomalies across:
  - `auth_diagnostics`
  - `ai_logs`
  - `webhook_logs`
  - security cleanup cron jobs
- A new `security_automation_status` view now exposes whether the cleanup jobs are active and when they last ran.
- `admin-dashboard` now has a `Security` page for these signals and automation states.

### Round 5

- Critical security signals now have external delivery instead of being dashboard-only:
  - new Edge Function: `security-alerts`
  - delivery channel: Telegram
- Alert state is now persisted in:
  - `public.security_alert_events`
- Delivery is now cooldown-aware and deduplicated per `signal_key + severity + channel`, which reduces alert spam during noisy periods.
- `pg_cron` + `pg_net` now invoke the alert function every 10 minutes through a Vault-backed helper:
  - `public.invoke_security_alerts_job()`
- `admin-dashboard` `Security` page now shows:
  - active signals
  - cron automation health
  - recent alert deliveries / failures / suppressed cooldown events
- The alert job is now defined in a more idempotent way, so repeated setup runs do not silently create duplicate cron jobs.
- OCR recognize-only requests now use a lighter thread-context window and smarter image resizing bounds, improving screenshot-analysis payload size without changing the product flow.

### Round 6

- Security alert delivery is no longer Telegram-only:
  - optional second sink: generic webhook delivery
- Alert dedupe/cooldown logic now works per signal + severity + channel, so a second channel can be added without breaking existing Telegram behavior.
- Internal test-account quota bypasses are no longer hardcoded in repo code:
  - `analyze-chat` now reads `TEST_ACCOUNT_EMAILS` from Edge Function env
- Source-of-truth security docs have been cleaned up:
  - `security-architecture.md`
  - `ocr-analysis-maturity-benchmark.md`

## Remaining Risks

### 1. `auth_diagnostics` still supports pre-auth ingestion

This is intentional because signup / resend / forgot-password diagnostics happen before login.

Current mitigation:

- dedicated edge-function ingress
- tighter schema policy
- smaller payloads
- hashed client fingerprinting
- coarse rate limiting
- retention helpers
- incident-response visibility

Still missing:

- finer-grained anomaly tuning as production volume becomes clearer
- secondary notification channels beyond Telegram

### 2. Secret / ownership hygiene still matters

Current default retention:

- `auth_diagnostics`: 14 days
- `webhook_logs`: 30 days
- `ai_logs`: 30 days

These windows are now scheduled automatically, and critical alerts can be pushed externally.

The remaining risk is operational:

- secrets must be rotated cleanly
- both founders should retain admin access
- alert secrets / Telegram routing should not live with only one person

### 3. Privacy disclosure still matters

The app is local-first, but user-triggered analysis still sends content to backend processing and Anthropic API.

That must stay aligned across:

- privacy policy
- App Store privacy disclosure
- in-app user-facing copy

### 4. Single-owner infrastructure risk

The partner-managed Vercel deployment is acceptable short term, but long term admin access and ownership should not sit with only one person.

## Most Important Files

- [security-architecture.md](/C:/Users/eric1/OneDrive/Desktop/VibeSync/docs/security-architecture.md)
- [security-incident-response.md](/C:/Users/eric1/OneDrive/Desktop/VibeSync/docs/security-incident-response.md)
- [security-alerting-setup.md](/C:/Users/eric1/OneDrive/Desktop/VibeSync/docs/security-alerting-setup.md)
- [supabase-ops-guide.md](/C:/Users/eric1/OneDrive/Desktop/VibeSync/docs/supabase-ops-guide.md)

## Next Recommended Security Upgrades

1. Review partner-owned deployment / domain / env access and ensure both founders retain control.
2. Tighten privacy disclosure and in-app copy so Anthropic processing / retention is described precisely and consistently.
3. Add alert escalation policy, not just technical delivery paths, so critical signals have a human owner and response-time expectation.
