# Security Hardening Status

Last updated: 2026-04-05

This file tracks the current security posture of VibeSync at a practical, launch-facing level.

## Current Rating

- Previous rough rating: `6/10`
- After round 1 hardening: `7/10`
- After round 2 hardening: `7.5/10`

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

## Remaining Risks

### 1. `auth_diagnostics` still allows pre-auth insert

This is intentional because signup / resend / forgot-password diagnostics happen before login.

Current mitigation:

- tighter insert policy
- smaller payloads
- retention helpers
- incident-response visibility

Still missing:

- a stronger server-side ingestion path
- automated cleanup / alerting

### 2. Retention is defined, but not yet automated

Current default retention:

- `auth_diagnostics`: 14 days
- `webhook_logs`: 30 days
- `ai_logs`: 30 days

Today this is manual / operator-triggered unless a scheduled job is added later.

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

1. Move auth diagnostics ingestion behind a server-controlled path instead of direct anon insert.
2. Add automated retention scheduling for observability tables.
3. Add anomaly alerts for:
   - unusual auth diagnostics volume
   - unusual webhook volume
   - sudden AI failure spikes
4. Review partner-owned deployment / domain / env access and ensure both founders retain control.
