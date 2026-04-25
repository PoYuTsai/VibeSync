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

## [2026-04-25] Partner Entity Refactor - Design Spec Review
Status: WAITING_ON_CODEX_REREVIEW
Request-Type: review
Raised-By: Claude
Owner: Codex
Scope: architecture
Branch/Commit: `working-tree`（spec v2 即將 commit）

Question:
- Does spec v2 fully close the v1 P1 / P2 findings, or does any blocker remain
  before A1 implementation planning?

Context:
- v1 review verdict: 🔴 Critical flaw (`docs/reviews/2026-04-25_partner-entity-design_codex-review.md`).
- Eric authorized Claude to revise spec without reopening locked brainstorm
  decisions (IA / Migration B / Union / Hybrid / Report D).
- v2 revision log lives at the top of the design doc.

Changed (v2 revision, 2026-04-25 18:05):
- §1 Data Model:
  - `Partner @HiveType(typeId: 5)` → `typeId = 8` with grep evidence.
  - Migration rewritten: `PARTNER_NAMESPACE_UUID` compile-time constant,
    deterministic UUID v5 from `conversation.id`, per-convo `partnerId` marker
    is the source of idempotency. SharedPreferences flag demoted to perf-only.
  - Crash scenario table covers loop interruption, account switch, OOM,
    backup failure.
- §3 Aggregation:
  - Riverpod invalidation narrowed to `partnerAggregateProvider(partnerId)`
    instead of fanning out on any conversation change.
  - Partner summary now has hard char cap (1500), ranking rules
    (`lastInteraction` desc, N=8 for interests / traits, N=5 for notes), and
    explicit assembly source (`lastAnalysisSnapshotJson` parsed fields, not
    raw JSON).
  - Pre-assembly safety checks added (length assert, ownerUserId mismatch,
    parse-fail isolation).
- §5 Tests:
  - Idempotent + crash-safe rerun unit test.
  - Deterministic UUID v5 contract + namespace constant regression guard.
  - Summary truncation tests for 30-conversation worst case.
  - Narrow invalidation tests.
  - Integration test extended with crash-safe rerun + backup byte-equality.
- §6 Phasing:
  - A1 estimate `1.5 day` marked `TBD` pending Codex re-review.
  - 9-10 day overall envelope retained, but internal allocation pending.

Evidence:
- [Design doc v2](../plans/2026-04-25-partner-entity-design.md) — see top "Spec Revision Log"
- [v1 critical review doc](./2026-04-25_partner-entity-design_codex-review.md)
- `grep -rn 'typeId:' lib/` → 0..7 occupied; 8 free as of 2026-04-25 18:05
- `lib/features/conversation/domain/entities/conversation.dart:8-62` → fields 0..14 used; 15 free

Open-Risks (deferred to v2 re-review):
1. Crash scenario table coverage — any unhandled path?
2. Truncation rules (N=8, cap=1500) — Free Haiku tier worst case still safe?
3. Narrow invalidation — does `conversationsByPartnerProvider` introduce its
   own fan-out problem?
4. A1 re-estimate — what is the realistic span after migration rewrite?
5. New test surface — anything still uncovered?

Claude-Position:
- v2 closes v1 P1 blockers via algorithmic change (deterministic UUID + per-convo
  marker) instead of just relabeling.
- v2 P2 findings (token budget, Riverpod fan-out) addressed with hard rules,
  not aspirations.
- A1 estimate honestly left as TBD instead of papering over the gap.

Codex-Position:
- v1 review complete (🔴 Critical, see review doc).
- v2 re-review pending.

Verdict:
- v1: Critical flaw - revise spec before A1 implementation planning. ✅ Done.
- v2: Pending re-review.

Eric-Decision:
- 2026-04-25 18:05 — Authorized Claude to revise spec along the lines proposed
  in DC (deterministic UUID + per-convo marker + hard token cap + narrow
  invalidation + A1 TBD). No reopening of brainstorm decisions.

Action-Items:
- [x] v1 Codex review complete + critical doc opened.
- [x] v1 P1 blockers revised in spec:
  - typeId=8 with grep evidence
  - rerun-safe migration via deterministic UUID v5 + per-convo marker
- [x] v1 P2 findings addressed:
  - Partner summary char cap + ranking + assembly source
  - Riverpod narrow invalidation
  - A1 estimate marked TBD
  - test coverage extended
- [x] queue item updated with v2 changeset.
- [ ] **Codex re-review** spec v2 against v1 findings + new "Open-Risks
  deferred to v2 re-review" list above.
- [ ] If v2 re-review verdict 🟢 PASS → status APPROVED → open new Claude
  session to write A1 implementation plan.

Close-Condition:
- Codex v2 re-review verdict 🟢 PASS, A1 implementation plan started.
