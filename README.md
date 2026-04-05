# VibeSync

VibeSync is a Flutter + Supabase app for screenshot-based chat analysis and reply coaching.
The product is currently focused on iOS launch readiness, OCR reliability, subscription flow
stability, and launch-facing privacy/security hardening.

## Current Status

Last updated: 2026-04-05

- Current phase: `Phase A - iOS Launch Stabilization`
- Current build under validation: `TestFlight v82`
- Primary workstream:
  - OCR edge-case validation
  - subscription / restore consistency
  - launch checklist / legal / disclosure alignment
  - security hardening and observability

### Already Working

- Auth flows:
  - Apple sign-in
  - Google sign-in
  - email sign-up / verify / resend
  - forgot-password and in-app reset
  - account deletion
- RevenueCat purchase and same-Apple-ID restore / transfer behavior
- `Free -> Essential` refresh back into premium reply generation
- OCR mainline cases:
  - normal chat screenshots
  - LINE quoted replies with layout-first speaker handling
  - screenshot import confirmation and correction flow
- Security hardening rounds 1-6:
  - JWT-verified user-facing edge functions
  - dedicated auth diagnostics ingress
  - observability retention jobs
  - security signals + dashboard visibility
  - external critical alerts pipeline
  - optional second alert sink / webhook delivery

### Still Open Before Launch

- Final OCR edge-case signoff:
  - long screenshots
  - overlapping multi-image imports
  - short continuation messages
  - media / sticker / video bubbles
  - contact-name OCR drift
- Subscription edge cases:
  - `Free -> Starter`
  - `Starter -> Essential`
  - `Essential -> Starter` next-renewal behavior
  - different Apple ID restore
- Launch/legal checks:
  - App Store Connect privacy disclosure
  - privacy / terms final pass
  - support email / support flow final pass

## Read First

These are the current source-of-truth docs for launch work:

- [Current test status](./docs/current-test-status-2026-04-03.md)
- [App review final checklist](./docs/app-review-final-checklist.md)
- [TestFlight regression checklist](./docs/testflight-regression-checklist.md)
- [Launch readiness checklist](./docs/launch-readiness-checklist.md)
- [Supabase ops guide](./docs/supabase-ops-guide.md)
- [RevenueCat ops guide](./docs/revenuecat-ops-guide.md)
- [Security hardening status](./docs/security-hardening-status.md)
- [Security architecture](./docs/security-architecture.md)
- [Security incident response](./docs/security-incident-response.md)
- [Security alerting setup](./docs/security-alerting-setup.md)

## Phase Map

- `Phase A`: [iOS launch stabilization](./docs/phases/phase-a-ios-launch-stabilization.md)
- `Phase B`: [Android / Google Play expansion](./docs/phases/phase-b-android-google-play-expansion.md)
- `Phase C`: [Growth content engine](./docs/phases/phase-c-growth-content-engine.md)
- `Phase D`: [LINE OA automation](./docs/phases/phase-d-line-oa-automation.md)

Historical product/design plans are still kept under `docs/plans/`, but they are baseline
documents, not the current launch truth.

## Platform Truth Sources

Use the right backend depending on the question:

- `Supabase`
  - main operations backend
  - users, tiers, auth diagnostics, AI logs, SQL, revenue/cost views
- `RevenueCat`
  - entitlement truth
  - restore / transfer / same Apple ID behavior
- `App Store Connect`
  - iOS products, subscription groups, upgrade / downgrade timing, privacy disclosure

## Tech Stack

- Frontend: Flutter 3.x + Riverpod
- Backend: Supabase (Auth, Postgres, Edge Functions)
- AI: Anthropic / Claude API via Supabase Edge Functions
- Billing: RevenueCat
- Local storage: Hive

## Local Development

```bash
flutter pub get
flutter run
flutter test
```

Useful alternatives:

```bash
flutter run -d chrome
flutter run -d "iPhone 15 Pro"
flutter devices
```

## Security / Privacy Posture

Current rough security rating: `9.2/10 for an early public launch`, with active monitoring.

This is good enough for a limited early launch, but it is not yet the posture of a mature
high-trust privacy product. Remaining work is mostly:

- keeping privacy disclosure aligned with actual Anthropic processing
- maintaining dual-founder control over infra / secrets / deployment
- continuing OCR and subscription edge-case monitoring after launch

Important privacy reality:

- the app is local-first
- but user-triggered analysis and screenshot recognition are still sent to backend processing
  and Anthropic API
- public-facing copy and App Store disclosure must continue to describe that precisely

## Repo Hygiene

- Do not store live credentials or test account passwords in tracked docs
- Treat `docs/plans/` as historical baseline unless a newer phase/status doc overrides it
- For operational questions, prefer the docs listed in `Read First`
