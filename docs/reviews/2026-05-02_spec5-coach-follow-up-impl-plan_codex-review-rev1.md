# Codex Plan Review Rev 1 — Spec 5 Coach Follow-up v1 Implementation Plan

**Date:** 2026-05-02  
**Reviewed plan:** `docs/plans/2026-05-02-spec5-coach-follow-up-v1-impl.md` @ `1d63d30`  
**Previous review:** `docs/reviews/2026-05-02_spec5-coach-follow-up-impl-plan_codex-review.md` @ `146b8e3`  
**Previous verdict:** NEEDS-FIX  
**Verdict:** REVISED_AND_APPROVED

## Summary

Rev 1 addresses the seven plan blockers from the first review. The implementation plan is now safe to execute after Eric resolves OQ-Sign-1. Recommended decision for OQ-Sign-1 is option (a): keep sign-out behavior unchanged; only delete-account / `StorageService.clearAll()` clears local Hive boxes.

This is the right boundary. Changing `signOut()` to wipe local data would affect conversations, partners, About Me, partner overrides, data-quality state, and follow-up results. That is a cross-app product decision, not a Spec 5 cleanup detail.

## Amendment Verification

| Previous item | Rev 1 result | Verdict |
|---|---|---|
| P1 #1 Phase A not truly standalone because CI deploy was deferred | CI deploy moved into Phase A as Task A9, manual smoke becomes A10, phase table now says Phase A includes CI deploy | Accepted |
| P1 #2 Cleanup targeted the wrong seam | Cleanup moved to `StorageService.clearAll()` and existing `storage_service_clear_all_test.dart`; `SupabaseService` cleanup wiring is explicitly prohibited | Accepted |
| P1 #3 Quota/cost matrix too thin | A6/A7 now include self-heal, daily reset, monthly reset, test-account skip, RevenueCat refresh, unknown/null tier fallback, and updated-counter deduct behavior | Accepted |
| P1 #4 Deno `assertRejects` examples could false-pass | Examples now use async test bodies and `await assertRejects(...)`; checklist includes audit line | Accepted |
| P1 #5 Product red lines were prompt-only | `assertCardSafe` added to server response validation path; A7 sequence is validate shape → assert safe → deduct credit; client double-check added | Accepted |
| P2 #6 Hive tests used `Hive.initFlutter()` | Repository tests now mirror temp-path Hive pattern from `storage_service_partner_box_test.dart` | Accepted |
| P2 #7 `lastConversationSummary` source was implicit | New `buildCoachFollowUpPartnerHint` helper with explicit tests and import/grep guard | Accepted |

## Implementation Notes

- OQ-Sign-1: choose option (a). Do not change sign-out semantics in Spec 5.
- In Task B16, keep the primary privacy contract as "new box is empty after `StorageService.clearAll()`." Do not make physical file deletion a required outcome unless the implementation explicitly calls `deleteFromDisk()`. Existing `clearAll()` semantics clear boxes; they do not remove every Hive file from disk.
- Keep the `coach-follow-up` CI line separate from `analyze-chat`; do not consolidate deploys into `deploy --all`.
- If CC splits work into worktrees, run Phase A and Phase B in parallel only after the plan is final. Phase C waits for Phase B entity/provider surfaces.

## NOT In Scope

- No production code should be written by this review.
- Do not edit `supabase/functions/analyze-chat/**`.
- Do not add push notifications, a fourth phase, chatbot mode, image input, history, or Learning deep links.
- Do not persist user answers.
- Do not write to partner summary, partner traits, About Me, or Partner Style Override.

## Final Verdict

**REVISED_AND_APPROVED.**

The plan can proceed to implementation once Eric confirms OQ-Sign-1 option (a). If Eric instead chooses option (b), pause Spec 5 implementation and open a separate cross-app sign-out data-clearing design item.
