# Partner Entity A2 Phase 4 Implementation Plan Review — Codex

> Date: 2026-04-28
> Branch: `feature/partner-entity-A2-polish`
> Scope: `docs/plans/2026-04-28-partner-entity-A2-phase4-impl.md`
> Verdict: REVISED_AND_APPROVED

## Summary

The implementation plan is directionally solid: Task 1-8 sequencing is right,
the TDD cadence is explicit, and it correctly maps design Tasks 18a/18b/14a/14b
to execution. I patched a few concrete traps that would otherwise surface as
compile failures or account-boundary bugs during implementation.

## Findings Patched

### P1 — Task 1 repository delete test snippet would not compile

The plan placed `partner_repository_delete_test.dart` under
`test/unit/features/partner/` and included an abbreviated test snippet that
missed required `Conversation` constructor fields (`messages`, `createdAt`) and
referenced an in-file helper that does not exist. Existing repository tests live
under `test/unit/repositories/` and already provide the correct Hive adapter
pattern.

Patch:
- Move the planned repo delete test to
  `test/unit/repositories/partner_repository_delete_test.dart`.
- Use the same `setUpAll` / `tearDownAll` Hive pattern as
  `partner_repository_merge_test.dart`.
- Add explicit helper constructors for `Partner` and `Conversation`.

### P1 — Task 4 preselect validation could bypass owner-scoped candidates

The plan validated `initialTargetId` via `partnerByIdProvider(initialTargetId)`.
That provider is a raw repository lookup, not the owner-scoped picker candidate
list. A query param should never be able to select a target outside
`partnerListProvider` candidates.

Patch:
- Validate `initialTargetId` against `partnerListProvider` after excluding
  `fromPartnerId`.
- Convert `PartnerMergePickerScreen` to `ConsumerStatefulWidget` for selected
  target state.
- Add a test: target outside the candidate list is ignored.

### P2 — Delete invalidation should stay partner-scoped

The plan proposed invalidating `conversationsProvider` from
`PartnerWriteController.delete()`. Unlike merge/reassign, delete only succeeds
when linked conversation count is zero, and failed delete does not mutate
conversations. Invalidating the global feed is unnecessary fan-out and cuts
against A2's narrow invalidation contract.

Patch:
- Remove `conversationsProvider` invalidation from the planned delete scope.
- Keep invalidation to `partnerListProvider`, `partnerByIdProvider`,
  `partnerAggregateProvider`, and `conversationsByPartnerProvider`.

### P2 — Task 2 needed compile/test hygiene notes

The PartnerListCard body references `DateFormat`, `GlassmorphicContainer`, and
`EnthusiasmLevel`, so the plan now explicitly lists imports. Existing
`partner_list_screen_test.dart` also asserts the old `N 段對話` subtitle, which
Phase 4 intentionally removes.

Patch:
- Add required imports to the plan.
- Tell implementation to update old render-test expectations and add
  `conversationsByPartnerProvider` overrides for every rendered row.

## Hot Spot Verdicts

- HP-P4-1: do not invalidate `conversationsProvider` for delete.
- HP-P4-2: `_previewTags` max-len loop is fine if interests-only and traits-only
  tests are included.
- HP-P4-3: preselect mode is compatible with PR-B when the no-query path keeps
  row tap -> confirm behavior.
- HP-P4-4: HomeContent removal gate is acceptable with grep + full analyze/test.
- HP-P4-5: copy sweep ordering is acceptable because banner/preselect copy ships
  before the sweep.

## Verdict

REVISED_AND_APPROVED. Claude can execute Tasks 1-8 from the patched plan.
