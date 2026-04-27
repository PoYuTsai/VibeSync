# Partner Entity A2 Phase 3 PR-A Code Review - Codex

Date: 2026-04-27
PR: #5 `feature/partner-entity-A2-flows-data` -> `main`
Base: `origin/main` @ `f2e791d`
Reviewed branch: `b992b58` plus Codex follow-up `d6cb659`
Scope: PR-A partnerId chain validation, test/docs only

## Findings

### [P2] Sheet manual-entry route hop was not covered - fixed

Anchors:

- Production: `lib/features/conversation/presentation/widgets/new_conversation_sheet.dart:20-27`
- Production: `lib/features/conversation/presentation/widgets/new_conversation_sheet.dart:64-68`
- Test: `test/widget/features/conversation/new_conversation_sheet_screenshot_test.dart`

PR-A claimed coverage for both manual and screenshot conversation creation
paths, but the tests did not cover the sheet's manual-entry hop itself. The
manual path tests mounted `NewConversationScreen(partnerId: ...)` directly, and
the sheet tests only covered screenshot creation. A regression in
`NewConversationSheet._manualEntryLocation` could drop the `partnerId` from
`/new?partnerId=...` while all PR-A tests still passed.

Fixed in `d6cb659` by making the `/new` route stub expose the query
`partnerId` and adding two route-sentinel widget tests:

- sheet `partnerId="p-test"` + manual entry routes to `manual-entry:p-test`
- sheet `partnerId=null` + manual entry routes to `manual-entry:null`

No production code changed.

## Review Results

- Hermetic boundary: OK. `RecordingConversationWriteController` is an in-memory
  test notifier and does not touch Hive, Supabase, or network state.
- partnerId chain contract: OK after `d6cb659`. The branch now covers
  `NewConversationScreen` value/null, sheet screenshot value/null, and sheet
  manual route value/null.
- r2 plan patches: OK. `_fillNameAndOneMessage()` adds a real message before
  tapping the CTA, and CTA targeting uses the production `GradientButton`
  surface.
- Reality Check: OK. The tests assert current behavior: null `partnerId` passes
  through as null, with no auto-derive-on-create and no default-name behavior
  smuggled into PR-A.
- Plan deviations: OK. `_settle()` instead of `pumpAndSettle()` and larger test
  surfaces are reasonable test-harness accommodations for this Flutter widget
  environment.
- Test-rot risk: Acceptable. The new manual-route tests use the stable icon and
  a route sentinel instead of copy-sensitive assertions.

## Verification

- `flutter test test\widget\features\conversation\new_conversation_screen_partner_id_test.dart test\widget\features\conversation\new_conversation_sheet_screenshot_test.dart --reporter expanded` -> 6/6 pass
- `flutter analyze test\widget\features\conversation\_fakes\recording_conversation_write_controller.dart test\widget\features\conversation\new_conversation_screen_partner_id_test.dart test\widget\features\conversation\new_conversation_sheet_screenshot_test.dart` -> no issues

Note: in Codex desktop on this Windows workspace, Flutter must run outside the
filesystem sandbox; the sandbox blocks Flutter's child `where aapt` probe. The
verification above was run through the approved escalated Flutter command path.

## Merge Readiness

No remaining blocking findings. PR-A remains test/docs only and does not touch
OCR, `analyze-chat`, or production app code.

Verdict: APPROVED
