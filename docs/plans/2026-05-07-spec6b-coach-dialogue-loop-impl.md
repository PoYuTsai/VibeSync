# Spec 6B Coach 1:1 Dialogue Loop Implementation Plan

Status: in progress
Owner: Codex
Date: 2026-05-07

## Goal

Upgrade Spec 6A `coach-chat` from a single-shot answer card into a lightweight coaching dialogue loop.

The product contract:

- The coach should understand the user's feeling, raw intended reply, intent, stage, risk, and real desire before giving advice.
- If context is insufficient, the coach asks one clear clarification question first.
- Clarification does not deduct quota.
- A formal coach answer deducts 1 message only after a safe, validated answer is generated.
- The coach must not over-edit user language. It can decide `keep_original`, `light_edit`, `rewrite`, or `do_not_send`.

## Non-Goals

- No new Edge Function.
- No OpenAI provider switch in this phase.
- No full analysis-screen redesign yet.
- No long-term memory writes from coach sessions.
- No OCR / `analyze-chat` changes.

## Phase A — Edge Contract

Files:

- `supabase/functions/coach-chat/schemas.ts`
- `supabase/functions/coach-chat/prompts.ts`
- `supabase/functions/coach-chat/validate.ts`
- `supabase/functions/coach-chat/generation.ts`
- existing coach-chat Deno tests

Tasks:

1. Add request fields:
   - `sessionId?`
   - `activeSessionTurns?`
   - `forceAnswer?`
   - `rawReplyDraft?`
2. Add response card fields:
   - `responseType: clarifyingQuestion | coachAnswer`
   - `rewriteDecision?: keep_original | light_edit | rewrite | do_not_send`
   - `rewriteReason?`
   - `userTruth?`
   - `costDeducted: 0 | 1`
3. Prompt rules:
   - Ask before answering when feeling / raw reply / intent / boundary is unclear.
   - Formal answer only when enough information exists or `forceAnswer=true`.
   - Preserve user's authentic intent; do not force a rewrite for professional-looking output.
4. Generation:
   - If `responseType=clarifyingQuestion`, return 200 and skip deduction.
   - If `responseType=coachAnswer`, deduct 1 on success only.

## Phase B — Flutter Wire + Local Result

Files:

- `coach_chat_result.dart` + adapter
- `coach_chat_api_service.dart`
- `coach_chat_repository_impl.dart`
- `coach_chat_providers.dart`
- existing unit tests

Tasks:

1. Extend local result with safe optional/default fields:
   - `responseType`
   - `sessionId`
   - `rewriteDecision`
   - `rewriteReason`
   - `userTruth`
   - `costDeducted`
2. Send active session turns and `forceAnswer` to Edge.
3. Controller keeps an in-memory active session per provider instance.
4. Usage refresh only after `costDeducted > 0`.
5. Stored old 6A results remain readable with defaults.

## Phase C — UX MVP

File:

- `coach_chat_card.dart`

Tasks:

1. Clarification card copy:
   - "教練想先問清楚"
   - show reflection question prominently
   - "補充不扣額度；正式建議才扣 1 則"
2. Buttons:
   - `補充我的想法` focuses the input
   - `直接給我建議` calls `forceAnswer`
3. Formal answer card:
   - show `userTruth` when present
   - show rewrite decision label
   - show suggested line only when useful
4. Keep existing copy / keyboard dismiss affordances.

## Phase D — Verification

Run:

- `deno test --allow-env supabase/functions/coach-chat`
- `flutter test test/unit/features/coach_chat`
- `flutter analyze`

Manual TF smoke after build:

1. Ask: "她說我很有故事是什麼意思？" and confirm either a good direct answer or a clarification question.
2. If clarification appears, answer: "我其實想回她，但怕太裝深沉" and confirm the next result becomes a formal answer.
3. Confirm clarification does not change remaining quota.
4. Confirm formal answer deducts 1.
5. Press "直接給我建議" from a clarification card and confirm it gives an answer instead of asking again.
