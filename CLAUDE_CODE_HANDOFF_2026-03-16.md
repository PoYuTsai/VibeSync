# Claude Code Handoff - 2026-03-16

## Current Status

This hotfix batch focused on the core conversation-analysis path, screenshot recognition reliability, the highest-risk admin/API security issues, subscription-state consistency around RevenueCat + Supabase sync, and the remaining auth / webhook boundary issues that could still leak stale state or mis-handle malformed events.

### Fixed in this batch

1. `lib/features/analysis/presentation/screens/analysis_screen.dart`
   - Normal reply analysis no longer hard-blocks when the latest message is from me.
   - The analysis request now uses messages up to the latest incoming message, so the suggestion still targets "her last reply".
   - Screenshot import now stores `recognizedConversation` in widget state.
   - After screenshot import succeeds, the snackbar now offers `立即分析`.

2. `lib/features/conversation/presentation/screens/new_conversation_screen.dart`
   - Removed the creation-time validation that required the last message to be from the other side.

3. `lib/features/analysis/data/services/analysis_service.dart`
   - Added safer response decoding for non-JSON edge-function responses.
   - Recognition failures now surface the server-side `message` instead of collapsing into a generic error.

4. `supabase/functions/analyze-chat/index.ts`
   - Added `normalizeRecognizedConversation()` to salvage screenshot-recognition payloads when Claude returns `messages` but omits or mangles `messageCount`.
   - Recognition error message is now more actionable for single-image uploads.

5. `supabase/functions/analyze-chat/logger.ts`
   - `ai_logs` and `token_usage` inserts now inspect returned `{ error }` instead of assuming Supabase JS throws.

6. `admin-dashboard/app/api/auth/login/route.ts`
   - Added a server-side login route that validates credentials and checks `admin_users` before issuing a dashboard session.
   - Dashboard auth now uses a server-set `HttpOnly` cookie.

7. `admin-dashboard/app/api/auth/logout/route.ts`
   - Added a server-side logout route that clears the admin session cookie.

8. `admin-dashboard/app/login/page.tsx`, `admin-dashboard/components/layout/nav.tsx`, `admin-dashboard/middleware.ts`, `admin-dashboard/lib/auth.ts`
   - Removed client-side token cookie writes.
   - Middleware now reads the `HttpOnly` admin cookie and clears it when the token is invalid or unauthorized.

9. `supabase/functions/submit-feedback/index.ts`
   - Added category validation, string length limits, `aiResponse` shape/size checks, and safer Telegram preview truncation.

10. `admin-dashboard/app/(dashboard)/activity/page.tsx`
   - Removed two unused variables so the dashboard lint run is clean.

11. `lib/core/services/usage_service.dart`, `lib/features/subscription/data/providers/subscription_providers.dart`
   - Local usage fallback now caches tier/limit snapshots from the real subscription provider instead of always returning free-tier limits.

12. `supabase/functions/analyze-chat/index.ts`
   - Added stricter API boundary validation for request body shape, message count/content, analyze mode, draft length, session context fields, image media types, duplicate image order, and `recognizeOnly` misuse.

13. `admin-dashboard/package-lock.json`
   - Applied lockfile-only `npm audit fix`; `npm audit` now reports 0 vulnerabilities.

14. `supabase/functions/revenuecat-webhook/index.ts`
   - Reworked the webhook handler so it can distinguish a real `UPDATE` from "0 rows updated".
   - Missing `subscriptions` rows are now inserted explicitly instead of being silently treated as success.
   - New records initialize `daily_reset_at` / `monthly_reset_at` / `started_at`.

15. `lib/core/services/supabase_service.dart`
   - Supabase client debug logging now only runs in `kDebugMode`.
   - Free-tier bootstrap records now initialize reset timestamps up front.

16. `lib/features/subscription/data/providers/subscription_providers.dart`
   - Added a shared helper for creating fresh subscription rows with reset timestamps.
   - Force-sync / upsert fallback now creates complete records instead of partial rows.

17. `lib/features/subscription/domain/entities/message_booster.dart`, `lib/features/subscription/presentation/widgets/booster_purchase_sheet.dart`
   - Cleaned up the booster package labels.
   - Removed the fake-success purchase flow; the sheet is now explicitly "coming soon" until booster IAP is actually wired to RevenueCat.

18. `supabase/functions/analyze-chat/index.ts`, `lib/features/analysis/data/services/analysis_service.dart`
   - `recognizeOnly` now accepts empty message history instead of being forced through normal conversation validation.
   - OCR/import requests no longer consume quota or get blocked by monthly/daily limits like a normal analysis call.

19. `pubspec.yaml`, `pubspec.lock`, `lib/features/analysis/presentation/screens/analysis_screen.dart`, subscription UI files
   - Added an explicit `shared_preferences` dependency so the onboarding service no longer relies on a transitive package.
   - `flutter analyze` now runs clean in this environment after installing Flutter locally and tightening several UI/analyzer edge cases.
   - `analysis_screen.dart` still contains mixed-encoding legacy comments; temporary file-level ignores were added for `dead_code` / `unchecked_use_of_nullable_value` so analyzer noise does not hide real findings while the file awaits a full cleanup pass.

20. `lib/features/conversation/data/services/memory_service.dart`, `lib/features/conversation/data/repositories/conversation_repository.dart`, `lib/features/conversation/data/providers/conversation_providers.dart`
   - Replaced the placeholder memory summary with a heuristic summary generator that extracts key topics, shared interests, participation balance, and question count.
   - Conversation saves now keep `currentRound` in sync with message history and automatically append summary segments once older rounds fall outside the active context window.

21. `lib/features/analysis/data/services/analysis_service.dart`, `supabase/functions/analyze-chat/index.ts`, `supabase/functions/submit-feedback/index.ts`
   - OCR-only requests now strip the client-side placeholder message before sending to the Edge Function, reducing prompt noise and token waste.
   - `analyze-chat` now enforces a total image payload cap in addition to the existing per-image limit.
   - Session context prompt text is rebuilt with clean interpolated values before prompt generation.
   - Telegram feedback notifications are rebuilt into a readable, correctly interpolated message payload.

22. `lib/features/conversation/data/services/memory_service.dart`, `lib/features/subscription/data/providers/subscription_providers.dart`, `supabase/functions/analyze-chat/index.ts`, `supabase/functions/submit-feedback/index.ts`
   - Conversation-summary round slicing now follows actual incoming-message boundaries instead of assuming every round is exactly two messages, which fixes summary drift when one side sends multiple messages in a row.
   - The app subscription loader now self-heals missing `subscriptions` rows by inserting a free-tier record instead of collapsing into a loading error.
   - `analyze-chat` now performs the same free-tier self-heal for older or partially-migrated accounts, avoiding a hard `No subscription found` failure on first analysis.
   - `submit-feedback` was rewritten into a clean ASCII-safe version, and Telegram notification failures now log non-200 API responses explicitly.

23. `lib/features/analysis/presentation/screens/analysis_screen.dart`, `lib/shared/widgets/image_picker_widget.dart`, `supabase/functions/analyze-chat/rate_limiter.ts`
   - Screenshot recognition now clears stale OCR state when the user picks new images or cancels the flow.
   - Cancelling the OCR import confirmation dialog now returns cleanly instead of falling through and dereferencing `dialogResult`.
   - Late OCR results are now ignored after user cancellation so the screen does not resurrect an abandoned flow.
   - `ImagePickerWidget` now returns copied image lists instead of leaking the same mutable list reference to the parent screen.
   - The legacy rate limiter helper now self-heals missing `subscriptions` / `rate_limits` rows, resets daily and monthly counters safely, clamps remaining counts to non-negative values, and routes usage increments through the canonical `increment_usage` RPC.

24. `lib/app/routes.dart`, `lib/core/services/social_auth/social_auth_native.dart`, `lib/core/services/supabase_service.dart`, `lib/features/auth/presentation/screens/login_screen.dart`, `lib/features/subscription/data/providers/subscription_providers.dart`, `lib/features/subscription/presentation/screens/settings_screen.dart`, `supabase/functions/submit-feedback/index.ts`, `supabase/functions/revenuecat-webhook/index.ts`
   - GoRouter now refreshes from the Supabase auth stream so sign-out / session changes no longer leave stale protected routes visible.
   - Native Google OAuth now lets Supabase parse the callback URL directly via `getSessionFromUrl()`, avoiding the previous manual token parsing and the incorrect `access_token -> setSession()` fallback.
   - Sign-out now also logs out RevenueCat, and login/logout invalidates the cached subscription provider so a previous user's tier does not bleed into the next session on the same device.
   - Subscription bootstrap / force-sync / webhook-backup paths now tolerate duplicate `subscriptions.user_id` races instead of failing on `23505` when the row is created concurrently.
   - Restore Purchases now syncs `free` back to Supabase as well, so stale paid tiers do not linger when RevenueCat reports no active entitlement.
   - `submit-feedback` now rejects malformed bearer headers, invalid JSON, and non-object payloads before auth/database work begins.
   - `revenuecat-webhook` now validates body shape and UUIDs, rejects unsupported product IDs instead of silently downgrading them to `free`, and records `status` / `expires_at` for tier-changing events.

25. `lib/core/config/environment.dart`, `lib/core/services/supabase_service.dart`, `lib/core/services/social_auth/social_auth_native.dart`, `lib/features/auth/presentation/screens/login_screen.dart`, `supabase/config.toml`
   - Supabase auth now initializes with PKCE instead of the legacy implicit flow.
   - Native Google Sign-In still uses `flutter_web_auth_2` / ASWebAuthenticationSession UX, but the actual OAuth URL is now generated by Supabase SDK PKCE helpers rather than being manually assembled.
   - The Google callback validation now checks both scheme and host before exchanging the PKCE code.
   - Email sign-up now supplies an auth redirect URI, so turning on email confirmations no longer breaks the mobile flow.
   - The login screen was rebuilt into a clean ASCII-safe version with client-side email validation, stronger signup-password validation, generic auth error mapping, and resend-verification actions.
   - Local Supabase auth defaults are now stricter: longer passwords, confirmation emails enabled, secure password change enabled, and redirect allow-lists include the mobile callback URI.

## Product / Logic Notes

- The "last message is me" hotfix does **not** increase token usage. It usually sends the same or fewer messages, because normal analysis is now anchored to the latest incoming message instead of forcing the whole thread to be analyzable.
- Image analysis still uses Sonnet. `my_message` remains Essential-only, and current model selection still routes Essential requests to Sonnet.
- If the user wants analysis of **their own latest message**, the existing Essential-only `my_message` flow is still the right path.

## High-Priority Review Findings Still Open

### P3 Incomplete Features / TODO

1. Booster one-time purchases are still not implemented end-to-end.
   - The UI is now honest and non-deceptive, but actual RevenueCat booster IAP integration is still a future feature.

## Suggested Next Review Sweep

1. Continue with `analyze-chat` + client analysis flow:
   - auth/token handling
   - request size / timeout behavior
   - logging volume / sensitive data review
2. Add regression tests around auth/session switching, login validation, OAuth callback handling, and subscription self-heal races
3. Complete the remaining TODO-backed product gaps (real booster IAP flow)

## Validation Checklist

After deploy, verify:

1. Manual conversation where the latest message is from me:
   - `分析熱度與建議` still returns reply suggestions
   - suggestions are based on the latest incoming message, not my outgoing one

2. Single screenshot upload:
   - recognition succeeds when `messages` exist even if Claude omits `messageCount`
   - snackbar shows `立即分析`

3. Edge Function logs:
   - no new `ai_logs` / `token_usage` silent failures

4. Admin dashboard auth:
   - login succeeds only for `admin_users`
   - cookie is no longer visible in `document.cookie`
   - logout clears access correctly

5. Admin dashboard toolchain:
   - `npm.cmd run lint` passes
   - `npm.cmd audit --json` reports 0 vulnerabilities

6. RevenueCat webhook:
   - retry a real purchase or `PRODUCT_CHANGE` event
   - confirm missing `subscriptions` rows are inserted instead of silently skipped
   - confirm new rows carry `daily_reset_at` / `monthly_reset_at`

7. Screenshot OCR only flow:
   - empty or brand-new conversations should still complete OCR/import
   - successful `recognizeOnly` requests should not increment usage

8. Flutter toolchain:
   - `flutter analyze` passes locally with Flutter `3.41.4`
   - `shared_preferences` is declared directly in `pubspec.yaml`

9. Memory summary / OCR request hygiene:
   - conversations with enough history should accumulate heuristic summary entries over time
   - OCR-only requests should no longer include the placeholder message in the request payload

10. Subscription self-heal path:
   - accounts missing a `subscriptions` row should recreate a free-tier record automatically
   - first analysis after self-heal should proceed instead of returning `No subscription found`

11. Local toolchain validation:
   - `flutter analyze` passes with local Flutter `3.41.4`
   - Supabase Edge Functions pass `deno check` with local Deno `2.7.5`

12. Screenshot cancel / retry behavior:
   - start OCR, then cancel before the request returns; no late dialog or stale error should reappear
   - cancel the import confirmation dialog; the screen should clear selected images and avoid a null-crash

13. Auth / subscription boundary behavior:
   - Google Sign-In should complete without `Refresh token cannot be empty` or stale-session issues
   - sign out, then sign in as a different user on the same device; the paywall/settings tier should reflect the new account immediately
   - session expiry / logout should redirect off protected routes without needing a manual restart

14. Feedback + RevenueCat malformed-input handling:
   - `submit-feedback` should return `400` for invalid JSON, array payloads, or malformed bearer headers
   - `revenuecat-webhook` should return `400` for malformed `app_user_id` or unsupported `product_id` and must not silently downgrade the user to `free`

15. Auth verification hardening:
   - confirm the hosted Supabase Dashboard matches the repo's stricter local auth posture (`enable_confirmations`, password policy, secure password change, redirect allow-list)
   - retest Google Sign-In on TestFlight/iPhone to confirm the SDK-generated PKCE URL still round-trips cleanly through ASWebAuthenticationSession
   - verify email sign-up + resend verification on a real inbox and ensure the confirmation deep link returns to the app correctly

## Notes for Claude Code

- When touching screenshot analysis again, preserve the current token-control approach:
  - `recognizeOnly` for OCR/import
  - Sonnet only when images are present
  - do not assume `my_message` uses Haiku; current Essential path selects Sonnet
- `flutter analyze` passes after this auth/webhook pass. Targeted `flutter test` runs were attempted for `environment_test.dart` and `settings_screen_test.dart`, but both timed out in this desktop environment before producing useful output, so those two tests still need a clean rerun outside this session timeout.
- This pass intentionally did not add an in-app password reset completion screen yet. The email verification / PKCE groundwork is in place, but full recovery UX still needs a dedicated follow-up if password reset should round-trip back into the mobile app.
- If users report "uploaded screenshot but no AI suggestion", check two stages separately:
  - OCR/import success
  - post-import analysis trigger / reply-analysis anchor
- `lib/features/analysis/presentation/screens/analysis_screen.dart` deserves a dedicated cleanup/refactor pass before large new feature work there; the file still has mojibake-era comment damage even though runtime logic is currently stable and `flutter analyze` is clean.
