# VibeSync Project

## gstack

This repo has gstack installed for Claude and Codex.

- Prefer `/gstack-review` for pre-landing code review
- Prefer `/gstack-investigate` for deep bug investigation
- Prefer `/gstack-cso` for security review
- Prefer `/gstack-document-release` when syncing docs after major work
- If repo-local gstack skills stop working for Claude, run:

```bash
cd .claude/skills/gstack && ./setup --prefix
```

## Current Snapshot

Last updated: 2026-04-05

```text
Current phase: Phase A / iOS Launch Stabilization
Current build: TestFlight v82
Primary goal: stable iOS launch with safe OCR, stable subscription behavior, and clean launch docs
```

### Already Working

- Auth mainline:
  - Apple sign-in
  - Google sign-in
  - email sign-up / verify / resend
  - forgot-password / in-app reset
  - account deletion
- Subscription mainline:
  - RevenueCat purchase
  - same Apple ID restore / transfer
  - `Free -> Essential` premium refresh on re-analysis
- OCR mainline:
  - screenshot import
  - LINE quoted reply handling
  - edit-before-import flow
- Security hardening rounds 1-6 completed

### Remaining Before Launch

- OCR edge-case signoff
- Starter upgrade / downgrade signoff
- different Apple ID restore signoff
- App Store Connect privacy disclosure final pass
- privacy / terms / support flow final verification

## Read Order

Always start from these docs:

1. `docs/current-test-status-2026-04-03.md`
2. `docs/app-review-final-checklist.md`
3. `docs/testflight-regression-checklist.md`
4. `docs/launch-readiness-checklist.md`
5. `docs/supabase-ops-guide.md`
6. `docs/revenuecat-ops-guide.md`
7. `docs/security-hardening-status.md`
8. `docs/security-architecture.md`
9. `docs/security-incident-response.md`
10. `docs/security-alerting-setup.md`

Then use these as needed:

- `docs/phases/phase-a-ios-launch-stabilization.md`
- `docs/phases/phase-b-android-google-play-expansion.md`
- `docs/phases/phase-c-growth-content-engine.md`
- `docs/phases/phase-d-line-oa-automation.md`

## Platform Truth Sources

- `Supabase`
  - ops backend
  - users, tiers, auth diagnostics, AI logs, revenue/cost views
- `RevenueCat`
  - entitlement truth
  - restore / transfer
  - same Apple ID behavior
- `App Store Connect`
  - iOS billing rules
  - subscription groups
  - upgrade / downgrade timing
  - privacy disclosure

## Working Rules

- Do not rely on archived v41-era notes or mojibake-heavy historical sections
- Treat `docs/plans/` as baseline / historical context unless newer launch docs override them
- Do not store test passwords or live credentials in tracked docs
- Use separate conversation threads for:
  - Phase planning
  - launch bug fixing
  - post-launch growth work

## Phase Workflow

- `Phase A`: iOS launch stabilization
- `Phase B`: Android / Google Play expansion
- `Phase C`: Growth content engine
- `Phase D`: LINE OA automation

Planning workflow:

1. Use Claude to define spec / MVP / backend/frontend scope
2. Land a phase doc
3. Create an implementation plan
4. Hand code/debug/review to Codex

Launch bug workflow:

1. Open a dedicated bug thread
2. Read current launch docs
3. Investigate and fix without mixing future-phase planning into the same thread

## Skill Routing

When the user request clearly matches an installed skill, prefer the skill workflow first.

- Bugs / regressions / root cause: `/gstack-investigate`
- Code review / merge safety: `/gstack-review`
- Security audit / threat review: `/gstack-cso`
- Documentation sync after major work: `/gstack-document-release`
- New product idea / phase brainstorming: `/gstack-office-hours`
- Architecture / execution plan review: `/gstack-plan-eng-review`
