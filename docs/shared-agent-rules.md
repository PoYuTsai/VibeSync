# Shared Agent Rules

> Audience: Shared
> Purpose: single source of truth for rules that both Claude and Codex must follow.

## Ownership

- Precedence is:
  1. global `~/.claude/CLAUDE.md`
  2. this file
  3. `AGENTS.md` / `CLAUDE.md` agent-specific addenda
- Shared workflow rules live here.
- `AGENTS.md` only keeps Codex-specific additions plus a pointer here.
- `CLAUDE.md` only keeps Claude-specific additions plus a pointer here.
- If a rule applies to both agents, edit this file instead of editing both agent files.
- If a local rule duplicates or conflicts with global constitution, remove the local copy.
- If a rule is not truly shared, keep it out of this file.

## Closeout Trigger

Run this check whenever:

- Daisy explicitly asks for `commit+push`
- a task is clearly done and about to be wrapped
- a small test / validation round is being closed out

## Closeout Matrix

Default: **write nothing beyond git history** unless one of these is true.

1. Bug with root cause or new recurring trap
   - Update `docs/bug-log.md`
   - Update `AGENTS.md` / `CLAUDE.md` Common Pitfalls only if it is likely to recur

2. Review, rebuttal, or arbitration output
   - Update one file under `docs/reviews/`
   - Use `docs/reviews/ai-arbitration-queue.md` for live cross-agent discussion

3. Lasting project rule that both agents must know
   - Update this file

4. Major stage / release posture change
   - Update `docs/snapshot.md`

5. ADR-level decision
   - Update `docs/decisions.md`

6. New contributor onboarding would fail or be materially misled
   - Update `README.md`
   - Triggers:
     - setup / install / run / test / deploy commands changed
     - required env vars, third-party services, or platform support changed
     - top-level feature map or project entrypoints changed enough that README overview is stale
     - docs entrypoint changed for first-30-minute onboarding

7. Another agent may later need to continue, review, or sanity-check this work
   - Update `docs/reviews/ai-arbitration-queue.md`
   - Required when:
     - Claude handled a DC / mobile-driven round that Codex may later read
     - Codex finished a pass that Claude may later validate
     - a task remains partially open across sessions or devices
     - the next agent would otherwise need human re-translation of context

If none apply:

- leave docs untouched
- let `git log` be the history

## Test Responsibility Split

Default testing owner is the implementation agent in the primary dev runtime.

- Claude / WSL runs Flutter TDD loops, `flutter test`, and `flutter analyze` for implementation work, and includes exact commands plus pass/fail output in handoff summaries.
- Codex does diff review, architecture / risk checks, grep contract checks, and targeted verification for touched or high-risk files only.
- Codex should not rerun full Flutter test suites when Claude already supplied credible exact commands/results, unless the diff contradicts the result or a high-risk invariant needs independent verification.
- If Codex does run Flutter locally, prefer the smallest relevant test scope; full-suite or repeated Flutter runs belong in WSL unless explicitly needed.

## Task Routing And Role Split

Use this section when Eric, Bruce, Claude, or Codex are unsure who should handle the next step.

Short rule:

- Unclear direction -> Codex.
- Clear implementation -> Claude.
- Finished work review -> Codex.
- Product feel / TF smoke -> Eric and Bruce.

### Start With Codex

Start with Codex before implementation when the question is about product direction, positioning, architecture, risk, or AI quality.

Examples:

- Product positioning changes, such as "reply consultant" -> "dating learning coach".
- Category / differentiation questions, such as whether VibeSync is just a reply generator or a memory + review + next-step learning app.
- Business / pricing / cost questions, especially second-layer AI, proactive review, long-term memory, or token cost.
- Major IA or flow changes, such as reshaping "My Report" into a learning / review center.
- Prompt, memory, user profile, partner profile, or AI-quality changes.
- OCR, `analyze-chat`, Edge schema, Hive migration, auth, payment, or subscription changes.
- Bruce or competitor research provides a broad product signal that must be converted into a testable spec.

Codex output should clarify:

- the core problem
- product positioning
- differentiation
- scope boundary
- roadmap / phase split
- what to do now vs later
- clear inputs for Claude to draft an executable plan

### Start With Claude

Start with Claude when Eric already knows what should change and the task is a clear Flutter/UI/hotfix execution item.

Examples:

- UI bugs: overflow, broken back navigation, dead buttons, blocked screens.
- Visual polish: spacing, colors, glass/card feel, chip styling.
- Copy tweaks that do not change product strategy.
- Flutter-only screen or widget work.
- Small TF dogfood regressions.
- Hotfixes with a known root cause.

Claude output should include:

- commit hash
- changed files
- tests run
- open risks
- whether Codex review is needed

### Standard Workflows

Product strategy or high-risk feature:

1. Eric + Codex strategy discovery.
2. Codex writes direction, scope, and roadmap.
3. Claude drafts executable spec / plan.
4. Eric sanity-checks product intent.
5. Codex reviews the spec.
6. Claude executes.
7. Codex reviews the code.
8. Eric / Bruce run TF smoke.

Routine UI / hotfix:

1. Eric / Bruce report the issue.
2. Claude writes a mini-spec and executes.
3. Claude runs tests.
4. Codex reviews if the change is risky or Eric wants another pass.
5. Eric / Bruce run TF smoke.

### High-Risk Changes Require Codex Review First

Do not let one agent implement these end-to-end without Codex review:

- OCR / `analyze-chat` prompt
- Edge Function schema or response format
- Hive schema or migration
- auth, payment, or subscription
- memory, partner aggregate, or conversation write path
- user profile / partner profile prompt injection
- changes affecting token cost, AI quality, OCR baseline, or App Review stability
- IA changes spanning multiple features

Required flow:

`Codex strategy/spec -> Claude plan/execute -> Codex review -> TF smoke`

### TF Build Gate

After several hotfixes accumulate, pause before starting a larger feature.

- Build from `main`.
- Eric / Bruce dogfood in TestFlight.
- If OK, start the next feature.
- If regression appears, fix-forward first.
- Do not mix a large feature with a hotfix batch.

### Context Hygiene

- Claude should open a new session for each major phase; long sessions are for short hotfixes, not architecture judgment.
- Claude's new session should read the latest handoff / queue / git log before acting.
- Codex should put review verdicts, risks, and durable decisions in `docs/reviews/`, queue, memory, or ADRs as appropriate.
- Shared facts come from git log + docs + memory, not any single model's chat memory.

## Anti-Bloat Rules

- One change should map to one primary shared document.
- Do not write the same summary into `bug-log`, `snapshot`, and `reviews`.
- `docs/snapshot.md` is a periodic rewrite, not an append-only diary.
- `docs/reviews/` should capture decisions, findings, or rebuttals; not routine changelogs.
- `docs/reviews/ai-arbitration-queue.md` is a live handoff/review queue, not an append-only log; one task should keep one live item.
- `AGENTS.md` / `CLAUDE.md` should stay short and point here for shared rules.
- `README.md` is an onboarding doc, not a changelog; only update it when first-30-minute developer understanding would otherwise drift.
- If a note is only useful for the current session, keep it out of permanent docs.

## Audience Tags

When adding a new operating rule, label it mentally as one of:

- `Shared`
- `Claude-only`
- `Codex-only`

Only `Shared` rules belong here.
