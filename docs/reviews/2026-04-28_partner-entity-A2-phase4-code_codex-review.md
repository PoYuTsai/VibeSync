# Partner Entity Refactor - A2 Phase 4 Code Review (Codex)

Date: 2026-04-28
Branch: `feature/partner-entity-A2-polish`
Reviewed diff: `main..f991359` (PR #8) + Codex review patch
Request: `docs/reviews/ai-arbitration-queue.md` `[2026-04-28] Partner Entity Refactor - A2 Phase 4 Code Review`

## Verdict

REVISED_AND_APPROVED

No remaining P1/P2 blockers found. I applied one small hardening patch for the only actionable review concern: newly-added Phase 4 generic error paths were swallowing details that would be useful during TF soak.

## Resolved Findings

### P2 - Silent catch paths made TF failures harder to diagnose

Files:
- `lib/features/partner/presentation/screens/partner_list_screen.dart`
- `lib/features/partner/presentation/screens/partner_merge_picker_screen.dart`
- `lib/features/partner/presentation/widgets/same_name_dedupe_banner.dart`

Finding:
- `PartnerListScreen` had two newly-added generic catch paths: banner dismiss invalidation after async disposal and delete fallback after unexpected controller/repo failures.
- `PartnerMergePickerScreen` also caught merge failures generically.
- The user-facing SnackBars were acceptable, but during TF soak these paths would leave no debug breadcrumb beyond "failed".

Patch:
- Added `debugPrint` breadcrumbs with error + stack for banner dismiss invalidation, partner delete fallback, and partner merge fallback.
- Const-ified the small Phase 4 `TextStyle` constructors touched in the same area.

## Hot Spot Review

- HS-Code-1 `_previewTags`: PASS. The max-length interleave loop correctly handles both one-sided edges (`interests=5/traits=0`, `interests=0/traits=5`) and mixed inputs cap at 3. Existing tests cover mixed + "keep at least one trait"; one-sided behavior follows directly from loop bounds.
- HS-Code-2 delete dialog race: PASS. UI first branches on `conversationsByPartnerProvider(p.id).length`, and the destructive path still catches `PartnerHasConversationsException` if a conversation appears between dialog open and repo delete.
- HS-Code-3 banner dismiss re-render: PASS. `PartnerBannerService.markDismissed(uid)` writes the per-account key, then `ref.invalidate(partnerDedupeBannerDismissedProvider(uid))` re-reads it. Widget test covers tap dismiss -> banner hidden + prefs true.
- HS-Code-4 merge picker preselect: PASS. Valid `?target=` only seeds `_selectedTarget`; row taps route through `onSelectedChanged` and do not call `onSelected`, so destructive dialog still requires explicit bottom CTA tap. Tests cover valid/self/unknown/out-of-scope targets.
- HS-Code-5 copy sweep: PASS for Phase 4 scope. Snapshot tests cover Home FAB tooltip, Partner list empty state, and Partner detail's intentional conversation-level "新增對話" wording. No OCR / analyze-chat surface changed.

## Verification

- `dart format` (WSL-native) on touched Phase 4 Dart files: pass.
- `flutter analyze --no-fatal-infos lib/features/partner/presentation/screens/partner_list_screen.dart lib/features/partner/presentation/screens/partner_merge_picker_screen.dart lib/features/partner/presentation/widgets/same_name_dedupe_banner.dart`: pass.
- `flutter test test/widget/features/partner/partner_list_screen_test.dart test/widget/features/partner/partner_merge_picker_screen_test.dart test/widget/features/partner/same_name_banner_test.dart`: 25 pass / 0 fail.
- `git diff --check`: pass; only repository-wide CRLF warnings unrelated to this patch.

## Notes

- `AGENTS.md` and `CLAUDE.md` remain byte-identical.
- `HomeContent` references are removed from `lib/` / widget tests; remaining hits are historical docs/queue references.
- TF regression checklist J remains the human gate before merge.

Reviewer-Hint: I reviewed PR #8 through `f991359` and patched only low-risk observability/style issues; no architecture or product decision was reopened.
Next-Step: Push this review patch, then Eric/Claude run TF checklist J and merge PR #8 if smoke is clean.
