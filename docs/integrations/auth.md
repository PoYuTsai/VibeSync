# Third-Party Login 整合

> Apple + Google Sign In 配置與除錯歷史。
>
> 兩者都透過 Supabase Auth，iOS OAuth 都走 `flutter_web_auth_2` (ASWebAuthenticationSession)。

---

## Apple Sign In

| 項目 | 狀態 | 備註 |
|------|------|------|
| Supabase Apple Provider | ✅ | Client ID: `com.poyutsai.vibesync` |
| Xcode Entitlements | ✅ | `ios/Runner/Runner.entitlements` |
| `sign_in_with_apple` 套件 | ✅ | v7.0.1 |
| LoginScreen 按鈕 | ✅ | 黑底白字 Apple 風格 |

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
  `CallbackActivity`（manifest 宣告）；MainActivity 不得重複宣告同
  scheme，否則會跳 activity 選擇器導致 OAuth 回不了 App。
- 已知缺口：Android 密碼重設等 email 深連結共用同一 redirect URI，會落在
  `CallbackActivity` 被吞掉——屬 AUTH-01（Slice 3）處理範圍。
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

## 驗證清單

- [x] Apple Sign In 完整流程
- [x] Google Sign In 完整流程（`flutter_web_auth_2` + ASWebAuthenticationSession）
- [x] 新用戶自動建立 subscription
- [x] 登出後重新登入

---

## 相關檔案

- `lib/core/services/social_auth/social_auth_native.dart` — `signInWithApple()` / `signInWithGoogle()`
- `lib/features/auth/presentation/screens/login_screen.dart` — 登入按鈕 UI
- `ios/Runner/Runner.entitlements` — Sign in with Apple capability
- `ios/Runner/Info.plist` — Google URL Scheme + callback scheme
