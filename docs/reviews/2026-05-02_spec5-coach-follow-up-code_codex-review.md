# Codex Code Review — Spec 5 Coach Follow-Up Phase A/B/C

**Date**: 2026-05-02  
**Branch**: `feature/spec5-coach-follow-up-v1`  
**Reviewed range**: `origin/main..feature/spec5-coach-follow-up-v1`  
**Verdict**: APPROVED-WITH-AMENDMENTS

This review covered the shipped Phase A/B/C implementation: standalone
`coach-follow-up` Edge function, local Hive persistence/cascade, and partner
detail UI integration. I found three functional/safety issues and patched them
directly in the review commit. No remaining code blocker was found after the
patches and scoped verification.

## Patched Findings

### [P1] Edge request schema accepted arbitrary `q1` / `q2` text

**File**: `supabase/functions/coach-follow-up/schemas.ts:17`

The Flutter client sends stable English option keys, but the Edge
`RequestSchema` previously accepted any non-empty `q1` and any optional `q2`.
That left a trust-boundary hole: a buggy or malicious client could send raw
prompt text through `q1` / `q2`, bypassing the stable-key contract and making the
prompt builder treat user-controlled strings as structured answers.

**Patch**: Added phase-specific allowlists for `q1` / `q2` and required `q2` for
`postDateReflection`. Added validator tests for prompt-injection text, invalid
phase-specific `q2`, and missing post-date `q2`.

### [P2] `postDateReflection` hint could never fire in real UI

**File**: `lib/features/coach_follow_up/data/providers/coach_follow_up_providers.dart:49`

`CoachFollowUpHintResolver` has a long-quiet-post-date heuristic, but the
provider only passed game stage, heat score, and recent message bodies. It never
provided `timeSinceLastMessage` or `averageMessageInterval`, so the
`postDateReflection` chip could be covered by resolver unit tests while staying
unreachable in the actual partner detail screen.

**Patch**: Added an overridable `coachFollowUpNowProvider`, computed last-message
age and average interval from local messages, and added a provider-level test for
the post-date long quiet scenario.

### [P2] Generation failures looked like a no-op

**File**: `lib/features/coach_follow_up/presentation/widgets/coach_follow_up_section.dart:254`

The controller entered `AsyncError`, but the section only disabled controls via
`isLoading` and never rendered error state. A schema failure, quota failure, or
network failure would close the sheet and leave the user with no visible
feedback, which is especially risky because this feature costs 1 credit on
success and users need to know when no credit was deducted.

**Patch**: Rendered low-pressure loading and error copy in both empty and
with-result states. Generation failures explicitly say "未扣額度". Added widget
coverage for failed generation feedback.

### [P2] Input sheet could overflow on small screens / keyboard

**File**: `lib/features/coach_follow_up/presentation/widgets/coach_follow_up_input_sheet.dart:160`

The sheet body was a non-scrollable `Padding > Column` with multiple option
groups plus a multiline text field. On smaller devices or with the keyboard up,
content could overflow instead of remaining usable.

**Patch**: Wrapped the sheet body in `SingleChildScrollView`. Existing input
sheet widget tests remain green.

## Verification

- `deno test --allow-env --allow-net supabase/functions/coach-follow-up`
  - `143 passed / 0 failed`
- `flutter test test/unit/features/coach_follow_up/ test/widget/features/coach_follow_up/ test/unit/repositories/partner_repository_cascade_test.dart test/unit/repositories/partner_repository_delete_test.dart test/unit/repositories/partner_repository_merge_test.dart test/unit/services/storage_service_clear_all_test.dart test/widget/features/partner/partner_detail_screen_test.dart test/widget/features/partner/partner_detail_screen_with_style_card_test.dart test/widget/features/copy_sweep_snapshot_test.dart`
  - `197 passed / 0 failed`
- `flutter analyze`
  - `0 issues`

## Residual Gates

- A10 production live smoke is still deferred: real JWT, real Claude response,
  real credit deduction, and validator-failure no-deduct paths.
- X25 staging telemetry verification is still deferred: client callback is typed,
  but the real sink is not wired in this phase.
- X26 Eric TF smoke is still required before merging the feature branch to main.

## Decision

The implementation is approved after the amendments above. The remaining work is
operational verification, not a code-shape blocker.
