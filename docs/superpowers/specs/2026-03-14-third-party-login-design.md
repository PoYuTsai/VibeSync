# Third-Party Login Integration Design

> Apple Sign In + Google Sign In for iOS

## Overview

為 VibeSync iOS App 新增 Apple Sign In 和 Google Sign In，提供用戶更便利的登入方式。

### 背景
- Apple Sign In 是 App Store 上架必要條件（若 App 提供第三方登入）
- Google Sign In 是用戶常用的登入方式
- 現有 Email 登入保留作為備選

### 目標
- 讓用戶可以用 Apple ID 或 Google 帳號一鍵登入/註冊
- 簡化註冊流程，提高轉換率
- 符合 App Store 審核要求

## Scope

### In Scope
- Apple Sign In (iOS)
- Google Sign In (iOS)
- 與現有 Email 登入整合
- 登入頁 UI 更新

### Out of Scope (未來)
- Android Google Sign In（之後再做）
- Web 平台第三方登入
- 帳號綁定/解綁功能
- 帳號合併功能

### 邊界情況處理
**同 Email 不同登入方式**：若用戶已用 Email 註冊，之後用 Apple/Google 登入（同 Email），Supabase 預設會建立新帳號。MVP 階段先接受此行為，未來再考慮帳號合併。

## Technical Design

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Flutter App (iOS)                     │
├─────────────────────────────────────────────────────────┤
│  LoginScreen                                             │
│  ├── Apple Sign In Button                               │
│  ├── Google Sign In Button                              │
│  └── Email Login (existing)                             │
├─────────────────────────────────────────────────────────┤
│  AuthService                                             │
│  ├── signInWithApple()                                  │
│  ├── signInWithGoogle()                                 │
│  └── signInWithEmail() (existing)                       │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                    Supabase Auth                         │
├─────────────────────────────────────────────────────────┤
│  Provider Configuration                                  │
│  ├── Apple Provider (enabled)                           │
│  ├── Google Provider (enabled)                          │
│  └── Email Provider (existing)                          │
└─────────────────────────────────────────────────────────┘
```

### 技術選擇：Supabase Native Auth

**選擇原因**：
1. ✅ 單一 SDK：使用 `supabase_flutter`，無需額外套件
2. ✅ 統一 Session：所有登入方式使用相同的 Supabase Session
3. ✅ 簡化後端：不需要自己處理 token 驗證
4. ✅ 現有整合：已使用 Supabase Auth，風險最低

**實作方式**：
- Apple: `supabase.auth.signInWithApple()` - Supabase Flutter v2 原生支援，無需額外套件
- Google: `supabase.auth.signInWithOAuth(OAuthProvider.google)`

**注意**：Sign in with Apple 需要在 TestFlight 或真機測試，模擬器不支援。

### 套件需求

```yaml
# pubspec.yaml (已有)
dependencies:
  supabase_flutter: ^2.0.0  # 已安裝

# 無需新增套件，Supabase Flutter 已支援 OAuth
```

### iOS 設定

#### 1. Apple Sign In

**Xcode 設定**：
- Target → Signing & Capabilities → + Capability → Sign in with Apple

**Apple Developer 設定**：
1. App ID 已啟用 Sign in with Apple ✅
2. 無需額外設定（Native iOS 自動處理）

**Supabase 設定**：
1. Authentication → Providers → Apple
2. 啟用 Apple Provider
3. 設定 Service ID、Team ID、Key ID、Private Key

#### 2. Google Sign In

**Google Cloud Console 設定**：
1. 建立 OAuth 2.0 Client ID (iOS)
2. Bundle ID: `com.poyutsai.vibesync`
3. 取得 Client ID

**Xcode 設定**：
- Info.plist 加入 URL Scheme (Reversed Client ID)
- 格式：`com.googleusercontent.apps.{CLIENT_ID}`

**Supabase 設定**：
1. Authentication → Providers → Google
2. 啟用 Google Provider
3. 設定 Client ID、Client Secret

### UI Design

#### Login Screen Layout

```
┌─────────────────────────────────┐
│                                 │
│         [VibeSync Logo]         │
│                                 │
│     "提升你的社交對話技巧"        │
│                                 │
├─────────────────────────────────┤
│                                 │
│  ┌─────────────────────────┐   │
│  │  🍎 使用 Apple 登入      │   │  ← 黑底白字 (Apple 規範)
│  └─────────────────────────┘   │
│                                 │
│  ┌─────────────────────────┐   │
│  │  G  使用 Google 登入     │   │  ← 白底黑字 + Google Logo
│  └─────────────────────────┘   │
│                                 │
│  ─────── 或 ───────            │
│                                 │
│  ┌─────────────────────────┐   │
│  │  📧 使用 Email 登入      │   │  ← 毛玻璃風格
│  └─────────────────────────┘   │
│                                 │
│  還沒有帳號？註冊               │
│                                 │
└─────────────────────────────────┘
```

#### Button 風格

| 按鈕 | 風格 | 原因 |
|------|------|------|
| Apple Sign In | 黑底白字 | Apple Human Interface Guidelines 規範 |
| Google Sign In | 白底黑字 + Logo | Google Sign-In Branding Guidelines 規範 |
| Email Login | 毛玻璃 | 與 App 設計一致 |

### Auth Flow

```
User taps "使用 Apple 登入"
         │
         ▼
    ┌────────────┐
    │ iOS Native │
    │ Apple Auth │
    └─────┬──────┘
          │ Apple ID Token
          ▼
    ┌────────────┐
    │  Supabase  │
    │    Auth    │
    └─────┬──────┘
          │ Supabase Session
          ▼
    ┌────────────┐
    │ Check if   │
    │ new user?  │
    └─────┬──────┘
          │
    ┌─────┴─────┐
    │           │
    ▼           ▼
  New       Existing
  User        User
    │           │
    ▼           ▼
 Create     Load
 Profile   Profile
    │           │
    └─────┬─────┘
          │
          ▼
    ┌────────────┐
    │  HomeScreen │
    └────────────┘
```

### 新用戶處理

當用戶首次使用 Apple/Google 登入：

1. **Supabase Auth** 自動建立 auth.users 記錄
2. **App 端** 檢查是否有 `subscriptions` 記錄
3. **若無記錄** → 建立 Free tier subscription：
   ```dart
   await supabase.from('subscriptions').insert({
     'user_id': user.id,
     'tier': 'free',
     'monthly_messages_used': 0,
     'daily_messages_used': 0,
     'started_at': DateTime.now().toIso8601String(),
   });
   ```
4. **導向首頁** (無 Onboarding)

### Error Handling

| 錯誤情況 | 處理方式 |
|---------|---------|
| 用戶取消登入 | 靜默處理，停留在登入頁 |
| Apple 服務異常 | 顯示錯誤，建議使用 Email 登入 |
| Google 服務異常 | 顯示錯誤，建議使用 Email 登入 |
| Supabase 連線失敗 | 顯示錯誤，提示檢查網路 |
| Session 過期 | 自動登出，導向登入頁 |

### 安全考量

1. **Token 處理**：所有 token 由 Supabase SDK 處理，不自行儲存
2. **Keychain**：iOS 會將 Sign in with Apple 憑證存入 Keychain
3. **隱私**：Apple Sign In 可隱藏 Email（使用 Relay Email）
4. **登出**：登出時清除所有本地 session

## Implementation Tasks

### Phase 1: Apple Sign In (優先)

1. **Supabase 設定** - 啟用 Apple Provider，設定必要參數
2. **Xcode 設定** - 加入 Sign in with Apple capability
3. **AuthService 擴充** - 新增 `signInWithApple()` 方法
4. **LoginScreen 更新** - 新增 Apple 登入按鈕
5. **新用戶處理** - 自動建立 subscription 記錄
6. **測試** - TestFlight 測試 Apple 登入流程

### Phase 2: Google Sign In

7. **Google Cloud Console** - 建立 OAuth Client ID
8. **Supabase 設定** - 啟用 Google Provider
9. **Xcode 設定** - 加入 URL Scheme
10. **AuthService 擴充** - 新增 `signInWithGoogle()` 方法
11. **LoginScreen 更新** - 新增 Google 登入按鈕
12. **測試** - TestFlight 測試 Google 登入流程

### Phase 3: 收尾

13. **UI 微調** - 確保按鈕風格符合各平台規範
14. **錯誤處理** - 完善錯誤訊息
15. **CLAUDE.md 更新** - 記錄設定步驟

## Dependencies

### 外部設定 (需手動完成)

| 項目 | 位置 | 狀態 |
|------|------|------|
| Apple Developer - Sign in with Apple | App ID 設定 | 待確認 |
| Supabase - Apple Provider | Dashboard | 待設定 |
| Google Cloud Console - OAuth Client | APIs & Services | 待建立 |
| Supabase - Google Provider | Dashboard | 待設定 |

### 現有資源

- Bundle ID: `com.poyutsai.vibesync` ✅
- Team ID: `TTQHTVG8CC` ✅
- Supabase Project: `fcmwrmwdoqiqdnbisdpg` ✅

## Success Criteria

- [ ] Apple Sign In 可在 TestFlight 上正常運作
- [ ] Google Sign In 可在 TestFlight 上正常運作
- [ ] 新用戶登入後自動建立 subscription 記錄
- [ ] 現有 Email 登入不受影響
- [ ] 登出功能正常運作
- [ ] 錯誤情況有適當處理和提示

## Timeline

- Phase 1 (Apple Sign In): 主要開發項目
- Phase 2 (Google Sign In): 接續開發
- Phase 3 (收尾): 測試和微調

---

*Created: 2026-03-14*
*Status: Ready for Review*
