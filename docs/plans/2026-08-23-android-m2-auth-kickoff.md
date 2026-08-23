# Android M2 Auth Kickoff（Frozen Code Tranche）

> 日期：2026-08-23（Asia/Taipei）
> Base：`fc83aaec1c7398a93efe09c812cc9d6591a373b9`
> Branch：`codex/android-m2-auth-20260823`
> 角色：Luna Max＝coding owner；Codex＝coordinator／main reviewer
> Delivery：只在 Android M2 分支實作、驗證與審查；本 tranche 不合入 `main`

## 來源與目標

本 tranche 落實 Frozen Spec v1 的 `AUTH-01`、`AUTH-02`，並延續 M1 已凍結的
`AND-03` OAuth callback 契約。若本文件與下列文件衝突，依序以前者為準：

1. `docs/plans/2026-08-21-android-public-release-roundtable-spec.md`
2. `docs/plans/2026-08-21-android-public-release-implementation-plan.md`
3. 本文件

目標是產出可審查、可建置的 M2 code candidate：Android 以 Google／Email 為
主要登入方式，另以清楚的次要入口讓既有 iPhone Apple 帳號走 web OAuth；
Email 註冊驗證與密碼重設不得再被 OAuth 專用 CallbackActivity 吞掉。

## 凍結範圍

1. Android 登入頁：
   - Google 與 Email 是主要入口。
   - Apple 顯示為次要入口，文案必須明示「已有 iPhone VibeSync 帳號」。
   - iOS 既有 Google 與原生 Apple 入口、排序與行為不得回歸。
2. OAuth：
   - Google 延用 Supabase OAuth＋`flutter_web_auth_2`。
   - Android Apple 使用 Supabase Apple web OAuth＋`flutter_web_auth_2`。
   - iOS Apple 保留 `sign_in_with_apple` 原生 token flow。
   - OAuth callback 仍為 `com.poyutsai.vibesync://login-callback`，且 Android
     唯一 owner 仍是 `CallbackActivity`。
3. Email callback 分流：
   - Email sign-up、resend confirmation 與 password recovery 使用獨立 URI。
   - Android 的獨立 URI 只能由 `MainActivity` 接收；不得與 OAuth host 產生
     chooser 或把 OAuth callback 交給 MainActivity。
   - URI 必須有機器可讀 contract，Dart、Manifest、Supabase local config、
     contract tests 與 Android gate scripts 共用同一真相源。
4. 錯誤語意：使用者取消不顯示成失敗；真正失敗可重試且有繁中訊息；錯 host／
   scheme fail closed，不得建立 session。
5. 文件：更新 auth integration runbook，列出 Apple Services ID、primary App ID、
   Supabase client ID 順序／return URL、Hide My Email same-user 驗證與最長六個月
   client secret 輪替步驟；不得記錄 secret 值。

## 非目標與授權邊界

- 不修改 Apple Developer、Google Cloud、Supabase Dashboard、Play Console、
  GitHub Secrets 或任何 credential。
- 不自動合併／連結兩個 Supabase user，不修改 production 使用者資料。
- 不處理 Billing、RevenueCat、18+、AI keyboard、Edge Function 或 migration。
- 不合 `main`、不觸發 Store release、不送審。
- 不宣稱 live Google／Apple／Hide My Email continuity 已通過，除非取得 exact
  build＋真實帳號／裝置證據。

## 實作順序與測試

1. 先加 failing tests：平台入口政策、OAuth provider／callback 驗證、Email 與
   OAuth ownership、Android Manifest／gate scripts、iOS 不變式。
2. 實作最小 platform-aware auth coordinator 與登入頁差異。
3. 新增 Email callback contract，接通 sign-up／resend／recovery，更新 Manifest、
   local Supabase config 與既有 Android gates。
4. 更新 runbook，再跑 focused tests、M2 範圍 analyze、完整 Flutter tests、
   `git diff --check`；需要 artifact 的命令全部在 WSL。
5. Luna 提交 task-owned commits；Codex 對 exact commit 做主審。Auth 屬 material
   R2，最終仍須獨立 read-only challenge；最多兩輪修正／重審。

## Exit 與狀態語意

### M2 code candidate

- Android UI／OAuth／Email callback contract 與負向測試完成。
- focused＋full tests、analyze、Android manifest gates 與雙平台 build evidence 通過。
- exact commit 已 review，無未解 P0／P1／P2。

### M2 完成

除 code candidate 外，還需要 Eric 授權的外部設定與真實證據：

- Android Google 成功／取消／失敗／重試，iOS 既有 Google 帳號回同一
  `auth.users.id`。
- Android Apple web flow（含 Hide My Email）回到 iOS Apple 原帳號的同一
  `auth.users.id`；若產生第二個 user，立即隱藏 Android Apple 入口，不做自動合併。
- Email 註冊驗證與 password recovery 在 Android 真實 callback 上成功。

在這些 live gate 完成前，只能稱 M2 code candidate，不稱完整 M2 完成。
