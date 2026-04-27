# Partner Entity A2 Phase 3 PR-B Code Review - Codex

Date: 2026-04-27
Branch: `feature/partner-entity-A2-flows-pickers`
Reviewed implementation: `0ce4d12..a7aa667` plus Codex follow-up patch
Plan baseline: `docs/plans/2026-04-27-partner-entity-A2-phase3-pr-b-impl.md` @ `843d98f`
Scope: merge picker + conversation reassign menu

## Findings

### [P2] Merge failure could leave provider caches stale after partial Hive writes - fixed

Anchors:

- Production: `lib/features/partner/data/providers/partner_write_controller.dart:28-34`
- Test: `test/unit/features/partner/partner_write_controller_test.dart:246-278`

`PartnerWriteController.merge()` only invalidated partner/conversation scopes after
`PartnerRepository.merge()` returned successfully. The repository merge is multi-step
Hive I/O: it moves conversations, saves the target note, then deletes the source.
If a failure occurs after a partial conversation move, the UI would show the failure
SnackBar while Riverpod could keep returning cached pre-merge provider values.

Fixed by moving merge-scope invalidation into a `finally` block. Added a unit test
with a partially failing repository double that moves one conversation and throws;
the test proves source and target `conversationsByPartnerProvider` scopes refresh
even on the failure path.

### [P3] Pre-existing info-level lint in controller test - fixed

Anchor:

- Test: `test/unit/features/partner/partner_write_controller_test.dart:65-67`

The top-level test variables used public names with a private type
(`late _CountingConversationRepository convoRepo`), triggering
`library_private_types_in_public_api`. Renamed the test globals to private names
so this branch no longer needs to carry Q3 as a follow-up.

## Open-Risk Decisions

- Q1 reassign failure SnackBar: accept current behavior. Keeping the sheet open is
  the better UX because the user can retry immediately, and the test proves the
  in-memory `conversation.partnerId` rolls back on save failure.
- Q2 `conversationsProvider` invalidation in `PartnerWriteController.merge`: accept
  as an A2 transition wart. It matches the existing `ConversationWriteController`
  contract and is explicitly tagged for post-A2 cleanup when report data leaves the
  legacy global feed.
- Q3 lint cleanup: fixed in this Codex patch, no separate cleanup needed.

## Review Results

- Plan coverage: OK. Tasks 1-8 are represented in code/tests, including
  `PartnerWriteController`, shared picker, confirm dialog, merge route, tile menu,
  reassign picker, PartnerDetail wiring, and CI subset expansion.
- Route behavior: OK. The `/partner/:partnerId/merge` route is covered by widget
  tests, including the same parametric route shape used by production.
- Merge UX: OK after the failure-path invalidation patch. Successful merge navigates
  to the target partner; failed merge stays on the picker and shows a SnackBar.
- Reassign UX: OK. Save success pops the modal; save failure keeps the sheet open,
  rolls back `partnerId`, and shows a SnackBar.
- Test boundaries: acceptable. The duplicate recording fakes are scoped and marked
  for Phase 4 cleanup.
- OCR / Edge Functions: untouched.

## Verification

- Static review: read changed production files + high-risk widget/unit tests.
- Grep contract: no direct `repository.create/update/deleteConversation` calls found
  in `lib` / `test` from this patch path.
- `git diff --check`: no whitespace errors; output only repository-wide CRLF warnings
  unrelated to this branch.
- Local verification caveat: Windows `dart format` and `flutter test` hung in this
  Codex desktop environment; WSL invocation hit the Windows Flutter CRLF shim. Per
  `docs/shared-agent-rules.md`, Claude/WSL remains the Flutter test owner and should
  rerun the touched unit test before PR merge:
  `flutter test test/unit/features/partner/partner_write_controller_test.dart`.

Verdict: REVISED_AND_APPROVED
