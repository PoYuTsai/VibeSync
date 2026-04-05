# VibeSync Security Architecture

Last updated: 2026-04-05

This document describes the practical security boundaries for the current
VibeSync launch architecture.

## Current Security Goal

VibeSync is targeting:

- safe enough for an early public iOS launch
- strong enough to limit common indie-app failure modes
- observable enough that suspicious behavior can be detected and investigated

It is **not** yet the posture of a fully mature, high-trust privacy product.

## System Boundaries

### Client

The Flutter app is responsible for:

- user authentication
- local conversation storage
- screenshot selection and pre-upload compression
- initiating analysis / OCR / billing sync / diagnostics requests

The client must **not** hold:

- Anthropic API secrets
- Supabase service-role credentials
- RevenueCat server credentials

The client **does** hold:

- Supabase anon key
- RevenueCat public SDK key

Those are acceptable client-side values.

### Supabase Edge Functions

Edge Functions are the main trust boundary for privileged server actions.

Current key functions:

- `analyze-chat`
- `submit-feedback`
- `sync-subscription`
- `delete-account`
- `auth-diagnostics`
- `revenuecat-webhook`
- `security-alerts`

Rules:

- user-facing functions should verify JWT
- webhook / pre-auth ingress must be explicit and narrowly scoped
- privileged writes should happen with service-role authority only on the server

### Database

Postgres holds:

- subscriptions
- revenue events
- AI logs
- auth diagnostics
- webhook logs
- security alert events

Operational tables are protected by:

- RLS where appropriate
- admin-only read paths
- service-role-owned maintenance functions
- retention cleanup jobs

### Third-Party Services

- `Anthropic`
  - used for screenshot recognition / analysis generation
- `RevenueCat`
  - used for mobile subscription truth
- `Telegram`
  - current external alert sink
- optional generic webhook sink
  - second alert delivery path

## Sensitive Data Classes

### Highest sensitivity

- `CLAUDE_API_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- RevenueCat server-side credentials / webhook secret
- security alert shared secrets

These must never ship in the client or tracked repo docs.

### Medium sensitivity

- auth diagnostics metadata
- webhook event summaries
- AI operational logs
- screenshot-derived conversation structure

These require:

- minimal retention
- minimal payload size
- no unnecessary raw content persistence

### Lower sensitivity

- Supabase project URL
- Supabase anon key
- public RevenueCat SDK key
- bundle identifiers

These are not private secrets, but should still be handled cleanly.

## Main Trust Boundaries

### 1. App -> Edge Function

For normal authenticated flows:

- app sends Supabase JWT
- edge function validates JWT
- function performs server-side checks
- function talks to Anthropic / RevenueCat / database

### 2. Pre-auth diagnostics

Auth diagnostics must work before login for:

- sign-up
- resend verification
- forgot password

This is why `auth-diagnostics` is a dedicated ingress function instead of a
direct public table insert.

Current protections:

- server-side validation
- hashed client fingerprint
- coarse throttling
- smaller payloads
- retention cleanup

### 3. Third-party webhook ingress

`revenuecat-webhook` is intentionally webhook-style ingress.

Its boundary is:

- webhook secret validation
- restricted purpose
- reduced payload persistence
- downstream sync into app-facing subscription state

## Data Handling Reality

VibeSync is local-first, but not local-only.

Current real behavior:

- conversations are stored locally on device
- when the user explicitly triggers analysis / OCR, the minimum necessary request
  content is sent through backend processing
- Anthropic processes that request content

Implication:

- privacy policy
- App Store privacy disclosure
- in-app copy

must all describe that reality precisely.

## Observability / Abuse Controls

Current controls in place:

- `ai_logs`
- `auth_diagnostics`
- `webhook_logs`
- `security_signals`
- `security_alert_events`
- nightly retention cleanup
- cron health visibility
- external critical alert delivery

This means suspicious patterns now have:

- local visibility in the admin dashboard
- persistent alert state
- external delivery for critical signals

## Current Security Strengths

- client does not hold privileged AI / service-role keys
- user-facing functions now default to JWT verification
- auth diagnostics no longer write directly from client to table
- webhook logs store reduced summaries instead of raw payload blobs
- security logs now have scheduled retention
- critical anomalies can leave the dashboard through alert channels
- admin dashboard data is now served through server-side API routes instead of
  browser-side direct database reads

## Current Security Gaps

These are still real, even after the latest rounds:

1. The product still depends on third-party processing for user-triggered analysis.
2. Privacy trust still depends on accurate disclosure and disciplined retention.
3. Infrastructure ownership and secret rotation must remain shared across founders.
4. OCR correctness and billing correctness are product-trust issues, not just UX issues.

## Launch Rating

Current rough security rating:

- `9.2/10 for an early public launch`

Meaning:

- good enough to launch with active monitoring
- not yet a finished enterprise-grade privacy posture

## Most Important Operational Docs

- [security-hardening-status.md](/C:/Users/eric1/OneDrive/Desktop/VibeSync/docs/security-hardening-status.md)
- [security-incident-response.md](/C:/Users/eric1/OneDrive/Desktop/VibeSync/docs/security-incident-response.md)
- [security-alerting-setup.md](/C:/Users/eric1/OneDrive/Desktop/VibeSync/docs/security-alerting-setup.md)
- [supabase-ops-guide.md](/C:/Users/eric1/OneDrive/Desktop/VibeSync/docs/supabase-ops-guide.md)
