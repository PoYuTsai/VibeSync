# Security Hardening Status

Last updated: 2026-04-05

This file tracks the current security posture of VibeSync at a practical, launch-facing level.

## Current Rating

- Previous rough rating: `6/10`
- After round 1 hardening: `7/10`
- After round 2 hardening: `7.5/10`
- After round 3 hardening: `8/10`
- After round 4 hardening: `8.5/10`

This is good enough for an early public launch with active monitoring.
It is not yet the posture of a mature, high-trust privacy product.

## What Is Now Hardened

### Round 1

- User-facing Edge Functions now deploy with JWT verification by default.
- `revenuecat-webhook` remains webhook-only and is the only function intentionally deployed with `--no-verify-jwt`.
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

- automated cleanup / alerting
- stronger anomaly detection

### 2. Alerting is still operator-driven

Current default retention:

- `auth_diagnostics`: 14 days
- `webhook_logs`: 30 days
- `ai_logs`: 30 days

These windows are now scheduled automatically, but alerts still need a human to look at the dashboard or run checks.

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
- [supabase-ops-guide.md](/C:/Users/eric1/OneDrive/Desktop/VibeSync/docs/supabase-ops-guide.md)

## Next Recommended Security Upgrades

1. Add external alert delivery (email/Slack/Telegram) for critical security signals.
2. Review partner-owned deployment / domain / env access and ensure both founders retain control.
3. Tighten privacy disclosure and in-app copy so Anthropic processing / retention is described precisely and consistently.
