# Claude Code Handoff - 2026-03-16

## Current Status

This hotfix batch focused on the core conversation-analysis path, screenshot recognition reliability, the highest-risk admin/API security issues, subscription-state consistency around RevenueCat + Supabase sync, and the remaining auth / webhook boundary issues that could still leak stale state or mis-handle malformed events.

## 2026-04-03 TestFlight v82 Snapshot

- Current phase: pre-submission stabilization on TestFlight v82
- Confirmed working on-device:
  - signup
  - email confirmation back into app
  - forgot password / reset password back into app
  - account deletion and re-registration
  - free -> essential upgrade and full-reply refresh
  - same-Apple-ID restore / transfer behavior
  - account isolation across logout / login
- Current docs of truth:
  - `docs/current-test-status-2026-04-03.md`
  - `docs/supabase-ops-guide.md`
  - `docs/revenuecat-ops-guide.md`
  - `docs/security-hardening-status.md`
  - `docs/security-incident-response.md`
  - `docs/app-review-final-checklist.md`
  - `docs/testflight-regression-checklist.md`

## 2026-04-05 Security Round 2

- `auth_diagnostics` now has schema-level guardrails instead of being a near-open insert sink: bounded event format, bounded field lengths, bounded metadata size, and bounded timestamps.
- Client-side auth diagnostics now also dedupe rapid repeated events and shrink metadata before insert, reducing normal-flow log spam and accidental oversized payloads.
- A new migration adds retention helpers for observability/security tables:
  - `cleanup_old_auth_diagnostics()`
  - `cleanup_old_webhook_logs()`
  - `cleanup_observability_logs()`
- A new incident-response runbook now lives at `docs/security-incident-response.md`, covering containment, secret rotation, investigation queries, recovery, and postmortem expectations.
- Security posture after this pass: stronger than the previous launch candidate, but still short of a "high-trust privacy product" until diagnostics ingestion, retention automation, and infra ownership are tightened further.

## 2026-04-03 Subscription Sync Root-Cause Fix

- The long-running "Free analyze -> upgrade to Essential -> analysis still behaves like free tier" bug was traced to `public.subscriptions` RLS: the app was trying to update the subscription row directly from the client, but `analyze-chat` only trusts the backend `subscriptions` row.
- Added a new Edge Function `sync-subscription` that authenticates the current user, asks RevenueCat for the latest subscriber state, and writes the resolved tier/usage back with the Supabase service role.
- `lib/features/subscription/data/providers/subscription_providers.dart` was rewritten so purchase / restore / forced tier sync now go through `sync-subscription` instead of client-side `subscriptions` updates.
- `.github/workflows/deploy-edge-function.yml` now deploys `sync-subscription` alongside the other Edge Functions.
- Follow-up hardening (2026-04-03): `sync-subscription` no longer trusts client-supplied `expectedTier` to elevate plan state. The persisted tier now comes only from RevenueCat's server-side subscriber view.
- Follow-up hardening (2026-04-03): `analyze-chat` now blocks requests whose projected `chargedMessageCount` would push daily/monthly usage over the tier limit, instead of only checking the pre-request counters.
- Follow-up UX + consistency hardening (2026-04-03): restore/sync now shows an explicit confirmation explaining that the current Apple ID's purchase may transfer onto the currently signed-in VibeSync account, and the RevenueCat `TRANSFER` webhook now upgrades the recipient account while downgrading the source account back to free so the backend does not leave both accounts premium indefinitely.
- Follow-up OCR hardening (2026-04-03): local OCR cache is now scoped by conversation ID in addition to user ID, reducing cross-thread replay of stale `contactName / warning / importPolicy`.
- Follow-up OCR hardening (2026-04-03): short-continuation and overlap-dedup heuristics were made more conservative so very short real replies are less likely to be auto-merged or auto-removed as screenshot overlap.

## 2026-04-01 Account Isolation Hotfix

- Local conversations are now scoped by signed-in user instead of being read from a global Hive list.
- Legacy ownerless local conversations created before this hotfix are quarantined instead of being shown to the wrong account.
- Login/logout now invalidate conversation + usage providers, and logout clears the local usage snapshot so a newly signed-in account does not inherit stale quota/tier UI.
- The email/password login form now has password visibility toggles for both the main password field and the recovery confirmation field.

## 2026-04-01 Auth Deep Link + Verification Mail Hotfix

- iOS `SceneDelegate.swift` now forwards incoming URL contexts / user activities to `app_links`, fixing cases where password-reset or signup-confirmation links opened the app but did not enter the expected auth flow.
- Android `AndroidManifest.xml` now declares the `com.poyutsai.vibesync://login-callback` intent filter so auth callback links can reopen the app correctly.
- `SupabaseService` no longer requires an already-active user session when detecting a password-recovery cold start link.
- Login/signup now best-effort resends the signup confirmation email when Supabase returns the "existing but still unconfirmed" style response, and the UI guidance now explicitly tells the user to open the auth link on the phone with the app installed.

## 2026-03-30 Discord Runtime Note

- VibeSync Discord bridge troubleshooting is documented in `docs/discord-vibesync-troubleshooting.md`.
- If mobile Discord should deterministically trigger Codex instead of relying on natural-language delegation, see `docs/discord-codex-command-bridge-design.md`.
- The real live state for this project is `~/.claude/channels/discord-vibesync/access.json`, not the generic `~/.claude/channels/discord/access.json`.
- The root cause of the Bruce monitoring issue was the live `discord-vibesync` allowlist missing his user ID.
- The live WSL plugin was also hardened with `GuildMembers` intent plus polling fallback, but that runtime patch lives outside this repo.

## 2026-03-31 Analysis Output Guardrail

- `supabase/functions/analyze-chat/index.ts` now guarantees non-empty reply output for normal analysis.
- If Claude returns blank `replies` or blank `finalRecommendation.content`, the edge function now fills from tier-allowed replies or a safe fallback instead of returning an empty recommendation card.
- `lib/features/analysis/domain/entities/analysis_models.dart` also adds a client-side fallback, so older or partial responses do not render an empty `AI 推薦回覆` block.

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

50. `lib/shared/services/link_launch_service.dart`, `lib/features/auth/presentation/screens/login_screen.dart`, `lib/features/subscription/presentation/screens/settings_screen.dart`, `lib/features/subscription/presentation/screens/paywall_screen.dart`
   - Website/legal link launching is now centralized in a shared helper that prefers `LaunchMode.inAppBrowserView` for normal `http/https` pages, which makes privacy / terms / website links feel embedded instead of always bouncing users into Safari.
   - Telegram-style external destinations are still kept on `LaunchMode.externalApplication`, so support/deep-link style URLs do not regress into an awkward in-app webview.
   - Login, settings, and paywall now all use the same launcher and show a consistent failure snackbar when the URL cannot be opened.

51. `supabase/functions/analyze-chat/index.ts`, `lib/features/analysis/domain/services/screenshot_recognition_helper.dart`
   - Screenshot OCR now distinguishes more explicitly between a standalone phone call log screen and a real one-to-one chat thread that happens to contain missed-call / call-record entries.
   - Prompting now tells Claude not to reject an otherwise-valid chat thread just because the visible content is mostly `未接來電` / call records, and to convert those in-thread call records into directional conversation events.
   - Server-side normalization also now catches the common false-negative shape where OCR extracts only call events but still labels the screenshot `unsupported`; that case is downgraded to `low_confidence + confirm` with Chinese guidance instead of a hard English rejection banner.

52. `lib/features/analysis/data/services/analysis_service.dart`, `lib/features/analysis/presentation/screens/analysis_screen.dart`
   - Analysis/OCR error handling is now mapped through a dedicated user-facing error taxonomy instead of leaking raw backend strings like `Analysis failed`, `timeout`, or exception dumps into the UI.

53. `supabase/functions/analyze-chat/index.ts`, `lib/features/analysis/domain/entities/analysis_models.dart`, `lib/features/analysis/data/services/analysis_service.dart`, `lib/features/analysis/presentation/widgets/screenshot_recognition_dialog.dart`, `lib/features/conversation/domain/entities/message.dart`, `lib/features/conversation/presentation/widgets/message_bubble.dart`
   - LINE-style quoted replies now preserve two layers of ownership instead of collapsing everything into one speaker guess.
   - The outer bubble still decides the real `我說 / 她說`, but readable quote cards can now carry `quotedReplyPreviewIsFromMe`, so a left-side Candy reply can correctly keep a nested quoted Bruce snippet as right-side historical context without emitting it as a new standalone row.
   - Imported messages, later analysis requests, the OCR edit dialog, and the in-thread message bubble UI now all preserve and display that quoted-preview speaker metadata end to end.
   - The service now normalizes oversized payloads, unsupported image types, no-incoming-message analysis attempts, auth expiry, upstream busy states, and generic network/timeout failures into clear Traditional Chinese messages plus suggested recovery actions.
   - The screen layer now uses those friendly messages directly and falls back to generic Chinese copy for unknown OCR / analysis / optimize failures, so TestFlight users should no longer see technical prefixes like `識別失敗: ...` or `優化失敗: ...`.

53. `lib/features/analysis/presentation/widgets/screenshot_recognition_dialog.dart`, `lib/features/analysis/presentation/screens/analysis_screen.dart`, `lib/features/analysis/domain/entities/analysis_models.dart`
   - Screenshot import now supports an editable OCR preview instead of a read-only top-5 preview. Before confirming import, users can fix text, switch each row between `我說 / 她說`, and delete obviously wrong messages.
   - The dialog now returns the edited recognized-message list, and the import path uses those corrected messages for both `加入目前對話` and `另存成新對話`, so small OCR mistakes no longer force the user to throw away the whole recognition result.
   - `RecognizedMessage` / `RecognizedConversation` now expose `copyWith`, which keeps the temporary in-screen recognized state aligned with the user-edited import result instead of the original raw OCR payload.

54. `test/widget/widgets/screenshot_recognition_dialog_test.dart`
   - The dialog widget test now also covers the new editable-preview flow: changing `我 / 她`, editing message text, deleting one recognized row, and confirming import.
   - `flutter analyze` passes after this pass.
   - The targeted widget test still timed out in this desktop session without useful output, so it needs a clean rerun before being treated as fully verified.

55. `supabase/functions/analyze-chat/index.ts`, `lib/features/analysis/domain/services/screenshot_recognition_helper.dart`, `test/unit/services/screenshot_recognition_helper_test.dart`
   - Screenshot preflight classification is now more product-specific instead of collapsing almost everything into `unsupported`: the OCR path now recognizes `group_chat`, `gallery_album`, `call_log_screen`, `system_ui`, and `sensitive_content` alongside the existing `valid_chat / low_confidence / social_feed / unsupported`.
   - Server-side normalization can now infer these categories from model warning/summary text even if the model forgets to emit the exact enum, and each reject-type category now gets a clearer Traditional Chinese explanation instead of one generic unsupported warning.
   - Chat-thread-only call-record screenshots still keep the special downgrade path: if OCR extracted only call events but the image still looks like an in-thread call-event list, the server demotes `call_log_screen/system_ui/unsupported` into `low_confidence + confirm` instead of hard reject.
   - `flutter analyze` and `deno check supabase/functions/analyze-chat/index.ts` pass after this pass.
   - The targeted helper unit test still timed out in this desktop session, so it needs a clean rerun before counting as fully verified.

56. `docs/website-landing-page-handoff.md`
   - The landing-page handoff doc is now updated to match the latest partner status instead of still reading like an open TODO list.
   - As of 2026-03-18, the repo assumes live `/privacy` and `/terms` are done, while the footer App Store CTA is intentionally deferred until the final pre-launch / post-approval pass.
   - Live `privacy` and `terms` were reachable from this desktop session during the check; the homepage root itself returned a transient remote-server connection failure twice, so the handoff keeps one final homepage/footer QA pass on the pre-launch checklist instead of claiming full homepage verification.

57. `supabase/functions/analyze-chat/index.ts`, `lib/features/subscription/data/providers/subscription_providers.dart`, `lib/core/services/usage_service.dart`, `lib/features/analysis/presentation/screens/analysis_screen.dart`
   - Business-logic review found two real consistency gaps and patched both:
     1. the server claimed test accounts should behave like Essential, but `my_message` gating and text-model selection were still checking the raw stored tier instead of the effective test tier;
     2. successful analyses were deducting quota on the server, but Flutter's in-memory subscription state was not being updated from the returned usage snapshot, so users could keep seeing stale remaining quota until the next full refresh.
   - `analyze-chat` now uses the effective tier consistently for test-account feature gating and model selection.
   - The Flutter side now syncs daily/monthly remaining quota from successful analysis responses into both `subscriptionProvider` state and the local usage cache, and `monthlyRemaining` / `dailyRemaining` are clamped to avoid negative UI values.
   - `flutter analyze` and `deno check supabase/functions/analyze-chat/index.ts` pass after this pass.

58. `supabase/functions/revenuecat-webhook/index.ts`
   - Business-logic review also found that RevenueCat `CANCELLATION` events were only being logged and not persisted into the subscription row, so the backend could not distinguish `active auto-renewing` from `cancelled but still active until expiry`.
   - The webhook now loads the current subscription row, preserves the current tier (or derives it from the product id), and writes `status: "canceled"` plus `expires_at` on `CANCELLATION` events instead of doing nothing.
   - `deno check supabase/functions/revenuecat-webhook/index.ts` passes after this patch.

59. `lib/core/services/message_calculator.dart`, `lib/shared/widgets/analysis_preview_dialog.dart`, `lib/features/analysis/presentation/screens/analysis_screen.dart`
   - The previously orphaned pre-analysis usage preview is now connected to the real manual-analysis flow instead of sitting unused in the widget library.
   - Billed-message preview now mirrors the backend's per-message `200 chars = 1 billed message` rule on the exact summary-aware request payload that will be sent, rather than guessing from the raw thread text.
   - The dialog also now uses cleaned-up Traditional Chinese copy, shows projected monthly/daily remaining quota after the run, and routes over-quota users toward the paywall without pretending an upgrade can fix an oversized payload.

60. `lib/features/analysis/data/services/ocr_recognition_cache_service.dart`, `lib/features/analysis/domain/entities/analysis_models.dart`, `lib/features/analysis/data/services/analysis_service.dart`, `lib/features/analysis/presentation/screens/analysis_screen.dart`
   - Screenshot OCR now uses a short-lived per-user local cache keyed by the exact compressed image batch, so retrying the same screenshots can reuse the previous recognition result instead of re-uploading to Claude every time.
   - Cache entries are versioned, encrypted through the existing Hive settings box, and pruned by age/count to reduce stale-result risk and unbounded growth.
   - OCR telemetry now exposes cache hits in the UI, so a near-instant recognition result reads as an intentional cache reuse rather than a broken latency card.

61. `lib/shared/services/screenshot_preflight_service.dart`, `lib/shared/widgets/image_picker_widget.dart`
   - Screenshot selection now runs a cheap local preflight before any upload or Claude call.
   - Landscape images, near-square images, and very low-resolution captures are rejected immediately with human Traditional Chinese guidance instead of spending OCR cost on obviously bad inputs.
   - Very long or lower-resolution portrait screenshots are still allowed, but now surface a warning first so testers can split or re-crop the capture before paying the full OCR cost.

62. `lib/features/analysis/presentation/screens/analysis_screen.dart`
   - The OCR entry flow copy was polished again so the screenshot-analysis path reads more like a shipped product and less like internal tooling.
   - The analysis intro, screenshot-length guidance, and "recognize first, analyze second" explanation are now cleaner and more explicit about what the app is doing.

63. `docs/testflight-regression-checklist.md`, `README.md`
   - The TestFlight checklist now includes an explicit stop point for this stage: once OCR preflight, user-facing OCR copy, and the core A/B/C smoke checks are stable, the team can pause coding and move into partner validation.
   - README now also reflects that this build is intended to be a reasonable pause point for the next TestFlight round, rather than an endlessly moving target.

64. `lib/features/analysis/presentation/screens/analysis_screen.dart`
   - The "optimize my message" result block now uses a darker, higher-contrast treatment so the generated text is readable inside the white glass container on mobile.
   - The post-analysis "continue conversation" composer now supports screenshot upload as well as manual typing, so users can import new chat screenshots without leaving the follow-up flow.
   - While screenshots are pending recognition, the bottom `她說 / 我說` actions now disable visually instead of letting users accidentally bypass the OCR step and create a confusing mixed flow.

65. `supabase/functions/analyze-chat/index.ts`
   - Screenshot OCR speaker-direction rules are now stricter: bubble alignment explicitly overrides semantic guessing when deciding `isFromMe`.
   - The prompt now warns against forcing alternating speakers and calls out short right-side bubbles like `超爽` as cases that must still follow layout rather than wording.
   - Both recognize-only and full image-analysis prompts now ask for a final side-check before returning JSON, so clearly right-aligned bubbles should be less likely to come back as `她說`.
   - The media-bubble case is now called out more explicitly too: a right-side image/photo placeholder and its same-side follow-up text should stay `我說` unless the layout clearly switches sides.

66. `supabase/functions/analyze-chat/index.ts`, `lib/features/analysis/domain/services/screenshot_recognition_helper.dart`, `lib/features/analysis/presentation/screens/analysis_screen.dart`, `lib/features/analysis/presentation/widgets/screenshot_recognition_dialog.dart`
   - Screenshot OCR now explicitly ignores LINE announcement banners, pinned-message jumps, and `回到最新訊息`-style system hints instead of turning them into fake messages.
   - If a screenshot starts from older history after tapping a LINE announcement/pinned item, the OCR instructions now tell the model to extract only the visible bubbles and not invent missing context above the capture.
   - Mixed-thread screenshot batches now downgrade to `low_confidence + confirm` with stronger Chinese warnings when the images appear to come from different contacts or unrelated thread segments.
   - Canceling the import dialog no longer discards finished OCR work: the recognized result is preserved as a resumable draft with `繼續匯入設定`, and the dialog's secondary action is now framed as `稍後再匯入`.

67. `supabase/functions/analyze-chat/index.ts`
   - The screenshot OCR path now adds a deterministic post-processing fix for isolated media-bubble speaker flips.
   - If a photo/image placeholder is the only opposite-side outlier between two same-side messages, the backend now snaps that placeholder back to the surrounding side instead of trusting the raw model label.
   - This specifically targets cases like `右側文字 -> 右側圖片泡泡 -> 右側補一句 -> 左側回覆`, where the image placeholder used to get mislabeled as `她說` even though the visual bubble was on the right.

68. `supabase/functions/analyze-chat/index.ts`, `lib/features/analysis/domain/entities/analysis_models.dart`
   - Screenshot OCR is now documented and normalized as a layout-first pipeline instead of a text-first guess: the model is instructed to identify each bubble's `side` from the outer bubble position before reading content.
   - Image-in-image content, photo previews, and screenshots inside a bubble are now explicitly forbidden from overriding the outer bubble side.
   - The app-side `RecognizedMessage` model now preserves the returned `side` field (`left/right/unknown`) so future debugging and post-processing no longer has to rely only on `isFromMe`.

69. `lib/features/analysis/domain/services/screenshot_recognition_helper.dart`, `lib/features/analysis/presentation/screens/analysis_screen.dart`, `lib/features/conversation/presentation/screens/home_screen.dart`
   - Screenshot import naming had a real business-logic bug: some flows created placeholder threads as `新的對話`, while the rename path only recognized `新對話`.
   - The helper now treats both `新對話` and `新的對話` as untitled placeholder names, so when OCR has already recognized a contact name like `Amy`, importing into an untitled thread now correctly promotes the title instead of leaving the app bar stuck on the placeholder text.
   - The screenshot-start flow on the home screen is also normalized to create `新對話` going forward, reducing future drift.

70. `supabase/functions/analyze-chat/index.ts`, `lib/features/analysis/domain/entities/analysis_models.dart`, `lib/features/analysis/domain/services/screenshot_recognition_helper.dart`, `lib/features/analysis/presentation/screens/analysis_screen.dart`, `lib/features/analysis/presentation/widgets/screenshot_recognition_dialog.dart`
   - Screenshot OCR now exposes a separate structure/speaker-direction confidence layer instead of collapsing everything into one generic recognition confidence.
   - The backend computes `sideConfidence` and `uncertainSideCount` from the returned bubble-side data and continuity corrections, so the app can distinguish "content mostly read fine" from "left/right assignment is still shaky".
   - The result card now shows a dedicated direction-confidence chip, helper copy escalates when speaker direction is uncertain, and the import dialog surfaces both the original detected side (`左側 / 右側 / 方向待確認`) and a warning when some rows need manual `我說 / 她說` review.

71. `lib/features/analysis/presentation/screens/analysis_screen.dart`, `lib/features/analysis/domain/entities/analysis_models.dart`
   - The main analysis screen now treats failures as a structured product state instead of a raw string: inline errors now track `message + suggested action + error origin + guidance`, so OCR and normal analysis can surface different recovery paths without brittle `contains(...)` matching.
   - The inline error card now offers action-aware CTAs such as `重新識別`, `補上對方訊息`, `查看方案`, `重新登入`, or `調整截圖`, and those CTAs now actually route into the correct path (`recognize`, `analyze`, paywall, logout/login, or reopening the follow-up composer).
   - A small lingering analyzer lint in `analysis_models.dart` was also cleaned up during this pass, and `flutter analyze` now passes clean again in this desktop session.

72. `lib/features/analysis/presentation/widgets/screenshot_recognition_dialog.dart`, `test/widget/widgets/screenshot_recognition_dialog_test.dart`
   - The screenshot import dialog now supports faster batch speaker correction instead of only per-row edits: users can reapply `左 / 右` bubble direction to all known rows in one tap, and each contiguous same-side bubble block now exposes `這組改成她說 / 我說` actions.
   - This is meant to reduce the real-world OCR cleanup cost when a screenshot has a short run of right-side image/text bubbles that all drifted to the wrong speaker together.
   - `flutter analyze` passed after this pass. The targeted widget test was updated for the new batch actions and the current `稍後再匯入` button label, but `flutter test test/widget/widgets/screenshot_recognition_dialog_test.dart` still timed out in this desktop session and needs a clean rerun elsewhere.

73. `supabase/functions/analyze-chat/index.ts`, `supabase/functions/analyze-chat/logger.ts`, `lib/features/analysis/data/services/analysis_service.dart`, `lib/features/analysis/presentation/screens/analysis_screen.dart`
   - `analyze-chat` observability is now one layer richer: request subtype is now explicit (`analyze`, `my_message`, `optimize_message`, `recognize_only`, `analyze_with_images`), and success logs now retain safe structured metadata like timeout lane, context-compaction mode, OCR classification, side-confidence, uncertain-side count, and quoted-preview normalization counts.
   - `ai_logs.request_body/response_body` now store sanitized observability metadata for successful runs too, not just failures, while still redacting sensitive conversation/image fields.
   - Flutter now parses that richer telemetry and shows a separate `上次分析量測` card for non-OCR runs, including request size, local prep time, round-trip, retry/fallback signals, timeout lane, and context-compaction summary, so partner QA can tell whether a slowdown came from OCR, text analysis, retries, or long-context trimming.
   - Verification after this pass: `deno check supabase/functions/analyze-chat/index.ts` passed and `flutter analyze` passed.

74. `supabase/functions/analyze-chat/index.ts`, `lib/features/analysis/data/services/analysis_service.dart`, `lib/features/analysis/presentation/screens/analysis_screen.dart`
   - OCR normalization now has a second grouped-structure heuristic beyond the old single media-placeholder fix: when the sequence looks like `same-side -> media/reply bridge -> short continuation -> same-side`, the short continuation can now be pulled back onto the same speaker instead of drifting to the wrong side.
   - Quoted-preview rows are also stripped more robustly now: if the tiny `名字 + 淡字` preview row drifts to `unknown` or keeps the same inferred speaker as the outer reply, it can still be attached back to the next real message as `quotedReplyPreview` instead of polluting the message list.
   - The OCR telemetry path now exposes this additional repair as `groupedAdjustedCount`, and the Flutter OCR telemetry card surfaces it as `群組校正 N 次`.
   - Verification after this pass: `deno check supabase/functions/analyze-chat/index.ts` passed and `flutter analyze` passed.

75. `lib/features/analysis/domain/services/screenshot_recognition_helper.dart`, `lib/features/analysis/presentation/screens/analysis_screen.dart`, `lib/features/analysis/presentation/widgets/screenshot_recognition_dialog.dart`, `test/unit/services/screenshot_recognition_helper_test.dart`, `test/widget/widgets/screenshot_recognition_dialog_test.dart`
   - Screenshot recognition now uses a shared guardrail guidance model instead of scattering low-confidence / mixed-thread / unsupported copy across multiple widgets.
   - The recognized-result card and the import dialog now show the same recommendation title + body (for example `建議另存成新對話`, `建議先檢查我說 / 她說`, `建議改傳雙人聊天截圖`) and color them by severity.
   - Import-mode helper text is now state-aware too: `加入目前對話 / 另存成新對話` descriptions change based on mixed-thread risk, side-confidence risk, and current-thread mismatch instead of always showing a generic static sentence.
   - Targeted helper/widget tests were updated to lock these copy decisions, though the desktop session still treats Flutter widget-test execution as flaky and should be rerun in a cleaner environment.

76. `lib/features/analysis/data/services/analysis_telemetry_guardrail_helper.dart`, `lib/features/analysis/presentation/screens/analysis_screen.dart`, `test/unit/services/analysis_telemetry_guardrail_helper_test.dart`, `docs/ocr-analysis-maturity-benchmark.md`
   - OCR / analysis telemetry now derives explicit benchmark guardrails instead of leaving partner QA to interpret raw milliseconds manually.
   - The app now surfaces labels like `OCR 偏慢`, `分析偏慢`, `方向待確認`, `非標準截圖`, `上下文已壓縮`, `接近逾時`, and `服務不穩定` directly on the telemetry cards, each with a short explanation tied to the current request.
   - The benchmark doc now records the current in-app threshold values (single-image OCR > 7s, multi-image OCR > 15s, analysis > 12s, near-timeout > 80%, etc.) so launch-readiness conversations have a fixed reference instead of fuzzy expectations.
   - A dedicated unit test now locks the guardrail evaluation logic for OCR and normal analysis telemetry.

77. `supabase/functions/analyze-chat/server_guardrails.ts`, `supabase/functions/analyze-chat/index.ts`, `supabase/functions/analyze-chat/fallback.ts`, `supabase/functions/analyze-chat/logger.ts`, `supabase/functions/analyze-chat/server_guardrails_test.ts`
   - `analyze-chat` now computes flat server-side guardrail flags for every logged run, including `slow_request`, `near_timeout`, `unstable_upstream`, `heavy_image_payload`, `compressed_context`, `nonstandard_screenshot`, `uncertain_speaker_side`, `structure_repaired`, `high_token_usage`, and `safety_filtered`.
   - These guardrails are attached to the safe `ai_logs.response_body` observability payload as top-level scalar fields, which makes Supabase-side triage/querying much easier than relying on nested JSON or screenshot-only QA notes.
   - Upstream Claude failures now carry retry/fallback metadata through `AiServiceError`, so even failed requests can record whether they exhausted retries, timed out, or died after a fallback path.
   - The logger's safe object-key budget was also raised so these observability fields are less likely to be truncated out of `ai_logs`, and a dedicated Deno test now locks the server guardrail thresholds.
   - Verification after this pass: `deno check supabase/functions/analyze-chat/index.ts` passed. `deno test supabase/functions/analyze-chat/server_guardrails_test.ts` hit a Windows-only Deno 2.7.5 pipe panic in this desktop session instead of a normal test failure, so that test should be rerun in a cleaner environment or after a Deno upgrade.

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

20. Screenshot OCR boundary behavior:
   - test a LINE screenshot that was opened from an announcement / pinned-message jump and confirm only the visible bubbles are extracted, without turning the banner or missing history into fake messages
   - intentionally mix screenshots from two different contacts and confirm the app warns clearly and defaults toward `另存成新對話`
   - open the import dialog, choose `稍後再匯入`, and confirm the recognized result remains resumable from the analysis screen without rerunning OCR

21. Post-upgrade reply unlock:
   - reproduce the `free -> Essential` flow from an existing analysis that only shows `extend`
   - confirm paywall purchase/restore now returns success to the analysis screen and triggers the upgraded-state snackbar
   - confirm the reply section no longer claims `AI 已判斷最適合` for an old free-tier snapshot; it should show `重新分析完整回覆` until the user reruns analysis

22. LINE quoted-reply OCR:
   - test a LINE bubble that contains a smaller quoted-reply card plus a larger main reply underneath
   - confirm the smaller avatar/name/light-gray quoted block is ignored as historical context and only the outer main reply is imported as the new message
   - if OCR still emits the quoted block as a separate row, confirm backend normalization strips that preview row instead of polluting the conversation

## Notes for Claude Code

- When touching screenshot analysis again, preserve the current token-control approach:
  - `recognizeOnly` for OCR/import
  - Sonnet only when images are present
  - image retries should stay on Sonnet; do not reintroduce cross-model fallback on Vision requests
  - `my_message` is still Essential-only but currently uses the lighter text-only path
- For the latest OCR boundary / resumable-import pass, `deno check supabase/functions/analyze-chat/index.ts` passed and the touched Dart files were successfully parsed/formatted with the local Dart SDK.
- Full Dart/Flutter analyzer runs in this desktop session were not trustworthy: `flutter analyze` hung repeatedly, and direct `dart analyze` failed with a local `CreateFile failed 5 / Access is denied` process-spawn error before returning code diagnostics.
- `flutter analyze` passes after this auth/webhook pass. Targeted `flutter test` runs were attempted again for `environment_test.dart` and `supabase_service_test.dart`, and they still timed out in this desktop environment without producing useful output; earlier `settings_screen_test.dart` attempts also timed out, so those tests still need a clean rerun outside this session timeout.
- The latest paywall/analysis unlock fix also adds `usage.tierUsed` to analysis responses, so if partner feedback says "I already upgraded but still only see one reply", inspect whether the screen is showing a stale free-tier analysis snapshot versus a genuinely fresh Essential-tier rerun.
- The latest LINE reply-preview fix is intentionally two-layered: the OCR prompt is stricter about treating quoted cards as context only, and backend normalization now removes likely same-side quoted-preview rows when the model still splits them out.
- Quoted-reply handling is now explicitly symmetric too: left/right outer bubble side remains the source of truth even when the quoted card shows the other speaker's avatar/name, so the quoted preview author should not flip the current speaker.
- Readable quoted-reply previews are now preserved as structured `quotedReplyPreview` metadata from OCR into imported messages, and later analysis requests send that metadata back so the model can understand what a visible bubble is replying to without treating the quote preview as a standalone row.
- OCR telemetry is now more benchmark-friendly too: the server returns recognized classification/confidence, direction-confidence signals, uncertain-side count, quoted-preview attach/remove counts, continuity-fix count, and summary-aware context compaction stats so partner QA can tell whether a failure came from OCR structure, thread heuristics, or context trimming.
- The latest OCR normalization pass also deduplicates immediate overlap between adjacent screenshots after quoted-preview cleanup, so multi-image imports with slight capture overlap should be less likely to import the same bubble twice.
- That overlap cleanup is now observable too: both app telemetry and server-side guardrails expose `overlapRemovedCount`, which helps separate `quoted preview repair`, `speaker continuity repair`, and `multi-image overlap repair` during partner QA.
- Analysis / OCR business logic is now clearer too: the backend returns `shouldChargeQuota`, `chargedMessageCount`, `estimatedMessageCount`, and `quotaReason`, so pure OCR, test-account waivers, and real billed analyses are no longer indistinguishable in telemetry.
- The pre-analysis dialog now explains the actual charging rule in-product: full analysis is message-based, OCR recognition-only is free, and whitelist test accounts only show an estimate without consuming quota.
- Settings copy is now cleaner for release usage too: restore-purchases, logout, and account-deletion failures no longer leak raw exception text, and logout now degrades more gracefully if Supabase sign-out succeeded but RevenueCat cleanup still threw.
- The pre-analysis dialog wording was also softened from internal quota language into more user-facing Traditional Chinese (`這次大約會用掉`, `這個月還能分析`, `今天還能分析`), which should read less like a billing console during partner QA.
- Screenshot preflight is also more tolerant now: heavily cropped but still readable chat captures are no longer automatically blocked just because they are landscape-ish or below the old `540px` height gate. Truly tiny images are still rejected, but cases like the partner's `780x484` chat crop now surface a warning and continue into OCR.
- The OCR edit dialog is also less fatiguing now: the recognized-message list gets its own scrollable region, batch speaker fixes are presented as an optional shortcut for obviously mis-grouped same-side bubbles, and the helper copy explicitly tells testers they can ignore that section when every row already looks correct.
- Screenshot speaker-direction repair now covers another LINE edge case too: when two same-side quoted-reply bubbles are followed by one last short bubble that drifted onto the wrong speaker, backend normalization now snaps that trailing bubble back to the previous same-side quoted run instead of letting it silently flip into `我說`.
- OCR local-cache version was bumped after this pass as well. Without that, repeated partner tests on the exact same screenshot could keep replaying a stale pre-fix recognition result from device storage and make the new server-side speaker heuristics look ineffective.
- `docs/ocr-analysis-maturity-benchmark.md`, `docs/launch-readiness-checklist.md`, and `docs/testflight-regression-checklist.md` were rewritten into clean Traditional Chinese versions during this pass, because the older Windows-visible copies had become hard to trust due to mojibake damage.
- A dedicated benchmark doc now exists at `docs/ocr-analysis-maturity-benchmark.md`, with launch-threshold targets for OCR accuracy, latency, stability, UX maturity, and go/no-go launch criteria.
- The auth pass now includes in-app password reset completion, but it still needs a real-device regression pass for both warm-start and cold-start recovery links.
- If users report "uploaded screenshot but no AI suggestion", check two stages separately:
  - OCR/import success
  - post-import analysis trigger / reply-analysis anchor
- `lib/features/analysis/presentation/screens/analysis_screen.dart` deserves a dedicated cleanup/refactor pass before large new feature work there; the file still has mojibake-era comment damage even though runtime logic is currently stable and `flutter analyze` is clean.
- The analysis screen's telemetry cards are now debug-only. Timing / guardrail UI like `上次分析量測`, `上次 OCR 量測`, and `分析偏慢` no longer appears in TestFlight or release builds, while the telemetry payloads are still collected for internal debugging.
- Screenshot OCR speaker repair now includes a conservative run-grouping pass: if quote/media bridge rows sit between same-side outer bubbles, the backend prefers the surrounding side run instead of trusting a single drifted speaker label.
- The OCR import dialog is lighter now too: manual correction is still there as a fallback, but the full editor defaults to a collapsed `檢查／修改` section unless the recognition result is already low-confidence enough to auto-expand.
- User-facing copy around screenshot import was simplified again: upload preflight warnings, OCR confirmation wording, and analysis-preview text now use shorter Traditional Chinese phrasing and hide more internal-looking status copy unless the result actually needs attention.
- OCR tail repair now handles the specific LINE pattern `same-side quoted reply -> same-side quoted reply -> same-side plain reply` more aggressively: if the trailing plain bubble drifts to a brand-new opposite side with no earlier support for that side, the backend now pulls it back to the quoted run. The local OCR cache version was bumped too, and cache writes are now restricted to high-confidence OCR results so repeated tests against the same image are less likely to reuse a bad first-pass recognition result.
- Screenshot OCR now also has a reusable `layout-first parser v1` layer after model output. The backend rebuilds visible left/right side runs, repairs isolated drifted runs before final import, and exposes that repair count as `layoutFirstAdjustedCount` in telemetry / guardrails.
- A dedicated `supabase/functions/analyze-chat/layout_parser_test.ts` file now covers the core run-grouping cases for that parser layer: same-side quoted tails, media bridges, and unknown rows between matching speaker columns.
- OCR retry UX is stronger now too: the app keeps enough local context to let users `重新讀圖` on the same screenshot batch while explicitly bypassing the local OCR cache, so partner QA can re-check a server-side speaker fix without needing to crop a new image every time.
- The OCR confirmation dialog is lighter for stable results: when classification, content confidence, and side confidence are all high, the full manual editor stays collapsed by default and only expands when the user chooses to inspect/fix something.
- The server-side layout parser now strips likely centered system rows before it rebuilds left/right runs, which should reduce false speaker flips caused by date separators, match banners, pinned-message notices, and similar mid-column UI rows across LINE and other chat-style apps.
- OCR observability now also records `systemRowsRemovedCount` / `system_rows_removed`, which makes it easier to tell apart true speaker-run repairs from cases where the parser first had to ignore centered UI noise.
- Follow-up hotfix: `layout_parser.ts` was rewritten into a clean ASCII-safe file after the first centered-row stripping pass proved too risky. System-row removal is now conservative on purpose: only obvious standalone date/time separators or simple system banners are stripped, and only when at least two known-side chat bubbles still remain afterward.
- OCR normalization now also fails open around the layout-first parser: if that parser throws at runtime for any screenshot shape, the backend logs the parser error and continues with the pre-parser grouped rows instead of returning a full `RECOGNITION_FAILED` generic failure to the app.
- The latest LINE quoted-reply pass is more targeted too: explicit quote-card rows are now allowed to attach back to the following main bubble even if the provisional OCR side drifted toward the quoted author, and a new conservative `body-only quote preview` heuristic can attach short inset snippets back through the same-side reply chain instead of treating them as standalone chat rows.
- OCR prompts now state more explicitly that quoted-reply cards may expose only the old message body, not the author line, and that visible names / nicknames should be preserved exactly instead of being normalized into a similar-looking Han character.
- OCR name stabilization now also uses a conservative app-provided thread-name hint. The backend only applies that hint when the recognized `contactName` is a near-match (for example one similar-looking Han character off), which helps preserve names like `糖糖` / `Candy 糖糖` without blindly overwriting genuinely different-contact screenshots.
- OCR speaker repair now also has a whole-screen override lane for one-sided chat captures: if the model reports that the visible outer bubbles are all on one side and only inset quoted-reply cards refer to the other person, normalization can lock the full visible run to `only_left` or `only_right` before quote-preview cleanup. This is aimed at LINE screenshots like `4.jpg`, where every live message is from Candy on the left even though the embedded quoted cards contain Bruce's old replies.
- The iOS release workflow now tolerates a specific App Store Connect false-negative upload failure pattern too: if `fastlane beta` exits non-zero but Apple's own `altool` log already contains `UPLOAD SUCCEEDED` / `No errors uploading` plus transient network / `409 updating` noise, the GitHub Actions step now treats that run as success instead of marking the whole TestFlight upload red. The step also retries one genuinely transient ASC network failure before giving up.
- A short final submission runbook now exists at `docs/app-review-final-checklist.md`, so the team can gate App Review on one concise auth / subscription / OCR / release / legal checklist instead of rebuilding the last-mile criteria from chat each time.
- The noisy `layout_first_parser_failed` warning was removed from the OCR fallback path. The backend still fails open to the pre-parser grouped rows if the layout parser throws, but partner QA should no longer be distracted by an internal parser warning that does not change user-facing behavior.
- The new-conversation manual-input preview also got a small readability hotfix: the already-added `她說 / 我說` rows now force the warm-theme dark glass text color instead of inheriting white body text on top of the light glass container.
- `CLAUDE.md` was brought back in sync with `AGENTS.md` at the top-level entry point too: it now starts with a clean 2026-03-30 current snapshot that points new Claude sessions at the app-review, TestFlight, launch-readiness, and OCR benchmark docs instead of the older v41-era quick-start block.
- Auth diagnostics now has a first real implementation too: the app logs signup, signin, resend-verification, reset-password, and recovery-link events into a new Supabase `auth_diagnostics` table with redacted email / app version / platform metadata, and `admin-dashboard` now exposes an `Auth 診斷` page so signup-vs-recovery failures can be traced without guessing from inbox behavior alone.
