# AddPartner UI Redesign Code Review (Codex)

Date: 2026-04-28
Branch: `feature/add-partner-ui-redesign`
Reviewed HEAD: `5d909f7` (PR #9) + Codex review patch
Base: `main` @ `f1b936e`
Scope: AddPartner screen visual / hint redesign only

## Verdict

REVISED_AND_APPROVED

No remaining P1/P2 blockers. I applied one small layout patch: when `extendBodyBehindAppBar` is enabled for the transparent AppBar, the form content now explicitly clears `kToolbarHeight` so the input cannot sit underneath the title/back button.

## Resolved Finding

### P2 - Transparent AppBar could overlap the input field

File:
- `lib/features/partner/presentation/screens/add_partner_screen.dart`

Finding:
- The redesign sets `extendBodyBehindAppBar: true` so the purple gradient paints under the AppBar.
- The body used `SafeArea` + `top: 16`, but `SafeArea` only avoids the status bar. It does not reserve the AppBar toolbar height.
- On devices/tests where the AppBar overlays the body, the first input could start underneath the title/back affordance.

Patch:
- Changed the top padding to `kToolbarHeight + 16`, preserving the behind-AppBar background while keeping interactive content below the transparent toolbar.
- Added a widget regression test asserting `GlassmorphicTextField` starts below the `AppBar` bottom.

## Hot Spot Review

- HS-AP-1 `_name.addListener`: PASS. Listener is added in `initState`, removed before controller disposal, and the callback gates `setState` on `mounted`.
- HS-AP-2 static bubbles: PASS. `IgnorePointer` + static `Container` shadows keep the screen testable and do not block input taps. This is the right trade-off for this post-A2 visual pass.
- HS-AP-3 transparent AppBar: REVISED_AND_APPROVED. Text/icon contrast is explicit; layout overlap is now guarded by `kToolbarHeight + 16` and a widget test.
- HS-AP-4 emoji hint: PASS. Literal hint is covered by an exact widget test; cross-platform glyph rendering remains TF visual smoke scope.
- HS-AP-5 `GradientButton.isLoading`: PASS. Existing `_busy` mutex still owns double-submit prevention; `isLoading` only reflects that state visually and disables the button through the existing widget contract.

## Verification

- `flutter analyze --no-fatal-infos lib/features/partner/presentation/screens/add_partner_screen.dart test/widget/features/partner/add_partner_screen_test.dart`: pass.
- `flutter test test/widget/features/partner/add_partner_screen_test.dart`: 6 pass / 1 skip.
- `flutter test test/widget/features/partner/ test/unit/features/partner/ test/unit/repositories/partner_repository_delete_test.dart`: 81 pass / 1 skip.
- `flutter analyze --no-fatal-infos lib test`: 0 issues.

Reviewer-Hint: Reviewed through PR #9 commit `5d909f7`; Codex touched production only for the transparent-AppBar content offset fix.
Next-Step: Eric/Bruce run TF visual smoke for emoji rendering, bubble placement, CTA contrast, and loading spinner before merge.
