# Flutter Test Debt - 2026-04-05

## Purpose

This document tracks Flutter tests that are currently excluded from the blocking CI smoke suite because they no longer reflect the current product flow, copy, or screen architecture.

The goal is **not** to hide failures. The goal is to keep release CI meaningful while we rewrite stale tests in smaller, intentional batches.

## Blocking CI vs Full Regression

- Blocking CI now runs `tool/run_flutter_ci_smoke_tests.sh`
- Full `flutter test` is still valuable, but currently includes legacy screen tests that need to be rewritten around the current UX

## Known Legacy / Rewrite Candidates

### Screen-level widget tests

- `test/widget/screens/home_screen_test.dart`
- `test/widget/screens/analysis_screen_test.dart`
- `test/widget/screens/new_conversation_screen_test.dart`
- `test/widget/screens/paywall_screen_test.dart`
- `test/widget/screens/settings_screen_test.dart`

### Widget tests tied to older copy / flows

- `test/widget/widgets/game_stage_indicator_test.dart`
- `test/widget/widgets/screenshot_recognition_dialog_test.dart`
- `test/widget/widgets/analysis_preview_dialog_test.dart`
- `test/widget/widgets/booster_purchase_sheet_test.dart`

### Unit tests still needing a second review

- `test/unit/services/analysis_service_test.dart`

## Rewrite Principles

When these tests are brought back into blocking CI:

- Prefer structural assertions over brittle exact marketing copy
- Prefer current UX states over historical assumptions
- Avoid asserting flows that are intentionally "coming soon" or staged behind future backend work
- Keep screen tests focused on one stable outcome per test

## Near-term Priority

1. `analysis_service_test.dart`
2. `screenshot_recognition_dialog_test.dart`
3. `paywall_screen_test.dart`
4. `settings_screen_test.dart`
5. `analysis_preview_dialog_test.dart`
