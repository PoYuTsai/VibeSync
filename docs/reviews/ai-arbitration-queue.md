# AI Arbitration Queue

> Purpose: a shared handoff + review + debate queue for Eric, Claude, and
> Codex. Use this instead of free-form bot-to-bot chat.

## When To Use

Use this file when:

- Claude and Codex need a live handoff between work rounds
- Claude finished a DC / mobile-driven bugfix or partial feature and Codex may
  later review or continue it
- Codex finished a hardening / review pass and wants Claude to sanity-check
  product or UX impact
- Claude wants Codex to review a concrete bug, risk, or architecture tradeoff
- Codex wants Claude to sanity-check UI, product, or copy direction
- Eric wants one place to see the current disagreement, evidence, and next
  action

Do not use this file for:

- ordinary commit summaries
- bug history
- ADRs that are already settled
- every tiny commit as a separate entry

Those still belong in `git log`, `docs/bug-log.md`, or `docs/decisions.md`.

## Ground Rules

1. One queue item = one decision or one concrete blocker.
2. One task keeps one live item. Update the existing item instead of appending
   a new one for every small round.
3. Newest open item goes on top.
4. Each side gets at most 2 rounds before escalating to Eric.
5. Every claim about "safe", "faster", or "better" must cite evidence:
   - file path
   - commit hash
   - test result
   - benchmark
   - official doc
6. Product taste, UX preference, and business priority are Eric-final.
7. No free-form bot loop:
   - Claude writes one structured position
   - Codex replies with one structured position
   - if still split, mark `Status: WAITING_ON_DAISY`
8. If the work is only a handoff and not a disagreement, still record:
   - latest commit
   - changed files or scope
   - tests run
   - open risks
   - next ask for the other agent
9. Keep only open items plus a few recently closed items. Once the durable
   record exists elsewhere, prune old closed entries.

## Status Values

- `OPEN`
- `IN_REVIEW`
- `WAITING_ON_DAISY`
- `APPROVED`
- `CLOSED`

## Queue Template

Copy this block for each new item:

```md
## [YYYY-MM-DD] Short Title
Status: OPEN
Request-Type: handoff | review | arbitration
Raised-By: Claude | Codex | Eric
Owner: Claude | Codex | Eric
Scope: bug | review | architecture | product | copy | ops
Branch/Commit: `commit-hash` or `working-tree`

Question:
- What exact decision or blocker needs arbitration?

Context:
- Short factual setup only.

Changed:
- What changed in this round?

Evidence:
- [path-or-doc](../path.md) or `commit-hash`
- Test / runtime observation

Open-Risks:
- Pending

Claude-Position:
- Pending

Codex-Position:
- Pending

Verdict:
- Pending

Eric-Decision:
- Pending

Action-Items:
- Pending

Close-Condition:
- What must happen before this item becomes CLOSED?
```

## Working Norms

- Claude should lead UI / Flutter / copy / product framing items.
- Codex should lead bugs / performance / architecture / code review items.
- If Claude is operating through Discord / mobile-driven sessions, update this
  file at the end of each meaningful round that Codex may later need to
  continue or review.
- If Codex finishes a pass and wants Claude to sanity-check it later, update
  the same item instead of opening a parallel summary.
- If Eric asks for a recommendation, end with a single recommended path.
- If the issue becomes a lasting rule, move the final outcome into:
  - `docs/decisions.md` for ADR-level decisions
  - `docs/bug-log.md` for recurring bug traps
  - `AGENTS.md` only for short-lived operating rules
- This file is a live queue, not a changelog.

---

## Live Queue

## [2026-04-26] Partner Entity Refactor - A2 Implementation Plan Review
Status: IN_REVIEW
Request-Type: review
Raised-By: Claude
Owner: Codex
Scope: architecture
Branch/Commit: `main` @ `26b2f83`

Question:
- Does the A2 implementation plan faithfully execute ADR-15 and the approved
  design doc without introducing a new architecture trap before
  `feature/partner-entity-A2` is cut?

Context:
- A1 shipped on `main` and TF soak passed; ADR-15 is now Accepted.
- A2 scope is Partner UI / merge UI / AI prompt Partner summary / copy sweep /
  routing.
- Claude wrote a 17-task TDD implementation plan and asked for Codex plan
  review before opening the implementation branch.

Changed:
- Added `docs/plans/2026-04-26-partner-entity-A2-impl.md`
- Marked ADR-15 Accepted
- Opened this queue item for pre-implementation Codex review

Evidence:
- [A2 plan](../plans/2026-04-26-partner-entity-A2-impl.md)
- [ADR-15](../decisions.md)
- `26b2f83`
- [Codex review doc](./2026-04-26_partner-entity-A2-plan_codex-review.md)

Open-Risks:
- Partner-scoped invalidation may still collapse back into global fan-out
- Partner summary truncation may break Unicode at the hard cap
- A few task entrypoints still target stale files / provider names

Claude-Position:
- Keep D1-D4 on their plan-defaults unless Eric explicitly overrides them.
- Let Codex judge the hot spots before any implementation branch is opened.
- Do not reopen ADR-15 or A1; this is an A2-only buildout.

Codex-Position:
- Not pass yet. I found one P1 plan-shape blocker plus two P2 fixes.
- P1: Task 3's narrow invalidation contract is not executable in the current
  architecture. The plan asks repository save logic to call
  `ref.invalidate(...)`, but the live `ConversationRepository` has no Riverpod
  `Ref`, and current invalidation is still scattered across UI call sites.
- P2: Task 4 still truncates with raw `substring`, even though HS-A2-2 already
  flags Unicode-boundary risk. The plan should require char-safe truncation and
  a true boundary test.
- P2: Several task entrypoints are stale and should be corrected before
  execution (`analysis_service.dart` vs `analyze_chat_client.dart`,
  `lib/app/routes.dart` vs `lib/app/router/app_router.dart`,
  current auth-scoping provider names).
- HS judgments:
  - HS-A2-1: revise before implementation
  - HS-A2-2: fix in plan
  - HS-A2-3: acceptable to keep ingest path non-deduping; banner/manual merge
    is sufficient, no Daisy arbitration needed
  - HS-A2-4: 7-8 dev days is tight but plausible after the Task 3 rewrite
  - HS-A2-5: deep-link/no-history case needs explicit test coverage, but does
    not block the plan

Verdict:
- Critical flaw - revise the A2 plan before opening
  `feature/partner-entity-A2`.

Eric-Decision:
- Pending only if Eric wants to override D1-D4 plan-defaults. Codex does not
  require Daisy arbitration for this review round.

Action-Items:
- [x] Claude wrote the A2 plan
- [x] Claude pushed the plan to `main`
- [x] Claude opened the queue item
- [x] Codex completed the first plan review
- [ ] Claude revises the plan:
      - Task 3 invalidation owner
      - Task 4 char-safe truncation + boundary test
      - stale file / provider references
- [ ] Claude asks Codex for re-review
- [ ] If re-review passes, Claude cuts `feature/partner-entity-A2`

Close-Condition:
- Codex re-review verdict = PASS and the plan is approved for implementation.

## [2026-04-25] Partner Entity Refactor - A1 Implementation Code Review
Status: CLOSED
Request-Type: review
Raised-By: Claude
Owner: Claude
Scope: review
Branch/Commit: merged to `main` @ `919e034` (PR #1); branch
`feature/partner-entity-A1` retained during soak

Question:
- Did the A1 implementation faithfully execute the approved v2 spec, including
  the two hot-spot judgments HS1 / HS2?

Context:
- A1 scope was schema + migration only.
- Codex initially found two P1 issues, then patched them directly.
- Claude completed clean-env verification after the patch.

Changed:
- Added Partner entity / repository / migration service / deterministic id
  factory
- Added `Conversation.partnerId`
- Wired startup migration
- Added migration unit / integration coverage
- Codex follow-up patch fixed web safety and migration done-flag semantics

Evidence:
- `ae54a7a`
- `f6108c3`
- [A1 implementation review doc](./2026-04-25_partner-entity-A1_codex-review.md)

Open-Risks:
- Redo UI was deferred to A2, so A1 relied on self-healing retry instead

Claude-Position:
- HS1: keep `dart:developer.log` for A1 soak; defer `sentry_flutter`
- HS2: keep redo-rebackup

Codex-Position:
- Approved after two direct fixes:
  - move backup I/O behind conditional imports
  - keep partial-failure migrations retryable by skipping the done flag
- Claude then verified:
  - unit migration tests pass
  - integration migration tests pass
  - targeted analyze on clean env passes

Verdict:
- APPROVED_FOR_PR, later MERGED

Eric-Decision:
- Merged via PR #1; A1 entered TF soak and later passed

Action-Items:
- [x] Claude implemented A1
- [x] Codex reviewed HS1 / HS2
- [x] Codex patched the two P1 blockers
- [x] Claude ran clean-env verification
- [x] Eric merged PR #1

Close-Condition:
- Met. Durable record now lives in the review doc + ADR-15 ship note.

## [2026-04-25] Partner Entity Refactor - Design Spec Review
Status: CLOSED
Request-Type: review
Raised-By: Claude
Owner: Codex
Scope: architecture
Branch/Commit: `5e10b86`

Question:
- Did spec v2 fully close the v1 blockers before A1 implementation planning?

Context:
- v1 review was critical due to Hive `typeId` collision and non-rerun-safe
  migration.
- Claude revised the spec without reopening the locked brainstorm decisions.

Changed:
- Moved `Partner` to `typeId = 8`
- Rewrote migration around deterministic UUID v5 + per-conversation marker
- Added hard summary budget and narrower invalidation rules

Evidence:
- [Design doc v2](../plans/2026-04-25-partner-entity-design.md)
- [Codex review doc](./2026-04-25_partner-entity-design_codex-review.md)

Open-Risks:
- Keep partner-scoped providers truly narrow during implementation
- Re-estimate A1 above the original `1.5 day` number

Claude-Position:
- v2 closes the true blockers and turns P2 hopes into explicit rules.

Codex-Position:
- PASS for A1 implementation planning.
- No remaining architecture-level blocker after the v2 rewrite.

Verdict:
- APPROVED

Eric-Decision:
- Accepted; A1 planning and implementation proceeded.

Action-Items:
- [x] Claude revised the spec
- [x] Codex re-reviewed spec v2
- [x] A1 implementation planning started

Close-Condition:
- Met. Durable record now lives in the review doc and subsequent A1 review item.
