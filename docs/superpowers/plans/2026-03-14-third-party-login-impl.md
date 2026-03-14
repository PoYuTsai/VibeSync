# Third-Party Login Implementation Plan

> Apple Sign In + Google Sign In for iOS

## Overview

根據設計規格 `docs/superpowers/specs/2026-03-14-third-party-login-design.md` 實作第三方登入功能。

**總任務數**: 15 個
**Phase 1**: Apple Sign In (Task 1-6)
**Phase 2**: Google Sign In (Task 7-12)
**Phase 3**: 收尾 (Task 13-15)

---

## Phase 1: Apple Sign In

### Task 1: Supabase Apple Provider 設定

**目標**: 在 Supabase 啟用 Apple 登入

**步驟** (手動):
1. 登入 Supabase Dashboard
2. 進入 Authentication → Providers → Apple
3. 啟用 Apple Provider
4. 填入必要資訊：
   - **Enabled**: ON
   - 其他欄位依 Supabase 文件填寫

**驗證**: Supabase Dashboard 顯示 Apple Provider 已啟用

**備註**: Apple Native Sign In 不需要在 Supabase 設定 Service ID 等，iOS 會直接處理

---

### Task 2: Xcode Sign in with Apple Capability

**目標**: 在 Xcode 專案啟用 Sign in with Apple

**步驟** (手動):
1. 打開 `ios/Runner.xcworkspace`
2. 選擇 Runner target
3. Signing & Capabilities tab
4. 點擊 `+ Capability`
5. 搜尋並加入 `Sign in with Apple`

**驗證**:
- Xcode 顯示 Sign in with Apple capability
- `ios/Runner/Runner.entitlements` 自動產生或更新

---

### Task 3: AuthService 新增 signInWithApple()

**目標**: 實作 Apple 登入方法

**檔案**: `lib/core/services/supabase_service.dart`

**實作內容**:
```dart
/// Apple Sign In
Future<AuthResponse> signInWithApple() async {
  return await _client.auth.signInWithApple();
}
```

**依賴**: Task 1, 2 完成

---

### Task 4: 新用戶 Subscription 自動建立

**目標**: 第三方登入的新用戶自動建立 Free subscription

**檔案**: `lib/features/auth/data/providers/auth_providers.dart` 或新增 helper

**實作邏輯**:
```dart
Future<void> ensureSubscriptionExists(String userId) async {
  final existing = await supabase
    .from('subscriptions')
    .select()
    .eq('user_id', userId)
    .maybeSingle();

  if (existing == null) {
    await supabase.from('subscriptions').insert({
      'user_id': userId,
      'tier': 'free',
      'monthly_messages_used': 0,
      'daily_messages_used': 0,
      'started_at': DateTime.now().toIso8601String(),
    });
  }
}
```

**依賴**: Task 3 完成

---

### Task 5: LoginScreen 新增 Apple 登入按鈕

**目標**: 更新登入頁 UI，加入 Apple 登入按鈕

**檔案**: `lib/features/auth/presentation/screens/login_screen.dart`

**UI 規格**:
- 位置：最上方
- 風格：黑底白字 (Apple HIG 規範)
- 圖示：Apple Logo
- 文字：「使用 Apple 登入」

**實作內容**:
```dart
// Apple Sign In Button (黑底白字)
ElevatedButton.icon(
  onPressed: _signInWithApple,
  icon: const Icon(Icons.apple, color: Colors.white),
  label: const Text('使用 Apple 登入'),
  style: ElevatedButton.styleFrom(
    backgroundColor: Colors.black,
    foregroundColor: Colors.white,
    minimumSize: const Size(double.infinity, 50),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
  ),
),
```

**依賴**: Task 3, 4 完成

---

### Task 6: Apple Sign In 測試

**目標**: 在 TestFlight 驗證 Apple 登入完整流程

**測試案例**:
1. [ ] 新用戶 Apple 登入 → 自動建立 subscription
2. [ ] 既有用戶 Apple 登入 → 正常進入首頁
3. [ ] 用戶取消登入 → 停留在登入頁
4. [ ] 登出後重新登入 → 正常運作

**驗證**:
- Supabase auth.users 有新記錄
- subscriptions 表有對應記錄
- App 正常導向首頁

**依賴**: Task 5 完成，需 TestFlight build

---

## Phase 2: Google Sign In

### Task 7: Google Cloud Console OAuth Client

**目標**: 建立 Google OAuth Client ID

**步驟** (手動):
1. 登入 Google Cloud Console
2. 建立新專案或選擇現有專案
3. APIs & Services → Credentials
4. Create Credentials → OAuth client ID
5. Application type: iOS
6. Bundle ID: `com.poyutsai.vibesync`
7. 記下 Client ID

**產出**:
- iOS Client ID
- Reversed Client ID (URL Scheme 用)

---

### Task 8: Supabase Google Provider 設定

**目標**: 在 Supabase 啟用 Google 登入

**步驟** (手動):
1. 登入 Supabase Dashboard
2. Authentication → Providers → Google
3. 啟用並設定：
   - Client ID (from Task 7)
   - Client Secret (from Google Cloud Console)

**驗證**: Supabase Dashboard 顯示 Google Provider 已啟用

---

### Task 9: Xcode URL Scheme 設定

**目標**: 加入 Google Sign In 所需的 URL Scheme

**檔案**: `ios/Runner/Info.plist`

**新增內容**:
```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>com.googleusercontent.apps.{CLIENT_ID}</string>
    </array>
  </dict>
</array>
```

**依賴**: Task 7 完成 (需要 Client ID)

---

### Task 10: AuthService 新增 signInWithGoogle()

**目標**: 實作 Google 登入方法

**檔案**: `lib/core/services/supabase_service.dart`

**實作內容**:
```dart
/// Google Sign In
Future<bool> signInWithGoogle() async {
  return await _client.auth.signInWithOAuth(
    OAuthProvider.google,
    redirectTo: 'com.poyutsai.vibesync://login-callback',
  );
}
```

**依賴**: Task 8, 9 完成

---

### Task 11: LoginScreen 新增 Google 登入按鈕

**目標**: 更新登入頁 UI，加入 Google 登入按鈕

**檔案**: `lib/features/auth/presentation/screens/login_screen.dart`

**UI 規格**:
- 位置：Apple 按鈕下方
- 風格：白底黑字 + Google Logo
- 文字：「使用 Google 登入」

**實作內容**:
```dart
// Google Sign In Button (白底黑字)
OutlinedButton.icon(
  onPressed: _signInWithGoogle,
  icon: Image.asset('assets/icons/google_logo.png', height: 24),
  label: const Text('使用 Google 登入'),
  style: OutlinedButton.styleFrom(
    foregroundColor: Colors.black87,
    minimumSize: const Size(double.infinity, 50),
    side: const BorderSide(color: Colors.grey),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
  ),
),
```

**需要**: Google Logo 圖片 (`assets/icons/google_logo.png`)

**依賴**: Task 10 完成

---

### Task 12: Google Sign In 測試

**目標**: 在 TestFlight 驗證 Google 登入完整流程

**測試案例**:
1. [ ] 新用戶 Google 登入 → 自動建立 subscription
2. [ ] 既有用戶 Google 登入 → 正常進入首頁
3. [ ] 用戶取消登入 → 停留在登入頁
4. [ ] OAuth 跳轉後返回 App → Session 正確建立

**驗證**:
- Supabase auth.users 有新記錄
- subscriptions 表有對應記錄
- App 正常導向首頁

**依賴**: Task 11 完成，需 TestFlight build

---

## Phase 3: 收尾

### Task 13: UI 微調與整合

**目標**: 確保登入頁整體視覺一致

**檔案**: `lib/features/auth/presentation/screens/login_screen.dart`

**調整項目**:
1. 按鈕間距統一
2. 「或」分隔線設計
3. Email 登入區塊調整為次要位置
4. 確保 Warm Theme 風格一致

**UI 順序**:
```
[Apple 登入按鈕]
[Google 登入按鈕]
─── 或使用 Email ───
[Email 輸入框]
[密碼輸入框]
[登入按鈕]
還沒有帳號？註冊
```

---

### Task 14: 錯誤處理完善

**目標**: 確保所有錯誤情況有適當提示

**檔案**: `lib/features/auth/presentation/screens/login_screen.dart`

**錯誤處理**:
```dart
try {
  await signInWithApple();
} on AuthException catch (e) {
  if (e.message.contains('canceled')) {
    // 用戶取消，不顯示錯誤
    return;
  }
  _showError('Apple 登入失敗，請稍後再試');
} catch (e) {
  _showError('登入失敗，請檢查網路連線');
}
```

---

### Task 15: 文件更新

**目標**: 更新 CLAUDE.md 記錄設定步驟

**檔案**: `CLAUDE.md`

**新增內容**:
- Third-Party Login 設定步驟
- Google Cloud Console 設定記錄
- Supabase Provider 設定記錄
- 常見問題 (Common Pitfalls)

---

## Dependencies Summary

### 外部設定 (手動)

| Task | 項目 | 優先序 |
|------|------|--------|
| 1 | Supabase Apple Provider | 🔴 必須先完成 |
| 2 | Xcode Sign in with Apple | 🔴 必須先完成 |
| 7 | Google Cloud Console OAuth | 🟡 Phase 2 前完成 |
| 8 | Supabase Google Provider | 🟡 Phase 2 前完成 |

### Task 依賴關係

```
Task 1 (Supabase Apple) ─┐
                         ├─→ Task 3 (AuthService Apple)
Task 2 (Xcode Capability)┘           │
                                      ▼
                              Task 4 (Subscription)
                                      │
                                      ▼
                              Task 5 (UI Apple Button)
                                      │
                                      ▼
                              Task 6 (Test Apple) ──→ TestFlight Build

Task 7 (Google Console) ─┐
                         ├─→ Task 9 (URL Scheme) ──→ Task 10 (AuthService Google)
Task 8 (Supabase Google)─┘                                    │
                                                               ▼
                                                      Task 11 (UI Google Button)
                                                               │
                                                               ▼
                                                      Task 12 (Test Google) ──→ TestFlight Build

Task 13, 14, 15 (收尾) ←── Phase 1 & 2 完成後
```

---

## Execution Order

### 建議執行順序

**手動設定先行**:
1. ✋ Task 1: Supabase Apple Provider
2. ✋ Task 2: Xcode Capability

**Phase 1 程式碼**:
3. 🔧 Task 3: AuthService signInWithApple
4. 🔧 Task 4: Subscription 自動建立
5. 🔧 Task 5: LoginScreen Apple 按鈕
6. 🧪 Task 6: TestFlight 測試

**Phase 2 手動設定**:
7. ✋ Task 7: Google Cloud Console
8. ✋ Task 8: Supabase Google Provider
9. ✋ Task 9: Xcode URL Scheme

**Phase 2 程式碼**:
10. 🔧 Task 10: AuthService signInWithGoogle
11. 🔧 Task 11: LoginScreen Google 按鈕
12. 🧪 Task 12: TestFlight 測試

**收尾**:
13. 🔧 Task 13: UI 微調
14. 🔧 Task 14: 錯誤處理
15. 📝 Task 15: 文件更新

---

*Created: 2026-03-14*
*Design Spec: `docs/superpowers/specs/2026-03-14-third-party-login-design.md`*
