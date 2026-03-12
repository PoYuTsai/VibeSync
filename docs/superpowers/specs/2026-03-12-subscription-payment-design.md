# VibeSync 訂閱付款系統設計 - Phase 1

> **狀態**: 設計完成，待實作
> **建立日期**: 2026-03-12
> **範圍**: RevenueCat + iOS 月訂閱

## 1. 概述

### 1.1 目標
實作 iOS 應用內購買 (IAP) 功能，讓用戶可以訂閱 Starter 或 Essential 方案。

### 1.2 Phase 1 範圍

| 包含 | 不包含 |
|------|--------|
| Starter/Essential 月訂閱 | 年訂閱 |
| iOS 平台 | Android、Web |
| RevenueCat SDK 整合 | Stripe |
| Webhook 訂閱同步 | Booster 加購包 |
| Sandbox 測試 | 試用期實作 |

### 1.3 後續 Phases

- **Phase 2**: 年訂閱 + Booster 加購包
- **Phase 3**: 試用期 + 進階功能
- **Phase 4**: Admin Dashboard

---

## 2. 系統架構

```
┌──────────────────────────────────────────────────────────────────┐
│                        用戶付款流程                               │
└──────────────────────────────────────────────────────────────────┘

  ┌──────────┐     ┌──────────────┐     ┌─────────────────┐
  │  用戶    │────▶│  Paywall UI  │────▶│  RevenueCat SDK │
  │  點擊    │     │  (Flutter)   │     │  purchase()     │
  └──────────┘     └──────────────┘     └────────┬────────┘
                                                  │
                                                  ▼
                                        ┌─────────────────┐
                                        │   App Store     │
                                        │   付款彈窗      │
                                        └────────┬────────┘
                                                  │
                   ┌──────────────────────────────┼──────────────────────────────┐
                   │                              │                              │
                   ▼                              ▼                              ▼
          ┌───────────────┐            ┌─────────────────┐            ┌──────────────┐
          │  RevenueCat   │◀───────────│   Apple 伺服器   │───────────▶│   Webhook    │
          │  Dashboard    │   收據驗證  │                 │   事件通知  │  (Supabase)  │
          └───────────────┘            └─────────────────┘            └──────┬───────┘
                                                                              │
                                                                              ▼
                                                                    ┌──────────────┐
                                                                    │  Supabase    │
                                                                    │ subscriptions│
                                                                    │    表        │
                                                                    └──────────────┘
```

### 2.1 核心流程

1. 用戶在 Paywall 點擊購買
2. RevenueCat SDK 呼叫 App Store 付款
3. 付款成功 → RevenueCat 驗證收據
4. RevenueCat 發送 Webhook 到 Supabase
5. Supabase 更新 `subscriptions` 表
6. App 刷新訂閱狀態

---

## 3. 產品設定

### 3.1 App Store Connect 產品

| 產品 ID | 類型 | 名稱 | 價格 |
|---------|------|------|------|
| `vibesync_starter_monthly` | 自動續訂訂閱 | Starter 月訂閱 | NT$149 (Tier 2) |
| `vibesync_essential_monthly` | 自動續訂訂閱 | Essential 月訂閱 | NT$930 (Tier 13) |

### 3.2 RevenueCat 設定

| 項目 | 值 |
|------|-----|
| App 名稱 | VibeSync |
| Bundle ID | `com.poyutsai.vibesync` |
| Entitlement | `premium` |
| Offering | `default` |

### 3.3 Entitlement 結構

```
premium (entitlement)
├── vibesync_starter_monthly    → tier = "starter"
└── vibesync_essential_monthly  → tier = "essential"
```

---

## 4. Flutter 端實作

### 4.1 檔案結構

```
lib/
├── core/
│   └── services/
│       └── revenuecat_service.dart    ← 新增
├── features/
│   └── subscription/
│       ├── data/
│       │   └── providers/
│       │       └── subscription_providers.dart  ← 修改
│       └── presentation/
│           └── screens/
│               ├── paywall_screen.dart          ← 修改
│               └── settings_screen.dart         ← 修改
└── main.dart                                    ← 修改
```

### 4.2 RevenueCatService API

```dart
class RevenueCatService {
  /// 初始化 SDK（在 main.dart 呼叫）
  static Future<void> initialize() async;

  /// 取得可購買的產品
  static Future<Offerings?> getOfferings() async;

  /// 購買訂閱
  static Future<CustomerInfo> purchase(Package package) async;

  /// 恢復購買
  static Future<CustomerInfo> restorePurchases() async;

  /// 取得目前訂閱狀態
  static Future<CustomerInfo> getCustomerInfo() async;

  /// 關聯 Supabase user_id（登入後呼叫）
  static Future<void> login(String userId) async;

  /// 登出（Supabase 登出時呼叫）
  static Future<void> logout() async;
}
```

### 4.3 購買流程

```
用戶點擊「訂閱 Starter」
        ↓
顯示 Loading
        ↓
呼叫 RevenueCatService.purchase()
        ↓
    ┌───┴───┐
    ↓       ↓
  成功     失敗
    ↓       ↓
隱藏 Loading  顯示錯誤訊息
顯示成功    (用戶取消/付款失敗)
刷新訂閱狀態
返回首頁
```

---

## 5. Webhook 設計

### 5.1 Edge Function

**路徑**: `supabase/functions/revenuecat-webhook/index.ts`

### 5.2 處理的事件

| 事件類型 | 處理邏輯 |
|---------|---------|
| `INITIAL_PURCHASE` | 新訂閱 → 更新 tier、重置額度 |
| `RENEWAL` | 續訂成功 → 重置月額度 |
| `CANCELLATION` | 取消訂閱 → 標記 status = cancelled |
| `EXPIRATION` | 訂閱到期 → 降級為 Free |
| `BILLING_ISSUE` | 付款問題 → 標記 status = billing_issue |

### 5.3 安全驗證

```typescript
// 驗證 RevenueCat 簽名
const signature = req.headers.get('X-RevenueCat-Signature');
const isValid = verifySignature(signature, body, WEBHOOK_SECRET);
if (!isValid) {
  return new Response('Unauthorized', { status: 401 });
}
```

### 5.4 資料庫更新

```typescript
// 根據 product_id 判斷 tier
const tier = product_id.includes('essential') ? 'essential' : 'starter';

// 更新 subscriptions 表
await supabase
  .from('subscriptions')
  .update({
    tier,
    status: 'active',
    rc_customer_id: customer_id,
    monthly_messages_used: 0,
    daily_messages_used: 0,
    monthly_reset_at: new Date().toISOString(),
  })
  .eq('user_id', app_user_id);
```

---

## 6. 環境設定

### 6.1 GitHub Secrets（新增）

| Secret | 說明 | 來源 |
|--------|------|------|
| `REVENUECAT_IOS_API_KEY` | iOS Public API Key | RevenueCat Dashboard |
| `REVENUECAT_WEBHOOK_SECRET` | Webhook 驗證密鑰 | RevenueCat Dashboard |

### 6.2 Flutter 環境變數

```dart
// lib/core/config/environment.dart
static String get revenueCatApiKey {
  return const String.fromEnvironment(
    'REVENUECAT_IOS_API_KEY',
    defaultValue: '', // Sandbox key for development
  );
}
```

---

## 7. 設定步驟

### Step 1: RevenueCat 帳號設定
1. 註冊 RevenueCat 帳號
2. 建立 VibeSync Project
3. 新增 iOS App (Bundle ID: com.poyutsai.vibesync)
4. 上傳 App Store Connect Shared Secret
5. 取得 API Keys

### Step 2: App Store Connect 產品設定
1. 建立 Subscription Group
2. 新增 Starter 月訂閱產品 (vibesync_starter_monthly)
3. 新增 Essential 月訂閱產品 (vibesync_essential_monthly)
4. 設定價格

### Step 3: RevenueCat 產品設定
1. 建立 Entitlement: premium
2. 建立 Offering: default
3. 新增 Packages
4. 關聯 App Store 產品

### Step 4: Flutter 程式碼實作
1. 新增 RevenueCatService
2. 修改 main.dart 初始化
3. 修改 PaywallScreen 購買邏輯
4. 修改 SettingsScreen 恢復購買
5. 整合 SubscriptionProvider

### Step 5: Webhook 實作
1. 建立 revenuecat-webhook Edge Function
2. 部署到 Supabase
3. 在 RevenueCat 設定 Webhook URL

### Step 6: Sandbox 測試
1. 建立 Sandbox 測試帳號
2. TestFlight 安裝測試版
3. 測試購買流程
4. 驗證訂閱狀態同步

---

## 8. 測試計畫

### 8.1 測試案例

| # | 案例 | 預期結果 |
|---|------|---------|
| 1 | Free 用戶購買 Starter | tier 變 starter，額度重置 |
| 2 | Free 用戶購買 Essential | tier 變 essential，額度重置 |
| 3 | Starter 升級 Essential | tier 變 essential |
| 4 | 取消訂閱 | status 變 cancelled，到期前維持權益 |
| 5 | 訂閱到期 | tier 降為 free |
| 6 | 恢復購買 | 還原之前的訂閱狀態 |
| 7 | 用戶取消付款 | 顯示取消訊息，狀態不變 |

### 8.2 測試環境

- **App**: TestFlight 版本
- **帳號**: App Store Sandbox Tester
- **RevenueCat**: Sandbox 模式
- **費用**: 免費（Sandbox 不扣款）

---

## 9. 定價（暫定，可能調整）

### 9.1 月訂閱

| 方案 | 價格 (TWD) | 價格 (USD) | 月額度 | 日額度 |
|------|-----------|-----------|--------|--------|
| Free | $0 | $0 | 30 則 | 15 則 |
| Starter | NT$149 | ~$4.99 | 300 則 | 50 則 |
| Essential | NT$930 | ~$29 | 1,000 則 | 150 則 |

### 9.2 未來可能調整

- 改為 Weekly 訂閱
- 調整試用期天數
- 新增 Booster 加購包

---

## 10. 風險與緩解

| 風險 | 緩解措施 |
|------|---------|
| Webhook 漏接 | App 啟動時也檢查 RevenueCat 訂閱狀態 |
| 網路失敗 | 本地快取訂閱狀態，背景重試 |
| 收據驗證失敗 | RevenueCat 自動處理重試 |
| 用戶詐騙退款 | RevenueCat 會發送 REFUND 事件，自動降級 |

---

## 附錄：相關文件

- 定價規格：`docs/pricing-final.md`
- 資料庫 Schema：`supabase/migrations/00001_initial_schema.sql`
- 現有訂閱 Provider：`lib/features/subscription/data/providers/subscription_providers.dart`
- 現有 Paywall UI：`lib/features/subscription/presentation/screens/paywall_screen.dart`
