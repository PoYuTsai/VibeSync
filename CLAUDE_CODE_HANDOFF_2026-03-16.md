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

25. `lib/app/routes.dart`, `lib/core/config/environment.dart`, `lib/core/services/supabase_service.dart`, `lib/core/services/social_auth/social_auth_native.dart`, `lib/features/auth/presentation/screens/login_screen.dart`, `pubspec.yaml`, `supabase/config.toml`, `test/unit/config/environment_test.dart`
   - Supabase auth now initializes with PKCE instead of the legacy implicit flow.
   - Native Google Sign-In still uses `flutter_web_auth_2` / ASWebAuthenticationSession UX, but the actual OAuth URL is now generated by Supabase SDK PKCE helpers rather than being manually assembled.
   - The Google callback validation now checks both scheme and host before exchanging the PKCE code.
   - Email sign-up now supplies an auth redirect URI, so turning on email confirmations no longer breaks the mobile flow.
   - The login screen was rebuilt into a clean ASCII-safe version with client-side email validation, stronger signup-password validation, generic auth error mapping, resend-verification actions, and a forgot-password entry point.
   - Password recovery now completes inside the app: the router intentionally keeps `/login` mounted during a recovery callback, users can set a fresh password on the login screen, and the service explicitly tracks recovery mode so the flow survives cold-start callbacks more reliably.
   - `app_links` is now declared directly in `pubspec.yaml` because auth code now relies on the startup deep link instead of a transitive dependency accident.
   - `environment_test.dart` was updated to match the real shared-dev Supabase setup and to assert the mobile auth callback URI instead of the old localhost-only assumption.
   - Local Supabase auth defaults are now stricter: longer passwords, confirmation emails enabled, secure password change enabled, and redirect allow-lists include the mobile callback URI.

26. `lib/features/auth/presentation/screens/login_screen.dart`, `lib/features/conversation/presentation/screens/home_screen.dart`, `lib/shared/services/image_compress_service.dart`, `lib/shared/widgets/image_picker_widget.dart`, `supabase/functions/analyze-chat/index.ts`
   - Home and login copy is now consistently Traditional Chinese again, replacing the temporary English/auth-hardening wording and lingering mojibake on the screenshot picker path.
   - The screenshot picker's visible labels and error messages were rebuilt cleanly, and the size gate now aligns with the image compression service instead of an outdated hard-coded limit.
   - Single-image screenshot imports now target smaller JPEG payloads (`960px`, about `350KB`) before upload.
   - `recognizeOnly` image requests now ask Claude for fewer output tokens, which should modestly reduce OCR-only latency without touching the higher-budget full image-analysis path.

27. `lib/features/conversation/presentation/screens/new_conversation_screen.dart`, `lib/features/analysis/presentation/screens/analysis_screen.dart`
   - Manual input now matches the live analysis logic: the last message can be from either side, and when the latest message is from the user the app clearly explains that normal analysis will anchor to the previous incoming reply.
   - If the user has only typed outgoing messages so far, manual input now saves that thread as a draft conversation instead of implying analysis should already work.
   - The analysis screen now returns a clearer boundary message when there is still no incoming message to analyze, with a better Essential-tier hint toward the existing `我說` continuation flow.

28. `lib/shared/widgets/image_picker_widget.dart`, `lib/features/analysis/data/services/analysis_service.dart`, `lib/features/analysis/presentation/screens/analysis_screen.dart`, `supabase/functions/analyze-chat/index.ts`
   - Screenshot picking now surfaces an explicit `壓縮中` state and records original/compressed image sizes for each selected screenshot.
   - OCR import now shows clearer progress states (`準備圖片中 / 上傳圖片中 / AI 辨識中`) instead of a single generic spinner.
   - The client now records request payload size, local payload-preparation time, round-trip latency, and server-side AI latency estimates.
   - `analyze-chat` responses now include lightweight OCR telemetry so TestFlight debugging can better distinguish transport overhead from Claude time.

29. `docs/legal/privacy-policy.md`
   - Rewrote the privacy policy so its wording matches the actual shipped product behavior more closely.
   - The doc no longer claims that user-submitted analysis content is never transmitted anywhere; it now explicitly documents the local-first storage model plus the fact that user-triggered analysis / screenshot recognition requests pass through backend processing and AI providers.
   - The user-rights section was also softened to email-based requests instead of implying in-app data export / consent-management screens that are not yet fully shipped.

30. `docs/legal/terms-of-service.md`
   - Rewrote the terms of service so the legal offering matches the product that is actually live today.
   - The doc now describes the current Free / Starter / Essential structure as monthly plans, keeps billing/refund language anchored to App Store / Play rules, and removes implied availability of annual plans, paid-plan free trials, and message-booster add-ons that are not fully launched yet.
   - The acceptable-use and AI-content sections were also tightened to cover unsupported screenshots, harmful uploads, OCR limitations, and the fact that VibeSync is a decision-support tool rather than a guaranteed outcome service.

31. `docs/launch-readiness-checklist.md`
   - Added a single launch-readiness document that turns the current review findings into a concrete execution checklist.
   - The checklist is split into `必修 / 應修 / 可延後 / 伙伴待辦 / 品質門檻`, covering legal sync, auth regression, subscription regression, OCR boundary cases, telemetry verification, and the higher-level quality bar needed before public launch.
   - This is intended to be the working source of truth for the remaining TestFlight-to-App-Review gap, instead of relying on scattered chat messages or handoff bullets alone.

32. `supabase/functions/analyze-chat/index.ts`, `lib/features/analysis/domain/entities/analysis_models.dart`, `lib/features/analysis/presentation/screens/analysis_screen.dart`
   - Screenshot recognition now returns a lightweight boundary decision alongside the OCR payload: `classification`, `importPolicy`, `confidence`, and `warning`.
   - The Edge Function now explicitly rejects likely social-feed / unsupported / unreadable images before they can be imported into a conversation, while lower-confidence chat detections are still allowed but marked as `confirm` instead of being treated like a clean high-confidence import.
   - The Flutter client now surfaces those warnings in the confirmation dialog and the recognized-conversation card, and it also warns when the recognized contact name does not match the current thread name, reducing accidental cross-thread screenshot pollution.

33. `lib/features/conversation/domain/entities/conversation.dart`, `lib/features/conversation/data/services/memory_service.dart`, `lib/features/analysis/data/services/analysis_service.dart`, `lib/features/analysis/presentation/screens/analysis_screen.dart`, `supabase/functions/analyze-chat/index.ts`
   - Historical conversation summaries are now wired into the live analysis request path instead of being generated only for storage.
   - The client now builds a summary-aware payload: older context is sent as `conversationSummary`, while the raw message list is clipped to recent incoming-message rounds when summary coverage exists.
   - The old round-window assumption (`2 messages = 1 round`) was also removed from the main context helpers, so both memory slicing and live analysis now follow actual incoming-message boundaries more consistently.

34. `lib/features/conversation/domain/entities/conversation.dart`, `lib/features/conversation/domain/entities/conversation.g.dart`, `lib/features/analysis/presentation/screens/analysis_screen.dart`
   - Conversations now persist the latest completed analysis snapshot locally (`lastAnalysisSnapshotJson` + `lastAnalyzedMessageCount`) alongside the existing metadata.
   - Reopening an analyzed thread now restores the previous score, strategy, reply set, recommendation, and raw AI payload instead of rendering the analysis area as blank state until the user manually reruns it.
   - The persisted analyzed-message count is also restored, so the existing "new messages arrived since last analysis" prompt still compares against the right baseline after a reopen.

35. `docs/app-store-strategy.md`, `docs/website-landing-page-handoff.md`
   - The App Store review strategy doc was rewritten into a clean current version and no longer contains the old inaccurate claim that all user conversation content always stays on-device and never passes through backend processing.
   - A new partner handoff doc now captures the exact homepage privacy copy, legal-link requirements, and footer download-button rule for the marketing site.
   - Because the public App Store listing is not live yet, the handoff explicitly tells the partner to stop using a fake `href="#"` download CTA and switch either to a real store URL or a non-clickable "coming soon / TestFlight" state.

36. `lib/core/services/supabase_service.dart`, `lib/features/subscription/presentation/screens/settings_screen.dart`, `supabase/functions/delete-account/index.ts`, `supabase/functions/revenuecat-webhook/index.ts`
   - The settings-screen account-deletion action is no longer a misleading local-only wipe; it now runs a real end-to-end delete flow.
   - The client requires an explicit `DELETE` confirmation, calls the new `delete-account` Edge Function, clears local storage, and cleans up the local auth / RevenueCat session after the server-side account is removed.
   - The new Edge Function deletes dependent records that do not cascade cleanly (`revenue_events`, `feedback`, `webhook_logs`) before removing the auth user, which lets the existing cascade take care of the rest of the user-owned data.
   - RevenueCat webhook handling now treats events for deleted users as ignorable and returns `200` instead of trying to recreate broken subscription state for a missing account.

37. `lib/features/subscription/presentation/screens/settings_screen.dart`
   - The settings screen was rewritten into a clean Traditional Chinese version so the account-management path no longer shows mojibake-era labels during TestFlight review.
   - The rebuilt screen keeps the same paywall / restore / legal / feedback / logout actions, but now surfaces the new real account-deletion flow in a cleaner and more review-friendly UI.

38. `lib/features/analysis/presentation/screens/analysis_screen.dart`, `supabase/functions/analyze-chat/index.ts`
   - Screenshot import confirmation now exposes two explicit import modes: append into the current thread or create a brand-new conversation, instead of always appending OCR output to the active tail.
   - When Claude marks the screenshot as `confirm` / low-confidence, or when the recognized contact name disagrees with the current thread name, the client now defaults the dialog to `另存成新對話` to reduce cross-thread pollution.
   - OCR prompting now explicitly tells Claude how to treat LINE-style quoted-reply bubbles: the quote preview is not a standalone new message, and should only be merged into the actual bubble content when needed for meaning.
   - The screenshot prompt also now emphasizes preserving Traditional Chinese exactly, reading long dense screenshots top-to-bottom, and avoiding guessed characters; `recognizeOnly` output budget was raised from `1200` to `1600` to support denser OCR payloads.

39. `lib/features/analysis/presentation/screens/analysis_screen.dart`, `lib/shared/widgets/image_picker_widget.dart`
   - OCR confirmation and recognized-result cards now surface explicit `分類 / 信心` chips plus a short "what to do next" guidance block instead of only dumping a warning string.
   - Low-confidence screenshots now tell the user more clearly when they should re-screenshot, preserve the full bubble, or switch to `另存成新對話`.
   - The image picker now adds capture tips before upload, including guidance for long Traditional Chinese screenshots and LINE's quoted-reply UI so testers can improve recognition quality without guessing.

40. `lib/features/analysis/domain/services/screenshot_recognition_helper.dart`, `test/unit/services/screenshot_recognition_helper_test.dart`, `docs/testflight-regression-checklist.md`
   - The screenshot import decision copy and boundary logic is now extracted into a pure helper instead of living only inside `analysis_screen.dart`, which makes the default import-mode choice, mismatch warning, naming fallback, and guidance strings unit-testable.
   - A new unit test file now locks in the highest-value OCR edge cases: empty-thread append, low-confidence new-thread default, name mismatch detection, social-feed rejection guidance, and LINE quoted-reply / blurry-screenshot guidance copy.
   - A dedicated TestFlight regression checklist now exists for auth, subscription, OCR import modes, LINE reply screenshots, dense Traditional Chinese screenshots, and telemetry capture, so manual partner QA can follow a consistent script instead of reconstructing scenarios from chat history.

41. `lib/features/analysis/presentation/widgets/screenshot_recognition_dialog.dart`, `test/widget/widgets/screenshot_recognition_dialog_test.dart`, `lib/features/analysis/presentation/screens/analysis_screen.dart`
   - The screenshot import confirmation dialog is now extracted into its own widget instead of being an inline `StatefulBuilder` buried inside `analysis_screen.dart`.
   - This keeps the production behavior the same, but it isolates the most fragile OCR UI path: low-confidence warnings, import-mode switching, preview rendering, and optional session-context capture.
   - A new widget-test file now targets that dialog directly so the `加入目前對話 / 另存成新對話 / 取消 / 低信心提示` interaction can be regression-tested independently, although `flutter test` still times out in this desktop session and should be rerun in a clean environment.

42. `lib/core/services/auth_recovery_helper.dart`, `lib/features/subscription/domain/services/subscription_tier_helper.dart`, `lib/core/services/supabase_service.dart`, `lib/core/services/revenuecat_service.dart`, `lib/core/services/usage_service.dart`, `lib/features/subscription/data/providers/subscription_providers.dart`
   - Password-recovery callback normalization and auth-event state transitions are now extracted into a pure helper instead of being buried as private inline logic inside `SupabaseService`.
   - Subscription tier normalization, product-id inference, and monthly/daily limits are now centralized in a shared helper that is reused by RevenueCat entitlement parsing, usage fallback defaults, and subscription state updates.
   - This reduces the risk that `free / starter / essential` rules drift apart between login, purchase, restore, force-sync, and cached usage paths.

43. `test/unit/services/auth_recovery_helper_test.dart`, `test/unit/services/subscription_tier_helper_test.dart`
   - Added focused unit tests for auth recovery callback parsing, password-recovery state transitions, tier-limit lookup, and product-id-to-tier inference.
   - `flutter analyze` passes after this refactor.
   - `flutter test` for these new unit tests still times out in this desktop session with no useful output, so they need a clean rerun on a less sticky local environment before treating them as verified.

44. `lib/features/subscription/presentation/screens/paywall_screen.dart`
   - The paywall screen was rebuilt into a clean Traditional Chinese version so TestFlight users no longer see mojibake-era copy on the purchase path.
   - Privacy / Terms buttons now open the real live legal pages instead of being no-op placeholders.
   - Purchase success now surfaces a simple launch-facing success message instead of an internal RevenueCat entitlement dump, while debug-only force-sync and diagnostics remain gated behind `kDebugMode`.
   - Restore-purchases and generic purchase-error messaging were also tightened so release builds do not leak raw exception strings to users.

45. `docs/testflight-regression-checklist.md`, `README.md`
   - The TestFlight regression checklist was rewritten into a readable master runbook that now covers auth recovery, paywall verification, OCR import modes, analysis persistence, account deletion, and OCR telemetry sign-off in one place.
   - README hotfix notes now document the paywall cleanup and the new master QA checklist so the next reviewer can see the latest launch-facing changes at a glance.

46. `supabase/functions/analyze-chat/index.ts`, `supabase/functions/analyze-chat/fallback.ts`, `supabase/functions/analyze-chat/logger.ts`
   - `analyze-chat` now rejects oversized request bodies up front using the incoming `content-length`, which avoids paying the JSON/base64 parse cost for obviously too-large requests.
   - Edge-function logging was tightened so request/subscription logs no longer print raw user email addresses or raw AI response snippets into function logs.
   - Claude JSON-parse failures now log only metadata like model, response length, and error type instead of dumping the first part of the generated output.
   - `ai_logs` failure payload storage is now sanitized and redacted before insert, so future error logging cannot accidentally persist full conversations, screenshots, or prompt bodies.
   - The fallback client now clears abort timers in a `finally` block, which avoids leaking timeout timers when fetch fails or retries.

47. `supabase/functions/analyze-chat/index.ts`, `supabase/functions/analyze-chat/fallback.ts`
   - Image-based requests now keep `allowModelFallback = false`, so screenshot OCR / image analysis no longer silently downgrades from Sonnet to Haiku on retry.
   - This brings the runtime behavior back in line with the original screenshot-upload design, which assumed Vision requests should stay on Sonnet.
   - Request timeouts are now split by path: OCR-only image requests fail faster than full image analysis, and text-only `my_message` requests use a shorter timeout than the heavier normal-analysis path.

48. `supabase/functions/analyze-chat/index.ts`
   - Screenshot prompting is now centralized into shared builders for `recognizeOnly` and full image analysis, instead of maintaining a second inline OCR prompt block deeper in the request handler.
   - This removes duplicated OCR instructions, keeps LINE quoted-reply / Traditional Chinese handling aligned across both image paths, and avoids future drift between the screenshot import flow and full screenshot analysis flow.
   - The `optimizedMessage` draft-injection path now also uses the same prompt-section joiner, so user drafts are appended through one consistent formatting path instead of ad-hoc string concatenation.

49. `lib/features/analysis/data/services/analysis_service.dart`, `lib/features/analysis/presentation/screens/analysis_screen.dart`
   - Analysis-service retry logs and screenshot-recognition debug logs are now gated behind `kDebugMode`, so TestFlight / release builds no longer emit OCR flow metadata, conversation IDs, or detailed recognition failures into normal device logs.
   - This keeps the existing developer-facing diagnostics intact in debug sessions, but it better matches the app's privacy posture during partner testing and release usage.
   - The stale `// TODO: Navigate to paywall screen` comment in `analysis_screen.dart` was also removed because the route is already implemented and should not keep showing up as a fake unfinished task.

## Product / Logic Notes

- The "last message is me" hotfix does **not** increase token usage. It usually sends the same or fewer messages, because normal analysis is now anchored to the latest incoming message instead of forcing the whole thread to be analyzable.
- Image analysis still uses Sonnet, and image retries no longer cross-downgrade to Haiku. `my_message` remains Essential-only and still uses the lighter text-only path.
- If the user wants analysis of **their own latest message**, the existing Essential-only `my_message` flow is still the right path.

## High-Priority Review Findings Still Open

### P3 Incomplete Features / TODO

1. Booster one-time purchases are still not implemented end-to-end.
   - The UI is now honest and non-deceptive, but actual RevenueCat booster IAP integration is still a future feature.

## Suggested Next Review Sweep

1. Continue with `analyze-chat` + client analysis flow:
   - request size / timeout behavior
   - logging volume / sensitive data review
   - sensitive-data exposure in logs and retries
2. Add regression tests around auth/session switching, login validation, forgot-password recovery callbacks, OCR import latency, OAuth callback handling, and subscription self-heal races
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

13. Screenshot import mode:
   - import a valid latest-chat screenshot into the current thread and confirm it still offers `立即分析`
   - import a screenshot from another person or older thread and confirm `另存成新對話` is the safer default path

14. Traditional Chinese / LINE reply OCR:
   - test a LINE screenshot that uses the built-in "回覆" quoted-message UI and confirm the quoted preview is not duplicated as a separate new message
   - test a long dense Traditional Chinese screenshot and compare recognition quality / latency against the previous TestFlight build

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
   - verify forgot-password on both warm-start and cold-start app launches, and confirm the new-password screen stays on `/login` until completion

16. Screenshot import latency:
   - measure a single-image OCR import on TestFlight after the new compression settings
   - verify recognition quality still holds on dense chat screenshots after lowering the upload size and OCR-only token budget

17. Manual-input edge cases:
   - create a conversation that ends with `我`
   - create a conversation that only contains `我`
   - verify the helper copy, draft-saving behavior, and post-save analysis guidance all feel consistent on TestFlight

18. Analysis persistence:
   - analyze a conversation, back out to the list, and reopen it; the previous analysis should still be visible without rerunning
   - append one or more new messages after that reopen and confirm the existing "new messages since last analysis" prompt still appears off the restored baseline

19. Account deletion:
   - from settings, open account deletion and confirm the `DELETE` gate blocks accidental taps
   - complete a real deletion once on a disposable test account and confirm the app returns to `/login`
   - retry login with that deleted account and confirm it no longer succeeds without a fresh sign-up
   - if that account had historical RevenueCat events, confirm later webhook deliveries are logged as ignored instead of failing

## Notes for Claude Code

- When touching screenshot analysis again, preserve the current token-control approach:
  - `recognizeOnly` for OCR/import
  - Sonnet only when images are present
  - image retries should stay on Sonnet; do not reintroduce cross-model fallback on Vision requests
  - `my_message` is still Essential-only but currently uses the lighter text-only path
- `flutter analyze` passes after this auth/webhook pass. Targeted `flutter test` runs were attempted again for `environment_test.dart` and `supabase_service_test.dart`, and they still timed out in this desktop environment without producing useful output; earlier `settings_screen_test.dart` attempts also timed out, so those tests still need a clean rerun outside this session timeout.
- The auth pass now includes in-app password reset completion, but it still needs a real-device regression pass for both warm-start and cold-start recovery links.
- If users report "uploaded screenshot but no AI suggestion", check two stages separately:
  - OCR/import success
  - post-import analysis trigger / reply-analysis anchor
- `lib/features/analysis/presentation/screens/analysis_screen.dart` deserves a dedicated cleanup/refactor pass before large new feature work there; the file still has mojibake-era comment damage even though runtime logic is currently stable and `flutter analyze` is clean.
