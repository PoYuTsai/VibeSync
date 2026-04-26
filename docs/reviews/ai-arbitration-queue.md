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
Branch/Commit: `main` @ `f1c7f29` (revision r4; r3 was `2a1163d`; r2 was `f89bec3`; r1 was `26b2f83`)

Question:
- Does the A2 implementation plan now faithfully execute ADR-15 and the
  approved design doc without introducing a new architecture trap before
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
- r2 (`f89bec3`) revised the plan per the first Codex verdict:
  - Task 3 rewritten around `ConversationWriteController extends Notifier<void>`
    as narrow-invalidation owner
  - Task 4 truncation switched to `String.characters`
  - Task 5 path fixed to `analysis_service.dart`
  - Task 6 path fixed to `lib/app/routes.dart`
  - Task 3 stale provider naming fixed
- r3 (`2a1163d`) revised the plan per the second Codex verdict:
  - Task 3 narrow contract redefined: "narrow" = cross-partner fan-out防火,
    NOT "never invalidates global feeds". Controller now also invalidates
    `conversationsProvider` (`_invalidateLegacyGlobal()` helper) so legacy
    consumers (e.g. `reportDataProvider`) stay fresh.
  - Task 3 test list rebuilt: dropped over-strict "never touches conversationsProvider";
    added cross-partner fan-out test + reportDataProvider freshness integration test.
  - Task 3 migration table expanded from 9 to 13 sites: 9 conversation **write**
    sites → controller; 4 **session-scope** auth boundary sites
    (`login_screen:70` / `settings_screen:568,584,690`) stay as-is — they are
    auth cleanup, not conversation writes.
  - Task 4 boundary test strengthened from generic non-ASCII to explicit ZWJ
    emoji grapheme cluster (`👨‍👩‍👧`, 7 codepoints / 11 UTF-16 units / 1
    grapheme cluster).
  - New §「Post-A2 cleanup」: spec for retiring `conversationsProvider` as a
    follow-up PR ~2 weeks post A2 ship (out of A2 scope).
- r4 (`f1c7f29`) revised the plan per the third Codex verdict (Eric chose
  option 1, the small doc patch path):
  - Task 3 Step 5 migration table unit-of-analysis 校正：from "invalidate
    site (9)" to "repo write site (13)". r3 used the wrong unit, missing 3
    repo write sites that only invalidate per-id `conversationProvider(id)`
    instead of global `conversationsProvider`.
  - Added 3 missed sites to migration table: `analysis_screen.dart:541` /
    `:613` / `:649` (message toggle / edit / delete; all `controller.save(c)`).
  - Migration table now lists all 13 repo write sites with explicit Op +
    paired invalidate column (per-id vs global vs none) for traceability.
  - Verification gate restructured: primary gate now greps
    `repository.{create,update,delete}Conversation` outside repo + controller
    + tests (expects 0 hits, no legitimate exceptions); secondary gate keeps
    the `ref.invalidate(conversationsProvider)` grep (still expects 5 hits).
  - 4 session-scope sites unchanged.
  - Manual smoke checklist adds: partner aggregate live updates after message
    edit / delete (the r3 missed scenario).

Evidence:
- [A2 plan](../plans/2026-04-26-partner-entity-A2-impl.md)
- [ADR-15](../decisions.md)
- `26b2f83` (r1 plan)
- `f89bec3` (r2 plan)
- `2a1163d` (r3 plan — narrow contract redefined + 4 missed sites + ZWJ + post-A2 cleanup §)
- `f1c7f29` (r4 plan — migration unit fixed to repo-write-site; 3 missed sites added; primary gate改 repo-write grep)
- [Codex review doc](./2026-04-26_partner-entity-A2-plan_codex-review.md)

Open-Risks:
- ~~Controller contract may be too narrow for remaining global consumers~~ —
  closed in r3.
- ~~Partner summary boundary test may still be weaker than the real ZWJ case~~ —
  closed in r3.
- ~~Migration table may miss direct repo writes that only do per-id invalidate~~ —
  closed in r4 by switching the unit-of-analysis to repo write sites and
  adding the repo-write grep as the primary verification gate.
- Deep-link/no-history route behavior still needs explicit test coverage
  (Task 6 — addressed in r1 plan, non-blocking per Codex).
- Post-A2 cleanup PR (retire `conversationsProvider`) deferred to follow-up
  ~2 weeks after A2 ship; spec is in plan §「Post-A2 cleanup」.

Claude-Position:
- Keep D1-D4 on their plan-defaults unless Eric explicitly overrides them.
- Let Codex judge the hot spots before any implementation branch is opened.
- Do not reopen ADR-15 or A1; this is an A2-only buildout.
- Eric chose option (a) `ConversationWriteController` over a repo-exposed
  partner stream to avoid poking the A1-stable repository baseline.
- **r3 update (2026-04-26)** — Eric picked the folded path on Codex r2's two
  options: keep `conversationsProvider` invalidation in the controller during
  A2 (Codex option 1), but redefine the narrow contract so this is not a
  contract violation. Rationale:
  (1) A2 scope discipline — option 2 (migrating reports off global feed in A2)
      smuggles a report-module refactor into A2, breaking ADR-15 scope and
      pushing 送審 timeline beyond the accepted ~2-week delay.
  (2) The over-strict r2 test ("controller never invalidates conversationsProvider")
      was Claude's over-spec; r1 HS-A2-1 only required cross-partner fan-out
      防火, not "never touches global". r3 restores the original contract intent.
  (3) `reportDataProvider` is a pure pass-through to `ReportDataService.generateReport()`;
      recompute cost on each conversation write is acceptable at VibeSync's user
      scale (O(50) conversations per user).
  (4) Truly retiring `conversationsProvider` lives in §「Post-A2 cleanup」, an
      independent follow-up PR scheduled ~2 weeks post A2 ship.
- **r4 update (2026-04-26)** — Eric picked Codex's recommended option 1 (quick
  doc patch) on r3's WAITING_ON_DAISY verdict. r4 closed the migration-unit
  gap by switching the analysis basis from invalidate sites to repo write
  sites and tightening the verification gate accordingly. Architecture
  direction unchanged from r3 (controller / narrow contract / session-scope
  distinction / post-A2 cleanup all preserved).

Codex-Position:
- **r3 latest**: architecture direction is acceptable, but one P1 execution-plan
  gap remains.
- r3 fixes the r2 blocker by redefining narrow as cross-partner fan-out
  prevention and keeping `_invalidateLegacyGlobal()` for legacy consumers like
  `reportDataProvider`.
- Task 4's `characters` truncation + explicit emoji ZWJ boundary test is now
  sufficient for the plan stage.
- Remaining gap: Task 3's migration table and verification gate only cover
  existing `ref.invalidate(conversationsProvider)` sites. Live code also has
  direct conversation writes without that invalidate:
  - `analysis_screen.dart:541` toggles message sender and saves
  - `analysis_screen.dart:613` edits a message and saves
  - `analysis_screen.dart:649` deletes a message and saves
- Those writes must be migrated through `ConversationWriteController`, or the
  plan must explicitly justify why any direct repository writes remain.
- Required gate: grep for direct `repository.createConversation`,
  `repository.updateConversation`, and `repository.deleteConversation` calls
  outside repository/tests, not only for `ref.invalidate(conversationsProvider)`.

Superseded r2 notes:
- r2 fixed three real issues from r1:
  - Task 3 now has a concrete invalidation owner
    (`ConversationWriteController`)
  - Task 4 now uses grapheme-safe truncation via `characters`
  - Task 5 / 6 / provider references are mostly corrected
- But I am still not passing the plan yet.
- New P1: the controller contract now explicitly forbids invalidating global
  `conversationsProvider`, while the live app still has non-Partner consumers
  depending on it, especially `reportDataProvider` / My Report. If A2 routes
  writes through the controller as written, report data can go stale.
- Required plan fix: either
  1. controller still updates those remaining legacy consumers during A2, or
  2. A2 migrates them off `conversationsProvider` before enforcing the
     no-global-invalidate rule.
- P2: Task 4 should keep the `characters` approach but strengthen the boundary
  test from generic non-ASCII to an explicit emoji ZWJ / grapheme case.
- HS judgments:
  - HS-A2-1: still revise before implementation
  - HS-A2-2: almost closed; just strengthen the boundary test
  - HS-A2-3: acceptable to keep ingest path non-deduping; banner/manual merge
    is sufficient, no Daisy arbitration needed
  - HS-A2-4: 7-8 dev days is tight but plausible after the Task 3 rewrite
  - HS-A2-5: deep-link/no-history case needs explicit test coverage, but does
    not block the plan
  - D1-D4: no override needed from Eric on this review round

Verdict:
- r3: WAITING_ON_DAISY (architecture OK; migration-unit gap on direct repo
  writes remained).
- r4 (`f1c7f29`): pending Codex re-review.

Eric-Decision:
- 2026-04-26: chose Codex's recommended option 1 (quick r4 doc patch). Patch
  was bounded to the migration table + verification gate; architecture from r3
  preserved unchanged.

Action-Items:
- [x] Claude wrote the A2 plan
- [x] Claude pushed the plan to `main`
- [x] Claude opened the queue item
- [x] Codex completed the first plan review
- [x] Claude revised the plan (commit `f89bec3`, r2)
- [x] Codex re-reviewed r2
- [x] Claude revised the plan again (commit `2a1163d`, r3):
      - Task 3 narrow contract redefined + `_invalidateLegacyGlobal()` added
      - Task 3 test list rebuilt
      - Task 3 migration table 9 → 13 sites (4 session-scope separated)
      - Task 4 boundary test upgraded to explicit ZWJ emoji case
      - New §「Post-A2 cleanup」 spec added
- [x] Codex re-reviewed r3 plan @ `2a1163d` (verdict: WAITING_ON_DAISY,
      migration-unit gap)
- [x] Eric decided: do the small r4 patch (option 1)
- [x] Claude shipped r4 plan patch (commit `f1c7f29`):
      - migration table unit-of-analysis: invalidate site → repo write site
      - 3 missed sites added (`analysis_screen.dart:541/613/649`)
      - 13-site full table with Op + paired invalidate column
      - primary verification gate: repo-write grep (0 hits expected)
      - secondary gate kept: invalidate grep (5 hits expected)
- [ ] **Codex re-reviews r4 plan @ `f1c7f29`** ← next action
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
  HS1 / HS2?

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
