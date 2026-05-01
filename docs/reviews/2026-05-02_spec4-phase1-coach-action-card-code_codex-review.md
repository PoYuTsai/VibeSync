# Codex Code Review — Spec 4 Phase 1 Coach Action Card

**Date:** 2026-05-02
**Reviewer:** Codex
**Scope:** code review for `e8d525d..2ca0257` (Spec 4 Phase 1 production code + tests)
**Verdict:** APPROVED-WITH-AMENDMENTS

## Summary

Spec 4 Phase 1 is structurally sound: the implementation keeps the decision policy app-side, preserves the exact article deep-link contract, hides CTA rows when `learningLink == null`, leaves `ScoreActionHint` in-tree as the agreed rollback safety net, and wires `CoachActionCard` into `AnalysisScreen` without touching OCR / prompt / Edge Function paths.

I found two functional risks in `CoachActionPolicy` and patched both directly:

1. `softInvite` was triggered by heat 81+ alone, instead of requiring an invite / close-stage gameplay signal.
2. The 1.8x reply-size guard compared against the first user reply after the partner message, which could miss later overlong follow-up messages.

No remaining blockers after the patch.

## Findings Patched

### P1 — `softInvite` could over-trigger on heat alone

**Severity:** Functional risk
**File:** `lib/features/analysis/domain/coach/coach_action_policy.dart`

The amended plan requires `heat >= 81 AND meeting-language gameplay confirmed -> softInvite`. The shipped implementation returned `softInvite` for any `heatScore > AppConstants.hotMax`, even if the conversation was still `opening` and no invite / close signal existed. This could push users toward an invite too early, which conflicts with Spec 4's low-pressure coaching direction.

**Patch:** Added `_hasMeetingGameplaySignal(...)` and gated `softInvite` on both `veryHot` heat and at least one close / meeting signal:

- `gameStage.current == GameStage.close`
- `gameStage.status == GameStageStatus.canAdvance`
- meeting keyword in `gameStage.nextStep`
- meeting keyword in `finalRecommendation.content`
- meeting keyword in `finalRecommendation.reason`

**Regression test:** Added `should not pick softInvite on veryHot heat without meeting signal`.

### P2 — 1.8x guard missed later overlong user replies

**Severity:** Functional risk
**File:** `lib/features/analysis/domain/coach/coach_action_policy.dart`

The shipped `_userOverextendedReply` scanned the latest partner message and returned based on the first user message after it. If the user sent a short acknowledgement and then a long follow-up, the policy missed the overlong latest reply and failed to trigger `rightSizeReply`.

**Patch:** Changed the scan to capture the latest user reply after the latest partner message, trim both sides, and compare that latest reply against the partner length × 1.8.

**Regression test:** Added `should compare against the latest user reply after the partner message`.

## Checked And Accepted

- `LearningLinkResolver` maps 7/9 action types to existing article IDs and returns `null` for `softInvite` / `pausePursuit` as planned.
- `CoachActionCard` hides the CTA row entirely when `learningLink == null`.
- `CoachActionCard` header has no emoji and renders the six-field card shape.
- `AnalysisScreen` no longer calls `ScoreActionHint`; it computes `flagged`, `practiceGoals`, and `CoachActionPolicy.evaluate(...)`, then renders `CoachActionCard`.
- `dataQualityFlagged` path stays inside the safe set because `CoachActionPolicy` exits through `_selectFlaggedSafeSet(...)` before any practice-goal tie-breaker.
- `ScoreActionHint` remaining in-tree is intentional per amended plan and not flagged.

## Verification

Passed:

```bash
flutter test test/unit/features/analysis/domain/coach/ test/widget/shared/coach_action_card_test.dart
# 37 tests, 0 failures

flutter analyze --no-fatal-infos lib test
# 0 issues
```

Additional non-blocking check:

```bash
flutter test test/widget/screens/analysis_screen_test.dart
```

This existing test file still fails on stale loading / `pumpAndSettle` assumptions (`CircularProgressIndicator` not found, timeouts). I did not repair it in this review because it is outside the Spec 4 perimeter and appears to be part of the known stale widget-test bucket rather than a regression introduced by the policy patch.

## Next Step

Proceed to TestFlight smoke for Spec 4 Phase 1. If smoke is green, do the planned follow-up cleanup commit that removes the legacy `ScoreActionHint` widget and its isolated tests.
