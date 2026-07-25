# VibeSync Operational References

> On-demand project rules for migration, deployment, high-risk review, and closeout. Do not load this entire file at session start.

## Precedence

1. System/developer policy and Eric's current request
2. Global agent policy and shared workflow skills
3. Root `AGENTS.md`
4. This task-specific reference
5. Historical plans, queues, handoffs, and chat

Code, tests, current service evidence, and recent commits outrank stale narrative documents.

## Durable Documentation

Write no extra history by default. Update a durable file only when:

- a bug has a reusable root cause → `docs/bug-log.md`
- the product stage materially changes → `docs/snapshot.md`
- a hard-to-reverse decision is made → `docs/decisions.md`
- a review or handoff must persist → `docs/reviews/` or graph handoff
- onboarding or supported commands change → `README.md`

Do not paste raw logs, full diffs, or transcripts into durable context files.

## Database Migration

- Never run `supabase db push` against production. The repository has historical migration-ledger drift and duplicate-version history.
- Apply only the intended SQL through the targeted Supabase migration operation.
- Verify the behavior, clean test rows, and confirm the migration ledger version matches the local filename.
- Treat schema, billing, quota, auth, and destructive-data migrations as R3. Require explicit production authorization and a rollback path.

## Website Deployment

- `https://www.vibesyncai.app/` deploys from `PoYuTsai/vibesync-web` `main`.
- `chiang53610-droid/vibesync-web` is historical and must not be used for release.
- Vercel private-repo deployments require a commit author with contributing access; use the repository's configured authorized identity.
- Pushing and deployment are separate externally consequential actions and require Eric's explicit authorization.

## High-Risk Review

High-risk scope includes:

- subscription, paywall, quota, RevenueCat, and 429 behavior
- auth, account deletion, encrypted local persistence, and private-data lifecycle
- `analyze-chat`, Opener, OCR, Edge response schemas
- AI prompts or routing that materially affect safety, quality, or cost

For material R2/R3 work:

1. The active primary implements and verifies.
2. The opposite frontier host performs an independent read-only review.
3. GLM performs a separate adversarial/falsification pass.
4. The primary checks findings against source evidence and integrates without majority vote.

Invoke configured reviewers directly through `cross-model-review`; do not stop at preparing a packet for Eric. Reviewers never edit, deploy, send messages, or invoke another model. Stop after at most two fix/review rounds.

Verdicts:

- `APPROVED`: no material P0/P1/P2 finding remains.
- `REVISE_REQUIRED`: verified material findings require repair.
- `NEEDS_ERIC`: a product, payment, data, or consequential tradeoff remains.

## High-Risk Invariants

- Remote delete failure must not erase local-only data.
- Remote delete success must not be reported as complete if required local cleanup failed.
- Logout or session expiry is not account deletion.
- A new user on the same device must not see another user's private data.
- A paid user must not be downgraded without an authoritative signal.
- Format, deadline, or model-limit failures must not charge quota or masquerade as paywall exhaustion.
- Same-request retries must not double-charge.

For ordering, atomicity, identity scope, money, or data-loss bugs, write the invariants and a compact failure matrix before editing.

## Evidence And Worktree Hygiene

- Check `git status --short` before editing and name unrelated dirty files.
- Use executable tests, live endpoint evidence, deployment logs, dashboard evidence, or TestFlight reproduction as appropriate.
- Repo grep alone cannot prove external service state.
- One workstream owns one dirty scope. Do not layer fixes over another unresolved high-risk change without explicit reassignment.
- State the exact review range when reviewing commits; do not mix unrelated changes without explanation.
