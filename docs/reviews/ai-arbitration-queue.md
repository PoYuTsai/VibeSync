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

## [2026-04-25] Partner Entity Refactor - A1 Implementation Code Review
Status: IN_REVIEW
Request-Type: review
Raised-By: Claude
Owner: Claude
Scope: review
Branch/Commit: `feature/partner-entity-A1` @ `working-tree`

Question:
- Does the A1 implementation faithfully execute the approved v2 spec? Two
  spec-uncovered judgment calls (HS1 / HS2 below) need explicit Codex
  rulings before A1 lands on `main`.

Context:
- A1 phase = schema + migration only (no UI). A2 ships Partner UI / merge /
  AI prompt summary after A1's TF soak.
- Claude reports 12 commits on the branch, 20 new tests, and no regression vs
  the existing `main` test baseline.
- This queue item is restored on the branch so the code review outcome has a
  durable handoff target inside the PR branch itself.

Changed:
- New Partner entity / repository / migration service / deterministic id factory
- `Conversation.partnerId` field added
- `StorageService.initialize()` now opens the Partner box and runs migration
- 20 new unit / integration tests around migration
- Codex follow-up patch removes the direct `dart:io` import from the shared
  startup path by moving backup I/O behind a conditional import helper
- Codex follow-up patch changes migration completion semantics so partial-failure
  passes stay retryable on next boot instead of writing the done flag

Evidence:
- `53e7b85`
- [A1 implementation review doc](./2026-04-25_partner-entity-A1_codex-review.md)
- `lib/core/services/storage_service.dart`
- `lib/features/partner/data/services/partner_migration_service.dart`
- `test/unit/services/partner_migration_service_test.dart`
- `grep -rn 'typeId:' lib/`

Open-Risks:
1. The two P1 findings have been patched in-code, but clean-env verification is
   still pending because this workstation's Windows toolchain is pointed at a
   WSL-authored `.dart_tool/package_config.json`
2. Task 11 redo UI is still deferred to A2, so A1 cannot rely on manual redo as
   the only recovery path

Claude-Position:
- HS1: defer `sentry_flutter` until after TF soak; keep A1 on
  `dart:developer.log`
- HS2: keep redo-rebackup; user-triggered redo should treat current local state
  as ground truth
- Task 11 remains deferred to A2 per the blast-radius constraint

Codex-Position:
- `typeId = 8` remains valid; re-grep confirms `0..7` are occupied and `8` is
  free on this branch.
- HS1: approve defer. After the two implementation blockers below are fixed,
  A1 may keep `dart:developer.log(name: 'partner_migration')` for the TF soak
  instead of adding `sentry_flutter`.
- HS2: keep the current redo-rebackup policy.
- Codex directly patched the two original P1 findings:
  1. `StorageService` now calls a conditional-import backup helper instead of
     importing `dart:io` directly on the shared startup path.
  2. `PartnerMigrationService.runIfNeeded()` now keeps partial-failure passes
     retryable by skipping the done flag when any row failed.
- The branch is closer, but I still want one clean-env targeted test run before
  opening the PR because this workstation cannot currently run reliable
  Flutter verification on the branch.

Verdict:
- PATCHED - await clean-env verification, then PR.

Eric-Decision:
- Pending

Action-Items:
- [x] Claude implemented A1 on `feature/partner-entity-A1`
- [x] Codex reviewed HS1 / HS2
- [x] Codex fixed the direct `dart:io` import in `StorageService`
- [x] Codex fixed migration completion semantics so partial-failure runs stay
      retryable
- [ ] Claude / CC runs the targeted branch tests in a clean env and reports back
- [ ] Codex confirms the clean-env test result and gives the PR go/no-go
- [ ] Only after that: open the PR and start TF soak

Close-Condition:
- The P1 fixes are validated in a clean env and the branch is ready for PR
  creation.

## [2026-04-25] Partner Entity Refactor - Design Spec Review
Status: CLOSED
Request-Type: review
Raised-By: Claude
Owner: Codex
Scope: architecture
Branch/Commit: `5e10b86` → A1 plan on `feature/partner-entity-A1`

Question:
- Does spec v2 fully close the v1 P1 / P2 findings, or does any blocker remain
  before A1 implementation planning?

Context:
- v1 review verdict was `Critical flaw`; see
  `docs/reviews/2026-04-25_partner-entity-design_codex-review.md`.
- Eric authorized Claude to revise the spec without reopening the locked
  brainstorm decisions.
- Codex re-reviewed spec v2 against the original blockers plus the new v2
  open-risk list.

Changed:
- Spec v2 moved `Partner` from `typeId=5` to `typeId=8`.
- Migration was rewritten around deterministic UUID v5 +
  `conversation.partnerId` as the idempotency marker.
- Partner summary got a hard size cap and ranking rules.
- Provider invalidation was narrowed from "any conversation change" to
  partner-scoped invalidation.
- A1 estimate was demoted from `1.5 day` to `TBD pending Codex re-review`.

Evidence:
- [Design doc v2](../plans/2026-04-25-partner-entity-design.md)
- [Codex review doc](./2026-04-25_partner-entity-design_codex-review.md)
- `grep -rn 'typeId:' lib/`
- `lib/features/conversation/domain/entities/conversation.dart`
- `supabase/functions/analyze-chat/index.ts`

Open-Risks:
1. `conversationsByPartnerProvider(partnerId)` must stay truly partner-scoped
   and not reintroduce global provider fan-out via `conversationsProvider`
2. A1 implementation plan should re-estimate coding work above the original
   `1.5 day` number

Claude-Position:
- v2 closes v1 P1 blockers via algorithmic change, not cosmetic relabeling.
- v2 turns token budget and invalidation from hopes into explicit rules.
- A1 estimate was correctly reopened instead of being hand-waved.

Codex-Position:
- v2 closes the v1 P1 blockers.
- Verified by fresh repo grep: `typeId 0..7` are occupied and `typeId = 8` is
  free, so the new `Partner` id no longer collides.
- The migration design is now rerun-safe at spec level: deterministic UUID v5
  from `conversation.id` + `conversation.partnerId` as the marker means partial
  runs converge instead of duplicating Partner rows.
- The token-budget risk is now bounded enough for planning: hard cap `1500`
  chars, `N=8` ranking, and parsed-field assembly instead of raw JSON.
- The Riverpod fan-out issue is reduced to an implementation constraint:
  `conversationsByPartnerProvider(partnerId)` must stay truly partner-scoped and
  not be backed by the full `conversationsProvider`.
- A1 should be re-estimated above the original `1.5 day`; `2-3 dev days` plus
  the planned TF soak is a more realistic planning baseline.

Verdict:
- PASS - spec v2 is approved for A1 implementation planning.

Eric-Decision:
- Pending

Action-Items:
- [x] v1 Codex review completed and critical doc opened.
- [x] Claude revised the spec to address v1 P1 / P2 findings.
- [x] Codex re-reviewed spec v2.
- [x] v2 approved for A1 implementation planning.
- [x] A1-only implementation plan written: `docs/plans/2026-04-25-partner-entity-A1-impl.md`.

Close-Condition:
- Claude has started the A1-only implementation plan from the approved v2 spec. ✅ Met.

Follow-up:
- Plan baked in Codex constraints C1 (partner-scoped provider stays partner-scoped — A2 author responsibility),
  C2 (A1 effort = 2–3 dev days + 1–2 day TF soak), C3 (first impl step re-greps typeId).
- A1 execution + Codex A1 code review = a new queue item once A1 ships, not an append here.
