# VibeSync 頻率調校師

社交溝通技巧教練 App - 幫助用戶提升對話品質與人際互動能力。

## 功能特色

- **熱度分析** - 即時評估對話互動程度 (0-100)
- **智慧建議** - 三種回覆風格：延展、共鳴、調情
- **1.8x 黃金法則** - 維持健康的對話節奏
- **隱私優先** - 對話預設保存在本地，分析時才傳送必要內容

## 技術架構

| 層級 | 技術 |
|------|------|
| Frontend | Flutter 3.x + Riverpod |
| Backend | Supabase (Auth, PostgreSQL, Edge Functions) |
| AI | Claude API |
| Payment | RevenueCat |

## 開發環境設置

```bash
# 安裝 Flutter 依賴
flutter pub get

# 執行開發版本
flutter run

# 執行測試
flutter test
```

## 專案結構

```
lib/
├── features/       # 功能模組 (Clean Architecture)
│   ├── auth/
│   ├── conversation/
│   ├── analysis/
│   └── subscription/
├── core/           # 共用元件
└── shared/         # 共用 UI 元件
```

## 文件

- [設計規格書](docs/plans/2026-02-26-vibesync-design.md)
- [Claude Code 專案慣例](CLAUDE.md)

## 授權

Private - All Rights Reserved

## 2026-03-16 Hotfix Notes

- Reply analysis now works even when the latest message is from me. The app analyzes up to the latest incoming message instead of hard-blocking the flow.
- Screenshot import now preserves the recognized conversation in UI state and shows an `立即分析` action after successful import.
- Screenshot recognition is more tolerant of partial Claude JSON. If `messages` are present but `messageCount` is missing or malformed, the Edge Function now normalizes the payload instead of failing the whole request.
- Client-side API parsing now handles non-JSON responses more safely and surfaces recognition failures with clearer messages.
- AI logging now checks returned Supabase insert errors instead of assuming `insert()` will throw.
- Admin dashboard auth now uses server-side login/logout routes with an `HttpOnly` cookie instead of a client-readable token cookie.
- Feedback submission now validates category / payload shape, enforces length limits, and truncates Telegram previews to reduce oversharing.
- Local usage fallback now syncs tier/limits from the subscription provider instead of always pretending the user is free-tier.
- `analyze-chat` now validates request shape more strictly: message count/content, analyze mode, draft length, session context, image media types, and recognition-only misuse.
- `admin-dashboard` dependency audit is now clean (`npm audit` reports 0 vulnerabilities after lockfile-only fixes).
- RevenueCat webhook now distinguishes "updated 0 rows" from a real update, inserts missing subscription records safely, and initializes reset timestamps on first write.
- New subscription records now initialize `daily_reset_at` / `monthly_reset_at`, which avoids an unnecessary first-analysis reset write and keeps quota state more consistent.
- Booster purchase UI no longer fakes a successful purchase. It is now explicitly marked as coming soon until RevenueCat one-time purchase support is implemented.
- Screenshot OCR requests (`recognizeOnly`) now accept empty message history and no longer consume quota like a normal analysis request.
- `shared_preferences` is now declared directly in `pubspec.yaml`, and `flutter analyze` currently passes clean with the local Flutter toolchain.
- Conversation history now auto-generates heuristic summary segments for older rounds instead of storing only a placeholder summary.
- OCR-only requests strip the placeholder message before upload, `analyze-chat` now caps total image payload size, and feedback Telegram notifications are rebuilt with readable interpolated text.
- Conversation summaries now slice rounds by actual incoming-message boundaries instead of assuming a strict 2-message pattern, which makes older-context summaries more accurate when one side sends multiple messages in a row.
- Missing `subscriptions` rows now self-heal in both the app subscription loader and `analyze-chat`, so older or partially-migrated accounts are less likely to hit a hard `No subscription found` failure.
- Local verification now covers both sides of the stack: `flutter analyze` passes and the Supabase Edge Functions pass `deno check` with the locally installed Deno toolchain.
- Screenshot recognition no longer crashes when the import confirmation dialog is cancelled, and stale OCR results are ignored after the user cancels the flow.
- The screenshot picker now returns copied image lists instead of sharing the same mutable list instance with the parent screen.
- The legacy `rate_limiter.ts` helper now self-heals missing `subscriptions` / `rate_limits` rows, clamps remaining counts to non-negative values, and reuses the canonical `increment_usage` RPC for quota updates.
- Native Google Sign-In now restores the Supabase session via `getSessionFromUrl()` instead of manually shoving callback tokens into `setSession()`, which avoids bad callback parsing and missing-refresh-token edge cases.
- App routing now refreshes from the Supabase auth stream, so logout / session changes redirect cleanly instead of leaving stale protected screens mounted.
- Sign-out now also logs out RevenueCat, and login/logout invalidates the cached `subscriptionProvider`, which prevents the previous account's tier from leaking into the next session on the same device.
- Subscription bootstrap / tier sync paths now tolerate duplicate-row races and retry safely instead of failing when `subscriptions.user_id` is created concurrently.
- Restore Purchases now syncs `free` back to Supabase too, so expired or missing entitlements do not leave a stale paid tier behind locally.
- `submit-feedback` now rejects malformed JSON, non-object payloads, and malformed bearer headers before touching the database.
- `revenuecat-webhook` now validates event shape and `app_user_id`, rejects unknown product IDs instead of silently mapping them to `free`, and records `status` / `expires_at` when tier-changing events arrive.
- Verification after this pass: `flutter analyze` passes, and `deno check` passes for `submit-feedback` and `revenuecat-webhook`.
- Supabase auth now initializes with PKCE instead of the legacy implicit flow, which hardens email-link and OAuth callback handling.
- Native Google Sign-In still uses the iOS web-auth session UX, but the OAuth URL now comes from Supabase SDK PKCE generation instead of a hand-built `/authorize` link.
- Email sign-up now uses an auth redirect URI, surfaces friendlier auth errors, enforces stronger client-side password rules for new accounts, and supports resending verification emails from the login screen.
- The login screen now supports forgot-password requests and in-app password recovery completion, including the router exception needed to keep `/login` open during a recovery callback.
- Password recovery now also checks the initial startup deep link, which protects the cold-start reset flow from missing the one-time `passwordRecovery` auth event without reusing stale old callbacks.
- `app_links` is now declared directly in `pubspec.yaml` because the auth service relies on it for password-recovery callback detection.
- Home and login user-facing copy is now consistently Traditional Chinese again, and the screenshot picker's visible labels / errors were cleaned up from mojibake-era text.
- Single-image OCR now sends smaller JPEGs (960px / ~350KB target) and `recognizeOnly` requests use a lower Claude token budget, which should modestly reduce screenshot import latency.
- Screenshot import now exposes clearer progress states across the flow: image compression while picking, then `準備圖片中 / 上傳圖片中 / AI 辨識中` during OCR.
- OCR requests now capture lightweight latency telemetry in-app: original vs compressed image size, request payload size, local preparation time, round-trip time, and Claude-side AI latency estimates for TestFlight debugging.
- Manual input no longer claims the last message must be from her. Users can end on either side, and if they only have outgoing messages so far the app now treats that as a saved draft instead of a dead-end.
- Local `supabase/config.toml` auth defaults are now stricter: 8-character passwords with letters+digits, email confirmations on, secure password change on, and redirect allow-lists include the mobile callback URI.
- `docs/legal/privacy-policy.md` now matches the real product data flow more closely: local-first storage is preserved, but user-triggered analysis / screenshot recognition is explicitly documented as passing through backend processing and AI providers instead of claiming nothing is ever transmitted.
- `docs/legal/terms-of-service.md` now reflects the actually shipped offering: current monthly Free / Starter / Essential plans, platform-managed billing, and quota-based usage limits without promising annual plans, paid free trials, or booster add-ons that are not live yet.
- `docs/launch-readiness-checklist.md` now captures the current go-live gap review in one place, split into `必修 / 應修 / 可延後 / 伙伴待辦`, so TestFlight feedback and launch prep can be tracked without digging through chat history.
- Screenshot OCR now carries a lightweight preflight decision: likely social-feed / unsupported / unreadable images are rejected before import, while low-confidence chat detections stay importable but surface an explicit warning banner and confirmation step instead of silently polluting the current thread.
- Long conversations now send `older context summary + recent turns` into live analysis instead of relying only on the raw tail of the thread. The round windowing logic also now follows actual incoming-message boundaries rather than the old `2 messages = 1 round` shortcut.
- The latest completed analysis is now persisted with each conversation locally, so reopening a thread restores the previous score, strategy, replies, and recommendation instead of showing a blank analysis screen until the user reruns it.
- `docs/app-store-strategy.md` was rewritten into a clean, current review guide that no longer claims "all data stays on device only" and now matches the shipped local-first + user-triggered AI processing flow.
- `docs/website-landing-page-handoff.md` now captures the exact homepage privacy copy and footer CTA rules for the partner-managed marketing site, including the instruction to stop using a fake `href=\"#\"` App Store button before the public listing exists.
- Account deletion is now a real end-to-end flow instead of a local-only reset: settings now requires an explicit `DELETE` confirmation, calls a new `delete-account` Edge Function, removes server-side account data, and then clears the local session/device state.
- RevenueCat webhook handling now acknowledges events for already-deleted users as ignored instead of failing when a subscription event arrives after the account is gone.
- The settings screen itself was also rebuilt into a clean Traditional Chinese version, removing the remaining mojibake-era labels around account, privacy, restore purchases, logout, and account deletion.
- Screenshot import confirmation now lets users choose between `加入目前對話` and `另存成新對話`, so low-confidence or wrong-thread captures no longer have to be appended into the active thread by default.
- OCR prompting now explicitly handles LINE-style quoted replies and dense Traditional Chinese screenshots more carefully, and the `recognizeOnly` output budget was raised to improve long-text recognition accuracy.
- OCR confirmation and result cards now surface clearer `分類 / 信心` badges plus actionable guidance, so users can tell whether to import, re-screenshot, or save into a new thread instead of only seeing a generic warning.
- The screenshot picker now teaches better capture habits up front, including keeping the title bar / full message bubbles visible and capturing LINE reply previews together with the main bubble.
- Screenshot recognition decision copy is now also extracted into a pure helper with unit tests, so key OCR boundary rules like `append vs new conversation`, mismatch warnings, and low-confidence guidance are no longer only protected by manual QA.
- `docs/testflight-regression-checklist.md` now gives a concrete TestFlight smoke/regression runbook for auth, subscription, OCR import, LINE reply screenshots, dense Traditional Chinese screenshots, and telemetry capture.
- The OCR import confirmation UI is now extracted into a dedicated widget, which makes the `加入目前對話 / 另存成新對話 / 取消 / 低信心提示` path much easier to regression-test and evolve without digging through `analysis_screen.dart`.
- A new widget test file now targets that import dialog flow directly, even though `flutter test` still times out in this desktop session and needs a clean rerun elsewhere.
- Password-recovery callback parsing and auth-state transitions are now extracted into a dedicated helper, so hash-fragment recovery links and `passwordRecovery -> signedIn/signedOut` state changes no longer depend on ad-hoc inline logic inside `SupabaseService`.
- Subscription tier/product-id mapping and tier limits are now centralized in a shared helper used by RevenueCat, usage fallback, and subscription state updates, which reduces the chance of `starter/essential/free` drift across login, purchase, restore, and sync flows.
- The paywall screen is now rebuilt into a clean launch-facing version with real privacy / terms links, safer purchase / restore messaging, and no raw RevenueCat success dump shown to testers after checkout.
- `docs/testflight-regression-checklist.md` is now a readable master TestFlight runbook that covers auth recovery, subscription, OCR import modes, analysis persistence, account deletion, and OCR telemetry sign-off in one place.
- `analyze-chat` now rejects oversized request bodies earlier, which reduces the chance of paying the JSON/base64 parse cost for obviously too-large payloads.
- Edge-function logging around `analyze-chat` is now safer and quieter: subscription/request logs no longer print raw user email or AI response snippets, and failed `ai_logs` payloads are sanitized before storage.
- Claude fallback requests now always clear timeout timers in a `finally` block, and parse-failure logs record only metadata instead of dumping raw AI output.
- Screenshot / OCR requests now stay on Sonnet end-to-end and no longer silently downgrade to Haiku during fallback retries, which keeps the Vision path aligned with the original design and avoids lower-quality image recognition on retry.
- Request timeouts are now tuned by request type: OCR-only images fail faster than full image analysis, and text-only `my_message` requests use a shorter timeout than full normal analysis.
- The screenshot-analysis prompt path is now rebuilt around shared prompt helpers instead of a second inline OCR prompt block, which removes duplicated instructions and avoids the old drift between `recognizeOnly` and full image-analysis behavior.
- The image-analysis path and `optimizedMessage` draft path now both use shared prompt-section builders, so OCR context injection and user-draft interpolation are easier to reason about and less likely to regress into broken prompt formatting later.
- Analysis-screen and analysis-service debug logs are now gated behind `kDebugMode`, so screenshot recognition metadata, conversation IDs, and detailed OCR failure traces no longer spill into device logs during TestFlight / release usage.
- The stale paywall TODO on `analysis_screen.dart` is also removed; the method now directly routes to `/paywall` without pretending there is still a missing implementation.
- URL launching is now centralized in a shared helper that prefers `LaunchMode.inAppBrowserView` for normal website/legal pages while keeping Telegram-style external destinations on `externalApplication`.
- Login, settings, and paywall now all use that helper and show a consistent failure snackbar, so privacy/terms links feel more native instead of always bouncing users out to Safari.
- Screenshot OCR now treats in-thread missed-call / call-record entries more carefully: chat screenshots dominated by `未接來電` or similar call events are no longer supposed to be rejected as a standalone call-log screen by default.
- If the model still hesitates on an all-call-record chat screenshot, the server now downgrades it to a confirmable import with Chinese guidance instead of hard-rejecting it with an English `call log / system notification` warning.
- Analysis/OCR error handling is now centralized into a real user-facing error taxonomy, so the app shows human Traditional Chinese guidance for timeout, oversized payload, unsupported screenshots, auth expiry, and no-incoming-message cases instead of leaking raw backend/debug strings.
- Screenshot import now supports editable OCR preview: before confirming import, users can fix text, flip `我 / 她`, or delete misrecognized messages so minor OCR mistakes do not force a full re-screenshot.
- Screenshot preflight classification is now more specific: group chats, album/gallery screens, phone call-log pages, generic system UI, social feeds, and sensitive-content screenshots each map to clearer reject reasons instead of being lumped into one generic `unsupported` state.
- `docs/website-landing-page-handoff.md` is now synced to the current partner status: live `/privacy` and `/terms` are done, while the footer App Store CTA is intentionally deferred until the final pre-launch pass.

See `CLAUDE_CODE_HANDOFF_2026-03-16.md` for the full review summary, outstanding risks, and Claude Code notes.
