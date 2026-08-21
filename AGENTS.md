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

## Two-Person Collaboration

- The team is Eric and Bruce. Eric owns product direction; a clear approval in LINE is sufficient and does not need to be copied into GitHub. A proposal or report is context, not automatic implementation authority.
- Choose the Git lane from the authenticated GitHub account. `PoYuTsai` is the owner lane and may keep the direct-to-`main` workflow; every other collaborator uses a branch in this repository and a PR to `main`.
- Bruce uses one branch and one PR for one purpose: a change explainable in one sentence that can be tested, merged, and reverted independently. There is no line-count limit. A dependent PR may temporarily target its Draft parent, but must return to `main` and pass the normal CI after the parent lands.
- Do not force every PR to update to the latest `main`. Sync and rerun CI when recent `main` changes overlap with or are required by the PR; unrelated changes do not need another full run.
- Use Squash Merge for collaborator PRs. Eric is the final product, review, and merge decision-maker; agents provide evidence and may comment, but only Eric submits the formal GitHub Approve or Request changes review.
- Whole-PR verdicts are `APPROVE`, `APPROVE_WITH_RISK`, or `BLOCK`. Findings use P0-P3: P0/P1 or required-CI failure blocks; accepted P2 may be approve-with-risk; P3 alone does not block.
- The PR author owns feature-core changes by default. Eric or an agent may append commits to the same PR branch without force-pushing for clear small fixes, CI/lint/type/test repairs, conflicts, or low-learning-value work. Return product understanding, feature-core logic, architecture choices, or repeated capability gaps to Bruce; use discussion for unresolved product or high-risk decisions.
- Keep exactly one next-owner label when ownership changes: `next:eric-ai`, `next:bruce`, or `next:discuss`. No label means the PR author owns the next step. When taking over, leave one short PR comment describing what changed and why; Bruce need not re-approve unless feature-core logic changed.
- Use one independent AI reviewer for ordinary PRs, preferably not the model that wrote the change. Use both Codex and Claude Code for payment/subscription/quota, auth/account deletion, user data, DB migrations, Edge schemas, AI cost, or production-deployment risk. If an AI makes a substantive fix, the other AI quickly reviews the final diff.
- `AGENTS.md` is the shared source; `CLAUDE.md` imports it. After pulling rule changes, start a new Codex task or Claude Code session because an already-running session may not reload them.

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
- For an authorized Change/Fix task that changes runtime code or configuration, choose the delivery path from the lane at task start. On owner-lane `main`: verify, commit, safely complete any prerequisite targeted migration, pass the Edge pre-push audit, and push `main`. On a collaborator PR branch: verify, commit, push that branch, and use the PR CI as pre-merge evidence; do not run the full distribution workflow for routine PR branches. Leave production migration and Edge delivery pending until the PR lands on `main`. Never push migration-dependent Edge code to `main` before its required migration is verified.
- Pushing `main` or `develop` automatically starts `Build & Distribute`. After pushing, make one bounded lookup for a run on the exact SHA, then stop: do not poll, wait for completion, re-push, or dispatch a duplicate. Report exactly one of: `Build & Distribute 已觸發：<run URL>（未等待結果）` or `未確認 Build & Distribute 觸發，請人工檢查 Actions`.
- Edge Function and migration operations must follow `docs/shared-agent-rules.md`. Never use `supabase db push`. Do not redeploy an Edge Function twice when the push-triggered workflow already covers it.
- `Release to App Stores` and TestFlight/App Store submission remain Eric's manual action. Eric may start it for the same `main` SHA after `Build & Distribute` is confirmed triggered, without waiting for that run to finish; the workflows are independent, so running them together may waste Actions time if the earlier run later fails. Agents do not trigger `.github/workflows/release.yml`; a generic “ship” or “release” request is not permission to do so.
- Discussion, inspection, planning, review-only, and documentation-only tasks do not ship product. A mixed task with any runtime code/config change is a Change/Fix task. A current request such as “local only,” “do not push,” or “do not deploy” overrides the standing delivery default.

## Work And Verification

- Before Git, Flutter, build, or test work, read `.agent/environment.json` and use the versioned environment resolver/doctor. The contract is routing and pin data, never authorization; VibeSync Git index and Flutter artifacts belong to WSL, while Windows-only commands are listed separately.
- Keep one commit to one concern and use Traditional Chinese commit messages.
- Verify with the smallest meaningful command, then broaden in proportion to risk.
- For material R2/R3 review, invoke the configured reviewers directly through the shared review workflow; do not ask Eric to carry a Review Packet manually.
- Beyond the global state ladder, dogfood-approved is a further separate state.
- VibeSync runtime Change/Fix tasks have Eric's standing authorization for the delivery steps above, including pushing the branch where the task started (including `main`) and `Build & Distribute` GitHub Actions usage, within the task's original scope. This does not authorize merging/rebasing a non-`main` task branch into `main`. Destructive or ambiguous data changes, expanded product scope, credentials, other paid actions, and App Store release still require current explicit authorization.
- End every task in plain Traditional Chinese with the outcome, expected behavior, and Eric's next check. For Change/Fix tasks also include: Git commit/branch/push state, Edge/migration state, what Eric should test on his iPhone, and anything intentionally not run. Mention `Build & Distribute` only once using the bounded-trigger sentence above; do not report or monitor its final result.

## On-Demand References

- Current stage: `docs/snapshot.md`
- Operational rules: `docs/shared-agent-rules.md`
- Product decisions: `docs/decisions.md`
- Durable bug history: `docs/bug-log.md`
- Launch: `docs/testflight-regression-checklist.md`, `docs/app-review-final-checklist.md`, `docs/launch-readiness-checklist.md`
- Integrations: `docs/integrations/`
- Reviews: `docs/reviews/`
- Context design: `docs/ai-harness/context-management.md`
