# 2026-04-30 ScoreActionHint + Two-Layer Plan Codex Review

Scope:
- Reviewed `279dd31` hotfix: `ScoreActionHint` dead-signal activation.
- Reviewed `15dd8a0` docs: two-layer profile design plan.

Findings:
- P1 fixed: low-heat defensive guard only covered `gameStage.nextStep`; `FinalRecommendation.reason` / `content` could still surface meeting or invite payload below very-hot.
- P2 fixed: two-layer plan described `userStyle` / `userInterests` as unused by Edge prompt, but Edge already renders them when received; the actual dead signal is the client payload gap.
- P2 fixed: plan referenced `analyzeMode === 'ocr'` / `'recognize-only'`, but current Edge OCR-only branch is controlled by `recognizeOnly`.
- P2 fixed: plan relied on dogfood for Partner HiveField 7 forward-compat; added an explicit Hive adapter round-trip test requirement.

Patch Summary:
- `ScoreActionHint` now applies the same low-heat meeting guard to headline, body, and example text.
- Added broader meeting-intent tokens for common CTAs such as coffee, dinner, movie, and go-together wording.
- Added widget coverage for low-heat recommendation payload suppression.
- Updated the two-layer plan to avoid duplicate prompt surfaces, use `recognizeOnly` for OCR short-circuiting, avoid `sortedBy` dependency in migration pseudocode, and require Hive adapter compatibility tests.

Verification:
- `flutter test --no-pub test/widget/widgets/score_action_hint_test.dart` → 4/4 pass.
- `flutter analyze --no-pub --no-fatal-infos lib/shared/widgets/score_action_hint.dart test/widget/widgets/score_action_hint_test.dart` → 0 issues.

Reviewer-Hint:
- Reviewed through main `15dd8a0`; Codex touched one production widget, one widget test, and the two-layer design plan.

Next-Step:
- If Phase 1 starts, keep Edge prompt change as an isolated commit/deploy and include the new duplicate-surface + `recognizeOnly` regression tests before deploy.

Verdict: REVISED_AND_APPROVED
