# Codex Plan Review — Spec 5 Coach Follow-up v1 Implementation Plan

**Date:** 2026-05-02  
**Reviewed plan:** `docs/plans/2026-05-02-spec5-coach-follow-up-v1-impl.md` @ `ee61485`  
**Binding design:** `docs/plans/2026-05-02-spec5-coach-follow-up-v1-design.md` @ `a66ca5b`  
**Design review:** `docs/reviews/2026-05-02_spec5-coach-follow-up-design_codex-review.md` @ `3d8dd3a`  
**Verdict:** NEEDS-FIX

## Summary

The plan has the right product and architecture shape: independent `coach-follow-up` Edge Function, 5-field result card, `boundaryReminder` required, no `analyze-chat` imports, stable English keys, separate Hive box, and no long-term memory writes.

Do not start implementation yet. There are several plan-level holes that would let the implementation pass its own checklist while still failing production behavior or privacy guarantees.

## Required Amendments

### P1 — Phase A is not actually standalone mergeable until CI deploy is moved into Phase A

The plan says Phase A is mergeable as a standalone server PR (`Phase Plan`, line 146), but the CI/CD deploy line is deferred to Task X23 (`CI/CD deploy step`, lines 1183-1207). Current `.github/workflows/deploy-edge-function.yml` deploys only the existing functions and does not deploy `coach-follow-up`.

If Phase A is merged to main before X23, the new function exists in git but the automatic Edge deploy ignores it. That violates the stated Phase A outcome: "`coach-follow-up` deployable + tested via curl".

**Fix:** Move X23 into Phase A before A9, or mark Phase A as not independently mergeable. Recommended: add the CI deploy line in Phase A immediately after the function is locally green, then A9 validates the same deploy path production will use.

### P1 — Account cleanup plan targets the wrong seam

The plan says to wire `CoachFollowUpRepository.clearAll()` into `SupabaseService.deleteAccount()` / `signOut()` (`lines 14, 38, 124, 906-916`). The actual delete-account local cleanup path is `SettingsScreen` calling `StorageService.clearAll()` after `SupabaseService.deleteAccount()` succeeds (`settings_screen.dart:686-688`). The central privacy contract is the box list inside `StorageService.clearAll()` (`storage_service.dart:124-150`), already locked by `test/unit/services/storage_service_clear_all_test.dart`.

Putting a feature repository into `SupabaseService` would be the wrong dependency direction and risks changing normal sign-out semantics. Also, `signOut()` currently does not clear local Hive data, so making sign-out wipe local results is a product behavior change, not a mechanical privacy fix.

**Fix:** Amend Phase B to add the new Hive adapter, box open, typed getter, and `StorageService.clearAll()` entry. Add the regression to `test/unit/services/storage_service_clear_all_test.dart` or mirror its pattern. If sign-out should clear local data too, make that an explicit Eric product decision and test the whole sign-out cleanup path.

### P1 — Quota/cost tests miss the edge cases that matter

Task A6/A7 correctly references `analyze-chat/index.ts:3296-3604`, but the planned tests cover only unauthenticated, invalid input, monthly cap, daily cap, success deduct, and failure-not-deduct (`lines 520-652`). The existing quota machinery includes self-heal when the subscription row is missing, daily reset, monthly reset, test-account skip, and RevenueCat tier refresh on cap exceeded (`analyze-chat/index.ts:3370-3565`).

The pseudocode also omits `accountIsTest` from the quota gate, which means the project test account could be blocked or charged differently from the rest of the app.

**Fix:** Expand A6/A7 test matrix before implementation:

- Missing subscription row self-heals to free tier and proceeds.
- Daily reset happens before daily cap evaluation.
- Monthly reset happens before monthly cap evaluation.
- `accountIsTest` bypasses quota check and deduct.
- RevenueCat refresh is attempted on monthly/daily cap before returning 429.
- Unknown or null tier falls back safely to free limits.
- Deduct happens only after response validation, and uses the same updated/reset counters from the gate.

### P1 — Deno async assertion examples are false-positive prone

The plan's Deno validation tests call `assertRejects(...)` without `await` or `return` inside non-async `Deno.test` callbacks (`lines 205-244, 345-358`). That can let tests pass without waiting for the rejection assertion. The plan is TDD-heavy; vacuous tests are exactly the kind of trap that makes a 25-task plan look green while missing the bug.

**Fix:** Every `assertRejects` example should be written as:

```ts
Deno.test("rejects missing phase", async () => {
  await assertRejects(
    () => validateRequest({ answers: { q1: "x" } }),
    Error,
    "phase",
  );
});
```

Apply this to A2/A3/A7 examples before CC starts coding.

### P1 — Product red-line vocabulary is prompt-only, not enforced at validation

Task A4 tests that the prompt contains banned terms as instructions (`lines 423-485`), but no validator rejects AI output that actually includes those terms. Spec 4 worked well because product red lines were encoded in deterministic tests. Spec 5 is an AI output surface, so prompt-only guardrails are weaker.

**Fix:** Add response-card validation tests and implementation that reject or fail the response when any visible card field contains hard-banned tokens such as `PUA`, `收割`, `控住`, `攻略`, `壞女人`, `高分妹`, or similar product-red-line vocabulary. Missing/invalid safety response should be 5xx and no credit deducted, same as missing `boundaryReminder`.

### P2 — Hive unit-test pattern should use a temp Hive path, not `Hive.initFlutter()`

Task B12's test sample uses `Hive.initFlutter()` (`line 848`). Existing pure unit tests use `Hive.init('./.dart_tool/...')`, register adapters manually, and delete boxes from disk in teardown. `Hive.initFlutter()` drags Flutter/plugin initialization into a repository unit test and can create path/binding flakes.

**Fix:** Mirror `test/unit/services/storage_service_clear_all_test.dart`: use a dedicated `.dart_tool/test_hive_*` directory, register `CoachFollowUpResultAdapter`, open a unique test box, and clean it in teardown.

### P2 — `lastConversationSummary` needs an explicit client-side source function

The design requires `lastConversationSummary` to be conversation-level only, capped at 200 chars, and omitted when Spec 3 is flagged. The plan has tests in C17 for "flagged omit", but it does not define the source selection function. Without that, the implementer may accidentally use `PartnerContextResolver`, partner aggregate summary, raw messages, or cross-conversation data.

**Fix:** Add a pure helper in Phase C, for example `buildCoachFollowUpPartnerHint(...)`, with unit tests:

- Uses only the latest selected/current conversation's `ConversationSummary.content`.
- Caps to 200 chars.
- Returns null if no conversation-level summary exists.
- Returns null when `dataQualityFlagProvider(partnerId).isFlagged == true`.
- Never reads `PartnerContextResolver`, partner summary, partner traits, or raw message bodies for the Edge payload.

## What Already Exists

- `StorageService.clearAll()` is the existing local privacy boundary. Reuse it; do not create a parallel repository cleanup path in `SupabaseService`.
- `test/unit/services/storage_service_clear_all_test.dart` already models the right privacy regression shape for new Hive boxes.
- `analyze-chat/index.ts:3370-3565` contains the full quota edge-case sequence. Copy a minimal subset, but copy the behavioral contract and tests, not just the happy path.
- `dataQualityFlagProvider(partnerId)` already exposes the Spec 3 flagged state.
- `GameStage.close` exists and the plan correctly avoids matching the Traditional Chinese display label.
- `.github/workflows/deploy-edge-function.yml` already has function-specific deploy flags. Add one explicit line for `coach-follow-up`; do not replace it with `deploy --all`.

## NOT In Scope

- Do not implement production code as part of this review.
- Do not edit `supabase/functions/analyze-chat/**`.
- Do not add image support, push notifications, history, chatbot follow-up, or Learning deep links.
- Do not introduce the fourth phase "她回覆變慢" in v1.
- Do not persist user input answers in Hive.

## Parallelization Notes

After the amendments above:

| Lane | Modules | Depends on |
|------|---------|------------|
| A | `supabase/functions/coach-follow-up/`, `.github/workflows/` | none |
| B | `lib/core/services/storage_service.dart`, `lib/features/coach_follow_up/domain+data`, Hive generated files | typeId decision |
| C | `lib/features/coach_follow_up/presentation`, `partner_detail_screen.dart` | B providers/entities |

Recommended execution: A and B can be implemented in separate worktrees after the plan is amended. C waits for B because it consumes the entity/repository/provider surface. X23 should move into A, not stay as a final cross-cutting task.

## Final Verdict

**NEEDS-FIX.** The plan is close, but these amendments should be applied before coding:

1. Move CI deploy into Phase A or remove the Phase A standalone-merge claim.
2. Re-target cleanup to `StorageService.clearAll()` and clarify sign-out semantics.
3. Expand quota tests to cover self-heal, resets, test account, RevenueCat refresh, and fallback tier.
4. Fix Deno `assertRejects` examples to await/return promises.
5. Enforce product red-line vocabulary in response validation, not prompt only.
6. Use temp Hive paths in repository unit tests.
7. Define a pure, tested client-side source for `lastConversationSummary`.

Once CC applies these to the plan, I would expect the next review to be `REVISED_AND_APPROVED` unless the amendment introduces new scope.
