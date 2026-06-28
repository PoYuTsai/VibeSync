# VibeSync Bug Log

> 歷史 bug 記錄與修復說明。新 bug 遇到時在這裡新增，**不寫進 CLAUDE.md**。
>
> 格式：`#### [YYYY-MM-DD] 標題` → 症狀 / Root Cause / 修復 / 預防 / 相關檔案
>
> 目前 Common Pitfalls（仍會踩）請看 `CLAUDE.md`，那裡只保留**現役陷阱**。

---

## 2026-06

### [2026-06-28] 新手 Hint 失敗只顯示通用錯誤

**Symptom**: TestFlight AI 實戰練習室新手模式按 Hint 後，畫面只顯示「提示暫時產生失敗，等一下再試」，沒有出現提示內容，也無法判斷是等待 AI 回覆、後端尚未部署，或真的生成失敗。

**Root Cause**: Flutter `requestHint` 只特別處理 `practice_hint_in_flight`，其餘 backend gate / validation code 都折成通用錯誤；API service 對 5xx 也丟掉 response body 的 `error` code。Edge handler 遇到 hint RPC/migration 尚未存在時，會回一般 500 `session_state_failed`，真機無法分辨部署未完成。

**Fix**: 保留 5xx response 的 hint error code；controller 將 `invalid_hint_*` / `practice_session_not_started` / `practice_hint_beginner_only` / `practice_hint_not_ready` 轉成明確文案；Edge handler 對缺少 hint RPC 的 schema-cache 錯誤回 `503 practice_hint_not_ready`。

**Validation**:

- `flutter test test/unit/features/practice_chat/data/services/practice_chat_api_service_test.dart test/unit/features/practice_chat/data/providers/practice_chat_controller_test.dart`
- `flutter analyze lib/features/practice_chat/data/services/practice_chat_api_service.dart lib/features/practice_chat/data/providers/practice_chat_providers.dart test/unit/features/practice_chat/data/services/practice_chat_api_service_test.dart test/unit/features/practice_chat/data/providers/practice_chat_controller_test.dart`
- `deno test --allow-read --allow-env --allow-net=127.0.0.1 supabase/functions/practice-chat`
- `deno check supabase/functions/practice-chat/handler.ts`

### [2026-06-24] AI 實戰練習室本地紀錄缺少續聊、刪除與扣費提示

**Symptom**: 使用者進 AI 實戰練習室後，看不到首次扣費時機；未完成練習離開再回來會開新場；最近練習只能看回顧，不能刪除。

**Root Cause**: Practice chat local repository 只有 save/recent/get，沒有 delete；畫面每次進場都建立新 controller，未從 local-only Hive session seed 狀態；歷史 sheet 原本是 read-only review list，且扣費語意只顯示剩餘回覆數。

**Fix**: controller 支援從未拆解 session 恢復，provider 進場自動載入最近未拆解場次；最近練習列可續聊/待拆解/已拆解並支援本機刪除；空狀態與底部列明確寫「首次 AI 回覆成功才扣 1 則，進來或送出失敗不扣，教練拆解不另扣」。

**Validation**:

- `flutter test test/unit/features/practice_chat test/widget/features/practice_chat/practice_chat_screen_style_test.dart`
- `flutter analyze`

### [2026-06-15] 升級後「重新分析完整回覆」仍被 pending 我說擋住

**Symptom**: Free 分析後升級到 paid，點「重新分析完整回覆」仍顯示「已記錄你剛剛說的內容，先不預測她可能怎麼回」，看起來像夥伴升級後還不能用完整回覆。

**Root Cause**: paid reply refresh 直接重用 `_runAnalysis()` 的完整對話路徑；若分析後使用者又補了一則「我說」，pending-outgoing guard 會在 entitlement/streaming 前早退。refresh 本意是重跑「上一輪已分析 slice」取得 paid replies，不應把後續 pending 我說納入。

**Fix**: `_refreshPremiumReplies()` 以 `lastAnalyzedMessageCount` 截出上一輪 slice，允許此路徑略過 pending guard；streaming state 額外攜帶 `analyzedMessageCount`，讓完成/重掛載持久化仍把 pending 訊息留在未分析狀態。

**Validation**:

- `flutter test test/widget/features/analysis/analysis_screen_hydration_test.dart`
- `dart analyze lib/features/analysis/presentation/screens/analysis_screen.dart lib/features/analysis/data/notifiers/streaming_analyze_notifier.dart test/widget/features/analysis/analysis_screen_hydration_test.dart`

### [2026-06-13] replySegments cap 3→5 改了 prompt＋server 卻漏改 Flutter client
**Symptom**: 對方連發多球時 app 最多只顯示 3 段分段回覆；模型照新標準出 4-5 段被靜默剪掉。

**Root Cause**: `c3f3ac6`（方案二件1 D1）把球判準 cap 放寬 3→5，同步了 prompt 與 server `sanitizeReplySegments`，但 client `_parseReplySegments` 的 `.take(3)` 漏改——同一條契約常數活在三處（prompt 文字、server sanitize、client parse），沒有單點。

**Fix**: `991f202` client `.take(3)`→`.take(5)`＋鎖 5 段的單元測試。

**預防**: 改任何 AI 輸出契約的數量/形狀上限時，grep 三處：`index.ts` prompt 字樣、`post_process.ts` sanitize、`analysis_models.dart` parse。測試端 `index_test.ts` 已有 prompt cap 錨，client 端現在也有 5 段錨。

**相關檔案**: `lib/features/analysis/domain/entities/analysis_models.dart`、`supabase/functions/analyze-chat/post_process.ts`

### [2026-06-09] Coach 0 quota showed generic failure and clarification had no hard cap
**Symptom**:

- Free user with `今日剩餘 0/15` asked Coach 1:1 and saw `這題教練沒接住`, even though the real condition was quota exhaustion.
- Coach card copy said clarification would not deduct quota, but there was no explicit cap, creating confusion about whether users could clarify indefinitely.

**Root Cause**:

- Flutter mapped `CoachChatQuotaExceededException` to the generic Coach failure notice instead of quota/paywall copy.
- `coach-chat` prompt/client flow relied on model behavior for no-charge clarification, without a shared policy constant across client and Edge.
- Edge quota preflight always assumed cost `1`, so it could block a bounded no-charge clarification before the model had a chance to return `clarifyingQuestion`.

**Fix**:

- Added Coach-specific quota error title/message/action so daily/monthly exhaustion opens the upgrade path instead of showing generic failure.
- Added a shared 3-turn no-charge clarification cap in Flutter and Edge policy; the 4th clarification attempt is sent/forced as a formal answer.
- `coach-chat` prompt and fallback copy now state `免費釐清最多 3 次`; formal `coachAnswer` still deducts one quota and remains gated by the user's actual tier.
- Edge preflight allows only bounded no-charge clarification attempts; formal answer deduction still re-checks quota and returns 429 if exhausted.

**Validation**:

- `flutter test --no-pub test/unit/features/coach_chat/data/services/coach_chat_api_service_test.dart test/unit/features/coach_chat/data/providers/coach_chat_providers_test.dart test/unit/features/coach_chat/presentation/coach_chat_card_error_copy_test.dart`
- `flutter analyze --no-pub lib/features/coach_chat/data/services/coach_chat_api_service.dart lib/features/coach_chat/data/providers/coach_chat_providers.dart lib/features/coach_chat/presentation/widgets/coach_chat_card.dart test/unit/features/coach_chat/data/services/coach_chat_api_service_test.dart test/unit/features/coach_chat/data/providers/coach_chat_providers_test.dart test/unit/features/coach_chat/presentation/coach_chat_card_error_copy_test.dart`
- `deno test --allow-read --allow-env supabase/functions/coach-chat/clarification_policy_test.ts supabase/functions/coach-chat/generation_test.ts supabase/functions/coach-chat/index_test.ts supabase/functions/coach-chat/prompts_test.ts supabase/functions/coach-chat/quality_smoke_test.ts`
- `deno check supabase/functions/coach-chat/index.ts supabase/functions/coach-chat/generation.ts supabase/functions/coach-chat/prompts.ts supabase/functions/coach-chat/clarification_policy.ts`

**Review note**: 3-turn cap is enforced for normal authenticated app flow from client session turns plus Edge validation. It is not yet a durable server-side anti-abuse counter across forged requests/new sessions; CC should review whether that is required before launch.

### [2026-06-09] Free quota / opener / screenshot P1 hardening after CC review
**Symptom**:

- Streaming quota exhaustion could show raw English `Daily limit exceeded` / `Monthly limit exceeded`.
- Free opener API responses still contained paid opener styles if called directly; client UI filtered them, but the server contract did not.
- Opener quota exhaustion opened the paywall without awaiting return, tier refresh, or clearing the Free error state.
- Client and Edge allowed 900KB per screenshot, but the Edge total image cap and raw request body guard could still reject three maximum-size screenshots.

**Root Cause**:

- Quota exception source messages were English, and streaming failure state displayed the exception message directly.
- Opener entitlement was enforced at Flutter cache/UI boundaries, not at the Edge response boundary before quota deduction.
- Opener paywall navigation used fire-and-forget `context.push('/paywall')`.
- Image validation mixed decoded-byte limits with the raw base64 request-body guard.

**Fix**:

- Localized daily/monthly quota exception messages at the source and added a streaming failure regression test.
- Filtered opener payloads by server-side `allowedFeatures` before quota deduction; no allowed style returns a no-charge retryable error.
- Added opener paywall return sync/refresh behavior and clears quota errors only after premium unlock.
- Raised opener total image cap to `MAX_IMAGE_BYTES * 3` and request body guard to 4MB so three 900KB screenshots reach validation.

**Validation**:

- `flutter test --no-pub test/unit/features/analysis/data/services/analysis_service_analyze_modes_test.dart test/unit/features/analysis/data/notifiers/streaming_analyze_notifier_test.dart test/unit/features/opener/presentation/opening_rescue_handoff_location_test.dart test/unit/features/opener/data/services/opener_service_test.dart`
- `flutter analyze --no-pub lib/features/analysis/data/services/analysis_service.dart lib/features/opener/presentation/screens/opening_rescue_screen.dart test/unit/features/analysis/data/services/analysis_service_analyze_modes_test.dart test/unit/features/analysis/data/notifiers/streaming_analyze_notifier_test.dart test/unit/features/opener/presentation/opening_rescue_handoff_location_test.dart`
- `deno test --allow-read supabase/functions/analyze-chat/index_test.ts`
- `deno check supabase/functions/analyze-chat/index.ts supabase/functions/analyze-chat/opener_image_validation.ts`

### [2026-06-09] Opener result allowed accidental second generation
**Symptom**:

- After opener generation completed, the screen still showed active generate / regenerate entry points.
- A user could tap again on the same generated result and potentially spend quota on another request.
- The copy confirmation snackbar used a dark bottom bar that obscured the lower opener guidance card.

**Root Cause**:

- The opener screen disabled generation only while `_isGenerating` was true.
- `_result != null` was not treated as a generated-result lock state, and the result section kept a direct `_generate()` regenerate button.
- Copy feedback used the default bottom snackbar style with a dark background.

**Fix**:

- Added opener UI guardrails so an existing result disables generation and `_generate()` returns before quota checks if a result already exists.
- Replaced the no-confirm regenerate button with copy explaining that changing the input clears the result before a new generation.
- Changed copy feedback to a light floating snackbar that tells the user to paste the opener and come back after she replies.

**Validation**:

- `flutter test --no-pub test/unit/features/opener/data/services/opener_service_test.dart test/unit/features/opener/data/services/opener_result_cache_service_test.dart test/unit/features/opener/presentation/opening_rescue_handoff_location_test.dart`
- `flutter analyze --no-pub`
- `git diff --check`

### [2026-06-09] Free opener handoff could carry locked opener copy
**Symptom**:

- Free user saw only one unlocked opener in the opener UI, but continuing into `開始分析對話` could seed a locked paid opener style from the cached five-style result.

**Root Cause**:

- Opener generation stores the full `OpenerResult` locally for paid upsell/display.
- The handoff/cache boundary did not reduce that result to the user's entitlement before saving latest / marking a partner draft continued.
- If downstream seed logic read a full cached result under an uncertain or stale subscription state, locked opener copy could be used as the first outgoing message.

**Fix**:

- Added `OpenerResult.visibleForAccess()` so Free-visible results contain only `extend` and drop locked recommendation reasons.
- Handoff save and partner-draft continued paths now persist the entitlement-visible result.
- New conversation seeding treats non-premium state as Free and reads from the visible result.

**Validation**:

- `flutter test --no-pub test/unit/features/opener/data/services/opener_service_test.dart test/unit/features/opener/data/services/opener_result_cache_service_test.dart test/unit/features/opener/presentation/opening_rescue_handoff_location_test.dart test/widget/screens/new_conversation_screen_test.dart test/widget/features/conversation/new_conversation_sheet_screenshot_test.dart`
- `flutter analyze --no-pub`

### [2026-06-06] Essential user still gets Free quota / one reply style
**Symptom**:

- Partner's TestFlight app showed Essential in the paywall and RevenueCat diagnostics, but analysis still returned one reply style.
- Video showed `Daily limit exceeded` while the paywall showed Essential with `105/120` daily remaining. The used count was 15, exactly the Free daily cap, so `analyze-chat` was still gating from the server-side Free subscription row.

**Root Cause**:

- Production Supabase secrets did not include `REVENUECAT_IOS_API_KEY`.
- Without that server RevenueCat key, `sync-subscription` cannot confirm and persist a paid tier, and `analyze-chat` cannot refresh a stale Free row when the client sends paid hints.
- The client could therefore display RevenueCat SDK paid state while Edge Functions still enforced Free quota.

**Fix**:

- Add the missing `REVENUECAT_IOS_API_KEY` Supabase secret before relying on paid entitlement rescue.
- Hardened client startup / restore paths so a Free user is not locally promoted to paid unless server sync confirms the paid tier.
- Added `analyze-chat` quota logs for expected tier, effective tier, and RevenueCat hint presence.
- Added a Supabase secret preflight to Edge deploy and App Store/TestFlight release workflows so missing production secrets fail before dogfood.

**Validation**:

- `flutter test --no-pub test/unit/features/subscription/data/subscription_state_package_test.dart`
- `flutter test --no-pub test/unit/features/analysis/data/services/analysis_service_two_stage_test.dart`
- `deno check supabase/functions/analyze-chat/index.ts`
- `flutter analyze --no-pub`
- `powershell -ExecutionPolicy Bypass -File tools/preflight/check-supabase-secrets.ps1 -ProjectRef fcmwrmwdoqiqdnbisdpg`

### [2026-06-06] TestFlight update/logout-login still shows Free
**Symptom**:

- Eric tested `main@ad83963`; TestFlight still showed Free.
- Logging out of Supabase and logging back into the same account still showed Free, so the previous local paid snapshot guard did not cover the RevenueCat identity boundary.

**Root Cause**:

- The app configured RevenueCat without a Supabase user id at startup, creating an anonymous App User ID before `logIn(user.id)`.
- Supabase sign-out also called native `Purchases.logOut()`, which generates a new anonymous RevenueCat App User ID. If a purchase or alias is attached to an anonymous id, later login can see Free under the custom Supabase id.
- This matches RevenueCat's documented identity behavior: avoiding anonymous ids requires configuring with a custom App User ID and not calling SDK logout for custom-ID-only flows.

**Fix**:

- RevenueCat initialization now accepts and uses the current Supabase user id when a session exists at cold start.
- Supabase sign-out no longer triggers native RevenueCat `logOut()`; account switching is handled by the next `RevenueCat.logIn(newUserId)`.
- Existing startup `syncPurchases()` paid rescue and paid snapshot guard remain in place.

**Validation**:

- `flutter test --no-pub test/unit/services/revenuecat_service_identity_test.dart`
- `flutter test --no-pub test/unit/features/subscription/data/subscription_state_package_test.dart`
- `flutter test --no-pub test/unit/services/usage_service_subscription_snapshot_test.dart`
- `flutter analyze --no-pub`

### [2026-06-06] Subscription still Free after RevenueCat identity guard
**Symptom**:

- Eric tested after `main@b164802`; the app still displayed Free.
- At this point the issue is no longer diagnosable from UI tier alone; we need to know whether RevenueCat CustomerInfo, Supabase subscription state, or local UI/cache is the layer returning Free.
- After build `238` / `6c07c49`, diagnostics showed the first Free state was a TestFlight sandbox expiration: RevenueCat identity matched the Supabase user and was not anonymous, but active subscriptions / entitlements were empty and the latest expiration was already in the past.
- After repurchase, RevenueCat and the app both returned Essential, but the app subscription metadata still showed the old `renewsAt` timestamp while RevenueCat had a new active expiration.

**Investigation Step**:

- Added a TestFlight-visible subscription diagnostic copy action in Settings.
- Diagnostic includes app version / Git SHA, Supabase user id, UI subscription state, local usage snapshot, RevenueCat appUserID, anonymous flag, active subscriptions, active entitlements, inferred RC tier, and expiration metadata.
- CI build commands now pass `GIT_SHA` via `--dart-define`, so dogfood can verify the installed build commit.
- Updated `sync-subscription` to persist and return the latest active RevenueCat expiration date when RevenueCat confirms a paid tier, instead of leaving `subscriptions.expires_at` stale.

**Validation**:

- `deno test --allow-env --allow-net supabase/functions/sync-subscription/revenuecat_expiration_test.ts supabase/functions/sync-subscription/usage_reset_test.ts supabase/functions/sync-subscription/revenuecat_identity_test.ts`
- `flutter test --no-pub test/unit/services/revenuecat_service_identity_test.dart`
- `flutter test --no-pub test/unit/features/subscription/data/subscription_state_package_test.dart`
- `flutter test --no-pub test/unit/services/usage_service_subscription_snapshot_test.dart`
- `flutter analyze --no-pub`

### [2026-06-06] TestFlight 更新後付費用戶退回 Free 並少 5 種回覆

**症狀**:

- Eric / 夥伴多次在 TestFlight 點「更新」後打開 App，已購買 Starter / Essential 仍顯示 Free。
- App 被判定 Free 後，`analyze-chat` 串流只拿到 Free allowed reply style，造成 5 種回覆/詳細報告看起來缺失。

**Root Cause**:

- 本機 usage cache 只有單一 `subscription_tier` key；任何一次 DB/RevenueCat transient Free sync 都可能覆寫掉 paid cache，下一次啟動沒有可信 paid snapshot 可恢復。
- Analyze Chat client 沒像 opener 一樣帶 `expectedTier` / RevenueCat app user id，後端在 DB 暫時 Free 時只能按 Free tier 產生回覆。

**修正**:

- 新增 per-user `last_known_paid_*` snapshot；同帳號且未過期時，transient Free cache write 不能洗掉 Starter / Essential。換帳號與 authoritative expired Free 會清掉 guard。
- 分析請求 quick/full/stream 與 legacy analyze path 都會在本機知道 paid 時送 `expectedTier`，並盡量附 RevenueCat app user id，讓後端可校正 stale DB Free。
- 補啟動 paid rescue：若舊版已把本機洗成 Free，新版啟動仍為 Free 時會背景同步 App Store receipt / RevenueCat cache；只有 RevenueCat 確認 paid 才升回 Starter / Essential。

**驗證**:

- `flutter test --no-pub test/unit/services/usage_service_subscription_snapshot_test.dart`
- `flutter test --no-pub test/unit/features/subscription/data/subscription_state_package_test.dart`
- `flutter test --no-pub test/unit/features/analysis/data/services/analysis_service_two_stage_test.dart`
- `flutter analyze --no-pub`

### [2026-06-05] TestFlight 上傳階段缺 Ruby gem 依賴

**症狀**:

- `Release to App Stores #229` 的 `release-ios` job 失敗，`release-android` 未執行。
- iOS tests、簽名、archive、IPA build 都成功；失敗發生在最後 `Upload to TestFlight`。

**Root Cause**:

- Workflow 直接用 `gem install fastlane` 安裝 fastlane。
- GitHub macOS runner 上的 fastlane / google APIs 依賴鏈啟動時需要 `multi_json >= 1.14.1`，但該 gem 沒有被安裝，導致 fastlane 尚未開始上傳就因 `Gem::MissingSpecError` 中止。

**修復**:

- 在 iOS / Android release job 的 `Install Fastlane` 步驟先明確安裝 `multi_json >= 1.14.1`，再安裝 fastlane。
- 同步補 Android release job，避免之後 Android 內測上傳遇到同一個 Ruby gem 缺依賴。

**驗證**:

- GitHub Actions run `27002131036` job log confirmed failure at `Upload to TestFlight`: `Could not find 'multi_json' (>= 1.14.1)`.
- `git diff --check`

### [2026-06-05] TestFlight 更新後付費方案暫時掉回 Free

**症狀**:

- Eric / Bruce 在 TestFlight 更新新版後，打開 App 常看到 Starter / Essential 退回 Free。
- 這會讓付費功能與額度判斷看起來失效；正式上架後若發生，屬於 P0 付費權益事故。

**Root Cause**:

- `SubscriptionNotifier` 啟動初始 state 固定是 `SubscriptionState(isLoading: true)`，但該 state 的預設 tier 是 `free`，所以 App 更新或 provider 重建時會先用 Free 顯示。
- `_loadSubscription()` 從 DB / RevenueCat 載入期間，如果 DB row 是 Free、RevenueCat 暫時回 Free/空 entitlement，會覆蓋本地上次已同步的 paid snapshot。
- `_loadSubscription()` catch path 也會建立新的預設 `SubscriptionState`，讓暫時性載入錯誤直接呈現 Free。

**修正**:

- provider 建立時從 `UsageService` 本地 subscription snapshot hydrate 初始 state；上次是 Essential / Starter 就先以 paid + loading 顯示，不再先閃 Free。
- 啟動 tier resolution 改成：DB / RevenueCat 有任一 paid 就用 paid；兩邊暫時都 Free 時，保留本地 paid snapshot，除非 server `expires_at` 已明確過期。
- `_loadSubscription()` 失敗時保留現有 state 的 tier / quota，只更新 loading/error，不再建立預設 Free state。

**驗證**:

- `flutter test test/unit/features/subscription/data/subscription_state_package_test.dart test/unit/services/subscription_tier_helper_test.dart`
- `flutter analyze lib/features/subscription/data/providers/subscription_providers.dart test/unit/features/subscription/data/subscription_state_package_test.dart`
- `flutter test --no-pub test/widget/screens/paywall_screen_test.dart test/widget/screens/settings_screen_test.dart`
- `deno test supabase/functions/sync-subscription/usage_reset_test.ts supabase/functions/sync-subscription/revenuecat_identity_test.ts`
- `git diff --check`

### [2026-06-05] 草稿潤飾跑不出結果

**症狀**:

- Dogfood 草稿潤飾送出後沒有產出可用的「優化後草稿」。
- 前端會收到成功以外的錯誤，或結果內沒有 `optimizedMessage.optimized`，導致使用者只看到失敗提示。

**Root Cause**:

- `optimize_message` 雖然是輕量草稿修句功能，但 Edge legacy path 仍使用完整 `SYSTEM_PROMPT`，模型同時被要求完整分析報告與 `optimizedMessage`。
- Text-only legacy token budget 對草稿潤飾仍落在一般分析分支，輸出負擔過高時容易解析失敗、截斷，或沒有穩定回 `optimizedMessage`。
- post-process 也沒有把 `optimize_message` 視為輕量模式，可能在只有 optimized payload 時補不必要的分析欄位。

**修復**:

- 新增 `OPTIMIZE_MESSAGE_PROMPT`，只要求回傳 `optimizedMessage` 窄 JSON。
- 新增 `OPTIMIZE_MESSAGE_MAX_TOKENS = 700`，初次與 parse-retry 都使用草稿潤飾專用 output budget。
- legacy post-process 將 `optimize_message` 視同 `my_message` 輕量模式，不補完整分析欄位。

**驗證**:

- `deno test --allow-read supabase/functions/analyze-chat/index_test.ts supabase/functions/analyze-chat/post_process_test.ts supabase/functions/analyze-chat/server_guardrails_test.ts`
- `flutter test --no-pub test/unit/entities/analysis_models_test.dart test/unit/services/analysis_service_test.dart test/unit/features/analysis/data/services/analysis_service_two_stage_test.dart`
- `deno fmt --check supabase/functions/analyze-chat/index.ts supabase/functions/analyze-chat/index_test.ts`

### [2026-06-05] Edge Function deploy 解析 Supabase CLI latest 被 rate limit

**症狀**:

- 手動觸發 `Deploy Edge Function` 在 `Setup Supabase CLI` 步驟失敗，後續 `Link Supabase Project` / `Deploy Edge Functions` 全部 skipped。
- Job log 顯示 `Failed to resolve latest Supabase CLI release: rate limit exceeded`。

**Root Cause**:

- Workflow 使用 `supabase/setup-cli@v1` + `version: latest`，每次 deploy 都要查 GitHub release 最新版本；GitHub Actions runner 偶發撞到 unauthenticated release API rate limit。
- `setup-cli@v1` 也出現 Node.js 20 deprecation warning。

**修復**:

- 改用 `supabase/setup-cli@v2`。
- 將 Supabase CLI pin 到 `2.105.0`，避免每次 deploy 解析 `latest`。

**驗證**:

- GitHub Actions run `26969144383` job log confirmed failure stopped at Setup Supabase CLI before deploy.
- `git diff --check`

### [2026-06-05] 完整分析串流失敗缺少 retry metadata

**症狀**:

- Dogfood 夥伴偶發看到「串流分析缺少完整結果，請重新分析。」或「無法再重試」，但另一支手機同時間可成功完成分析。
- 失敗畫面會保留部分串流段落，代表主流程已產生內容，但收尾或重試路徑未穩定完成。

**Root Cause**:

- 本地最新 stream reframer/handler 已會合成 `finalResult` 或將缺結果轉成 retryable error；截圖較像 live Edge 仍在舊版或部署未完成。
- stream branch 的 `markFailed` 只寫入 ledger，沒有把 `MAX_STREAM_RETRIES - retry_count` 回填到即將送出的 `analysis.error.retriesRemaining`，前端只能用 fallback 猜剩餘次數，容易讓重試狀態和 server ledger 不一致。

**修復**:

- stream 失敗寫入 `analysis_stream_runs` 後，使用回傳 row 的 `retry_count` 計算 `retriesRemaining` 並附回 `analysis.error`。
- 新增 stream branch 測試，鎖住失敗事件必須由 ledger 回報剩餘 retry slot。

**驗證**:

- `deno test --allow-read supabase/functions/analyze-chat/reframer_test.ts supabase/functions/analyze-chat/stream_handler_test.ts supabase/functions/analyze-chat/stream_branch_test.ts`
- `flutter test --no-pub test/unit/features/analysis/data/services/analysis_service_two_stage_test.dart test/unit/features/analysis/data/notifiers/two_stage_analyze_notifier_test.dart`
- `deno fmt --check supabase/functions/analyze-chat/index.ts supabase/functions/analyze-chat/stream_branch_test.ts`
- `git diff --check`

### [2026-06-05] 完整分析串流仍漏 allowed reply styles

**症狀**:

- 部署 guardrail 後，dogfood 仍偶發看到 `Streaming analysis ended before every allowed reply style was generated.`。
- 這代表 server 已成功擋下 incomplete result，但模型仍有機率在五種回覆未全部生成前結束。

**Root Cause**:

- Stream prompt 同時要求五種 `analysis.reply_option`、深入段落、以及 `analysis.done.finalResult.replies/replyOptions` 再次包含所有 style，造成五種回覆被重複輸出，token 與遵循負擔偏高。
- `STREAM_ANALYZE_MAX_TOKENS = 2200` 對 paid 五種 style + legacy-compatible result 邊界太緊，模型偶發省略 style 或提前 done。

**修復**:

- Prompt 改成五種回覆必須先透過 `analysis.reply_option` 事件完成；`finalResult` 保持 compact，不再重複完整五種 `replyOptions`。
- 明確要求 optional report sections 可以縮短，但不能省略 required `analysis.reply_option`。
- Stream output budget 從 `2200` 提到 `3200`，只影響 stream path。

**驗證**:

- `deno test --allow-read supabase/functions/analyze-chat/stream_prompt_test.ts supabase/functions/analyze-chat/reframer_test.ts supabase/functions/analyze-chat/stream_handler_test.ts supabase/functions/analyze-chat/stream_branch_test.ts`

### [2026-06-04] 完整分析等待狀態遮擋與工程文案外露

**症狀**:

- 完整分析串流等待中，底部「建立這段對話 / 補訊息」輸入區仍固定顯示，遮住分析進度與下方內容。
- 等待中的「心理訊號」段落偶發顯示 raw JSON，例如 `{"subtext":...,"qualificationSignal":false}`。
- 推薦回覆的引用標籤顯示英文 schema key `recommended`，看起來像工程文案。

**Root Cause**:

- `AnalysisScreen` 在 `_isAnalyzing` 時仍回傳完整手動訊息 composer。
- `AnalysisStreamContent._stringify` 對不含 `title/message/body/summary/suggestion` 的 map 直接 `jsonEncode`，且沒有處理字串形式的 JSON。
- `ReplySegment.displayLabel` 直接使用模型 label，未本地化穩定 schema key。

**修復**:

- 完整分析跑動期間收起底部 composer，分析完成後再恢復原本入口。
- stream report section 將常見 structured payload 轉成短中文行，並解析 stringified JSON，避免 raw JSON 外露。
- `recommended/quote/quoted/source` 顯示為「引用對方」，`selected` 顯示為「推薦接法」。

**驗證**:

- `flutter test --no-pub test/unit/features/analysis/data/services/analysis_service_two_stage_test.dart`
- `flutter test --no-pub test/unit/entities/analysis_models_test.dart`
- `flutter test --no-pub test/widget/features/analysis/analysis_screen_hydration_test.dart`
- `flutter analyze --no-pub lib/features/analysis/data/services/analysis_service.dart lib/features/analysis/domain/entities/analysis_models.dart lib/features/analysis/presentation/screens/analysis_screen.dart test/unit/features/analysis/data/services/analysis_service_two_stage_test.dart test/unit/entities/analysis_models_test.dart test/widget/features/analysis/analysis_screen_hydration_test.dart`
- analysis 相關 135 個 unit/widget tests

### [2026-06-04] 完整分析串流少四種回覆

**症狀**:

- 最新 build dogfood 多次測試完整分析串流時，paid 應有五種回覆，但結果常只剩單一推薦回覆，少了其餘四種 style。

**Root Cause**:

- 串流 reframer 只要求有扣費錨點與 completion anchor，沒有在 `analysis.done` 前驗證目前 tier 允許的 reply styles 是否都到齊。
- Shared post-process 只保證回覆非空並做 entitlement filter，不保證 paid tier 的五種回覆完整，因此 partial stream 會被存成成功結果。
- Stream path 仍沿用 legacy full 的 `1536` output token 上限，但串流要額外輸出 decision / recommendation / reply_option / finalResult，讓模型更容易省略 fan-out。
- Client parser 只用 `finalResult.replies` 產生回覆卡片；當 stream final result 的 `replyOptions` 已有五種、但 `replies` 只保留 selected style 時，Flutter UI 仍只顯示單一卡片。

**修正**:

- `stream_prompt` 依 active tier 限定 allowed reply styles，明確要求每個 allowed style 都要有 `analysis.reply_option`，且 `finalResult.replies/replyOptions` 必須齊全。
- `reframer` 在 done 前檢查 required styles；paid 缺四種會回 `STREAM_INCOMPLETE_REPLY_OPTIONS` 並保留 retry path，不再把 partial result 當成功。
- `reframer` 過濾 tier 外的 `analysis.reply_option`，並拒絕 tier 外 selected style，避免 Free 串流中途外洩付費 style。
- Stream Claude output budget 改用 `STREAM_ANALYZE_MAX_TOKENS = 2200`，只影響 stream path，不動 quota/扣費順序。
- `AnalysisResult.fromJson` 保留既有 `replies`，只在缺 style 時從 `replyOptions.copyText` 補回，並讓推薦 fallback 使用補齊後的回覆 map。

**驗證**:

- `deno test --allow-read supabase/functions/analyze-chat`
- `flutter test --no-pub test/unit/services/analysis_service_test.dart`
- `flutter test --no-pub test/unit/services/analysis_telemetry_guardrail_helper_test.dart test/unit/services/analysis_service_test.dart test/unit/entities/analysis_models_test.dart test/unit/features/analysis/domain/entities/quick_analysis_result_test.dart test/unit/features/analysis/domain/coach/learning_link_resolver_test.dart test/unit/features/analysis/domain/coach/coach_action_policy_test.dart test/unit/features/analysis/data/services/analysis_service_two_stage_test.dart test/unit/features/analysis/data/services/analysis_hint_service_test.dart test/unit/features/analysis/data/notifiers/two_stage_analyze_notifier_test.dart`
- `flutter analyze --no-pub lib/features/analysis/domain/entities/analysis_models.dart test/unit/services/analysis_service_test.dart`

## 2026-05

### [2026-05-29] 問名字後的 AI 建議被教練卡誤判太長

**症狀**:

- 使用者採用 AI 建議回「hi! 怎麼稱呼你？」後，對方回「Amy」。
- 使用者再採用 AI 建議「Amy 好呀😊 最近在忙什麼？」後，完整分析的「本回合怎麼接」卻提示「這次回得有點長」，看起來像 VibeSync 自己否定自己的建議。

**Root Cause**:

- `CoachActionPolicy._userOverextendedReply` 只用最新我方回覆與對方上一句的字數比例判斷 1.8x。
- 對方上一句是姓名這類極短資訊時，正常寒暄也會超過 1.8x，且 policy 不知道上一句是 AI 建議產生，因此出現自我矛盾。

**修復**:

- 若上一輪我方訊息是在問稱呼/名字，且對方回覆是短回答，只對一小段自然寒暄放寬「回得剛剛好」長度懲罰；若使用者接超長段落仍會提醒精簡。
- 「回得剛剛好」文案改成前瞻式提醒，不再直接說「這次回得有點長」。

**驗證**:

- `flutter test test/unit/features/analysis/domain/coach/coach_action_policy_test.dart`
- `flutter test test/widget/screens/analysis_screen_test.dart`
- `flutter analyze lib/features/analysis/domain/coach lib/features/analysis/presentation/screens/analysis_screen.dart`
- `git diff --check`

### [2026-05-14] 開場救星付費用戶被 Free quota 擋住

**症狀**:

- Settings 顯示 Essential 月繳與 800/120 額度，但開場救星回 429，payload 顯示 `monthlyLimit: 30`、`dailyLimit: 15`。
- 同一輪 dogfood 也發現開場救星會帶出上一個對象的舊結果，以及同名對象合併多跳一層選擇頁。

**Root Cause**:

- `analyze-chat` 只用 Supabase `user.id` 去 RevenueCat 查 subscriber。TestFlight/RevenueCat 可能把 active entitlement 掛在 `originalAppUserId` 或 alias，導致 Edge Function 補 tier 失敗，沿用 DB 內舊 Free quota。
- 開場救星結果用全域 latest cache 自動 restore，沒有跟目前輸入或對象 scope 綁定。
- 同名對象 banner 的 CTA 仍導到舊 merge route，而不是直接執行明確的同名合併。

**修復**:

- opener client 傳 `expectedTier` 與 `revenueCatAppUserId`；Edge Function 仍只在 RevenueCat 驗證到 paid entitlement 後才提升 DB tier。
- `analyze-chat` quota refresh 改為依序查 RevenueCat app user id 與 Supabase user id，避免 alias/匿名 ID 對不上時誤用 Free quota。
- 新開場頁不再自動 restore 全域 latest result；更換截圖、文字或來源會清掉舊結果，避免跨對象殘留。
- 同名對象「立即合併」直接 merge newer duplicate into older partner，成功後 dismiss banner。

**驗證**:

- `flutter test test/unit/features/opener/data/services/opener_service_test.dart test/widget/features/partner/same_name_banner_test.dart`
- `deno test --allow-read supabase/functions/analyze-chat/index_test.ts`

**後續 UX 收斂（2026-05-14）**:

- 開場結果從單筆 latest cache 升級為最多 10 筆本機加密草稿，只存 AI 結果與輸入摘要，不存原始截圖。
- 開場頁不再自動恢復舊結果；使用者要主動點「最近開場草稿 / 回看」，避免 A 對象結果遺留到 B 對象。
- 從草稿接續到新對話前會把目前草稿設成 handoff source，避免 `latest` 被其他對象覆蓋。
- 驗證：`flutter test test/unit/features/opener/data/services/opener_result_cache_service_test.dart`、`flutter analyze`。

### [2026-05-12] 開場救星同圖偶發格式異常 502

**症狀**:

- Essential 月繳與 Essential 季繳用同一組交友軟體截圖生成開場時，一台成功、一台回 `開場產生格式異常` / 502。
- 錯誤 payload 顯示 `shouldChargeQuota: false`，代表 quota 沒被扣，但使用者會誤以為方案或帳號權限壞掉。

**Root Cause**:

- 開場救星 prompt 在 5 種開場、profileAnalysis、pioneerPlan 都變完整後，原本 `max_tokens: 1024` 偶爾不足，Claude 可能回傳被截斷或帶說明的 JSON。
- opener 解析器只做一次 `parseJsonObjectFromText`，沒有走既有 `repairJson` 或格式修復重試；因此同圖會因模型輸出長短差異出現偶發 502。

**修復**:

- opener 輸出 token 提升到 1800，降低 schema 截斷率。
- `parseJsonObjectFromText` 增加 `repairJson(candidate)` 嘗試，先補齊常見缺括號/尾逗號。
- 新增 `repairMalformedOpenerPayload`：初次格式不合時，用 Sonnet 做一次「只修 JSON 格式」的 repair pass；成功才扣原本 opener quota，不額外扣用戶額度。
- opener 有圖片時強制 Sonnet，符合「有圖片時所有層走 Sonnet」穩定基線。

**驗證**:

- `deno check supabase/functions/analyze-chat/index.ts`
- `deno test --allow-read supabase/functions/analyze-chat/index_test.ts supabase/functions/analyze-chat/opener_prompt_test.ts`

### [2026-05-11] Paywall 月繳選項誤送季繳商品

**症狀**:

- Free 升 Starter 後，再點月繳升級時，系統購買 sheet 顯示成季繳商品。
- 這是 P0 誤購風險，因為 UI 選項與實際送進 RevenueCat/StoreKit 的商品不一致。

**Root Cause**:

- Paywall package 對應使用 `text.contains('month')` 這類 fuzzy matching。
- RevenueCat 的 `PackageType.threeMonth` 轉成文字後也包含 `month`，導致季繳 package 可能被月繳 getter 吃到。
- `_resolvedSelectedOption` 在 selected option 尚未 ready 時會立即解析成第一個 available option，存在同一幀 UI 選月繳、purchase 使用 fallback 商品的風險。

**修復**:

- 訂閱商品對應改成先用 exact product id 白名單，再用 `PackageType.monthly/threeMonth` 與 `P1M/P3M` 精準判斷。
- 月繳判斷明確排除 `threeMonth/P3M/quarterly`；季繳判斷明確排除 `monthly/P1M`。
- Paywall 不再用 fallback option 直接購買；目前選項未 ready 時先禁用，等 UI 明確切到 fallback 後才可按。
- 補測試覆蓋 Offering packages 與 direct StoreProduct 的四產品 mapping，並防 threeMonth 被月繳誤吃。

**驗證**:

- `flutter test test/unit/features/subscription/data/subscription_state_package_test.dart`
- `flutter test test/widget/screens/paywall_screen_test.dart`
- `flutter test test/unit/services/subscription_tier_helper_test.dart`
- `flutter analyze`

### [2026-05-11] 付費用戶更新後退回 Free，升級/恢復購買卡在同步

**症狀**:

- TestFlight 更新後，已購買 Essential/Starter 的用戶可能顯示為 Free，分析額度被 Free quota 擋住。
- Paywall 按升級 Starter 可能停在「正在同步方案資訊」，恢復購買後也沒有把 tier 同步回來。

**Root Cause**:

- App 端 RevenueCat SDK 可能能讀到付費訂閱，但 `sync-subscription` 只用 Supabase `user.id` 查 RevenueCat；若訂閱仍掛在 RevenueCat 原始/匿名 appUserId 或 alias 尚未穩定，Server 會查到 free，導致 Supabase `subscriptions` 仍是 free。
- Staging/Firebase build 傳入 `REVENUECAT_SANDBOX_KEY`，但 AppConfig 沒讀這個 key，可能造成 offerings/package 取不到而購買按鈕卡住。

**修復**:

- App 登入/購買/恢復/同步時帶上 RevenueCat `originalAppUserId`，Edge Function 同時查 Supabase user id 與 RevenueCat appUserId。
- Edge Function 遇到 client 期望 paid、DB/RevenueCat 都未確認 paid 時回 409，不再把疑似付費同步失敗誤寫成 free。
- AppConfig 對 RevenueCat key 做 public SDK key guard；只接受 `appl_` key，其他 server/API key 一律 fallback 到 iOS public key。
- Paywall package 對應不再只靠 product id 字串，同時讀 RevenueCat package id、package type、`P1M/P3M` 訂閱週期與 title，避免 offerings 已載入但方案卡仍判定 package 為空。
- Paywall 新增 direct StoreKit product fallback：若 RevenueCat Offerings 為空或未回 packages，App 會改用 `getProducts()` 直接抓新舊 iOS product id，仍可顯示價格並購買。
- App 端 RevenueCat SDK key 現在只接受 `appl_` public SDK key；GitHub App build 不再把 `REVENUECAT_PROD_KEY/SANDBOX_KEY` server key 塞進 Flutter，避免購買時 `Invalid API Key`。

**驗證**:

- `flutter analyze`
- `flutter test test/unit/features/subscription/data/subscription_state_package_test.dart`
- `deno check supabase/functions/sync-subscription/index.ts`
- `deno test supabase/functions/sync-subscription/usage_reset_test.ts supabase/functions/sync-subscription/revenuecat_identity_test.ts`

### [2026-05-09] 開場救星返回後結果遺失
**症狀**:

- 新對話進入開場救星，成功分析並扣額度後，如果使用者按上一頁離開，再回來就看不到剛才的開場結果。
- 這會造成「已付費/已扣額度，但成果消失」的體驗落差。

**Root Cause**:

- `OpeningRescueScreen` 只把 `OpenerResult` 放在頁面 state `_result`，route pop 後 widget dispose，結果沒有任何本機保存。

**修復**:

- `OpenerResult` 補 `toJson/fromJson`。
- 新增 `OpenerResultCacheService`，把最近一次開場結果寫入既有 encrypted Hive `settingsBox`。
- 開場救星頁 init 時自動恢復最近一次結果；成功分析後先保存，再更新畫面。

**驗證**:

- `flutter analyze lib/features/opener/data/services/opener_service.dart lib/features/opener/data/services/opener_result_cache_service.dart lib/features/opener/presentation/screens/opening_rescue_screen.dart`
- `flutter test test/unit/features/opener/data/services/opener_service_test.dart test/unit/features/opener/data/services/opener_result_cache_service_test.dart`

**影響檔案**:

- `lib/features/opener/data/services/opener_service.dart`
- `lib/features/opener/data/services/opener_result_cache_service.dart`
- `lib/features/opener/presentation/screens/opening_rescue_screen.dart`
- `test/unit/features/opener/data/services/opener_result_cache_service_test.dart`

### [2026-05-09] 付費功能門檻與額度表不一致
**症狀**:

- Free 使用者可能在「我的報告」看到付費報表入口，與產品設定的 Starter/Essential 限制不一致。
- 草稿潤飾器在 UI 上可被非 Essential 使用者觸發，後端也沒有獨立擋 `optimize_message`。
- 舊 DB helper `check_and_reset_usage` 仍保留 Essential 1000/月、150/日，和目前定價 800/月、120/日不一致。

**Root Cause**:

- 方案調整後，主要 Edge quota 與 App constants 已更新，但舊 DB helper 與部分 UI gate 沒有同步收斂。
- `healthCheck` 是 Essential 專屬，但 App 端仍可能保留舊分析快取，降級後若未 gate 會污染複製內容或 Coach context。

**修復**:

- Free 的「我的報告」改成 Starter 解鎖卡。
- 草稿潤飾器改為 Essential-only：App 端先擋並導 Paywall，Edge Function 對 `optimize_message` 回 `FEATURE_NOT_AVAILABLE`。
- Health Check 顯示、複製與 Coach snapshot 全部加 Essential gate。
- 修正 initial schema，並新增 migration 讓既有 DB 的 `check_and_reset_usage` 對齊 30/15、300/50、800/120。

**驗證**:

- `flutter analyze`
- `flutter test test/unit/services/subscription_tier_helper_test.dart test/unit/features/opener/data/services/opener_service_test.dart test/widget/widgets/analysis_preview_dialog_test.dart test/widget/screens/paywall_screen_test.dart test/widget/screens/settings_screen_test.dart`
- `deno test --allow-read supabase/functions/_shared/quota_test.ts supabase/functions/sync-subscription/usage_reset_test.ts supabase/functions/analyze-chat/index_test.ts`
- `deno check supabase/functions/analyze-chat/index.ts supabase/functions/sync-subscription/index.ts supabase/functions/revenuecat-webhook/index.ts`

**相關檔案**:

- `lib/features/analysis/presentation/screens/analysis_screen.dart`
- `lib/features/report/presentation/screens/my_report_screen.dart`
- `supabase/functions/analyze-chat/index.ts`
- `supabase/migrations/00001_initial_schema.sql`
- `supabase/migrations/20260509_fix_check_and_reset_usage_limits.sql`

### [2026-05-08] 本回合練習卡忽略具體生活話題
**症狀**:

- 對方明確丟出「在家追劇 看絕命毒師」這類可延展話題時，分析頁仍顯示泛用的「互動品質觀察」。
- 文案反覆出現「先別下定論」「練觀察」，和當下對話不夠貼合。

**Root Cause**:

- `CoachActionPolicy` 的 fallback 只看熱度與 GAME stage。
- opening 階段沒有讀最後一則對方訊息的生活話題訊號，導致具體 topic hook 也掉到 fitCheck。

**修復**:

- 新增最後一則對方訊息的 concrete topic hook 偵測。
- 追劇、電影、音樂、運動、餐廳等可延展生活話題改顯示「接住生活話題」。
- 收斂 fitCheck fallback 文案，避免一直重複「先別下定論」。

**驗證**:

- `flutter test test/unit/features/analysis/domain/coach/coach_action_policy_test.dart`
- `flutter analyze`

**相關檔案**:

- `lib/features/analysis/domain/coach/coach_action_policy.dart`
- `test/unit/features/analysis/domain/coach/coach_action_policy_test.dart`

### [2026-05-07] 對象卡備註重複累積
**症狀**:

- 對象詳情卡的「備註」會把每次分析擷取到的 `targetProfile.notes` 逐行串起來。
- 同一個觀察，例如「喜歡測試對方反應」「對教父牛排有興趣但用忙拒絕邀約」「可能需要更多信任建立」，會在卡片裡重複出現多次。
- 使用者看起來像記憶很亂，而不是 AI 有統整過同一個對象。

**Root Cause**:

- `Partner.aggregateOver()` 對 interests / traits 有 recency ranking + dedupe + cap，但 notes 只是把所有 snapshot notes 依時間串接。
- 每段對話重新分析時，AI 會穩定抽到相似備註，舊邏輯沒有 exact dedupe、near-duplicate collapse，也沒有顯示上限。

**修復**:

- 新增 `unionNotes` 聚合規則：先選最新 notes、去掉完全重複和近似重複，再保留最多 8 條。
- 顯示仍維持時間線順序，避免卡片讀起來像倒序碎片。
- 新增 regression tests 覆蓋 exact duplicate、near duplicate、latest-8 cap。

**驗證**:

- `flutter test test/unit/entities/partner_aggregates_test.dart`
- `flutter test test/unit/features/coach_chat test/unit/entities/partner_aggregates_test.dart`
- `flutter analyze`

**相關檔案**:

- `lib/features/partner/domain/extensions/partner_aggregates.dart`
- `test/unit/entities/partner_aggregates_test.dart`

### [2026-05-06] userDraft 優化改掉使用者真正想表達的主題

**症狀**:

- 夥伴在「我有想說的，幫我優化」輸入「感覺你潛水很厲害」。
- 上方對話脈絡裡，對方上一句是「你有在健身嗎」。
- AI 優化後輸出「有在勤，但不算很勤勞。你是規律運動派？」這類健身回答，沒有保留使用者真正想表達的潛水稱讚。

**Root Cause**:

1. `userDraft` prompt 只寫「根據以上原則優化」，並把 1.8x 法則綁到「她最後一則訊息長度」。
2. Prompt 沒明確定義 userDraft 是使用者主要意圖，導致模型把「幫我優化」誤解成「幫我回答她上一句」。
3. 對話脈絡權重過高，蓋掉了使用者輸入本身的主題、稱讚對象與互動意圖。

**修復**:

1. 在 `SYSTEM_PROMPT` 的用戶訊息優化段落新增「語義保真規則」。
2. 明確要求 userDraft 的核心對象、主題、稱讚 / 邀約 / 界線意圖必須保留。
3. 明確限制對話脈絡只能調整語氣、長度、禮貌程度與接續感，不得把 userDraft 改寫成回答對方最後一題。
4. 新增「優化品質規則」：幫我優化必須真的把原句變得更口語、更順、更有情緒溫度、更好接球，而不是照抄、摘要、評論或改成另一個意圖。
5. 在 runtime 追加的 `User Draft To Optimize` 區塊補上英文 optimization contract，避免模型把 draft 當成 vague hint。
6. 新增 Deno prompt regression test，鎖住「潛水稱讚」不能被上一句「健身」帶偏，且必須變成可直接送出的優化訊息。

**驗證**:

- `deno test --allow-read supabase/functions/analyze-chat/index_test.ts`

**涉及檔案**:

- `supabase/functions/analyze-chat/index.ts`
- `supabase/functions/analyze-chat/index_test.ts`

### [2026-05-06] Coach Action Card 過度重複顯示情緒共鳴

**症狀**:

- 使用者連續測試主分析畫面的「本回合練什麼」卡片，約 10 次有 8 次顯示「情緒共鳴」。
- 卡片文案高度重複，例如「熱度 X，先接住情緒」「這次只做：先用一句接住她的情緒」「先不要：別急著給建議或解釋」。
- 實際對話有些只是人格觀察、話題球或一般傳訊號，不應全部被歸成情緒共鳴。

**Root Cause**:

1. `CoachActionPolicy` 只要 `psychology.subtext.length >= 8` 就觸發 `emotionalResonance`，條件過寬。
2. 主分析幾乎每次都會輸出一段「她話裡的意思」，因此 deterministic policy 很容易被長 subtext 吸走。
3. 互動測試與真實情緒共鳴共用同一張「情緒共鳴」卡，導致使用者感覺像模板。

**修復**:

1. 移除「subtext 長度 >= 8」作為情緒共鳴 trigger。
2. 新增明確情緒 keyword gate，只有不安、焦慮、壓力、委屈、修復、前任、邊界等情緒/關係壓力訊號才走情緒共鳴。
3. 互動測試仍保留 safe coaching，但顯示成「接住試探球」，文案改成穩住語氣、不要自證或反擊。
4. 一般人格觀察 / 想了解你 / 話題球改走故事框架或其他 mid-game action，避免 8/10 卡片重複。

**驗證**:

- `flutter test test/unit/features/analysis/domain/coach/coach_action_policy_test.dart`
- `flutter analyze`

**涉及檔案**:

- `lib/features/analysis/domain/coach/coach_action_policy.dart`
- `test/unit/features/analysis/domain/coach/coach_action_policy_test.dart`

### [2026-05-05] 主分析介面殘留早期 Game 語彙造成誤判感

**症狀**:

- 夥伴測試只輸入一則「她說：感覺你是個很有故事的人」。
- AI 對話解讀本身接近正確，但主介面把 `qualificationSignal` 顯示成「她在向你證明自己」，使用者感覺很怪，像是 UI label 在亂貼標籤。
- 同類早期語彙也散落在階段描述與心理卡，例如「讓她證明自己」「廢測」「男女框架」。

**Root Cause**:

1. `qualificationSignal` 的早期產品語義偏 Game/PUA，等同「她在證明自己」。
2. 現在產品定位已收斂成「有記憶的 AI 約會教練」，但部分 UI 文案與 prompt schema example 沒同步升級。
3. Prompt 沒明確區分「她在觀察 / 稱讚你」與「她主動投入 / 分享自己」，導致單句人格觀察也可能被標成 qualification。

**修復**:

1. Prompt 補 `qualificationSignal` 定義：它代表「主動投入互動」，不是「她在證明自己」；「感覺你是個很有故事的人」應視為好奇與觀察，不是展示自己。
2. 主介面與 `PsychologyCard` 將可見文案改成「她有主動投入訊號」。
3. GAME 階段文案改成「互相評估 / 她在觀察你，你也判斷是否同頻」。
4. 可見「廢測」改成「互動測試訊號」，移除早期黑話。
5. 分析 preview 補上「重新分析會用目前整段對話重新判斷；舊訊息只作為背景，不重複扣額度，這次只計算新增內容。」

**驗證**:

- `deno test --allow-read supabase/functions/analyze-chat/index_test.ts`
- `flutter test test/unit/entities/game_stage_test.dart test/unit/services/game_stage_service_test.dart test/widget/widgets/game_stage_indicator_test.dart test/widget/widgets/analysis_preview_dialog_test.dart test/widget/features/analysis/psychology_card_test.dart`
- `flutter analyze`

**涉及檔案**:

- `supabase/functions/analyze-chat/index.ts`
- `lib/features/analysis/domain/entities/game_stage.dart`
- `lib/features/analysis/domain/services/game_stage_service.dart`
- `lib/features/analysis/presentation/screens/analysis_screen.dart`
- `lib/features/analysis/presentation/widgets/psychology_card.dart`
- `lib/shared/widgets/analysis_preview_dialog.dart`

### [2026-05-05] 續聊手動新增訊息後分析仍讀到舊對話

**症狀**:

- 使用者先輸入 1 則「她說」並完成分析，再從「繼續對話」手動新增 1 則「她說」。
- 點「分析新增內容」後，分析畫面沒有反映新增那則訊息，右上角仍像是在等待網路請求。
- 截圖路徑尚未測，但同屬「寫入目前對話後立刻讀回分析」的資料新鮮度問題。

**Root Cause**:

1. `ConversationWriteController.save()` 只 invalidate partner scope 與 `conversationsProvider`，沒有 invalidate `conversationProvider(id)`。
2. `AnalysisScreen` 續聊分析、額度 preview 與畫面回復都依賴 `conversationProvider(id)`；手動補訊息後若 detail provider 仍是舊快照，就可能把舊訊息送去分析，或保存錯誤的已分析訊息數。
3. 截圖匯入路徑有手動 `ref.invalidate(conversationProvider(id))`，因此手動輸入路徑與截圖路徑的 invalidation discipline 不一致。

**修復**:

1. `ConversationWriteController` 新增 detail provider invalidation，`create/save/delete` 都刷新 `conversationProvider(conversationId)`。
2. 分析快照保存時改用重新讀回的最新 conversation 長度寫入 `lastAnalyzedMessageCount`，避免舊參照覆蓋續聊計數。
3. 補 `ConversationWriteController.save invalidates conversationProvider detail after save` 測試，鎖住「新增第二則她說後，下次讀 detail 必須看到第二則」契約。

**驗證**:

- `flutter test test/unit/services/conversation_write_controller_test.dart test/widget/features/analysis/analysis_screen_continue_input_test.dart`

**涉及檔案**:

- `lib/features/conversation/data/providers/conversation_write_controller.dart`
- `lib/features/analysis/presentation/screens/analysis_screen.dart`
- `test/unit/services/conversation_write_controller_test.dart`

### [2026-05-05] Paywall 方案卡在手機寬度下溢出

**症狀**:

- 上線前檢查付款頁時，widget test 在 430px 手機寬度下抓到 `Essential 季繳 + 最划算 + 省 36% + radio` 同列超出卡片寬度。
- 使用者可能在較窄手機、較大字體或價格文案較長時看到方案卡右側被截斷。

**Root Cause**:

1. 方案卡 header 使用單列 `Row`，方案名稱、badge、折扣 badge、目前方案 badge 與 radio 都在同一行。
2. 原本付款頁測試仍停在舊版文案，沒有守住新版四方案 layout，因此這個 overflow 沒有被測試及早抓到。

**修復**:

1. 方案卡 header 改成 `Expanded + Wrap`，讓名稱與 badge 可自然換行，radio 保持在右側。
2. 功能比較表補上 Free / Starter / Essential 表頭，並把 `V / --` 改成 `可用 / 未開放`。
3. 更新 Settings / Paywall widget tests 到目前上線文案，鎖住版本顯示、方案比較、價格同步狀態與刪除帳號確認流程。

**驗證**:

- `flutter test test/widget/screens/paywall_screen_test.dart test/widget/screens/settings_screen_test.dart`
- `flutter analyze`

**涉及檔案**:

- `lib/features/subscription/presentation/screens/paywall_screen.dart`
- `lib/features/subscription/presentation/screens/settings_screen.dart`
- `test/widget/screens/paywall_screen_test.dart`
- `test/widget/screens/settings_screen_test.dart`

### [2026-05-05] 編輯剛剛那則訊息文字對比不足

**症狀**:

- 使用者在「繼續對話」手動補上一則訊息後，點「編輯剛剛那則」打開編輯 Dialog，輸入框文字顏色在實機上與背景對比不足，看起來太深、不易讀。

**Root Cause**:

1. 編輯 Dialog 只指定 `TextField.style`，沒有把輸入框底色 `fillColor` 固定。
2. `AlertDialog` 仍可能受 Material surface tint / 外層主題影響，導致實機視覺不是穩定的「淺底深字」。

**修復**:

1. `AlertDialog` 關閉 `surfaceTintColor`，避免主題 tint 讓底色跑掉。
2. 編輯 `TextField` 固定為白色填底、深色正文、primary 游標，確保 OCR/手動訊息修正時可讀。
3. 補 widget test 鎖住 Dialog 背景、TextField 填底與文字色契約。

**驗證**:

- `flutter test test/widget/features/analysis/analysis_screen_continue_input_test.dart`
- `flutter analyze`

**涉及檔案**:

- `lib/features/analysis/presentation/screens/analysis_screen.dart`
- `test/widget/features/analysis/analysis_screen_continue_input_test.dart`

### [2026-05-05] iOS 手動輸入鍵盤無法明確收起

**症狀**:

- 使用者在「繼續對話」底部手動輸入新訊息後，iOS 鍵盤覆蓋「這句是她說 / 這句是我說」按鈕。
- 多行輸入框右下角顯示 return / 換行，沒有明確「完成」語意；使用者不知道怎麼收起鍵盤繼續下一步。
- 同類型的「輸入文字後，下方才有 CTA」也會遇到相同問題：訊息優化、問題回饋補充、教練跟進 sheet 的補充輸入。

**Root Cause**:

1. 手動補訊息的 `TextField` 使用 `TextInputAction.newline`，導致 iOS keyboard 優先呈現換行，而不是完成輸入。
2. speaker 選擇按鈕放在輸入框下方；鍵盤開啟時按鈕容易被遮住，但畫面內沒有 visible keyboard dismiss control。
3. 類似多行文字輸入沒有統一 keyboard-dismiss convention。

**修復**:

1. 手動輸入框改用 `TextInputAction.done`，`onEditingComplete` 主動 unfocus 收起鍵盤。
2. 輸入框右側新增 `keyboard_hide` 按鈕，讓使用者不用猜 iOS 鍵盤怎麼收。
3. 按「看上方對話」與成功加入訊息前也主動 unfocus，避免鍵盤卡住流程。
4. 同步補「訊息優化」、「問題回饋補充」、「教練跟進 sheet」的多行輸入：done action + 右側收鍵盤按鈕 + submit 前 unfocus。

**驗證**:

- `flutter test test/widget/features/analysis/analysis_screen_continue_input_test.dart`
- `flutter test test/widget/features/coach_follow_up/coach_follow_up_input_sheet_test.dart`
- `flutter analyze`

**涉及檔案**:

- `lib/features/analysis/presentation/screens/analysis_screen.dart`
- `test/widget/features/analysis/analysis_screen_continue_input_test.dart`
- `lib/features/coach_follow_up/presentation/widgets/coach_follow_up_input_sheet.dart`
- `test/widget/features/coach_follow_up/coach_follow_up_input_sheet_test.dart`

### [2026-05-05] Coach follow-up 對模糊赴約缺少時間成本判斷

**症狀**:

- 使用者在「我有其他問題」輸入「有男友了還約我幹嘛？」時，AI 回覆有邊界感，但 task 仍偏向「下次見面時觀察」，沒有先幫使用者判斷這個局是否值得去。
- AI 缺少「健康進攻性 + 全局判斷」的教練姿態：知道怎麼推進、幽默逗對方開心，也要知道什麼時候該收、何時不值得投入時間。
- 對幽默、調侃、互動張力這類 game 技巧，prompt 沒明確要求「內部理解、外部不展示術語」，容易在過保守與技巧化之間搖擺。

**Root Cause**:

1. `openCoach` prompt 只有開放式診斷與健康主動性，沒有明確要求把「赴約是否值得」當成時間成本 / 關係透明度問題處理。
2. 系統 prompt 對露骨、辱罵、亂碼已有 guard，但缺少「對方有伴侶、邀約動機模糊、局面不透明」的 go/no-go triage。
3. prompt 沒有把「技巧服務狀態」寫成規則；教練可能知道要推進，但不知道應避免把推拉、套路、話術等術語直接展示給使用者。

**修復**:

1. 系統 prompt 補上教練立場：鼓勵健康進攻性，但也要有全局觀，判斷何時推進、何時收手、何時保護時間成本與尊嚴。
2. `openCoach` 補上模糊赴約判斷：遇到「她有男友/伴侶還約我」或「這局該不該去」時，先看對方動機、關係透明度、是否低成本可退出；資訊不足時不直接建議見面，改成先釐清或降級成公開短時間。
3. 系統 prompt 補上「內部可理解互動張力 / 輕微調侃 / 誇張曲解 / 推進節奏，但輸出不要展示技巧名稱；翻成自然的人味、幽默感、狀態與真誠表達」。

**驗證**:

- `deno test supabase/functions/coach-follow-up/prompts_test.ts`
- `deno test --allow-env --allow-net supabase/functions/coach-follow-up`

**涉及檔案**:

- `supabase/functions/coach-follow-up/prompts.ts`
- `supabase/functions/coach-follow-up/prompts_test.ts`

### [2026-05-05] TF smoke：手動輸入回饋、額度用完導頁、付費升級額度沿用

**症狀**:

- 繼續對話輸入一則訊息後點「加入為她說」，上方對話預覽仍停在舊訊息，使用者看不出來是否加入成功。
- 成功加入後只出現黑色 snackbar + 右側 action，使用者仍不確定剛剛那句是否已寫進對話，也不知道打錯字如何補救。
- 已分析過的長對話中，上一輪分析資訊仍留在頁面；使用者在底部補新訊息後，必須在上方對話框與底部輸入區之間來回拉動確認。
- 使用者不知道「補了幾則再分析會扣多少」、「舊對話會不會重扣」、「前面幾輪到底怎麼被帶入」。
- 「我有想說的，幫我優化」與「教練跟進」在額度用完時只顯示 snackbar / inline error，沒有直接帶到升級方案頁。
- Free 用戶升級 Essential 後仍沿用 Free 已使用量，顯示本月已使用 28 / 今日剩餘已被扣。

**Root Cause**:

1. 對話預覽折疊狀態使用 `conversation.messages.take(5)`，只顯示最舊 5 則；新增訊息 append 到尾端後被藏住。
2. 成功狀態放在 transient snackbar，且文案只說「已新增對方訊息」，沒有把「已加入哪一邊 / 內容摘要 / 下一步 / 可編輯」放回使用者正在操作的底部輸入區。
3. 繼續對話與開新對話共用輸入區，但沒有呈現「已補上幾則新訊息」的 bottom-side state；對已分析過的長頁面尤其容易造成上拉下拉。
4. 增量計費與舊對話摘要屬於系統內部邏輯，UI 沒有轉成用戶能理解的「只補新增、分析前確認、舊訊息不重扣」。
5. 分析優化與 coach-follow-up 的 quota exception 只轉成文字狀態，沒有接 paywall navigation。
6. `sync-subscription` 讀到 client `resetUsage` 但後端把 `shouldResetUsage` 寫死為 `false`，付費升級不會清 usage counters。

**修復**:

1. 折疊預覽改顯示最新 5 則，讓新增的「她說 / 我說」立即出現在上方對話框。
2. 成功加入後改成底部 inline feedback：「已補上 N 則新訊息｜最新：她說/我說」+ 內容摘要 + 下一步；提供「編輯剛剛那則」與「看上方對話」，她說時另提供「分析這段 / 分析新增內容」。
3. 展開的繼續對話區塊把「收合」改成「看上方對話」，點擊後收起輸入區並跳回上方對話框。
4. 輸入區新增說明卡：開新對話說明「照聊天順序補、分析前確認額度」；繼續對話說明「只補新訊息、舊對話用必要摘要和最近訊息當背景、舊訊息不重複扣」。
5. 空對話預覽加第一步提示；按鈕文案從「加入為她說/我說」改成「這句是她說/我說」，降低新用戶的判斷成本。
6. Daily / Monthly quota exceeded 都直接觸發 paywall；coach-follow-up section 透過 `onQuotaExceeded` callback 由 Partner Detail 開升級頁。
7. `sync-subscription` 新增 paid-upgrade reset helper：只有 RevenueCat 確認 tier 變成付費且 client 要求 reset 時才清 `monthly_messages_used` / `daily_messages_used`；restore、same-tier、scheduled downgrade、RC transient free snapshot 不清。

**驗證**:

- `flutter test test/widget/features/analysis/analysis_screen_continue_input_test.dart`
- `flutter test test/widget/features/coach_follow_up/coach_follow_up_section_test.dart --plain-name "quota exceeded opens the upgrade surface callback"`
- `deno test supabase/functions/sync-subscription/usage_reset_test.ts`

**涉及檔案**:

- `lib/features/analysis/presentation/screens/analysis_screen.dart`
- `lib/features/coach_follow_up/presentation/widgets/coach_follow_up_section.dart`
- `lib/features/partner/presentation/screens/partner_detail_screen.dart`
- `supabase/functions/sync-subscription/index.ts`
- `supabase/functions/sync-subscription/usage_reset.ts`

### [2026-05-05] Coach follow-up 邊界提醒半句 + 額度日切後顯示 stale

**症狀**:

- 「教練跟進」結果卡的 `boundaryReminder` 連續出現半句，例如句子被切在「誠實溝」或破折號後。
- Free 用戶在台灣時間 08:00 後仍看到舊的今日剩餘；使用 coach follow-up 後才刷新成新的 server usage，造成「2/15 用 3 次後變 12/15」的跳動感。

**Root Cause**:

1. `truncateCard()` 對可見欄位用硬 `slice(0, cap)`，AI 一旦超過 60 字就會被切成半句。
2. 設定頁 / 付費頁開啟時沒有主動 refresh subscription usage snapshot；日額度在 Edge function 端已依 UTC 日切重置，但前端仍可能暫時顯示舊 state。

**修復**:

1. `boundaryReminder` prompt 收斂到 45 字、完整短句；server truncation 改成優先切完整句，沒有句界才加省略號。
2. Settings / Paywall 開頁後透過 `subscriptionScreenRefreshProvider` 主動刷新 usage snapshot，測試可 override 避免真網路。

**驗證**:

- `deno test --allow-env --allow-net supabase/functions/coach-follow-up`
- `flutter test test/widget/screens/settings_screen_test.dart --plain-name "refreshes subscription usage snapshot on entry"`
- `flutter test test/widget/screens/paywall_screen_test.dart --plain-name "refreshes subscription usage snapshot on entry"`
- `flutter analyze lib/features/subscription lib/features/coach_follow_up test/widget/screens/settings_screen_test.dart test/widget/screens/paywall_screen_test.dart`

**涉及檔案**:

- `supabase/functions/coach-follow-up/validate.ts`
- `supabase/functions/coach-follow-up/prompts.ts`
- `lib/features/subscription/data/providers/subscription_providers.dart`
- `lib/features/subscription/presentation/screens/settings_screen.dart`
- `lib/features/subscription/presentation/screens/paywall_screen.dart`

## 2026-04
### [2026-04-30] TestFlight upload 被 Apple 拒收：IPA 使用 iOS 18.5 SDK

**症狀**:

- GitHub Actions `release.yml` 可成功 build IPA，但 Fastlane `upload_to_testflight` 失敗。
- App Store Connect 回 `Validation failed (409) SDK version issue`。
- 錯誤訊息指出 app was built with iOS 18.5 SDK，必須改用 iOS 26 SDK / Xcode 26 或更新版本。

**Root Cause**:

- iOS workflow 使用 `runs-on: macos-latest`。
- 2026-04-29 當次 run 被配置到 Xcode 16.4 / iOS 18.5 SDK 環境。
- Apple 自 2026-04-28 起要求 App Store Connect 上傳必須使用 Xcode 26 / iOS 26 SDK。

**修復**:

1. `release.yml` 的 iOS job pin 到 `macos-26`。
2. `distribute.yml` 的 iOS job 同步 pin 到 `macos-26`。
3. 兩個 iOS job 加 `Verify Xcode SDK` step，輸出 `xcodebuild -version` 與 iPhone SDK 清單，避免下次只能從 upload error 反推。

**預防**:

- App Store / TestFlight 發佈 workflow 不要依賴 `macos-latest` 的漸進遷移；SDK deadline 後要 pin 到符合 Apple 要求的 macOS/Xcode runner。
- 下次 Apple SDK requirement 更新時，先改 runner，再 debug Flutter / signing。

**相關檔案**:

- `.github/workflows/release.yml`
- `.github/workflows/distribute.yml`

### [2026-04-26] Partner detail 新增對話未帶入 partnerId

**症狀**:

- A2 Phase 2 將 Home 改成 Partner-first，並在 Partner detail 顯示「新增對話」FAB。
- 使用者從某個對象頁建立對話時，實作仍開啟 legacy `NewConversationSheet`，沒有傳入目前的 `partnerId`。
- 新對話會被建立並可進入分析頁，但不會回到該對象的對話列表 / aggregate / AI partner context。

**Root Cause**:

1. `_NewConversationSheet` 從 `main_shell.dart` pure move 成共用 widget 時，仍維持 legacy 無 partner scope 行為。
2. `PartnerDetailScreen` 把這個 action 暴露成看似 partner-scoped 的 UI，但沒有把 `partnerId` 傳進 sheet / `/new` / `ConversationWriteController.create`。

**修復**:

1. `NewConversationSheet` 新增 optional `partnerId`。
2. 手動輸入路徑改成 `/new?partnerId=...`。
3. `NewConversationScreen` 讀 route query 並在 create conversation 時寫入 `partnerId`。
4. 截圖開始路徑直接把 `partnerId` 傳給 `ConversationWriteController.create`。
5. `PartnerDetailScreen` 開 sheet 時傳入目前對象 id。

**學到**:

- 從 detail page 觸發的 create action 若看起來屬於某個 entity，就必須真的帶 entity scope；不能只靠後續 Phase 補。
- UI 可以先 ship，但不能讓使用者建立「看似成功、實際上消失在該頁列表外」的資料。

**相關檔案**:

- `lib/features/partner/presentation/screens/partner_detail_screen.dart`
- `lib/features/conversation/presentation/widgets/new_conversation_sheet.dart`
- `lib/features/conversation/presentation/screens/new_conversation_screen.dart`
- `lib/app/routes.dart`

### [2026-04-25] VibeSync Discord bridge session 還活著，但 bot 顯示離線不回訊息
**症狀**:

- `VibeSyncClaude` 在 Discord 顯示 offline
- VibeSync 的 WSL / VSCode session 仍在運行
- Supabase `submit-feedback` 仍可用同一個 bot token 發 Discord 通知
- 但 bot 不會回應頻道內的新訊息

**Root Cause**:

1. 全域 `~/.claude/settings.json` 把 `discord@claude-plugins-official` 設成 `false`
2. TravelAPP 有 project-local `.claude/settings.local.json` override，VibeSync 沒有
3. VibeSync bridge 主程序雖然存在，但 Discord plugin child 沒被拉起來，所以沒有 gateway 連線

**修復**:

1. 讓 `.claude/settings.local.json` 成為 repo 內可追蹤的最小設定，明確啟用 `discord@claude-plugins-official`
2. 更新 `.gitignore`，只放行這個安全的 project-local Claude 設定檔
3. 重啟 `discord-vibesync` bridge，確認 Discord plugin child process 成功啟動

**預防**:

- Discord bot「能發通知」不等於 bridge「在線監聽」；Supabase REST 發文和 WSL gateway 監聽是兩條路
- 若 bot 顯示 offline，但 session 還在，先查 `.claude/settings.local.json` 和 plugin child process

**相關檔案**:

- `.gitignore`
- `.claude/settings.local.json`
- `AGENTS.md`
- `docs/discord-vibesync-troubleshooting.md`


### [2026-04-24] submit-feedback 對舊版 TestFlight feedback payload 相容性不足

**症狀**:

- TestFlight Build 137
  點「送出反饋」時，使用者只看到「回饋暫時沒有送出，稍後可以再試一次」
- Supabase Dashboard 上 `submit-feedback` logs 幾乎沒有線索
- 同時間 server 端已經是新版本 Edge Function，但 TF137 還是舊 Flutter payload

**Root Cause**:

1. 舊版 Flutter 會固定送出最後 6 則對話片段，且未先截斷
2. `submit-feedback` 對 optional string 欄位仍採「超長直接 400」策略
3. Flutter `functions.invoke()` 在非 2xx 會 throw，而 app 端把 400/401/network
   都吃成同一句 generic snackbar

**修復**:

1. `submit-feedback` 對 optional string 欄位改成 server-side truncate，相容舊版
   client
2. 若 `aiResponse` 在 sanitize 後仍超出上限，直接丟棄該欄位，不讓整筆 feedback
   失敗
3. 補上 unit tests 覆蓋 truncate 行為與 sanitize 後長字串壓縮

**預防**:

- client/server 獨立生命週期的功能，optional diagnostics payload 要做
  backward-compatible 容錯
- 舊版 app 可能仍在野外時，server 不應因 optional feedback context oversized
  就回 400

**相關檔案**:

- `supabase/functions/submit-feedback/index.ts`
- `supabase/functions/submit-feedback/feedback_utils.ts`
- `supabase/functions/submit-feedback/feedback_utils_test.ts`

### [2026-04-24] submit-feedback Discord bot fallback 被 webhook 早退短路

**症狀**:

- `submit-feedback` 切到 Discord 後，負評仍會正常寫入 `feedback` table
- 但在「只有 `DISCORD_BOT_TOKEN` + `DISCORD_FEEDBACK_CHANNEL_ID`、沒有 webhook
  URL」的實際線上配置下，Discord 完全收不到通知
- log 只會出現 `Discord feedback webhook not configured`

**Root Cause**:

1. `supabase/functions/submit-feedback/index.ts` 在 `sendDiscordNotification`
   一進來就先檢查 `DISCORD_FEEDBACK_WEBHOOK_URL`
2. 若 webhook 沒設，函式直接 `return`
3. 後面的 Discord bot channel fallback 分支因此永遠不會執行

**修復**:

1. 抽出 `resolveDiscordNotificationTarget()`，統一判斷通知要走 `webhook` 或
   `bot`
2. 只有在 webhook 和 bot config 都缺時才視為未配置
3. 補上 regression tests，覆蓋：
   - webhook 優先
   - 無 webhook 時走 bot fallback
   - config 不完整時回傳 `undefined`

**預防**:

- 有 fallback 路徑時，配置判定必須集中在單一 helper，避免前面 branch
  提早短路後面路徑
- 新通知通道至少補一個「primary 缺席時 fallback 仍可用」的測試

**相關檔案**:

- `supabase/functions/submit-feedback/index.ts`
- `supabase/functions/submit-feedback/feedback_utils.ts`
- `supabase/functions/submit-feedback/feedback_utils_test.ts`

### [2026-04-24] 上傳頁 helper text + 識別按鈕 disabled 狀態白字低對比 — WCAG AA 不過

**症狀**:

- Bruce 在 Build 137 回報三張截圖標註紅框：
  - 上傳頁兩條 helper text（「每張盡量保留 15
    則內」/「請上傳聊天畫面…」）白字貼淺色 glass 漸層，幾乎看不見
  - 識別中 loading 按鈕「AI 辨識中」在 disabled 狀態幾乎透明
- 對比度不足，實機肉眼難讀；送審 App Store 若走 WCAG AA 檢查會卡

**Root Cause**:

1. `image_picker_widget.dart` 三處 `Text` widget 色號寫死
   `Colors.white.withValues(alpha: 0.85)`——原本設計假設背景是深色
   `AppColors.background`（`#121212`），但該 widget 被嵌進淺色 glass
   surface（`AppColors.glassWhite` `#F5F0F8`）時沒套對應 token
2. `analysis_screen.dart` 兩處 `ElevatedButton.styleFrom` 只設
   `backgroundColor: AppColors.primary`，沒設 `disabledBackgroundColor` /
   `disabledForegroundColor`——按鈕 `onPressed: null`（識別中）時 Material 預設把
   BG 和 label 都灰化，結果白字 label 貼淺灰 BG，對比度 ~1.3:1

**修復**:

1. `image_picker_widget.dart` 三處 helper text
   色：`Colors.white.withValues(alpha: 0.85)` →
   `AppColors.glassTextHint`（`#8B4557`，跟 `analysis_screen.dart:756` 既有
   pattern 對齊）
2. `analysis_screen.dart` 兩處 ElevatedButton 明確加 4 個色號：
   - `foregroundColor: Colors.white`（active 的 label + icon）
   - `disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.7)`（disabled
     時仍是可見紫）
   - `disabledForegroundColor: Colors.white.withValues(alpha: 0.95)`（disabled
     時白字保持可讀）
3. 不動設計系統、不動其他 `Colors.white.withValues` 用法（最小 blast radius）

**預防**:

- 新增 `Text` widget 時，禁用 `Colors.white.withValues(...)` 直寫——一律走
  `AppColors.glass*` 或 `AppColors.text*` token
- ElevatedButton 有 `onPressed: null` 分支時，必設 `disabledBackgroundColor` +
  `disabledForegroundColor`（Material 預設會把按鈕灰到幾乎看不見）
- 送審前走一次全頁 WCAG AA 掃（對比度 < 4.5:1 的 text 都要改）

**相關檔案**:

- `lib/shared/widgets/image_picker_widget.dart` (lines 194, 202, 215)
- `lib/features/analysis/presentation/screens/analysis_screen.dart`
  (ElevatedButton styleFrom × 2)

**不動範圍**:

- `analysis_screen.dart:3239` 還有一條 `Colors.white.withValues(alpha: 0.55)`
  類似問題（「建議每張截圖保留 15 則內完整對話…」）——Bruce 未標，暫不動，等全域
  design audit 一起收
- 其他畫面的 `Colors.white` 用法未掃（避免超 scope）

**Reviewer-Hint**（留給 Codex）:

- `glassTextHint` 色號是否真的對 glass surface 有 ≥4.5:1 對比度？沒跑 contrast
  checker，憑 eye-ball
- `disabledBackgroundColor: primary.withValues(alpha: 0.7)` 的 0.7
  是拍腦袋挑的——若實機看起來太亮太像 active，改 0.5 或 0.6

---

### [2026-04-24] 圖片壓縮對拼貼版面失效 — 截圖顯示「太大」擋住上傳

**症狀**:

- Bruce 上傳約會軟體 profile 截圖（1.5MB、iPhone 高解析度、多張照片拼貼版面）
- App 顯示「壓縮後圖片仍然太大，請裁小一點再試。」，無法上傳
- Claude Vision API 實際可吃 ~5MB 原始 / ~3.75MB base64，350KB 硬限制過度保守

**Root Cause**:

1. `ImageCompressService.compressImage` 只試兩次：quality 78 → 60，寬度都固定
   960px
2. 對「高解析度 + 拼貼版面」（JPEG 壓縮阻抗高）兩次都打不到 350KB 上限
3. 壓不下時直接把超標結果回給 widget，widget 看到 `> maxSizeBytes` 直接擋
4. 錯誤訊息「請裁小一點」對用戶沒實際引導——用戶不知道該裁哪裡

**修復**:

1. `maxSizeBytes` 放寬：350KB → 1MB（3 張 × 1MB + JSON overhead 仍在 Claude API
   body limit 內）
2. 壓縮策略改 progressive fallback，6 階段：
   `(960, 78) → (960, 60) → (768, 60) → (768, 45) → (640, 45) → (640, 30)`
3. 全部超標時回傳「最小的版本」而非任意一次結果，讓 caller 可用「目前最佳」判斷
4. 錯誤訊息改成具體引導：「這張截圖內容太複雜（例如多張照片拼貼），請只截自介文字段落再試。」

**預防**:

- 新增壓縮策略時，要用「多張拼貼截圖」當 worst-case fixture 驗證
- 不在 mobile-only 本機環境（WSL）做最終 analyze；Codex review + 真機測試當閘門

**相關檔案**:

- `lib/shared/services/image_compress_service.dart`
- `lib/shared/widgets/image_picker_widget.dart`（錯誤訊息）

**不動範圍**:

- `lib/features/analysis/data/services/analysis_service.dart:228`（Edge Function
  回的 `Request body too large`，屬不同路徑）
- Edge Function 本身（L3 邊緣，未觸碰）

**Discord context**: 群組 `1487899618090946634`，Bruce 回報 message
`1497131529854521506`

---

## 2026-03

### [2026-03-15] 購買後 Tier 未同步到 Supabase — 截圖功能 Timeout

**症狀**:

- 測試帳號（白名單）截圖識別 8 秒成功
- 真實帳號（已購買訂閱）截圖識別永遠 timeout
- Edge Function 日誌顯示 `tier: "free"`，但用戶已購買 Essential

**Root Cause**:

1. RevenueCat 購買後，`_updateSupabaseTier()` 可能靜默失敗
2. Force Sync 按鈕呼叫 `getTierFromCustomerInfo()`，但 RevenueCat 可能返回
   `free`（entitlements 未正確設定）
3. Supabase 的 `subscriptions` 表中 tier 仍是 `free`
4. Edge Function 根據 `free` tier 檢查額度，15 則/天很快用完
5. 超過額度後返回 429，但前端沒有正確處理，導致 timeout

**修復**:

1. 臨時：手動 SQL 更新 tier
   ```sql
   UPDATE subscriptions SET tier = 'essential'
   WHERE user_id = (SELECT id FROM auth.users WHERE email = 'xxx@xxx.com');
   ```
2. 永久：
   - Force Sync 顯示 RevenueCat 詳細資訊，允許手動選擇 tier
   - `_updateSupabaseTier` 用 `select()` 驗證更新成功，失敗時 upsert
   - `forceSyncTier` 檢查記錄存在與否，不存在則 insert
   - `purchase` 流程從 product ID 推測 tier，重試 3 次同步

**預防**:

- RevenueCat Entitlements 必須正確關聯產品
- 購買後顯示同步結果，不要靜默失敗
- Edge Function 返回明確 429 錯誤，前端正確處理

**相關檔案**:

- `lib/features/subscription/data/providers/subscription_providers.dart`
- `lib/features/subscription/presentation/screens/paywall_screen.dart`

---

### [2026-03-14] Google Sign In Nonce 錯誤 + 空白頁面

**症狀**:

1. 使用 `google_sign_in` 套件 → Nonce 錯誤
2. 使用 `signInWithOAuth` → 空白頁面 / 一直轉圈圈不返回

**Root Cause**:

- `google_sign_in` 套件與 Supabase 的 nonce 處理不相容
- `signInWithOAuth` 在 iOS 上的 redirect 處理有問題

**修復**: 改用 `flutter_web_auth_2` 實現 ASWebAuthenticationSession（像 Claude
app）：

```dart
final result = await FlutterWebAuth2.authenticate(
  url: authUrl.toString(),
  callbackUrlScheme: 'com.poyutsai.vibesync',
  options: const FlutterWebAuth2Options(preferEphemeral: false),
);
```

**預防**:

- iOS OAuth 登入優先用 `flutter_web_auth_2`
- ASWebAuthenticationSession 提供最流暢的體驗
- Callback scheme 必須在 Info.plist 註冊

**相關檔案**: `lib/core/services/social_auth/social_auth_native.dart`

---

### [2026-03-14] RevenueCat 無法取得產品資訊

**症狀**: App 顯示「無法取得產品資訊」，RevenueCat Products 顯示 "Could not
check"

**Root Cause**: RevenueCat 有兩個 P8 key 設定區塊，只設定了一個：

1. **In-app purchase key configuration** — 已設定 ✅
2. **App Store Connect API** — 沒設定 ❌

且 App Store Connect API 需要 **App Manager 權限**的 Key，原本的 Subscription
Key 權限不夠。

**修復**:

1. App Store Connect → Users and Access → Integrations → **App Store Connect
   API** 建立新 Key
2. 權限選擇 **App Manager**
3. 下載 P8 檔案，命名為 `AuthKey_XXXXXX.p8`
4. 上傳到 RevenueCat 的 "App Store Connect API" 區塊
5. 填入 Key ID、Issuer ID、Vendor Number

**預防**:

- RevenueCat 設定時，兩個 P8 key 區塊都要設定
- In-App Purchase Key 和 App Store Connect API Key 是不同的 Key
- App Store Connect API Key 必須有 App Manager 權限

**關鍵資源**（見 `docs/integrations/revenuecat.md`）

---

### [2026-03-12] warnings 欄位型別轉換錯誤

**症狀**: 解析 Edge Function 回應失敗 **Root Cause**: `warnings` 可能是 String
或 Object 陣列，直接 cast 會失敗 **修復**:

```dart
final rawWarnings = json['warnings'] as List? ?? [];
final warnings = rawWarnings.map((w) => w is String ? w : w.toString()).toList();
```

**相關檔案**: `lib/features/analysis/domain/entities/analysis_models.dart:362`

---

### [2026-03-12] 付費用戶看到升級提示

**症狀**: 付費用戶在某些情境只收到延展回覆，卻看到「升級解鎖」提示 **Root
Cause**: UI 判斷邏輯只看「是否只有 extend」，沒考慮 tier **修復**: 依 tier
顯示不同提示

- Free：「升級解鎖共鳴、調情、幽默、冷讀等回覆風格」
- 付費：「AI 判斷此情境最適合使用延展回覆」

**相關檔案**:
`lib/features/analysis/presentation/screens/analysis_screen.dart:1515-1565`

---

### [2026-03-12] 測試帳號功能被限制為 Free tier

**症狀**: 測試帳號看到「升級解鎖共鳴、調情...」提示，只有延展回覆 **Root
Cause**: Edge Function 從資料庫讀 tier，資料庫可能設定錯誤 **修復**:
測試帳號強制使用 essential tier 功能

```javascript
const effectiveTier = isTestAccount ? "essential" : sub.tier;
```

**相關檔案**: `supabase/functions/analyze-chat/index.ts:750`

---

### [2026-03-06] Slack 通知失敗導致整個 workflow 失敗

**症狀**: TestFlight 上傳成功，但 workflow 顯示失敗 **Root Cause**: Slack
webhook URL 無效時 Fastlane 會拋錯，中斷整個 lane **修復**:

```ruby
begin
  slack(...)
rescue => e
  UI.important("Slack failed (non-fatal): #{e.message}")
end
```

**預防**: 選用性通知用 `begin/rescue` 包住 **相關檔案**: `ios/fastlane/Fastfile`

---

### [2026-03-06] TestFlight 拒絕重複 build number

**症狀**:
`The bundle version must be higher than the previously uploaded version: '1'`
**Root Cause**: TestFlight 要求 build number 遞增，但 Flutter 預設吃
pubspec.yaml 版本 **修復**:
`flutter build ipa --release --build-number=${{ github.run_number }}` **預防**:
CI 永遠用 `github.run_number` 作為 build number **相關檔案**:
`.github/workflows/release.yml`

---

### [2026-03-06] Fastfile 找不到 IPA 檔案

**症狀**: `No IPA found in ../build/ios/ipa` **Root Cause**: Fastfile 用相對路徑
`../build/ios/ipa`，工作目錄不固定 **修復**:

```ruby
project_root = File.expand_path("../../..", __FILE__)
ipa_dir = File.join(project_root, "build", "ios", "ipa")
```

**預防**: Fastfile 永遠用 `__FILE__` 計算絕對路徑 **相關檔案**:
`ios/fastlane/Fastfile`

---

### [2026-03-06] App Store 拒絕上傳：MinimumOSVersion 缺失

**症狀**:
`Invalid MinimumOSVersion. MinimumOSVersion in 'Runner.app/Frameworks/App.framework' is ''`
**Root Cause**: Flutter 預設的 `AppFrameworkInfo.plist` 缺少 `MinimumOSVersion`
**修復**: 在 `ios/Flutter/AppFrameworkInfo.plist` 加入：

```xml
<key>MinimumOSVersion</key>
<string>13.0</string>
```

**預防**: Flutter 專案檢查 `AppFrameworkInfo.plist` 是否有 `MinimumOSVersion`
**相關檔案**: `ios/Flutter/AppFrameworkInfo.plist`

---

### [2026-03-06] GitHub Actions iOS Code Signing 失敗

**症狀**: `No profile for team 'TTQHTVG8CC' matching 'VibeSync App Store' found`
**Root Cause**:

1. `PROVISIONING_PROFILE_SPECIFIER` 用 profile **名稱**匹配
2. Xcode 在 CI 安裝 profile 用 **UUID** 作檔名
3. 名稱匹配找不到已安裝 profile

**修復**:

1. 分離 `flutter build ios --no-codesign` 和 `xcodebuild archive`
2. `PROVISIONING_PROFILE=UUID` 直接指定（非名稱）
3. 從 profile 提取
   UUID：`security cms -D -i profile.mobileprovision | PlistBuddy -c "Print :UUID"`
4. 動態產生 ExportOptions.plist 使用 UUID

**預防**:

- iOS CI 簽名永遠用 UUID，不用名稱
- 加入充分除錯輸出（證書列表、profile UUID/Name/TeamID）

**相關檔案**:

- `.github/workflows/release.yml`
- `ios/Runner.xcodeproj/project.pbxproj`
- `ios/ExportOptions.plist`

---

### [2026-03-06] 分析失敗錯誤訊息太籠統

**症狀**: 所有錯誤都顯示 "Network error" 或 minified 錯誤碼 **修復**:

1. 移除 `dart:io`（Web 不支援）
2. 顯示完整錯誤類型和訊息以便除錯
3. 新增自動重試（最多 2 次）
4. 新增 60 秒 timeout

**相關檔案**:

- `lib/features/analysis/data/services/analysis_service.dart`
- `lib/core/services/supabase_service.dart`

---

### [2026-03-06] Edge Function 變數重複宣告導致 Boot Failure

**症狀**: 點擊分析後顯示 "Failed to fetch"，Edge Function 完全無法啟動 **Root
Cause**: `actualModel` 變數在同一 scope 宣告兩次（line 717 和 762） **修復**:
第一個 `actualModel` 改名為 `selectedModel` **預防**: 新增變數前先
`grep "const\|let" <name>` 確認無同名 **相關檔案**:
`supabase/functions/analyze-chat/index.ts:717`

---

### [2026-03-01] 熱度分析受用戶發言影響

**症狀**: 熱度分數因用戶自己話多而升高 **Root Cause**: AI
沒明確指示只從對方回覆判斷熱度 **修復**: System Prompt
新增「熱度分析規則」，明確列出只從「她」的訊息判斷：回覆長度、表情符號、主動提問、話題延伸、回應態度
**相關檔案**: `supabase/functions/analyze-chat/index.ts:88-95`

---

## 2026-02

### [2026-02-28] Edge Function CORS 錯誤

**症狀**: Flutter web 顯示 "Failed to fetch" **Root Cause**: 錯誤回應沒有 CORS
headers **修復**: 新增 `jsonResponse()` helper，所有回應包含 CORS headers
**相關檔案**: `supabase/functions/analyze-chat/index.ts:193-205`

---

### [2026-02-28] Claude 模型名稱過期

**症狀**: Edge Function 回傳 "model not found" **Root Cause**: Claude 3.5
模型已停用 **修復**:

- `claude-3-5-haiku-20241022` → `claude-haiku-4-5-20251001`
- `claude-sonnet-4-20250514` 保持不變 **相關檔案**:
  `supabase/functions/analyze-chat/index.ts:190`

---

### [2026-02-28] 每次開對話都自動分析

**症狀**: 進入對話頁就自動呼叫 API 分析，浪費額度 **修復**:
改為手動觸發，新增「開始分析」按鈕 **相關檔案**:
`lib/features/analysis/presentation/screens/analysis_screen.dart:71`

---

### [2026-02-28] iOS Safari Pull-to-refresh 關閉頁面

**症狀**: iOS Safari 上下滑動時整個網頁被關閉 **Root Cause**: iOS Safari
pull-to-refresh 手勢觸發頁面關閉 **修復**:

1. `web/index.html` 加 JS 防頂部下拉默認行為
2. `overscroll-behavior: none` CSS
3. Flutter 端用 `ClampingScrollPhysics` + `ScrollConfiguration`

**相關檔案**:

- `web/index.html`
- `lib/features/analysis/presentation/screens/analysis_screen.dart:452-458`
