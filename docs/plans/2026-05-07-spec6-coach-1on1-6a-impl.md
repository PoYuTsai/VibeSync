# Spec 6A Coach 1:1 Implementation Plan

Status: SHIPPED - implemented by Codex on 2026-05-07.

Binding design:
- `docs/plans/2026-05-07-spec6-coach-1on1-design.md`
- `docs/reviews/2026-05-07_spec6-coach-1on1-design_cc-review.md`

## Goal

Ship the smallest useful Coach 1:1 surface on the analysis result page.

The user asks one open-ended coaching question about the current conversation. VibeSync answers with context-aware judgment using the conversation, latest analysis, Spec 2.5 style context, and safe partner hint. This is not an infinite chat, not a replacement for `analyze-chat`, and not a new long-term memory writer.

## Locked Scope

In:
- New independent Supabase Edge Function: `coach-chat`.
- New local encrypted Hive box: `coach_chat_results`.
- New Flutter feature: API service, repository, provider/controller, compact analysis-page card.
- Cost: successful generation deducts 1 message credit, test account bypasses, failures do not deduct.
- Persistence: local only, recent 3 answers per conversation.
- Context: recent messages, latest summary, latest analysis snapshot, effective style context, partner hint.

Out:
- No OpenAI provider in production for 6A. Claude remains default; OpenAI is future ablation only.
- No free-form infinite thread history.
- No Supabase persistence of free text.
- No writes to partner summary, partner traits, about-me, or analyze-chat memory.
- No OCR changes.

## Amendments From Review

A1 Banned-token contract:
- Add `supabase/functions/_shared/banned_tokens.ts`.
- `coach-chat` and `coach-follow-up` both use the same server-side banned token list.
- Flutter client mirrors the same list for defense in depth.

A4 Field caps:
- `coach-chat` response fields are capped and truncated before validation.
- Visible caps: headline 32, answer 220, userState 90, nextStep 90, suggestedLine 100, boundaryReminder 80, reflectionQuestion 90.

A7 Data quality flag:
- Client omits partner traits when `dataQualityFlagged == true`.
- Server rejects payloads that send `partnerHint.traits` while flagged.
- Prompt tells the coach to avoid partner-memory claims when flagged.

## Files

Add backend:
- `supabase/functions/_shared/banned_tokens.ts`
- `supabase/functions/coach-chat/index.ts`
- `supabase/functions/coach-chat/schemas.ts`
- `supabase/functions/coach-chat/prompts.ts`
- `supabase/functions/coach-chat/validate.ts`
- `supabase/functions/coach-chat/logger.ts`
- `supabase/functions/coach-chat/generation.ts`
- `supabase/functions/coach-chat/*_test.ts`

Reuse backend:
- `supabase/functions/coach-follow-up/quota.ts` — shared minimal quota helper. This is intentionally reused instead of copy-pasting the same reset / RC refresh / test-account edge cases.

Modify backend:
- `supabase/functions/coach-follow-up/validate.ts`
- `.github/workflows/deploy-edge-function.yml`

Add Flutter:
- `lib/features/coach_chat/domain/entities/coach_chat_mode.dart`
- `lib/features/coach_chat/domain/entities/coach_chat_result.dart`
- `lib/features/coach_chat/domain/entities/coach_chat_result.g.dart`
- `lib/features/coach_chat/domain/repositories/coach_chat_repository.dart`
- `lib/features/coach_chat/data/repositories/coach_chat_repository_impl.dart`
- `lib/features/coach_chat/data/services/coach_chat_api_service.dart`
- `lib/features/coach_chat/data/providers/coach_chat_providers.dart`
- `lib/features/coach_chat/presentation/widgets/coach_chat_card.dart`
- Tests under `test/unit/features/coach_chat/`.

Modify Flutter:
- `lib/core/services/storage_service.dart`
- `lib/features/conversation/data/repositories/conversation_repository.dart`
- `lib/features/analysis/presentation/screens/analysis_screen.dart`

## Task Plan

1. Backend shared guard
- Add `_shared/banned_tokens.ts`.
- Move `coach-follow-up` server validator to shared list without changing token values.
- Test: follow-up validator still blocks banned token.

2. Backend `coach-chat` schema and validator
- Validate request shape, reject images, enforce body caps.
- Enforce A7: flagged payload cannot include partner traits.
- Truncate and validate response card.
- Test: request validation, field caps, banned token, flagged partner hint.

3. Backend generation pipeline
- Build prompt from request context.
- Call Claude using existing model policy.
- Parse JSON, truncate, validate, assert safe, deduct on success only.
- Test: success deducts once; schema/banned/Claude/deduct failure do not return a card incorrectly.

4. Backend HTTP handler + deploy line
- Reuse coach-follow-up quota/self-heal/reset/RC-refresh helper.
- Add CI deploy line for `coach-chat` without `--no-verify-jwt`.
- Test: GET health, OPTIONS CORS, unauth 401, invalid body 400.

5. Flutter local entity/repo/storage
- Add Hive typeId 17 entity and encrypted box.
- `StorageService.clearAll()` clears it.
- Repository keeps latest 3 per conversation.
- Conversation delete/deleteAll cascades local coach chat rows.
- Test: put/list/latest/delete/clear/latest-3 and cascade.

6. Flutter API service
- Invoke Supabase function `coach-chat`.
- Map 429 to quota exception, 5xx to generation failure, success to entity.
- Client-side response guard mirrors banned token + required fields.
- Test: success/request body/429/5xx/malformed/banned token.

7. Flutter provider/controller
- Build safe request context from `Conversation`, latest analysis state, Spec 2.5 style context, partner aggregate, and data quality flag.
- Omit partner traits when flagged.
- Persist only on success.
- Refresh usage after state shows result.
- Test: context builder, flagged stripping, success ordering, failure no write.

8. Flutter UI
- Add `CoachChatCard` near final recommendation on analysis page.
- Suggested chips fill question input; user can ask one question.
- Show latest result compactly and preserve keyboard usability.
- Quota exceeded opens paywall.
- Test: covered through controller/API contracts; widget-specific polish deferred to 6B because existing `analysis_screen_test.dart` is stale and animation-based.

9. Verification
- Deno scoped tests for `coach-chat` and touched follow-up guard.
- Flutter scoped tests for coach chat + touched storage/conversation/analysis widget if feasible.
- `flutter analyze`.
- Commit + push.

## TF Smoke After Build

Use current analysis results and ask:
- `她這句話是真的有興趣嗎？`
- `我是不是太急？`
- `這局值不值得繼續？`
- `她有男友還約我，我該怎麼判斷？`
- `我想短期，但不要讓人不舒服，怎麼推進？`

Pass criteria:
- Coach does not moralize, but names cost/boundary/risk.
- Coach asks for inner state only when needed.
- Coach gives one usable next step, not a long generic essay.
- No banned-token vocabulary appears.
- Quota deducts once on success and not on failure.
