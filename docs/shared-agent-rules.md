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

## Discord Frontline Response Contract

Applies to Claude Code sessions listening in VibeSync Discord.

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
- `!codex adversarial-review latest`
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

Setup:

- If `!codex setup` says auth is missing, run once in Ubuntu terminal: `codex login --device-auth`.

## Rotation Protocol: `!cc-rotate`

`!cc-rotate` is the only v1 phone/DC rotation command. There is no `!cc-handoff`, no `--force`, and no `!cc-status`.

Use it when context approaches the orange/red zone or after a scoped external task is complete.

Green-context bands:

- 35-45%: yellow reminder.
- 45-55%: orange, prepare `!cc-rotate`; high-risk work should avoid starting here.
- 55%+: hard stop; rotate before new work.

Proactive reminder rule:

- Do not rotate after every task by default; keep momentum when context is still healthy.
- At 35-45%, only mention rotate if the completed task was high-risk/large, or the next requested task is medium/high-risk.
- At 45%+, do not start a new scoped task without first telling Eric: `建議先 !cc-rotate，再接下一個任務。`
- At 55%+, refuse new work except handoff/rotate/blocker cleanup.
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
