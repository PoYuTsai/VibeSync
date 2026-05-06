# Spec 6A Coach 1:1 Implementation Summary

Verdict: READY FOR CC CODE REVIEW

Branch / base:
- `main` after Spec 6 design commits.
- Implementation scope starts after `f4ea6ff [docs] 鎖定 Spec 6 provider 策略`.

## What Shipped

Spec 6A adds a compact Coach 1:1 question box on the analysis result page. The user can ask one open-ended coaching question about the current conversation; VibeSync answers using recent messages, latest summary, current analysis snapshot, Spec 2.5 style context, and a privacy-safe partner hint.

This is deliberately not an infinite chat thread, not an OpenAI provider switch, and not a new long-term memory writer.

## Backend

Added independent Supabase Edge Function:
- `supabase/functions/coach-chat/`
- JWT verified by default; no `--no-verify-jwt`.
- GET health / OPTIONS CORS / POST auth gate.
- Successful generation deducts 1 credit; test account bypasses; schema / banned-token / Claude / deduct failure does not deduct.

Shared guard:
- `supabase/functions/_shared/banned_tokens.ts`
- `coach-follow-up` now imports the same banned-token list.

Provider strategy:
- Claude remains the only production provider for 6A.
- The implementation reuses `supabase/functions/coach-follow-up/quota.ts` for quota/reset/RevenueCat/test-account edge cases instead of copy-pasting the machinery. CC should review this cross-function import as an explicit implementation choice.

## Flutter

Added feature module:
- `lib/features/coach_chat/domain/`
- `lib/features/coach_chat/data/`
- `lib/features/coach_chat/presentation/widgets/coach_chat_card.dart`

Local persistence:
- New encrypted Hive box `coach_chat_results`.
- New Hive typeId `17`.
- Keeps latest 3 coach answers per conversation.
- `StorageService.clearAll()` wipes the box.
- `ConversationRepository.deleteConversation()` and `deleteAll()` cascade local coach-chat rows when the box is open.

Analysis page:
- Inserts `CoachChatCard` after the final recommendation block.
- Card shows suggested chips, a 240-char question field, latest result, and quota-exceeded paywall routing.
- Controller sets `AsyncData(result)` before usage refresh so RevenueCat/usage sync cannot hide a successful card.

Privacy boundaries:
- Spec 3 `dataQualityFlagged == true` strips partner traits on Flutter provider and API service layers.
- Edge schema rejects flagged payloads that still include `partnerHint.traits`.
- No writes to partner summary, partner traits, About Me, analyze-chat memory, or Supabase free-text storage.

## Tests / Verification

Passed:
- `deno test --allow-env supabase/functions/coach-chat supabase/functions/coach-follow-up/validate_test.ts`
- Result: `77 passed / 0 failed`

Passed:
- `flutter analyze`
- Result: `No issues found`

Passed:
- `flutter test test/unit/features/coach_chat test/unit/services/storage_service_clear_all_test.dart test/unit/repositories/conversation_repository_partner_test.dart test/unit/repositories/conversation_repository_test.dart`
- Result: `33 passed / 0 failed`

Full suite:
- `flutter test` was run.
- Result observed this run: `867 pass / 1 skip / 44 fail`.
- Failures are in pre-existing stale areas such as `message_booster_test`, `reply_card_test`, `widget_test`, and animation-heavy `analysis_screen_test`. Scoped Spec 6A suites are green.

## CC Review Focus

1. Backend quota reuse:
- Review whether importing `../coach-follow-up/quota.ts` from `coach-chat/index.ts` is acceptable as a shared-helper reuse, or whether it should be moved to `_shared/quota.ts` before merge.

2. Privacy boundary:
- Confirm `dataQualityFlagged` strips partner traits in Flutter provider + API service and is rejected at Edge schema if violated.

3. Cost contract:
- Confirm success-only deduction ordering in `generation.ts`, including deduct failure returning 500 and not giving the user a free card.

4. UI placement:
- Confirm placing Coach 1:1 after final recommendation is the right 6A insertion point before the future 6B UI simplification.

5. Test gap:
- Widget-specific tests for `CoachChatCard` are deferred because existing `analysis_screen_test.dart` is stale/animation-based. Unit/provider/API/backend coverage is green.

## TF Smoke

After build, manually ask:
- 她這句話是真的有興趣嗎？
- 我是不是太急？
- 這局值不值得繼續？
- 她有男友還約我，我該怎麼判斷？
- 我想短期，但不要讓人不舒服，怎麼推進？

Pass criteria:
- Names the real user intent instead of ignoring it.
- Does not moralize, but clearly names cost / boundary / risk.
- Gives one useful next step, not a generic essay.
- No banned-token vocabulary.
- Quota deducts once on success and not on failure.
