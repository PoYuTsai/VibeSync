# Shared Agent Rules

> Audience: Claude + Codex.
> Purpose: one durable operating contract for VibeSync agents.

## Ownership

Precedence:

1. global model/system/developer rules
2. this file
3. `AGENTS.md` / `CLAUDE.md`
4. task-specific prompt

If a rule applies to both Claude and Codex, edit this file. Do not duplicate it into both agent files.

## Current Truth Contract

At every new session, rotation, or handoff:

1. Read `docs/snapshot.md`.
2. Read `git log --oneline -15`.
3. Read latest handoff if one exists.
4. Read newest OPEN item in `docs/reviews/ai-arbitration-queue.md`.

These override old chat memory, Claude persisted output, and stale screenshots.

Agent rule files must stay clean:

- `AGENTS.md` and `CLAUDE.md` must not contain injected `<claude-mem-context>` / "Memory Context" blocks.
- `AGENTS.md` and `CLAUDE.md` must remain synchronized.
- If either file is polluted or out of sync, stop and clean it before `!cc-rotate`, Codex review, or dogfood approval.
- The global `claude-mem@thedotmack` plugin is disabled for VibeSync workflow safety; use `docs/snapshot.md`, handoffs, queue, and git history instead.

Current project truth as of 2026-05-14:

- Coach 1:1 is shipped into dogfood.
- The active phase is TestFlight dogfood / App Review stabilization.
- Active risk zones are subscription, quota, RevenueCat, paywall, opener, analyze-chat, Coach 1:1, and OCR.
- Do not revive archived roadmap labels or old planning tracks unless Eric explicitly asks.
- Discord ready replies should suggest only current tracks: P0/P1 dogfood bug intake, workflow verification, Codex review gate, or App Review stabilization.

## Closeout Matrix

Default: write nothing beyond git history unless one of these applies.

- Bug with durable root cause -> update `docs/bug-log.md`.
- Shared agent rule changed -> update this file.
- Major stage changed -> update `docs/snapshot.md`.
- ADR-level decision -> update `docs/decisions.md`.
- Review/arbitration/handoff needed -> update `docs/reviews/`.
- Onboarding commands changed -> update `README.md`.

Every finished code/doc task should still commit and push.

## Role Split

Claude leads:

- Flutter/UI/product flow/copy execution.
- First-line dogfood bug fixes.
- Small scoped implementation when product intent is clear.

Codex leads:

- Read-only code review.
- OCR, algorithmic logic, refactor plans, performance, architecture risk.
- Adversarial checks on payment/quota/auth/data/AI prompt changes.

Eric/Bruce lead:

- Product feel, TestFlight smoke, real dating/chat UX judgment.
- Final call when product/payment/data tradeoffs are ambiguous.

## DB Migration Deploy Rule（2026-06-11 Eric 拍板）

- **絕不對 prod 跑 `supabase db push`**。歷史原因：repo 曾有重複版本號 migration（20260315×2，後改名 20260316），帳本與檔案曾長期漂移，盲 push 會重放歷史孤兒 SQL（見 `docs/security/2026-05-11-prelaunch-security-scan.md`）。
- 標準流程 = **目標式套用**：Supabase MCP `apply_migration` 只打該份 SQL → 功能驗證（含清理測試列）→ **把帳本 version 對齊本地檔名**（MCP 自動產生的 timestamp ≠ 檔名時必須 UPDATE `supabase_migrations.schema_migrations`，否則製造新漂移）。
- 範例：ADR #19 `20260611120000_adr19_overcharge_confirmations.sql` 即依此流程套用（claimed/replay/mismatch 三態驗證通過）。

## High-Risk Changes Need Codex Review

High-risk includes:

- subscription, paywall, quota, RevenueCat, 429
- auth, account deletion, Hive/local persistence
- `analyze-chat`, opener, OCR, Edge response schema
- AI prompt changes affecting quality, safety, or token/cost

Rule:

- Claude may fix first.
- Before telling Eric/Bruce the build is safe to test, run Codex read-only review.
- A valid Codex review must leave evidence: job id/result, review doc, queue update, or linked commit.
- Do not claim "Codex approved" from memory or vibes.

Verdicts:

- `APPROVED`: no P0/P1/P2.
- `REVISE_REQUIRED`: P0/P1/P2 exists; Claude fixes only required findings.
- `NEEDS_ERIC`: product/payment/data ambiguity or unresolved second-round disagreement.

Review loop:

- Maximum two Claude-fix + Codex-review rounds.
- After two rounds, stop and wait for Eric if still blocked.

### High-Risk Patch Stop Rule

Use this rule for auth, account deletion, Hive/local persistence, subscription,
quota, RevenueCat, OCR, Edge schema, and AI cost/token behavior.

- A Codex `REVISE_REQUIRED` finding is first a design signal, not a todo list.
- Before editing high-risk code, write the invariants in the reply or review doc.
- If the bug involves ordering, atomicity, identity scope, or money/data loss,
  include a small failure matrix before changing code.
- If two Claude-fix + Codex-review rounds do not converge, stop patching.
- After the stop, choose one:
  - revert to the last known-safe baseline,
  - mark `WAITING_ON_ERIC`,
  - write a design/ADR and reopen as a new scoped task.
- Do not start round 3+ by "just moving the ordering" unless Eric explicitly
  approves the design and tradeoff.
- For state-machine bugs, prefer a new helper/service with targeted regression
  tests over more conditional branches inside a screen widget.

High-risk invariant examples:

- Remote delete failure must not erase local-only data.
- Remote delete success must not be reported as fully complete if local cleanup
  failed.
- Logout/session expiry is not the same lifecycle as account deletion.
- A new user on the same device must not see the previous user's private data.
- A paid user must not be downgraded to Free unless the signal is authoritative.

### Review Evidence And False Positives

- Repo grep is not enough for external facts such as live web URLs, App Store
  metadata, RevenueCat dashboard state, or deployed Edge behavior.
- For high-risk bugs crossing SaaS services, secrets, webhooks, or deployed
  Edge Functions, verify live environment state before treating the issue as a
  code-only regression. Examples: Supabase Edge secrets, RevenueCat API keys,
  webhook delivery, dashboard product state, and the currently deployed
  function revision.
- Close external-fact findings with direct evidence, for example `curl -I -L`,
  deployment logs, dashboard screenshots, or TestFlight repro notes.
- If a finding is closed by external evidence, record it as
  `accepted with external evidence`; do not claim `Codex APPROVED` unless Codex
  actually returned `APPROVED`.
- Do not rerun review only to get a cleaner label when the only blocker was
  already resolved by stronger external evidence.

### Multi-Thread Review Hygiene

- One thread owns one workstream. Do not let another thread fix over a dirty
  worktree unless Eric explicitly reassigns ownership.
- Before editing, check `git status --short` and name any unrelated dirty files.
- Before queueing Codex, state the exact review range and why it is the right
  range.
- If a review range mixes unrelated feature/code/docs changes, either explain
  why it is intentional or stop and create a cleaner range.
- If one thread has an unresolved high-risk `REVISE_REQUIRED`, other threads
  should avoid building on top of that scope until it is approved, reverted, or
  moved to `WAITING_ON_ERIC`.

## Discord Frontline Response Contract

Applies to Claude Code sessions listening in VibeSync Discord.

- Treat every new non-bot message from Eric or Bruce as an interrupt, not background context. Pause the current task after the current atomic tool call returns, read the new request, acknowledge it, and re-evaluate whether to continue, redirect, or stop.
- If Eric/Bruce says stop, pause, wait, no, wrong path, "先不要", "不要採用", or gives a correction, abort the previous plan until the correction is acknowledged and the next action is confirmed.
- Do not continue a long investigation/review/fix while ignoring fresh Discord messages. Between tool calls, check whether new user input arrived and answer it before proceeding.
- Avoid starting long blocking commands in Discord frontline mode unless necessary. Prefer bounded commands, short status updates, and resumable steps so Eric/Bruce can interrupt safely from mobile.
- Treat every non-bot message from Eric or Bruce as requiring explicit acknowledgment unless it is clearly a duplicate/reaction/already answered.
- If Eric and Bruce both speak before the agent replies, answer both in the same response.
- Use `Eric:` / `Bruce:` or quote the key phrase when ambiguity is possible.
- If one person's message is only context, still say `Bruce: 收到，先當脈絡保留。` or `Eric: 收到，先當脈絡保留。`.
- If a report is ambiguous or has billing/data/product risk, ask a concise clarifying question before editing files.
- Read-only investigation is allowed before asking; write operations need a clear task.
- Keep Discord replies phone-screen friendly: 8 lines or fewer whenever possible.
- Bug status format: `收到 -> 先查 -> root cause -> 修法 -> commit/push -> 是否需要 rebuild`.
- Discord text/screenshots are reliable; videos are not. For video-only reports, ask for key screenshots, timestamps, repro steps, expected result, and actual result.
- If Eric says to queue a bug, update the newest OPEN item in `docs/reviews/ai-arbitration-queue.md`. Do not invent root cause before intake.

## Discord Fix / Review Closeout Format

When Claude reports a completed hotfix, investigation, or Codex review back to Discord, the reply must make Eric and Bruce able to reconstruct the thread without reading terminal logs.

Use this phone-friendly shape, ideally 8 lines or fewer:

```text
Bug/Task: <who reported + symptom>
Change: <what changed, 1-2 bullets max>
Commit: <hash or "not committed yet">
Codex: <not needed + reason | queued job-id | APPROVED | REVISE_REQUIRED | NEEDS_ERIC>
Findings: <none | P0/P1/P2 summary>
Tests: <commands run, or "not run">
Build: <needs rebuild/TestFlight/Edge deploy? yes/no>
Next: <owner + exact next action>
```

Rules:

- If Codex review is only queued, say `Codex: queued`, not approved.
- If Codex returns `REVISE_REQUIRED`, do not ask Eric/Bruce to dogfood yet; list required fixes first.
- If Codex returns `NEEDS_ERIC`, pause and ask the exact decision question.
- If no Codex review ran, explicitly say why: `low-risk docs only`, `read-only investigation`, or `not high-risk`.
- For high-risk zones, "safe to test" requires both fix evidence and Codex review evidence.
- Always mention whether a rebuild, TestFlight build, or Edge deploy is needed.

## External Codex Review Gate

Phase 1 commands:

- `!codex setup`
- `!codex review latest`
- `!codex review <base-ref>`
- `!codex adversarial-review latest`
- `!codex adversarial-review <base-ref>`
- `!codex status <job-id>`
- `!codex result <job-id>`
- `!codex cancel <job-id>`

Disabled in Discord Phase 1:

- `!codex task`
- `!codex rescue`
- `!codex login`
- write-enabled Codex commands

External mode rule:

- Codex is read-only.
- Codex reports findings.
- Claude applies required fixes.
- Eric/Bruce dogfood after `APPROVED` or explicit Eric decision.
- If Eric replies "yes/要" when Claude asks whether to run Codex review, Claude must review the actual hotfix diff, not blindly `HEAD~1..HEAD`.
- `latest` is valid only when the entire hotfix is exactly the current HEAD commit.
- `latest` is blocked when the current HEAD is a docs/chore commit; pass an explicit base ref if that review is intentional.
- If a hotfix spans multiple commits, or if docs/workflow commits landed after the hotfix, use an explicit base ref: `!codex review <commit-before-first-hotfix>`.
- Before queueing Codex review, Claude must state the target range in Discord: `Codex scope: <base>..HEAD, includes <commit list / files>`.
- If the target range would include unrelated docs/workflow commits, stop and ask Eric whether to review a broader range or create a clean review branch/range.
- Do not substitute `codex:rescue`, `!codex rescue`, or any write-capable Codex flow for normal external review.

Setup:

- If `!codex setup` says auth is missing, run once in Ubuntu terminal: `codex login --device-auth`.

## Rotation Protocol: `!cc-rotate`

`!cc-rotate` is the only v1 phone/DC rotation command. There is no `!cc-handoff`, no `--force`, and no `!cc-status`.

Use it when context approaches the orange/red zone or after a scoped external task is complete.

Important: `!cc-rotate` is the manual safety rope, not the warning system. The warning system is the green-context hook/statusline. Keep their thresholds aligned so Eric is warned before the terminal becomes hard to use.

Green-context bands:

- 20-25%: soft notice in external/Discord mode. If a bugfix/review is finishing, remind Eric that `!cc-rotate` is available before the next task.
- 25-35%: yellow reminder. Finish the current scoped task; do not start medium/high-risk work casually.
- 35-45%: orange, prepare `!cc-rotate`; high-risk work should avoid starting here.
- 45%+: hard stop; rotate before new work.

Proactive reminder rule:

- Do not rotate after every task by default; keep momentum when context is still healthy.
- At 20-25%, mention rotate only when the current item is wrapping up or the next item is likely to be non-trivial.
- At 25-35%, include a one-line rotation reminder in Discord closeout for bugfix/review work.
- At 35%+, do not start a new scoped task without first telling Eric: `建議先 !cc-rotate，再接下一個任務。`
- At 45%+, refuse new work except handoff/rotate/blocker cleanup.
- If Eric is mobile or the session is in Discord frontline mode, prefer a short direct reminder over a long explanation.

When receiving `!cc-rotate`, the current session must:

1. Reply: `Validating rotate conditions...`
2. Run `tools/cc-rotate/validate.sh`.
3. Self-check internal blockers:
   - B5 TodoWrite has `in_progress`.
   - B6 background Bash still alive.
   - B7 background Task agent pending.
   - B8 plan mode not exited.
   - B9 permission request pending.
   - B10 long-running command active.
4. If any hard block exists, reply with blockers and stop.
5. Fold warnings into handoff.
6. Run handoff skill; it must write `reference_session_handoff_latest.md`.
7. Verify handoff mtime is within 60 seconds.
8. Write `cc-rotate.request.json` to `$CC_ROTATE_DIR`.
9. Reply: `Handoff OK. Rotating in ~5s. New session will read it.`
10. Stop accepting new tool calls and wait for supervisor SIGTERM.

Failure format:

```text
!cc-rotate refused:
- <CODE>: <reason>

Next:
- Fix <CODE>: <how>
- After blockers are cleared, type !cc-rotate again
```

New session bootstrap must:

- read `AGENTS.md`
- read this file
- read `docs/snapshot.md`
- read newest OPEN queue item
- read latest handoff
- run `git log --oneline -15`, `git status --short --branch`, and `git rev-parse --short HEAD`
- reply to Discord that it is ready
- delete `cc-rotate.bootstrap.json`

The new session must not trust old persisted context over these files.
The ready reply must report the live `git rev-parse --short HEAD`, not the handoff or bootstrap HEAD.

## Anti-Bloat Rules

- One change should map to one primary shared document.
- `docs/snapshot.md` is a periodic rewrite, not an append-only diary.
- `docs/reviews/ai-arbitration-queue.md` is a live queue, not a history dump.
- Do not copy the same summary into `bug-log`, `snapshot`, and `reviews`.
- `AGENTS.md` and `CLAUDE.md` stay short and point here for shared rules.
- If a note is only useful for the current session, keep it out of permanent docs.
