# VibeSync Project

## Current Snapshot

Last updated: 2026-04-05

```text
Current phase: Phase A / iOS Launch Stabilization
Current build: TestFlight v82
Primary goal: launch-safe, stable, privacy-aligned iOS release
Primary workstream: OCR edge validation + subscription consistency + launch checklist + security hardening
```

## Read First In Every New Session

Use these files as the current source of truth:

- `docs/current-test-status-2026-04-03.md`
- `docs/app-review-final-checklist.md`
- `docs/testflight-regression-checklist.md`
- `docs/launch-readiness-checklist.md`
- `docs/supabase-ops-guide.md`
- `docs/revenuecat-ops-guide.md`
- `docs/security-hardening-status.md`
- `docs/security-architecture.md`
- `docs/security-incident-response.md`
- `docs/security-alerting-setup.md`
- `docs/ocr-analysis-maturity-benchmark.md`
- `docs/flutter-test-debt-2026-04-05.md` - full `flutter test` 目前仍有一批落後現況的 legacy widget/screen tests；blocking CI 改跑 curated smoke suite
- `docs/discord-vibesync-troubleshooting.md`

## Current Truth

### Working

- Auth:
  - Apple sign-in
  - Google sign-in
  - email sign-up / verify / resend
  - forgot-password / in-app reset
  - account deletion
- Subscription:
  - RevenueCat purchase flow
  - same Apple ID restore / transfer
  - `Free -> Essential` re-analysis refresh
- OCR:
  - mainline screenshot recognition
  - LINE quoted reply handling
  - append vs new conversation confirmation
  - editable OCR correction before import
  - 2026-04-05 reliability rollback: restored fuller screenshot context, OCR retries, parse-failure retry, and conservative image compression after a recognition regression
- Security:
  - JWT-verified user-facing edge functions
  - auth diagnostics ingress function
  - retention automation
  - security signals dashboard
  - external critical alerts pipeline
  - optional second alert sink / webhook delivery

### Still Open Before iOS Launch

- OCR edge-case signoff:
  - long screenshots
  - overlapping multi-image imports
  - short continuation bubbles
  - media / sticker / video bubbles
  - name drift / small-text OCR
- Subscription edge cases:
  - `Free -> Starter`
  - `Starter -> Essential`
  - `Essential -> Starter`
  - different Apple ID restore
- Launch/legal:
  - App Store Connect privacy disclosure
  - final privacy / terms / support flow verification

## Platform Truth Sources

- `Supabase`
  - main ops backend
  - users, tiers, auth diagnostics, AI logs, SQL, revenue/cost views
- `RevenueCat`
  - entitlement truth
  - restore / transfer behavior
  - same Apple ID subscription behavior
- `App Store Connect`
  - iOS product rules
  - subscription group behavior
  - upgrade / downgrade timing
  - privacy disclosure

## Phase Map

- `Phase A`: `docs/phases/phase-a-ios-launch-stabilization.md`
- `Phase B`: `docs/phases/phase-b-android-google-play-expansion.md`
- `Phase C`: `docs/phases/phase-c-growth-content-engine.md`
- `Phase D`: `docs/phases/phase-d-line-oa-automation.md`

Historical planning docs under `docs/plans/` remain useful context, but they are baseline
documents, not the current operational truth.

## Collaboration Workflow

- Discord live bot:
  - bug reports
  - short syncs
  - tester updates
  - quick coordination
- Claude:
  - new phase specification
  - MVP definition
  - frontend / backend scope
  - implementation plans
- Codex:
  - coding
  - debugging
  - logic validation
  - security hardening
  - code review
  - documentation sync

Rules:

- Do not run long phase-planning inside the Discord live thread
- Use one thread per major phase
- Use separate bug threads for Phase A regressions so launch work does not mix with future-phase planning

## Security Posture

Current rough rating: `9.2/10 for an early public launch`

Good enough for limited early launch, but not yet a mature high-trust privacy posture.
Keep monitoring:

- OCR trust / correctness
- subscription state consistency
- privacy disclosure accuracy
- infra ownership / secret rotation hygiene

## Repo Hygiene

- Do not store live credentials or test account passwords in tracked files
- Prefer ASCII or clean UTF-8 docs; avoid mojibake-heavy edits
- Use current launch docs above before relying on older notes
