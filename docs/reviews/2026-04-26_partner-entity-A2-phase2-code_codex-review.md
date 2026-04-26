# Partner Entity A2 Phase 2 Code Review — Codex

Date: 2026-04-26
Branch: `feature/partner-entity-A2-ui`
Reviewed HEAD: `d9ce767`, then r2 scoped review at `f9815b7`
Verdict: **APPROVED_WITH_TF_QA_NOTE**

## Findings

### [P1] Partner detail "新增對話" created unscoped conversations

`PartnerDetailScreen` exposed a user-facing "新增對話" FAB, but it opened the
legacy `NewConversationSheet` without passing the current `partnerId`.

Impact: a user on Alice's detail page could create a new conversation that is
not attached to Alice. The row would navigate to `/conversation/:id`, but later
it would not appear under Alice's `conversationsByPartnerProvider` list or feed
Alice's aggregate/AI context. This is worse than a deferred Phase 3 feature
because the Phase 2 UI made the action look partner-scoped.

Fix applied by Codex:

- `NewConversationSheet` now accepts optional `partnerId`.
- Manual entry navigates to `/new?partnerId=...`.
- `NewConversationScreen` reads that query param and passes it into
  `ConversationWriteController.create`.
- The screenshot-start path also passes `partnerId` directly into
  `create(...)`.
- `PartnerDetailScreen` passes its current `partnerId` to the sheet.
- Added a widget test asserting the sheet receives the current `partnerId`.

### [P2] Create flows could fail without user-visible recovery

`AddPartnerScreen._submit` set `_busy = true` and then awaited repository write.
If that write threw, the button could stay locked and the user would not get a
recoverable error path.

Fix applied by Codex:

- Wrapped the create flow in `try/catch/finally`.
- Shows a snackbar on failure.
- Always restores `_busy` while mounted.
- Also wrapped the `NewConversationSheet` screenshot-start create path with a
  snackbar fallback and captured `GoRouter` before dismissing the sheet.

## Reviewer asks

- Navigation test omission: acceptable only as a temporary harness gap. The
  manual TF checklist still needs to verify back-stack behavior.
- Radar card "未分析" label: no blocker. Current behavior already falls back
  when `lastAnalysisSnapshotJson` is null/malformed or lacks `dimensions`; this
  is acceptable for Phase 2. Copy polish can wait for Phase 4.

## Verification

- `git diff --check` passed.
- Local `go_router-14.8.1` source confirms `GoRouterState.uri` exists.
- `flutter test`, `flutter analyze`, `flutter --version`, and `dart --version`
  all timed out in this shell, so Dart/Flutter verification is **not** complete
  in Codex. Claude/CC should rerun the 19+1 widget tests and touched-file
  analyze before opening/merging the PR.

## Next step

Claude should rerun:

```bash
flutter test test/widget/router_test.dart \
  test/widget/features/partner/add_partner_screen_test.dart \
  test/widget/features/partner/partner_list_screen_test.dart \
  test/widget/features/partner/partner_detail_screen_test.dart \
  test/widget/features/partner/partner_radar_summary_card_test.dart

flutter analyze lib/app/routes.dart \
  lib/features/conversation/presentation/screens/new_conversation_screen.dart \
  lib/features/conversation/presentation/widgets/new_conversation_sheet.dart \
  lib/features/partner/presentation/screens/add_partner_screen.dart \
  lib/features/partner/presentation/screens/partner_detail_screen.dart \
  test/widget/features/partner/partner_detail_screen_test.dart
```

## r2 scoped review — 2026-04-26

Scope: only `f9815b7` plus the explicit reviewer asks.

Verdict: **APPROVED_WITH_TF_QA_NOTE** after one Codex P2 follow-up fix.

### `f9815b7` findings

No blocker in the two-file test infra patch.

- `partner_detail_screen_test.dart`: setting the test surface to `400x900` is
  acceptable. The old 800x600 default was an artificial bottom-sheet height
  constraint, not a production phone layout.
- `add_partner_screen_test.dart`: accepting `skip: true` is reasonable for
  this phase. The disclosure is explicit, the surrounding auth-gate tests
  still run, and the end-to-end submit/navigation contract is now a required
  TF QA item.

Important caveat: `PartnerRepository` unit tests do not fully replace the
skipped widget test, because they do not prove `AddPartnerScreen` maps
`authConversationScopeProvider` into `Partner.ownerUserId`. The source code is
simple enough to accept this as a temporary harness gap, but the PR body / TF
checklist should keep the manual submit path.

### Reviewer asks

- Skip: accepted as a temporary Windows `flutter_test` harness limitation.
  Long-term fix is `integration_test/`, not more local cache archaeology.
- Radar "未分析" label: no Phase 2 blocker. Current fallback is safe; copy polish
  can live in Phase 4 Task 15.
- `NewConversationScreen._createConversation` missing catch: accepted as a P2
  follow-up and fixed directly by Codex. Manual-entry create failures now show a
  snackbar instead of surfacing as an unhandled error while only resetting
  loading state.

### Final gate

Before PR merge, Claude should rerun the touched tests/analyze after this P2
fix. If green, Phase 2 is ready to open/merge with the TF QA note preserved.
