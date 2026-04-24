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
| `flutter_web_auth_2` 套件 | v4.0.1（ASWebAuthenticationSession） |
| Callback Scheme | `com.poyutsai.vibesync://login-callback` |

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
