# VibeSync Bug Log

> 歷史 bug 記錄與修復說明。新 bug 遇到時在這裡新增，**不寫進 CLAUDE.md**。
>
> 格式：`#### [YYYY-MM-DD] 標題` → 症狀 / Root Cause / 修復 / 預防 / 相關檔案
>
> 目前 Common Pitfalls（仍會踩）請看 `CLAUDE.md`，那裡只保留**現役陷阱**。

---

## 2026-05

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
