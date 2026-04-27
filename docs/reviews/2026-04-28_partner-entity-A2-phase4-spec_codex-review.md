# Partner Entity A2 Phase 4 Spec Review — Codex

> Date: 2026-04-28
> Scope: `docs/plans/2026-04-28-partner-entity-A2-phase4-design.md`
> Verdict: REVISED_AND_APPROVED

## Summary

Phase 4 direction is sound: Task 18 first, then dedupe banner, copy sweep,
deprecated cleanup, and ship gate is the right sequence. I patched the spec
because a few implementation contracts did not match the code that Phase 3
already shipped.

## Findings Patched

### P1 — Delete API referenced non-existent provider / repository surfaces

The draft called `listByPartner(partnerId)` from `PartnerRepository.delete()`,
but `PartnerRepository` currently has no public `listByPartner` surface; it
owns a lazy `_conversationBox` getter instead. The controller example also
invalidated `partnerListProvider(partner.ownerUserId)`, but
`partnerListProvider` is not a family.

Patch:
- `PartnerRepository.delete()` now guards by scanning `_conversationBox.values`.
- `PartnerWriteController.delete()` now uses `ref.read(partnerRepositoryProvider)`
  and invalidates `partnerByIdProvider`, `partnerAggregateProvider`,
  `conversationsByPartnerProvider`, and `partnerListProvider`.

### P1 — Delete dialog used aggregate rounds as a conversation-existence guard

The draft used `aggregate.totalRounds == 0` to choose confirm vs informational
dialog. That can be false-safe: a partner can have a conversation with zero
rounds, and delete must still be blocked.

Patch:
- `PartnerListScreen` must pass `conversationCount` from
  `conversationsByPartnerProvider(partner.id).length`.
- Tests now include the zero-round conversation case.

### P2 — Banner dismissed state needed an async-state contract

`PartnerBannerService.isDismissed()` is async, but the draft did not specify
how `PartnerListScreen` should consume it. That leaves room for build-time
awaits or a visible banner flicker before SharedPreferences resolves.

Patch:
- Added `partnerDedupeBannerDismissedProvider =
  FutureProvider.family<bool, String>`.
- Loading/error states hide the banner; dismiss invalidates the provider after
  persisting the uid-scoped flag.

### P2 — Merge picker `?target=` needed exact preselect semantics

The draft said "pre-select row" but did not lock how this interacts with the
existing PR-B picker flow.

Patch:
- No query param preserves the original row-tap confirm flow.
- Valid target preselects and shows a confirm CTA, but does not auto-open a
  destructive dialog.
- Unknown/self target is ignored.

### P2 — Tag preview should not starve traits

`(interests + traits).take(3)` can show only interests. Since traits are often
more descriptive, the spec now interleaves interests and traits before capping
to 3.

## Hot Spot Verdicts

- HS-P4-1: single `PartnerHasConversationsException` is OK; enum is YAGNI.
- HS-P4-2: `try/finally` invalidation is acceptable after provider API fixes.
- HS-P4-3: presentation-layer duplicate detection is acceptable; async banner
  dismissed state must be provider-backed.
- HS-P4-4: optional `?target=` route param is backward-compatible with the
  patched preselect contract.
- HS-P4-5: use interleave, not simple take.

## Verdict

REVISED_AND_APPROVED. Claude can proceed to the Phase 4 implementation plan
from the patched design doc.
