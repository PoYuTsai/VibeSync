# Partner Entity A2 Phase 3 PR-A Plan Review - Codex

Date: 2026-04-27
Branch: `feature/partner-entity-A2-flows-data`
Reviewed HEAD: `360ce07`
Plan: `docs/plans/2026-04-27-partner-entity-A2-phase3-pr-a-impl.md`
Design: `docs/plans/2026-04-27-partner-entity-A2-phase3-design.md`

Verdict: REVISE_BEFORE_IMPLEMENTATION

## Findings

### [P1] Manual-path helper never adds a message

`docs/plans/2026-04-27-partner-entity-A2-phase3-pr-a-impl.md:167-176`

`_fillNameAndOneMessage()` only enters the first `TextField` (`Alice`) and then settles. It does not enter the second `TextField` nor tap the "her message" add control. In production, `NewConversationScreen._createConversation()` returns early when `_messages.isEmpty`, so Tasks 2 and 3 will not call `ConversationWriteController.create()` and will not validate the partnerId chain.

Patch r2 to make the helper actually add one incoming message, for example:

```dart
await t.enterText(find.byType(TextField).first, 'Alice');
await t.enterText(find.byType(TextField).at(1), '嗨');
await t.tap(find.byIcon(Icons.add).first);
await t.pumpAndSettle();
```

If the icon finder is unstable, adding a production `Key` as a test hook is acceptable, but keep it isolated in its own small commit.

### [P1] CTA finder targets a widget that does not exist

`docs/plans/2026-04-27-partner-entity-A2-phase3-pr-a-impl.md:194` and `:256`

The plan uses `find.widgetWithText(ElevatedButton, RegExp('儲存|建立').toString())`, but production renders the CTA as `GradientButton`, not `ElevatedButton`. Also, `RegExp(...).toString()` produces a literal string rather than a regex matcher. After fixing the helper above, this finder still cannot reliably tap the real CTA.

Patch r2 to target the actual UI surface, for example `find.text('建立對話')`, `find.byType(GradientButton)`, or a stable `Key` on the `GradientButton`.

## Open-Risk Acknowledgement

- R1 accepted: PR-A should not test auto-derive-on-create or default `YYYY/MM/DD 新對話` because current code does not implement either behavior. `ConversationRepository.createConversation()` stores `partnerId` as passed, while `PartnerIdFactory.deriveFromConversationId()` is migration-only.
- R2 accepted with constraint: adding widget `Key`s for testability is fine if the finder cannot be made stable, but the key-only production diff should be isolated and not change user-visible behavior.
- R3 accepted: the minimal `GoRouter` harness is appropriate because `NewConversationSheet` and `NewConversationScreen` depend on router plumbing for `push` / `go`; keep the harness sentinel-only and avoid full app router/auth side effects.
- R4 accepted: no ADR-16 is needed before PR-A. Deferring auto-derive/default-name is a scoped execution decision, not a durable architecture decision yet. Write an ADR only if Phase 4 permanently rejects or implements that behavior.

## Required r2 Patch

Update the plan before implementation:

- Make `_fillNameAndOneMessage()` create one real incoming message.
- Replace the CTA finder with `GradientButton`, visible text, or a stable key.
- Keep the Reality Check section as-is; it is the right scope boundary.

After that patch, this plan should be small enough for a scoped r2 re-review.

## r2 Scoped Re-review

Date: 2026-04-27
Reviewed commits: `59b26b1` plan patch + `9c5df4d` queue update

Verdict: APPROVED

No new findings.

The r2 patch resolves both r1 blockers:

- `_fillNameAndOneMessage()` now fills the second `TextField`, taps the first
  `Icons.add`, and therefore creates one real incoming message before tapping
  the create CTA. This prevents the `_messages.isEmpty` early return.
- The CTA finder now targets the actual production surface:
  `find.byType(GradientButton)`, with `find.text('建立對話')` as an additional
  assertion after `_hasIncomingMessage=true`.

The `GradientButton` import is valid because `warm_theme_widgets.dart` exports
`gradient_button.dart`.

The earlier risk acknowledgements still stand: PR-A should not add
auto-derive/default-name behavior, and a production `Key` remains acceptable
only as an isolated testability fallback if the icon finder proves unstable
during implementation.
