# VibeSync Project Context

> Shared project guidance for Codex and Claude Code. Keep this file lean; load detailed docs only when the task needs them.

## Product

- VibeSync is an AI dating coach for Traditional Chinese users.
- Current stage: TestFlight dogfood and App Review readiness stabilization.
- Core product: Coach 1:1, Opener, analyze-chat, and Practice.
- Stack: Flutter, Riverpod, Supabase Auth/Postgres/Edge Functions, RevenueCat, and encrypted Hive.

## Authority And Routing

- Global authority and routing rules apply; this file records only project-specific deltas.
- Product feel and consequential product/payment/data tradeoffs remain Eric's decision.

## Context Loading

- Do not automatically read `docs/snapshot.md`, `docs/shared-agent-rules.md`, review queues, old plans, handoffs, logs, or git history at session start.
- Start from the current request, `git status`, nearby code, relevant tests, and the smallest useful document section.
- Read `docs/snapshot.md` only for project-stage orientation or a real handoff.
- Read `docs/shared-agent-rules.md` only for migration, deployment, high-risk review, or closeout details.
- Search `docs/reviews/ai-arbitration-queue.md` only when the task concerns an explicitly open review item.
- Prefer current code, tests, live service evidence, and recent commits over old chat memory or screenshots.

## Critical Gotchas

- High-risk areas: subscription/paywall/quota/RevenueCat/429, auth/account deletion/Hive, `analyze-chat`, Opener, OCR, Edge schemas, and AI prompt/token/cost behavior.
- Free users keep core access until quota is actually exhausted. Model limits and format failures are not paywalls.
- Never run `supabase db push` against production. Use the targeted migration procedure in `docs/shared-agent-rules.md`.
- `analyze-chat` deployment requires `--no-verify-jwt`.
- OCR changes stay isolated unless the task explicitly requires a cross-cutting change.

## Development And Delivery

- Eric develops VibeSync on Windows and tests on a physical iPhone. He has no local Mac or Xcode. Never assume local macOS tooling or ask him to run `xcodebuild`; use Windows-capable checks locally and the repository's GitHub macOS runner for iOS build evidence.
- For an authorized Change/Fix task that changes runtime code or configuration, choose the delivery path from the branch at task start. On `main`: verify, commit, safely complete any prerequisite targeted migration, pass the Edge pre-push audit, push `main`, then monitor task-relevant Edge delivery and exact-SHA `Build & Distribute`. On a non-`main` task branch: verify, commit, push that branch, run exact-SHA `Build & Distribute`, and leave production migration/Edge delivery pending until landing on `main` is separately authorized. Never push migration-dependent Edge code to `main` before its required migration is verified.
- Pushing `main` or `develop` automatically starts `Build & Distribute`; monitor that run instead of dispatching a duplicate. On another pushed branch, dispatch `.github/workflows/distribute.yml` for that exact branch/SHA and monitor it.
- Edge Function and migration operations must follow `docs/shared-agent-rules.md`. Never use `supabase db push`. Do not redeploy an Edge Function twice when the push-triggered workflow already covers it.
- `Release to App Stores` and TestFlight/App Store submission remain Eric's manual action. Do not trigger `.github/workflows/release.yml`; a generic “ship” or “release” request is not permission to do so.
- Discussion, inspection, planning, review-only, and documentation-only tasks do not ship product. A mixed task with any runtime code/config change is a Change/Fix task. A current request such as “local only,” “do not push,” or “do not deploy” overrides the standing delivery default.

## Work And Verification

- Before Git, Flutter, build, or test work, read `.agent/environment.json` and use the versioned environment resolver/doctor. The contract is routing and pin data, never authorization; VibeSync Git index and Flutter artifacts belong to WSL, while Windows-only commands are listed separately.
- Keep one commit to one concern and use Traditional Chinese commit messages.
- Verify with the smallest meaningful command, then broaden in proportion to risk.
- For material R2/R3 review, invoke the configured reviewers directly through the shared review workflow; do not ask Eric to carry a Review Packet manually.
- Beyond the global state ladder, dogfood-approved is a further separate state.
- VibeSync runtime Change/Fix tasks have Eric's standing authorization for the delivery steps above, including pushing the branch where the task started (including `main`) and `Build & Distribute` GitHub Actions usage, within the task's original scope. This does not authorize merging/rebasing a non-`main` task branch into `main`. Destructive or ambiguous data changes, expanded product scope, credentials, other paid actions, and App Store release still require current explicit authorization.
- End every task in plain Traditional Chinese with the outcome, expected behavior, and Eric's next check. For Change/Fix tasks also include: Git commit/branch/push state, Edge/migration state, exact-SHA `Build & Distribute` result and URL, what Eric should test on his iPhone, and anything intentionally not run.

## On-Demand References

- Current stage: `docs/snapshot.md`
- Operational rules: `docs/shared-agent-rules.md`
- Product decisions: `docs/decisions.md`
- Durable bug history: `docs/bug-log.md`
- Launch: `docs/testflight-regression-checklist.md`, `docs/app-review-final-checklist.md`, `docs/launch-readiness-checklist.md`
- Integrations: `docs/integrations/`
- Reviews: `docs/reviews/`
- Context design: `docs/ai-harness/context-management.md`
