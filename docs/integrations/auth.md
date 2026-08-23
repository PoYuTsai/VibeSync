# Third-Party Login 整合

> Apple + Google Sign In 配置與除錯歷史。本文只記錄無 secret 的設定順序與
> 可重現檢查；不把 Console 設定或 live same-user 驗證當成 code candidate 證據。
>
> Google 兩平台與 Android Apple web flow 透過 Supabase Auth＋
> `flutter_web_auth_2`；iOS Apple 保留 `sign_in_with_apple` 原生 token flow。

---

## Apple Sign In

| 項目 | 狀態 | 備註 |
|------|------|------|
| Supabase Apple Provider | M2 external pending | Client IDs（有序完整保留）：`[Services ID first, com.poyutsai.vibesync native App ID later]`；provider／client secret live 對帳待授權 |
| Xcode Entitlements | ✅ | `ios/Runner/Runner.entitlements` |
| `sign_in_with_apple` 套件 | ✅ | v7.0.1 |
| LoginScreen 按鈕 | ✅ | 黑底白字 Apple 風格 |

### Android Apple web flow（M2 code candidate）

- Android Apple 是次要入口，文案必須明示「已有 iPhone VibeSync 帳號」。
- Android 走 Supabase Apple OAuth，callback 仍是
  `com.poyutsai.vibesync://login-callback`，唯一 Android owner 是
  `com.linusu.flutter_web_auth_2.CallbackActivity`。
- iOS 的 Apple 原生 token flow 不改；這個 code candidate 沒有宣稱 Apple
  Services ID、Hide My Email 或 same-user live gate 已通過。

---

## Google Sign In

| 項目 | 值 |
|------|-----|
| Google Cloud Project | VibeSync |
| iOS OAuth Client ID | `568378103108-ptl0icvkk7v2vp6ob21hatm73unokg52.apps.googleusercontent.com` |
| Web OAuth Client ID | `568378103108-3nsc1ecskfpod51dqgko2d7g2q7pccad.apps.googleusercontent.com` |
| Supabase Google Provider | ✅（Client ID + Secret） |
| `flutter_web_auth_2` 套件 | v4.1.0（ASWebAuthenticationSession） |
| Callback Scheme | `com.poyutsai.vibesync://login-callback` |

### Android callback 契約（AND-03，Slice 2 凍結）

機器可讀唯一真相源：`contracts/auth-callback.json`。

- OAuth callback 兩平台都凍結在 `com.poyutsai.vibesync://login-callback`
  （既有 Supabase Redirect URLs allowlist 條目，免新增）。
- Android 端該 URI 的唯一擁有者是 `flutter_web_auth_2` 4.1.0 的
  `CallbackActivity`（manifest 宣告）；MainActivity 不得宣告 OAuth host，
  否則會跳 activity 選擇器導致 OAuth 回不了 App。
- Email signup confirmation、resend confirmation、password recovery 共用
  獨立的 machine-readable contract：`contracts/email-auth-callback.json`。
  base URI 是 `com.poyutsai.vibesync://email-callback`，Android 唯一 owner
  是 `MainActivity`；不得把它加到 OAuth `CallbackActivity`，也不得讓其他
  activity／alias 搶走，否則 gate 會 fail closed。
- 三個寄信入口使用固定 machine-readable flow path：signup／resend 使用
  `com.poyutsai.vibesync://email-callback/signup`，password reset 使用
  `com.poyutsai.vibesync://email-callback/recovery`。
  Supabase Redirect URLs 使用 glob 語意，其中 `?` 是單字元 wildcard；因此
  flow provenance 放在 exact path，不放在 query，避免 allowlist 被錯解。
  `AppConfig`、`supabase/config.toml`、Android gate 與 contract tests 必須
  對帳這兩個 exact allowlist entries；不保留 bare Email URI 作為寄信
  redirect。flow path 只選擇失敗後的 retry 文案／操作，不能證明 session 或
  recovery；PKCE code 交換與 Supabase accepted auth event 才是權威。
- Email callback 若 flow path 缺失、未知、額外或錯誤，native listener 會
  fail closed，不 exchange、不改 auth state，也不發布 retry failure。Supabase
  error redirect 可沒有 `type=recovery`；不可把 raw `type` 當 provenance。
  Supabase Auth 仍會驗證 code／error；錯 scheme、host、path 或沒有有效 auth
  payload 不得建立 session。
- Native 端關閉 Supabase 的寬鬆 URI auto-detect；`app_links` 只把 exact Email
  callback 且帶 code／error payload 的連結交給 `getSessionFromUrl`。OAuth
  callback 不走這條 listener，仍只由 `flutter_web_auth_2` 回傳給社群登入流程。
- iOS 維持 ASWebAuthenticationSession 單一 `login-callback`，行為不變。
- 證據邊界：CI 的 install smoke（synthetic VIEW intent）只驗 callback
  routing（唯一擁有者、無 chooser）與 process stability（同 PID、不
  crash），**不等於**已驗證 `FlutterWebAuth2.authenticate` 收到 OAuth
  結果；live Google OAuth 完成流程屬實機驗證證據（AUTH-01／QA 階段）。

### Info.plist 配置
- 加入 reversed iOS client ID 作為 URL Scheme
- 加入 `com.poyutsai.vibesync` callback scheme

---

## 為什麼用 flutter_web_auth_2，不用原生 SDK

見 `docs/bug-log.md#2026-03-14-google-sign-in`。速查：

1. ❌ `google_sign_in` 套件：與 Supabase nonce 處理不相容
2. ❌ `signInWithOAuth`：iOS 空白頁 / 轉圈圈不返回
3. ✅ **`flutter_web_auth_2` + ASWebAuthenticationSession**：流暢穩定（Claude app 也是這做法）

### 關鍵實作

```dart
final result = await FlutterWebAuth2.authenticate(
  url: authUrl.toString(),
  callbackUrlScheme: 'com.poyutsai.vibesync',
  options: const FlutterWebAuth2Options(
    preferEphemeral: false, // 使用共享 Safari cookies，體驗更好
  ),
);
```

---

## 新用戶流程

Apple / Google 登入成功後：
1. Supabase Auth 建立新 user（若首次登入）
2. 自動建立 `subscriptions` 記錄（tier = `free`）
3. 導向首頁（新用戶觸發三步引導卡片）

---

## No-secret 外部設定 runbook（授權後才執行）

以下是 Eric 取得外部設定授權後的對帳順序。不要把 client secret、private
key、JWT、完整 callback response、Email 或真實 user ID 寫入 repo、issue、
log 或本文件；只留遮罩後的名稱／fingerprint 與 pass/fail 結果。

### Apple：Services ID、primary App ID、Supabase

1. 在 Apple Developer 先確認 primary App ID 是現有 iOS App ID
   `com.poyutsai.vibesync`，並確認 Sign in with Apple capability 已啟用。
2. 再確認 Apple Services ID（Android web flow 使用的 client ID）已正確
   關聯該 primary App ID；不要把 Services ID、Bundle ID 與 Team ID 互相
   猜成同一個值。
3. 以 Apple Developer 顯示的 Services ID 對照 Supabase Apple provider 的
   Client IDs 欄位；欄位必須完整保留有序清單
   `[Services ID first, com.poyutsai.vibesync native App ID later]`。第一個
   Services ID 供 Android web OAuth 使用；iOS 原生
   `signInWithIdToken` 可接受清單內任一 audience，不能把後面的 native App ID
   移除或誤替換成 Services ID。
4. 在 Supabase provider／Apple Service 設定中分層對照 URL：Apple 的 return
   URL 是 Supabase Dashboard 顯示的 **Supabase HTTPS callback**（provider
   層）；App 的 `com.poyutsai.vibesync://login-callback` 與兩個 marked
   Email URI (`.../signup`／`.../recovery`) 是 **App custom redirect**，
   只放在 Supabase Auth redirect allowlist（App 層），
   不可把 custom URI 填成 Apple return URL，也不可混用兩個 callback。
5. Hide My Email 必須用一個既有 iOS Apple 帳號做受控 live test，核對
   Android web flow 回到同一 Supabase `auth.users.id`。這是外部 gate，M2
   code candidate 不得宣稱已完成；若出現第二個 user，立即隱藏 Android
   Apple 入口並停止，不做自動合併或改資料。

### Apple client secret 輪替（最長六個月）

- 以 secret manager 保存 Apple client secret 的值；repo 只記 secret name、
  產生／到期月份與遮罩 fingerprint，不記明文。
- 最晚每六個月建立新 secret，先在受控窗口更新 Supabase provider，做取消、
  callback error／retry 與既有帳號驗證，再撤銷舊 secret。
- 輪替前後只保留無 secret 的變更紀錄：provider 設定已更新、舊值已撤銷、
  live gate pass/fail 與 exact build SHA；不得把 JWT 或 Apple response 貼到
  ticket。

### Google／Supabase 對齊

- Google Cloud OAuth client ID、Supabase Google provider client ID 與預期的
  web client ID 必須逐字對照；只核對 ID／project／redirect metadata，不在
  repo 保存 client secret。
- Supabase provider 的 callback、App 的
  `com.poyutsai.vibesync://login-callback`、`contracts/auth-callback.json`、
  Android merged manifest 必須全部一致；錯 host／scheme 不得以放寬 allowlist
  的方式修復。
- 先以取消、provider error、callback timeout、重試驗證狀態機，再做同一個
  iOS Google 帳號跨平台 live same-user gate。只有 exact build＋受控帳號／裝置
  證據才算完成；本文件和本 M2 code candidate 不提供該證據。

---

## 驗證清單

- [x] Apple／Google code path 與取消、錯誤、重試文案已覆蓋
- [x] Google OAuth callback（`flutter_web_auth_2` + ASWebAuthenticationSession）
- [x] Android Apple Supabase web OAuth code path（外部 Console／same-user gate 待授權）
- [x] Email signup／resend／recovery callback contract、Manifest owner 與 local allowlist
- [x] 新用戶自動建立 subscription
- [x] 登出後重新登入
- [ ] Android／iOS 實機 Google same-user live evidence
- [ ] Android Apple（含 Hide My Email）same-user live evidence
- [ ] Android Email confirmation／password recovery live callback evidence

---

## 相關檔案

- `lib/core/services/social_auth/social_auth_native.dart` — `signInWithApple()` / `signInWithGoogle()`
- `lib/features/auth/presentation/screens/login_screen.dart` — 登入按鈕 UI
- `ios/Runner/Runner.entitlements` — Sign in with Apple capability
- `ios/Runner/Info.plist` — Google URL Scheme + callback scheme
