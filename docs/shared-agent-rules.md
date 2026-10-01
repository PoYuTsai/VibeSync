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

- Never run `supabase db push` against any database. The repository has historical migration-ledger drift and duplicate-version history.
- Do not use `scripts/setup-supabase.sh` for production because it contains the forbidden broad push path.
- Applying a production migration needs Eric's explicit authorization for that migration file, asked after its required review and safety gates pass; when it unblocks a `main` push, list it in the same approval summary as that push. Apply only that migration.
- Apply the exact intended SQL through the targeted Supabase migration operation. Never “sync everything,” repair unrelated ledger history, or include migrations outside the task.
- Before applying, inspect the SQL, identify affected objects and rollback/recovery steps, and stop for Eric if the operation is destructive, ambiguous, or requires a new product/data tradeoff.
- Use Supabase MCP `apply_migration` for the exact SQL when callable. `supabase migration up --linked --yes` is allowed only after `supabase migration list --linked` proves the task's exact file is the sole pending migration and history has no unresolved ambiguity. Never use `--include-all`.
- If neither sanctioned path is callable and unambiguous, stop. Do not substitute raw `execute_sql`, `psql`, Dashboard SQL Editor, or another out-of-band production channel.
- Before applying, prove the migration is backward-compatible with the currently deployed client and Edge code for the whole migration-to-deploy window. Constraint tightening or other compatibility-breaking DDL requires current explicit authorization and a staged rollout.
- After applying, verify the schema/RPC contract and confirm the remote migration ledger version exactly matches the local filename. Use production test rows only when the task's reviewed runbook defines an isolated test identity, expected side effects, and cleanup; otherwise verify without writes.
- If post-apply verification fails, do not improvise a destructive rollback. Execute only a pre-reviewed, non-destructive recovery already authorized by the task; otherwise stop, preserve evidence, and ask Eric about rollback versus forward-fix.
- Treat schema, billing, quota, auth, and destructive-data migrations as R3: they get the High-Risk Review below (main review plus adversarial pre-review) and Eric's explicit authorization before the production operation.

## Edge Function Delivery

- Identify exactly which function directories changed and their JWT/auth contract.
- If a generic Edge change depends on a migration, apply and verify that targeted migration before pushing `main`; the push-triggered Edge workflow can start immediately. Do not apply the production migration merely to push or review a non-`main` branch.
- A push to `main` that touches a generic function starts `.github/workflows/deploy-edge-function.yml`; monitor that exact-SHA run and do not manually deploy the same change again.
- The generic workflow intentionally redeploys its entire checked-in generic function set one by one. Before pushing `main`, compare generic Edge changes since the last successful `Deploy Edge Function` run and stop if the workflow would include an unrelated or unreviewed function state. `analyze-chat` and `revenuecat-webhook` use `--no-verify-jwt`; do not improvise flags.
- `keyboard-reply` and `keyboard-assist` are excluded from the generic workflow. Follow their checked-in migration-gated runbook, apply the matching targeted migration first, verify secrets/contracts, then deploy only the intended function.
- Do not deploy production Edge code from a non-`main` task branch. Validate the branch (push it only once approved), then report production migration/Edge delivery as pending. Landing/merging that branch into `main` requires separate authorization; once Eric approves the merge and the actions listed for it, apply any prerequisite migration, perform the full-set Edge audit, land the change, monitor the exact-SHA `Deploy Edge Function` run, and report `Build & Distribute` with the bounded-trigger sentence in `AGENTS.md`.
- If a changed function is not safely covered by an existing workflow or runbook, stop and repair the delivery path or ask Eric about the consequential choice. Do not fall back to a broad deploy.

## Build And Distribute

- Eric's development host is Windows; his device check is a physical iPhone. Local Mac/Xcode commands are not available.
- `.github/workflows/distribute.yml` is the authoritative cross-platform release-candidate check: Flutter analyze/tests and keyboard contract on Ubuntu, Android APK plus Firebase distribution, and a signed iOS IPA artifact on GitHub's macOS runner.
- After a runtime code/config Change/Fix is pushed to `main` or `develop`, make one bounded lookup for the automatically triggered run on the exact commit SHA and report it with the bounded-trigger sentence in `AGENTS.md`. Do not wait, poll, or dispatch a duplicate.
- Dispatching `Build & Distribute` on any other branch needs Eric's explicit authorization for that run (with `android` or `both` it sends an APK to Firebase testers); routine PR branches use PR CI instead. After an authorized dispatch, verify that the run's `headSha` is the pushed commit.
- A task is not verified-delivered while the run is queued or in progress; report that state instead of claiming delivery. When Eric reports a failed run or asks you to check one, diagnose and fix within scope, or report the exact failing job/step and blocker.
- Allow at most two fix rounds for the same CI or Edge delivery gate; every re-push, workflow re-run or re-deploy inside them still needs Eric's per-action approval (see `AGENTS.md`). Then stop the loop and report the verified blocker and next decision. Never blindly re-apply a migration after an uncertain result; inspect the remote ledger and target objects before deciding the next action.
- The iOS IPA artifact is build evidence, not an App Store/TestFlight submission. Eric manually triggers `Release to App Stores`; agents must not trigger it.

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
2. One independent read-only main review through `dual-brain-review`, by a model family that wrote none of the code; pick the seat by current quota, and Eric's named seat wins.
3. A separate session, neither the primary nor the main reviewer, performs an adversarial/falsification pre-review. Pre-reviews, including any `cross-model-review` answer, are finding lists, not the gate.
4. The primary checks findings against source evidence and integrates without majority vote.

Reviewers never edit, deploy, send messages, or invoke another model. Default: one full review, then one batched fix and one delta review; a further round needs Eric's one-line exception in the review record.

Verdicts (the reviewer's single `VERDICT:` line):

- `APPROVED`: no material P0/P1/P2 finding remains.
- `APPROVED_WITH_RISK`: only residual risk remains; it needs Eric's explicit risk acceptance.
- `BLOCKED`: verified material findings require repair, or a product, payment, data, or consequential tradeoff needs Eric.

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

## Closeout Format

For every Change/Fix task, answer Eric in plain Traditional Chinese:

- `本輪完成` — the user-visible change and the important implementation facts.
- `Git` — commit SHA, branch, and whether push succeeded.
- `Backend` — changed Edge Functions and deployment result; targeted migration filename/version and result; or `本輪無`.
- `Build & Distribute` — the one bounded-trigger sentence from `AGENTS.md` (run URL, not waited for), or `本輪無`.
- `你預期會看到` — observable behavior after this change.
- `請 Eric 用 iPhone 測` — a short, task-specific physical-device checklist. These are requested manual checks, not tests the agent claims to have executed.
- `未執行/仍待處理` — always state that `Release to App Stores` was left for Eric, plus any real blocker.

Do not call a task “完成” when commit, push, required backend operation, or CI is still pending. Keep each state separate and evidence-backed.
