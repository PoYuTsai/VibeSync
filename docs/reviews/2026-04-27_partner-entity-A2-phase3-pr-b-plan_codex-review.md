# Partner Entity A2 Phase 3 PR-B Plan Review - Codex

Date: 2026-04-27
Branch: `feature/partner-entity-A2-flows-pickers`
Reviewed commits: `c4d9474` / `6b2a2f8`
Codex patch commit: `843d98f`
Plan: `docs/plans/2026-04-27-partner-entity-A2-phase3-pr-b-impl.md`
Design: `docs/plans/2026-04-27-partner-entity-A2-phase3-design.md`

Verdict: REVISED_AND_APPROVED

## Findings Fixed Directly

### [P1] Async merge was hidden behind a `VoidCallback`

Original anchors:

- `docs/plans/2026-04-27-partner-entity-A2-phase3-pr-b-impl.md` Task 3 dialog API
- `docs/plans/2026-04-27-partner-entity-A2-phase3-pr-b-impl.md` Task 4 merge picker `_confirm`

The original dialog API passed async destructive merge work through a
`VoidCallback`, then immediately dismissed the dialog. That could hide merge
failures and navigate inconsistently because the caller was not awaiting the
operation.

Fixed in `843d98f`: the dialog now returns `bool`; the picker screen awaits
`PartnerWriteController.merge()` after confirmation and shows a SnackBar on
failure.

### [P1] Plan snippets referenced nonexistent code symbols

Original anchors:

- Task 1: `_StubAuthScope('u1')`
- Task 1: `partnerAggregateProvider('B').count`
- Task 4: `fromAgg.traits.length`

These do not match the current codebase. The real auth override pattern is
`authConversationScopeProvider.overrideWith((ref) => Stream.value('u1'))`, and
`PartnerAggregateView` exposes `totalRounds`, `totalMessages`, and
`unionTraits`, not `count` or `traits`.

Fixed in `843d98f`: snippets now use the real provider override and
`totalRounds` / `unionTraits`.

### [P2] Reassign save failure could leave the in-memory conversation mutated

Original anchor:

- Task 6 `showConversationReassignPicker`

The original snippet set `conversation.partnerId = target.id` before `save()`
and did not roll it back if `ConversationWriteController.save()` failed.

Fixed in `843d98f`: the plan now restores the previous partnerId and shows a
SnackBar if save fails.

### [P2] New partner unit tests were not part of the PR CI gate

Original anchor:

- Task 8 full sweep

PR-B adds `PartnerWriteController` unit coverage, but the existing CI partner
subset only runs `test/widget/features/partner/`. Local-only unit tests are too
easy to miss during future review.

Fixed in `843d98f`: the plan now calls out updating `.github/workflows/flutter-ci.yml`
so PR checks also run `test/unit/features/partner/`.

## Open-Risk Acknowledgement

- R1 accepted: `PartnerWriteController` is the right correction. The design doc
  was wrong to imply repository-owned invalidation because `PartnerRepository`
  has no `Ref`.
- R2 accepted: deferring `showCreateNewAction: true` is appropriate for PR-B.
  Empty-state guidance is enough for this phase.
- R3 accepted: keeping `PartnerRepository.merge` as the transaction boundary is
  reasonable. `PartnerWriteController` can own post-hoc invalidation for both
  partner sides and the legacy global feed.
- R4 accepted: replacing the tile chevron with a visible `⋮` menu is the
  agreed B-variant trigger. Long-press does not need to be revived.
- R5 resolved: use `PartnerAggregateView.unionTraits.length`.
- R6 accepted with update: PR-A is now merged, so the fake is no longer
  off-limits. Because the PR-A fake only captures `create()`, PR-B may either
  extend it or create a reassign-specific partner fake and consolidate in Phase
  4 cleanup.

## Residual Notes

- PR-B branch was merged with latest `main` in `843d98f`; the queue now keeps
  PR-B live above the closed PR-A item.
- No OCR, `analyze-chat`, or production code was changed during this review.
- I did not run Flutter tests because this was a docs/spec review; the plan's
  implementation phase owns the TDD test runs.

Verdict: REVISED_AND_APPROVED
