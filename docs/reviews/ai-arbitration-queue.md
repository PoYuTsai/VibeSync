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

## [2026-04-25] Partner Entity Refactor — A1 Implementation Code Review
Status: OPEN
Request-Type: review
Raised-By: Claude
Owner: Codex
Scope: review
Branch/Commit: `feature/partner-entity-A1` @ `53e7b85` (pushed to origin)

Question:
- Does the A1 implementation faithfully execute the approved v2 spec? Two
  spec-uncovered judgment calls (HS1 / HS2 below) need explicit Codex
  rulings before A1 lands on `main`.

Context:
- A1 phase = schema + migration only (no UI). A2 ships Partner UI / merge /
  AI prompt summary after A1's TF soak.
- Implementation followed the plan at `docs/plans/2026-04-25-partner-entity-A1-impl.md`.
- 12 commits on the branch. Tasks 0–10 + 12 implemented; Task 11 (settings UI
  redo entry) **intentionally deferred to A2** because no advanced/debug
  section exists in the current settings IA and the plan forbade inventing
  one for A1. The service surface (`PartnerMigrationService.resetForRedo()`)
  is in place so A2's UI hookup is a one-call wire.
- Subagent-driven-development workflow used for execution; each task ran
  through implementer → spec reviewer → code-quality reviewer.

HS-Review-Asks (Eric 2026-04-25, MUST be ruled on):
- **HS1 — Sentry SDK gap.** `pubspec.yaml` has no `sentry_flutter`. A1
  logs migration events via `dart:developer.log(name: 'partner_migration')`.
  Question: acceptable for the planned 1–2 day TF soak, or should A1 add
  `sentry_flutter` despite "minimum blast radius" framing? Trade-off: no
  remote signal during soak vs. one new SDK in A1.
  Code site: `lib/features/partner/data/services/partner_migration_service.dart`
  search for `_kLogTag`.
- **HS2 — Redo-backup policy.** `PartnerMigrationService.resetForRedo()`
  clears both `partner_migration_v1_done` and `partner_migration_v1_backup_done`,
  so the next `runIfNeeded` re-takes the backup, **overwriting the prior
  backup file**. Alternative: backup is one-shot, never overwritten.
  Spec §5 #6 is ambiguous; current choice = redo-rebackup, encoded by
  the test `redo re-takes the backup (HS2 hot spot)` in
  `test/unit/services/partner_migration_service_test.dart` asserting
  `backupCalls == 2`. If Codex flips the policy, the assertion + the
  `resetForRedo` dartdoc + the plan's HS2 description all need flipping.

Changed:
- New: `lib/features/partner/{domain/entities,data/repositories,data/services}/`
- Modified: `lib/features/conversation/domain/entities/conversation.dart` (+ `.g.dart`)
- Modified: `lib/core/services/storage_service.dart` (+ `lib/core/constants/app_constants.dart`)
- New tests: `test/unit/{entities,services,repositories}/...` + `test/integration/`
- Total: 20 new tests, all green.

Evidence:
- 12 commits, listed via `git log --oneline feature/partner-entity-A1 ^main`
- A1 branch test count: **227 PASS / 86 FAIL** (full `flutter test`)
- Main baseline test count: **207 PASS / 86 FAIL** — confirming all 86 failures
  are pre-existing baseline noise (settings_screen widget tests with
  pumpAndSettle timeouts, message_booster localization mismatches, etc.),
  **none introduced by A1**. Delta = +20 PASS / +0 FAIL.
- Continuity guard: `'conv-abc' → 3a9475c9-fb99-5117-8e19-6a42c0298c49`
  (Task 3 namespace constant + Task 6 happy path agree).
- Bruce regression guard: integration test asserts 5 conversations with
  2 named '糖糖' produce 5 distinct Partners (Migration B contract).
- Codex C3 evidence: re-grep typeId output verbatim in commit `4a46cf9`'s body.

Open-Risks:
1. HS1 unresolved → no remote signal if migration corrupts a TF user's box.
2. HS2 unresolved → ambiguous spec leaves redo behaviour up to interpretation.
3. Web platform (kIsWeb) untested in CI — backup short-circuits but the
   wider `StorageService.initialize()` path on Web is unverified.
4. Settings UI for `重做升級` is deferred to A2 (intentional). If a TF user
   suspects corruption before A2 ships, they have no in-app recovery — only
   a fresh install.
5. Pre-existing 86 failures on `main` are not addressed by this branch and
   represent ambient tech debt; flagging for awareness, not for this PR.

Claude-Position:
- Implementation is faithful to v2 spec on all sections that were ruled on.
- HS1: `dart:developer.log` is acceptable for the soak window because (a) Bruce
  + Eric are TF testing on physical devices we can hand-instrument, and
  (b) adding `sentry_flutter` in A1 expands blast radius beyond "schema +
  migration" — the dep's init code itself is a new failure surface during
  the very soak we'd be using it to observe. Recommend: add `sentry_flutter`
  in a dedicated commit AFTER A1 TF soak passes, BEFORE A2 starts.
- HS2: redo-rebackup is the safer default because the redo button is a user-
  initiated panic action — they're saying "something is wrong, try again".
  At that point a stale backup is more dangerous than a fresh one (the user's
  current Hive state is the new ground truth). One-shot backup would freeze
  the user's recovery point at first-run, which is wrong for the Bruce-style
  scenario where the bug manifested after multiple TF cycles.
- Task 11 deferral: defensible because the production settings IA has no
  natural slot, and inventing a "Debug" section for A1 violates the plan's
  blast-radius principle. A2 plan must include the UI hookup.

Codex-Position:
- Pending

Verdict:
- Pending

Eric-Decision:
- Pending

Action-Items:
- [x] A1 plan written (`docs/plans/2026-04-25-partner-entity-A1-impl.md`).
- [x] 12 implementation commits on `feature/partner-entity-A1`, pushed to origin.
- [x] 20 new tests, all green; zero regressions over `main` baseline.
- [ ] Codex reviews diff against design doc v2 + this queue item's HS1 / HS2.
- [ ] Codex rules on HS1 (Sentry now vs. after soak) and HS2 (redo-rebackup
      policy). If either rules differently, update tests + dartdoc + plan.
- [ ] Eric merges PR after Codex verdict.
- [ ] TF soak 1–2 days on the merged branch (Codex C2). A2 plan does NOT
      start until soak passes.
- [ ] After soak: flip ADR-15 status from 🟡 Proposed → 🟢 Active (A1 shipped).

Close-Condition:
- A1 lands on `main` with HS1 + HS2 resolved AND TF soak signed off.

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
