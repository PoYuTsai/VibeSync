# 拆訪客模式＋起步清單 3 項＋抽卡獎勵改造（2026-08-01）

> 真相源。三批各自獨立可審可交付。決策人：Eric（與 Bruce 討論拍板）。

## 背景與拍板

- 訪客模式（批 B，ADR #33）上線後內測討論：Bruce 主張「免費額度是製造稀缺的工具，不付錢的再多送也不會付」；Eric 拍板**整個移除訪客模式**，先前訪客額度／註冊禮 A/B/C 討論全部作廢。
- 起步清單 4→3：移除「開啟跟進提醒」項（**設定頁的跟進提醒功能本身保留**）。
- 抽卡獎勵改造（**A 案**）：free 每日免費抽 1 次砍掉；改為「起步清單全部完成 → 送一次性免費抽卡」，全 tier 適用；**starter 每日 3 抽／essential 每日 5 抽保留**（訂閱權益）；付費加抽（5 則/次）不動。
- Android 無鍵盤項：完成該平台可見的全部項目（Android＝2 項）即送。
- 老用戶一視同仁：已完成者更新後即可領；不做排除。
- 內測階段（僅 Eric/Bruce），拆除一刀到位：client＋server＋config 同批；**Eric 已授權刪 prod 匿名帳號**。

## 批 1：拆訪客模式

盤點真相源＝本檔撰寫當日的 Explore 盤點（觸點 ~40 檔）。要點：

### 1a Client
- 登入頁「先逛逛」按鈕＋`_continueAsGuest()`（login_screen.dart:934-942, 563-595）。
- `/register` 路由＋RegisterScreen 整條（僅訪客可達；**保留**登入頁自己的 `_isSignUp` 註冊路徑，勿混淆）。
- `GuestSessionVault`＋`GuestSignInFlow` 整檔；SupabaseService 的 `isGuestUser`/`signInAnonymously`/`signInAsGuest`/vault 掛載/轉正三路（linkApple/linkGoogle/registerGuestWithEmail）。
- social_auth 只刪 `linkAppleIdentity`/`linkGoogleIdentity`；`signInWithApple/Google` 是登入主路徑勿動。
- `SubscriptionState.isGuest` 欄位（呼叫端最廣）：`effectiveMonthly/DailyLimit` getter 保留但去 guest 分支（低風險路線）；`_authGuestSync` 訂閱連 dispose 清掉。
- `AppConstants.guestTotalLimit`、usage_service `skipResets`/`debugIsGuestOverride`。
- UI 訪客分支：home_quota_strip（訪客文案/sheet）、streaming_analysis_loading_widgets isGuest 變體、analysis_screen 三處、settings_screen 四處（含剛上的訪客跟進提醒說明 sheet e2f642ef——變死碼一併拆）。
- `resolveAppRedirect` 簽名去 `isAnonymous`；訪客 /paywall 與 /register 分支刪。
- 埋點：funnel_tracker 白名單三事件（guest_mode_enter / guest_register_view / guest_register_success）。
- `flutter_secure_storage` 套件**保留**（keyboard_token_bridge、storage_service 共用）。
- Dart 測試同批：guest_session_vault_test 整檔刪、redirect_matrix、funnel_tracker 鍵級鎖、subscription_state、usage_service snapshot、home_quota_strip、settings_screen、streaming widgets、register_screen_test 整檔刪、onboarding_gate_router 簽名。

### 1b Server
- `_shared/quota.ts`：`GUEST_TOTAL_LIMIT`/`isAnonymousAuthUser`/`noResetResult` 刪；`resolveLimits`/`quotaExceededMessage`/`buildQuotaExceededPayload` 去 anonymous 參數（函式本體共用保留）。
- 六支 Edge：coach-chat、coach-follow-up、keyboard-reply、keyboard-assist、practice-chat（handler＋draw_handler）、analyze-chat。**注意**：匿名分支散在 CAS retry 內；analyze-chat 自帶三層 reset 閘（`!anonymous && !sameUtcDay` → 拿掉 `!anonymous &&` 語意才對）＋四組 limits 重算＋五處 payload。
- funnel_utils 字典：三 guest 事件＋source/method PropSpec 移除（**鐵則：Edge/client/鍵級鎖測試三處同批**）。
- `config.toml`：`enable_anonymous_sign_ins=false`、`enable_manual_linking=false`、匿名 rate limit 段刪。
- Migration：新增 `CREATE OR REPLACE` 拿掉 `prepare_practice_subscription_usage` 的 `v_is_anonymous` 判斷（不可直接刪 20260801120000 檔）；`20260801130000` email DROP NOT NULL **不可回退**（匿名 row email 為 NULL），留著無害。
- Deno 測試同批：quota_test 訪客原語、各 index_test guest 條目、三個 source-string 斷言檔（analyze-chat index_test:2542-2592、keyboard-reply/keyboard-assist index_source_test）、migration_source_test、draw_handler_test 訪客條。

### 1c Prod 收尾（targeted migration 程序，絕不 db push）
1. 新 RPC migration 上 prod＋帳本對齊。
2. Management API PATCH `external_anonymous_users_enabled=false`（`security_manual_linking_enabled` 一併關）。
3. 刪匿名帳號：先 `SELECT count(*), ...` 確認 `auth.users where is_anonymous`，再刪（cascade 清 public 三表）。Eric 已授權。

### 風險
- 舊 build（378/379）按「先逛逛」會失敗：內測可接受，Eric 知情。
- funnel_events 既有 guest rows 保留不刪（歷史資料）。

## 批 2：起步清單 4→3
- getting_started_checklist.dart 移除 follow_up 項與其 provider 讀取；測試同批改。
- 清單語意：iOS 3 項（關於我／首次分析或練習／AI 鍵盤）、Android 2 項。

## 批 3：抽卡獎勵改造（A 案，高風險走 Codex 審）
- Server：`PRACTICE_DRAW_FREE_ALLOWANCE` free 1→0（starter 3/essential 5 不動；free `paidExtraDrawAllowedForTier` 仍 false）。
- 贈抽機制（一次性、跨窗）：新表（user_id 唯一、granted_at/consumed_at/source='getting_started'）＋grant RPC（冪等）＋draw 路徑消耗：Edge 在 `drawAllowanceForTier(tier)` 之外檢查未消耗贈抽 → 該抽 cost=0 並標記消耗。抄 `refine_free_allowance` 的冪等鍵形狀。留意 ledger `UNIQUE(user_id, window, profile_id)` 與 `MAX_DRAW_SELECT_ATTEMPTS=3`。
- Grant 觸發：client 起步清單全勾時呼叫 grant（best-effort＋冪等；信任 client 宣稱，濫用面＝一抽，可接受）。
- UI：清單全勾 → 卡片變身「🎉 起步完成！送你一次免費抽卡」＋「去抽卡」CTA（導 /practice-collection）；贈抽消耗後卡片永久消失。老用戶回溯靠同一機制自然呈現。
- 文案誠實化：free 用戶不再有每日抽 →「每日翻牌解鎖」「每日登入解鎖新女孩」等文案對 free 需改（付費 tier 仍為真）；402 文案檢查。
- 驗證：Deno draw 測試、PG smoke、client widget 測試；Codex 對抗式審。

## 交付
- 每批：analyze＋相關測試綠 → commit（繁中、一事一 commit）→ push main → 盯 Build & Distribute。
- iOS build 由 Eric 手動 dispatch。
- CLOSE gate：Eric/Bruce 真機——註冊登入正常、無先逛逛入口、清單 3 項、全勾領獎卡、贈抽一次、starter/essential 每日抽不變。
