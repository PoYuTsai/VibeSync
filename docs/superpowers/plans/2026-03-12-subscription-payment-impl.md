# 訂閱付款系統 Phase 1 實作計畫

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 實作 iOS 應用內購買功能，讓用戶可以透過 RevenueCat 訂閱 Starter 或 Essential 方案。

**Architecture:** Flutter App 透過 RevenueCat SDK 處理購買，RevenueCat 驗證收據後發送 Webhook 到 Supabase Edge Function 更新訂閱狀態。App 啟動時和購買後都會同步訂閱狀態。

**Tech Stack:** Flutter + RevenueCat SDK (purchases_flutter) + Supabase Edge Functions + App Store Connect IAP

**Spec Document:** `docs/superpowers/specs/2026-03-12-subscription-payment-design.md`

---

## File Structure

```
lib/
├── core/
│   ├── config/
│   │   └── environment.dart              ← 修改：更新 RevenueCat key 取得方式
│   └── services/
│       └── revenuecat_service.dart       ← 新增：RevenueCat SDK 封裝
├── features/
│   └── subscription/
│       ├── data/
│       │   └── providers/
│       │       └── subscription_providers.dart  ← 修改：整合 RevenueCat
│       └── presentation/
│           └── screens/
│               ├── paywall_screen.dart          ← 修改：購買邏輯
│               └── settings_screen.dart         ← 修改：恢復購買 + 狀態顯示
└── main.dart                                    ← 修改：初始化 SDK

supabase/
└── functions/
    └── revenuecat-webhook/
        └── index.ts                             ← 新增：Webhook 處理
```

---

## Chunk 1: 帳號與產品設定

> **Note:** 此 Chunk 為設定指引，需用戶在瀏覽器操作。Claude 協助指引步驟。

### Task 1: RevenueCat 帳號設定

**目標:** 建立 RevenueCat 帳號並設定 VibeSync iOS App

- [ ] **Step 1: 註冊 RevenueCat**

前往 https://app.revenuecat.com/signup 註冊帳號

- [ ] **Step 2: 建立 Project**

1. 點擊 "Create new project"
2. Project name: `VibeSync`
3. 點擊 "Create project"

- [ ] **Step 3: 新增 iOS App**

1. 在 Project 內點擊 "Add app"
2. 選擇 "App Store"
3. App name: `VibeSync iOS`
4. Bundle ID: `com.poyutsai.vibesync`
5. 點擊 "Save changes"

- [ ] **Step 4: 設定 App Store Connect 連線**

1. 前往 App Store Connect → Users and Access → Integrations → In-App Purchase
2. 產生 "App-Specific Shared Secret"
3. 複製 Shared Secret
4. 回到 RevenueCat → 點擊你的 iOS App → "App Store Connect"
5. 貼上 Shared Secret
6. 點擊 "Save changes"

- [ ] **Step 5: 記錄 API Keys**

1. 在 RevenueCat 側邊欄點擊 "API Keys"
2. 複製 "Public app-specific API key" (iOS) → 這是 `REVENUECAT_IOS_API_KEY`
3. 點擊 "Show key" 複製 → 保存備用

---

### Task 2: App Store Connect 產品設定

**目標:** 在 App Store Connect 建立訂閱產品

- [ ] **Step 1: 進入 App Store Connect**

前往 https://appstoreconnect.apple.com → 選擇 VibeSync App

- [ ] **Step 2: 建立 Subscription Group**

1. 點擊 "Subscriptions" (左側選單)
2. 點擊 "Create" 旁邊的 "+"
3. Subscription Group Name: `VibeSync Premium`
4. 點擊 "Create"

- [ ] **Step 3: 新增 Starter 月訂閱**

1. 在 Subscription Group 內點擊 "+"
2. Reference Name: `Starter Monthly`
3. Product ID: `vibesync_starter_monthly`
4. 點擊 "Create"
5. Subscription Duration: `1 Month`
6. 點擊 "Add Subscription Price"
7. 選擇 Price: `Tier 2` (NT$149 / $4.99)
8. 點擊 "Next" → "Confirm"
9. Localization: 加入繁體中文
   - Display Name: `Starter 月訂閱`
   - Description: `每月 300 則訊息額度，解鎖完整回覆建議`
10. Review Information:
    - Screenshot: 上傳 Paywall 截圖
    - Review Notes: `This subscription unlocks premium features including 300 messages per month.`

- [ ] **Step 4: 新增 Essential 月訂閱**

1. 在 Subscription Group 內點擊 "+"
2. Reference Name: `Essential Monthly`
3. Product ID: `vibesync_essential_monthly`
4. 點擊 "Create"
5. Subscription Duration: `1 Month`
6. 點擊 "Add Subscription Price"
7. 選擇 Price: `Tier 13` (NT$930 / $29.99)
8. 點擊 "Next" → "Confirm"
9. Localization: 加入繁體中文
   - Display Name: `Essential 月訂閱`
   - Description: `每月 1000 則訊息額度，對話健檢，Sonnet 優先模型`
10. Review Information: 同上

- [ ] **Step 5: 確認產品狀態**

確認兩個產品狀態為 "Ready to Submit" 或 "Approved"

---

### Task 3: RevenueCat 產品關聯

**目標:** 在 RevenueCat 建立 Entitlement 和 Offering，關聯 App Store 產品

- [ ] **Step 1: 建立 Entitlement**

1. 在 RevenueCat 側邊欄點擊 "Entitlements"
2. 點擊 "+ New"
3. Identifier: `premium`
4. Description: `Premium subscription access`
5. 點擊 "Add"

- [ ] **Step 2: 同步 App Store 產品**

1. 在 RevenueCat 側邊欄點擊 "Products"
2. 點擊 "+ New"
3. App Store Product ID: `vibesync_starter_monthly`
4. 點擊 "Add"
5. 重複新增 `vibesync_essential_monthly`

- [ ] **Step 3: 關聯產品到 Entitlement**

1. 點擊 "Entitlements" → "premium"
2. 點擊 "Attach"
3. 選擇 `vibesync_starter_monthly` → "Attach"
4. 再點擊 "Attach"
5. 選擇 `vibesync_essential_monthly` → "Attach"

- [ ] **Step 4: 建立 Offering**

1. 在 RevenueCat 側邊欄點擊 "Offerings"
2. 點擊 "+ New"
3. Identifier: `default`
4. Description: `Default offering`
5. 點擊 "Add"

- [ ] **Step 5: 建立 Packages**

1. 點擊 "default" Offering
2. 點擊 "+ New Package"
3. Identifier: `starter_monthly` (或選擇 `$rc_monthly`)
4. 選擇產品: `vibesync_starter_monthly`
5. 點擊 "Add"
6. 再點擊 "+ New Package"
7. Identifier: `essential_monthly`
8. 選擇產品: `vibesync_essential_monthly`
9. 點擊 "Add"

- [ ] **Step 6: 設定 Webhook**

1. 在 RevenueCat 側邊欄點擊 "Integrations"
2. 點擊 "Webhooks"
3. 點擊 "+ New"
4. Webhook URL: `https://fcmwrmwdoqiqdnbisdpg.supabase.co/functions/v1/revenuecat-webhook`
5. Authorization header: 複製並保存 (這是 `REVENUECAT_WEBHOOK_SECRET`)
6. 選擇事件: `INITIAL_PURCHASE`, `RENEWAL`, `CANCELLATION`, `EXPIRATION`, `BILLING_ISSUE`
7. 點擊 "Save"

---

## Chunk 2: Flutter SDK 整合

### Task 4: 建立 RevenueCatService

**Files:**
- Create: `lib/core/services/revenuecat_service.dart`

- [ ] **Step 1: 建立 RevenueCatService 檔案**

```dart
// lib/core/services/revenuecat_service.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../config/environment.dart';

/// RevenueCat 服務封裝
class RevenueCatService {
  static bool _isInitialized = false;

  /// 初始化 RevenueCat SDK
  /// 應在 main.dart 中 Supabase 初始化後呼叫
  static Future<void> initialize() async {
    if (_isInitialized) return;

    // Web 不支援 RevenueCat
    if (kIsWeb) {
      debugPrint('⚠️ RevenueCat: Web platform not supported');
      return;
    }

    final apiKey = AppConfig.revenueCatApiKey;
    if (apiKey.isEmpty) {
      debugPrint('⚠️ RevenueCat: API key not configured');
      return;
    }

    await Purchases.setLogLevel(LogLevel.debug);

    PurchasesConfiguration configuration;
    if (Platform.isIOS) {
      configuration = PurchasesConfiguration(apiKey);
    } else if (Platform.isAndroid) {
      // Android 暫不支援，之後再加
      debugPrint('⚠️ RevenueCat: Android not yet configured');
      return;
    } else {
      debugPrint('⚠️ RevenueCat: Unsupported platform');
      return;
    }

    await Purchases.configure(configuration);
    _isInitialized = true;
    debugPrint('✅ RevenueCat initialized');
  }

  /// 檢查是否已初始化
  static bool get isInitialized => _isInitialized;

  /// 關聯用戶 ID（登入後呼叫）
  /// 這讓 RevenueCat 知道訂閱屬於哪個 Supabase 用戶
  static Future<void> login(String userId) async {
    if (!_isInitialized) return;

    try {
      await Purchases.logIn(userId);
      debugPrint('✅ RevenueCat: User logged in: $userId');
    } catch (e) {
      debugPrint('❌ RevenueCat login error: $e');
    }
  }

  /// 登出（Supabase 登出時呼叫）
  static Future<void> logout() async {
    if (!_isInitialized) return;

    try {
      await Purchases.logOut();
      debugPrint('✅ RevenueCat: User logged out');
    } catch (e) {
      debugPrint('❌ RevenueCat logout error: $e');
    }
  }

  /// 取得可購買的產品
  static Future<Offerings?> getOfferings() async {
    if (!_isInitialized) return null;

    try {
      final offerings = await Purchases.getOfferings();
      return offerings;
    } catch (e) {
      debugPrint('❌ RevenueCat getOfferings error: $e');
      return null;
    }
  }

  /// 購買訂閱
  /// 回傳 CustomerInfo，購買失敗會拋出 PurchasesErrorCode
  static Future<CustomerInfo> purchase(Package package) async {
    if (!_isInitialized) {
      throw Exception('RevenueCat not initialized');
    }

    try {
      final customerInfo = await Purchases.purchasePackage(package);
      debugPrint('✅ RevenueCat: Purchase successful');
      return customerInfo;
    } on PurchasesErrorCode catch (e) {
      debugPrint('❌ RevenueCat purchase error: $e');
      rethrow;
    }
  }

  /// 恢復購買
  static Future<CustomerInfo> restorePurchases() async {
    if (!_isInitialized) {
      throw Exception('RevenueCat not initialized');
    }

    try {
      final customerInfo = await Purchases.restorePurchases();
      debugPrint('✅ RevenueCat: Purchases restored');
      return customerInfo;
    } catch (e) {
      debugPrint('❌ RevenueCat restore error: $e');
      rethrow;
    }
  }

  /// 取得目前訂閱狀態
  static Future<CustomerInfo?> getCustomerInfo() async {
    if (!_isInitialized) return null;

    try {
      final customerInfo = await Purchases.getCustomerInfo();
      return customerInfo;
    } catch (e) {
      debugPrint('❌ RevenueCat getCustomerInfo error: $e');
      return null;
    }
  }

  /// 檢查用戶是否有 premium entitlement
  static Future<bool> hasPremiumEntitlement() async {
    final customerInfo = await getCustomerInfo();
    if (customerInfo == null) return false;

    return customerInfo.entitlements.active.containsKey('premium');
  }

  /// 從 CustomerInfo 取得 tier
  static String getTierFromCustomerInfo(CustomerInfo? customerInfo) {
    if (customerInfo == null) return 'free';

    final premiumEntitlement = customerInfo.entitlements.active['premium'];
    if (premiumEntitlement == null) return 'free';

    final productId = premiumEntitlement.productIdentifier;
    if (productId.contains('essential')) return 'essential';
    if (productId.contains('starter')) return 'starter';

    return 'free';
  }
}
```

- [ ] **Step 2: 驗證程式碼無錯誤**

Run: `flutter analyze lib/core/services/revenuecat_service.dart`
Expected: No issues found

- [ ] **Step 3: Commit**

```bash
git add lib/core/services/revenuecat_service.dart
git commit -m "[feat] 新增 RevenueCatService - SDK 封裝"
git push
```

---

### Task 5: 修改 main.dart 初始化

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: 新增 RevenueCat 初始化**

在 `lib/main.dart` 的 `main()` 函數中，於 Supabase 初始化後加入：

```dart
// lib/main.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'core/config/environment.dart';
import 'core/services/revenuecat_service.dart';  // 新增
import 'core/services/storage_service.dart';
import 'core/services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Log environment info
  if (kDebugMode) {
    debugPrint('🚀 Running in ${AppConfig.environmentName} mode');
    debugPrint('📡 Supabase URL: ${AppConfig.supabaseUrl}');
  }

  // Initialize local storage
  await StorageService.initialize();

  // Initialize Supabase using environment config
  await SupabaseService.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  // Initialize RevenueCat (非 Web 平台)  // 新增
  await RevenueCatService.initialize();  // 新增

  runApp(
    const ProviderScope(
      child: App(),
    ),
  );
}
```

- [ ] **Step 2: 驗證程式碼無錯誤**

Run: `flutter analyze lib/main.dart`
Expected: No issues found

- [ ] **Step 3: Commit**

```bash
git add lib/main.dart
git commit -m "[feat] main.dart 新增 RevenueCat 初始化"
git push
```

---

### Task 6: 修改 SubscriptionProvider 整合 RevenueCat

**Files:**
- Modify: `lib/features/subscription/data/providers/subscription_providers.dart`

- [ ] **Step 1: 更新 SubscriptionNotifier**

```dart
// lib/features/subscription/data/providers/subscription_providers.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../../../../core/services/revenuecat_service.dart';
import '../../../../core/services/supabase_service.dart';

/// 訂閱狀態
class SubscriptionState {
  final String tier;
  final int monthlyMessagesUsed;
  final int dailyMessagesUsed;
  final int monthlyLimit;
  final int dailyLimit;
  final bool isLoading;
  final String? error;
  final Offerings? offerings;  // 新增：可購買的產品

  const SubscriptionState({
    this.tier = 'free',
    this.monthlyMessagesUsed = 0,
    this.dailyMessagesUsed = 0,
    this.monthlyLimit = 30,
    this.dailyLimit = 15,
    this.isLoading = false,
    this.error,
    this.offerings,
  });

  bool get isFreeUser => tier == 'free';
  bool get isStarter => tier == 'starter';
  bool get isEssential => tier == 'essential';
  bool get isPremium => tier == 'starter' || tier == 'essential';

  int get monthlyRemaining => monthlyLimit - monthlyMessagesUsed;
  int get dailyRemaining => dailyLimit - dailyMessagesUsed;

  /// 取得 Starter 的 Package
  Package? get starterPackage {
    return offerings?.current?.availablePackages.firstWhere(
      (p) => p.storeProduct.identifier.contains('starter'),
      orElse: () => offerings!.current!.availablePackages.first,
    );
  }

  /// 取得 Essential 的 Package
  Package? get essentialPackage {
    return offerings?.current?.availablePackages.firstWhere(
      (p) => p.storeProduct.identifier.contains('essential'),
      orElse: () => offerings!.current!.availablePackages.first,
    );
  }

  SubscriptionState copyWith({
    String? tier,
    int? monthlyMessagesUsed,
    int? dailyMessagesUsed,
    int? monthlyLimit,
    int? dailyLimit,
    bool? isLoading,
    String? error,
    Offerings? offerings,
  }) {
    return SubscriptionState(
      tier: tier ?? this.tier,
      monthlyMessagesUsed: monthlyMessagesUsed ?? this.monthlyMessagesUsed,
      dailyMessagesUsed: dailyMessagesUsed ?? this.dailyMessagesUsed,
      monthlyLimit: monthlyLimit ?? this.monthlyLimit,
      dailyLimit: dailyLimit ?? this.dailyLimit,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      offerings: offerings ?? this.offerings,
    );
  }
}

/// 訂閱 Provider
class SubscriptionNotifier extends StateNotifier<SubscriptionState> {
  SubscriptionNotifier() : super(const SubscriptionState(isLoading: true)) {
    _initialize();
  }

  static const _tierLimits = {
    'free': {'monthly': 30, 'daily': 15},
    'starter': {'monthly': 300, 'daily': 50},
    'essential': {'monthly': 1000, 'daily': 150},
  };

  Future<void> _initialize() async {
    await _loadSubscription();
    await _loadOfferings();
  }

  /// 從 Supabase 載入訂閱狀態
  Future<void> _loadSubscription() async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) {
        state = const SubscriptionState(error: 'Not logged in');
        return;
      }

      // 關聯 RevenueCat 用戶
      await RevenueCatService.login(user.id);

      final response = await SupabaseService.client
          .from('subscriptions')
          .select()
          .eq('user_id', user.id)
          .single();

      final tier = response['tier'] as String? ?? 'free';
      final limits = _tierLimits[tier] ?? _tierLimits['free']!;

      state = state.copyWith(
        tier: tier,
        monthlyMessagesUsed: response['monthly_messages_used'] as int? ?? 0,
        dailyMessagesUsed: response['daily_messages_used'] as int? ?? 0,
        monthlyLimit: limits['monthly']!,
        dailyLimit: limits['daily']!,
        isLoading: false,
      );
    } catch (e) {
      debugPrint('❌ Load subscription error: $e');
      state = SubscriptionState(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// 載入可購買的產品
  Future<void> _loadOfferings() async {
    try {
      final offerings = await RevenueCatService.getOfferings();
      if (offerings != null) {
        state = state.copyWith(offerings: offerings);
        debugPrint('✅ Offerings loaded: ${offerings.current?.availablePackages.length} packages');
      }
    } catch (e) {
      debugPrint('❌ Load offerings error: $e');
    }
  }

  /// 重新載入訂閱狀態
  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    await _loadSubscription();
    await _loadOfferings();
  }

  /// 購買訂閱
  Future<bool> purchase(Package package) async {
    try {
      state = state.copyWith(isLoading: true);

      await RevenueCatService.purchase(package);

      // 購買成功後刷新訂閱狀態
      // Webhook 會更新 Supabase，但我們也主動從 RevenueCat 確認
      final customerInfo = await RevenueCatService.getCustomerInfo();
      final tier = RevenueCatService.getTierFromCustomerInfo(customerInfo);
      final limits = _tierLimits[tier] ?? _tierLimits['free']!;

      state = state.copyWith(
        tier: tier,
        monthlyLimit: limits['monthly']!,
        dailyLimit: limits['daily']!,
        isLoading: false,
      );

      return true;
    } catch (e) {
      debugPrint('❌ Purchase error: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  /// 恢復購買
  Future<bool> restorePurchases() async {
    try {
      state = state.copyWith(isLoading: true);

      final customerInfo = await RevenueCatService.restorePurchases();
      final tier = RevenueCatService.getTierFromCustomerInfo(customerInfo);
      final limits = _tierLimits[tier] ?? _tierLimits['free']!;

      state = state.copyWith(
        tier: tier,
        monthlyLimit: limits['monthly']!,
        dailyLimit: limits['daily']!,
        isLoading: false,
      );

      return tier != 'free';
    } catch (e) {
      debugPrint('❌ Restore error: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }
}

final subscriptionProvider =
    StateNotifierProvider<SubscriptionNotifier, SubscriptionState>((ref) {
  return SubscriptionNotifier();
});
```

- [ ] **Step 2: 驗證程式碼無錯誤**

Run: `flutter analyze lib/features/subscription/data/providers/subscription_providers.dart`
Expected: No issues found

- [ ] **Step 3: Commit**

```bash
git add lib/features/subscription/data/providers/subscription_providers.dart
git commit -m "[feat] SubscriptionProvider 整合 RevenueCat"
git push
```

---

## Chunk 3: UI 整合

### Task 7: 修改 PaywallScreen 購買邏輯

**Files:**
- Modify: `lib/features/subscription/presentation/screens/paywall_screen.dart`

- [ ] **Step 1: 更新 PaywallScreen**

```dart
// lib/features/subscription/presentation/screens/paywall_screen.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
import '../../data/providers/subscription_providers.dart';

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  String _selectedTier = 'essential'; // 預設選 Essential
  bool _isYearly = false; // Phase 1 只有月訂閱，先設 false
  bool _isPurchasing = false;

  @override
  Widget build(BuildContext context) {
    final subscription = ref.watch(subscriptionProvider);

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text('升級方案', style: AppTypography.titleLarge.copyWith(color: AppColors.onBackgroundPrimary)),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => context.pop(),
          ),
        ),
        body: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Text(
                    '解鎖完整功能',
                    style: AppTypography.headlineLarge.copyWith(color: AppColors.onBackgroundPrimary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '提升你的社交溝通能力',
                    style: AppTypography.bodyLarge.copyWith(color: AppColors.onBackgroundSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // Plan cards
                  _buildPlanCard(
                    tier: 'starter',
                    name: 'Starter',
                    package: subscription.starterPackage,
                    features: const [
                      '300 則訊息/月',
                      '每日 50 則上限',
                      '5 種回覆建議',
                      'Needy 警示',
                      '話題深度分析',
                    ],
                    isSelected: _selectedTier == 'starter',
                    onTap: () => setState(() => _selectedTier = 'starter'),
                  ),
                  const SizedBox(height: 16),
                  _buildPlanCard(
                    tier: 'essential',
                    name: 'Essential',
                    package: subscription.essentialPackage,
                    features: const [
                      '1,000 則訊息/月',
                      '每日 150 則上限',
                      '5 種回覆建議',
                      'Needy 警示',
                      '話題深度分析',
                      '對話健檢 (獨家)',
                      'Sonnet 優先模型',
                      '「我說」話題延續建議',
                    ],
                    isSelected: _selectedTier == 'essential',
                    isRecommended: true,
                    onTap: () => setState(() => _selectedTier = 'essential'),
                  ),
                  const SizedBox(height: 32),

                  // CTA button
                  GradientButton(
                    text: _isPurchasing ? '處理中...' : '立即訂閱',
                    onPressed: _isPurchasing ? null : _subscribe,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '可隨時在 App Store 取消訂閱',
                    style: AppTypography.caption.copyWith(color: AppColors.onBackgroundSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // Terms
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () {},
                        child: Text('使用條款', style: AppTypography.caption),
                      ),
                      Text(' | ', style: AppTypography.caption),
                      TextButton(
                        onPressed: () {},
                        child: Text('隱私權政策', style: AppTypography.caption),
                      ),
                      Text(' | ', style: AppTypography.caption),
                      TextButton(
                        onPressed: _restorePurchases,
                        child: Text('恢復購買', style: AppTypography.caption),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
            // Loading overlay
            if (_isPurchasing)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard({
    required String tier,
    required String name,
    required Package? package,
    required List<String> features,
    required bool isSelected,
    bool isRecommended = false,
    required VoidCallback onTap,
  }) {
    // 從 RevenueCat Package 取得真實價格，否則顯示預設
    final priceString = package?.storeProduct.priceString ??
        (tier == 'starter' ? 'NT\$149' : 'NT\$930');

    return GestureDetector(
      onTap: onTap,
      child: GlassmorphicContainer(
        isSelected: isSelected,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(name, style: AppTypography.titleLarge.copyWith(color: AppColors.glassTextPrimary)),
                if (isRecommended) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppColors.selectedStart, AppColors.selectedEnd]),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '推薦',
                      style: AppTypography.caption.copyWith(color: Colors.white),
                    ),
                  ),
                ],
                const Spacer(),
                Radio<String>(
                  value: tier,
                  groupValue: _selectedTier,
                  onChanged: (v) => setState(() => _selectedTier = v!),
                  activeColor: AppColors.selectedStart,
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Price display
            Text(
              '$priceString/月',
              style: AppTypography.headlineMedium.copyWith(
                color: AppColors.glassTextPrimary,
              ),
            ),
            const SizedBox(height: 12),
            ...features.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.check, size: 16, color: AppColors.success),
                    const SizedBox(width: 8),
                    Expanded(child: Text(f, style: AppTypography.bodyMedium.copyWith(color: AppColors.glassTextPrimary))),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _subscribe() async {
    // Web 不支援購買
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請在 iOS App 中訂閱')),
      );
      return;
    }

    final subscription = ref.read(subscriptionProvider);
    final package = _selectedTier == 'essential'
        ? subscription.essentialPackage
        : subscription.starterPackage;

    if (package == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('無法取得產品資訊，請稍後再試')),
      );
      return;
    }

    setState(() => _isPurchasing = true);

    try {
      final success = await ref.read(subscriptionProvider.notifier).purchase(package);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('訂閱成功！'),
              backgroundColor: AppColors.success,
            ),
          );
          context.pop();
        }
      }
    } on PurchasesErrorCode catch (e) {
      if (mounted) {
        String message = '購買失敗';
        if (e == PurchasesErrorCode.purchaseCancelledError) {
          message = '購買已取消';
        } else if (e == PurchasesErrorCode.paymentPendingError) {
          message = '付款處理中';
        } else if (e == PurchasesErrorCode.productNotAvailableForPurchaseError) {
          message = '產品暫時無法購買';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('購買失敗: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPurchasing = false);
      }
    }
  }

  Future<void> _restorePurchases() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請在 iOS App 中恢復購買')),
      );
      return;
    }

    setState(() => _isPurchasing = true);

    try {
      final restored = await ref.read(subscriptionProvider.notifier).restorePurchases();

      if (mounted) {
        if (restored) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('購買已恢復！'),
              backgroundColor: AppColors.success,
            ),
          );
          context.pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('沒有找到可恢復的購買')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('恢復失敗: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPurchasing = false);
      }
    }
  }
}
```

- [ ] **Step 2: 驗證程式碼無錯誤**

Run: `flutter analyze lib/features/subscription/presentation/screens/paywall_screen.dart`
Expected: No issues found

- [ ] **Step 3: Commit**

```bash
git add lib/features/subscription/presentation/screens/paywall_screen.dart
git commit -m "[feat] PaywallScreen 整合 RevenueCat 購買邏輯"
git push
```

---

### Task 8: 修改 SettingsScreen 顯示實際訂閱狀態

**Files:**
- Modify: `lib/features/subscription/presentation/screens/settings_screen.dart`

- [ ] **Step 1: 更新 SettingsScreen**

```dart
// lib/features/subscription/presentation/screens/settings_screen.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
import '../../data/providers/subscription_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscription = ref.watch(subscriptionProvider);
    final user = SupabaseService.currentUser;

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text('設定', style: AppTypography.titleLarge),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildSection(
                  title: '帳戶',
                  children: [
                    _buildTile(
                      context: context,
                      icon: Icons.workspace_premium,
                      title: '訂閱方案',
                      trailing: _getTierDisplayName(subscription.tier),
                      onTap: () => context.push('/paywall'),
                    ),
                    _buildTile(
                      context: context,
                      icon: Icons.analytics,
                      title: '本月用量',
                      trailing: '${subscription.monthlyMessagesUsed}/${subscription.monthlyLimit} 則',
                    ),
                    _buildTile(
                      context: context,
                      icon: Icons.person,
                      title: '帳號',
                      trailing: user?.email ?? '未登入',
                    ),
                    if (!kIsWeb) // 只在 App 顯示恢復購買
                      _buildTile(
                        context: context,
                        icon: Icons.restore,
                        title: '恢復購買',
                        onTap: () => _restorePurchases(context, ref),
                      ),
                  ],
                ),
                _buildSection(
                  title: '隱私與安全',
                  children: [
                    _buildTile(
                      context: context,
                      icon: Icons.delete_forever,
                      title: '清除所有對話資料',
                      titleColor: AppColors.error,
                      onTap: () => _showDeleteDialog(context),
                    ),
                    _buildTile(
                      context: context,
                      icon: Icons.download,
                      title: '匯出我的資料',
                      onTap: () => _showComingSoonSnackBar(context, '匯出功能'),
                    ),
                    _buildTile(
                      context: context,
                      icon: Icons.privacy_tip,
                      title: '隱私權政策',
                      onTap: () => _showComingSoonSnackBar(context, '隱私權政策'),
                    ),
                  ],
                ),
                _buildSection(
                  title: '關於',
                  children: [
                    _buildTile(
                      context: context,
                      icon: Icons.info,
                      title: '版本',
                      trailing: '1.0.0',
                    ),
                    _buildTile(
                      context: context,
                      icon: Icons.description,
                      title: '使用條款',
                      onTap: () => _showComingSoonSnackBar(context, '使用條款'),
                    ),
                    _buildTile(
                      context: context,
                      icon: Icons.feedback,
                      title: '意見回饋',
                      onTap: () => _showComingSoonSnackBar(context, '意見回饋'),
                    ),
                    _buildTile(
                      context: context,
                      icon: Icons.logout,
                      title: '登出',
                      titleColor: AppColors.error,
                      onTap: () => _logout(context, ref),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getTierDisplayName(String tier) {
    switch (tier) {
      case 'starter':
        return 'Starter';
      case 'essential':
        return 'Essential';
      default:
        return 'Free';
    }
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
          child: Text(
            title,
            style: AppTypography.labelLarge.copyWith(
              color: AppColors.onBackgroundSecondary,
            ),
          ),
        ),
        GlassmorphicContainer(
          padding: EdgeInsets.zero,
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    String? trailing,
    Color? titleColor,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: titleColor ?? AppColors.glassTextHint),
      title: Text(
        title,
        style: AppTypography.bodyLarge.copyWith(
          color: titleColor ?? AppColors.glassTextPrimary,
        ),
      ),
      trailing: trailing != null
          ? Text(
              trailing,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.glassTextHint,
              ),
            )
          : Icon(Icons.chevron_right, color: AppColors.glassTextHint),
      onTap: onTap,
    );
  }

  Future<void> _restorePurchases(BuildContext context, WidgetRef ref) async {
    // 顯示 loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final restored = await ref.read(subscriptionProvider.notifier).restorePurchases();

      if (context.mounted) {
        Navigator.pop(context); // 關閉 loading

        if (restored) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('購買已恢復！'),
              backgroundColor: AppColors.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('沒有找到可恢復的購買')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // 關閉 loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('恢復失敗: $e')),
        );
      }
    }
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.glassWhite,
        title: Text(
          '確定要登出？',
          style: TextStyle(color: AppColors.glassTextPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('取消', style: TextStyle(color: AppColors.unselectedText)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('登出', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await SupabaseService.signOut();
      if (context.mounted) {
        context.go('/login');
      }
    }
  }

  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.glassWhite,
        title: Text(
          '確定要刪除所有對話？',
          style: TextStyle(color: AppColors.glassTextPrimary),
        ),
        content: Text(
          '此操作無法復原。您所有的對話紀錄都會被永久刪除。',
          style: TextStyle(color: AppColors.glassTextPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('取消', style: TextStyle(color: AppColors.unselectedText)),
          ),
          TextButton(
            onPressed: () async {
              await StorageService.clearAll();
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('所有對話資料已清除'),
                    backgroundColor: AppColors.success,
                  ),
                );
              }
            },
            child: Text(
              '刪除',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  void _showComingSoonSnackBar(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature 即將推出'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
```

- [ ] **Step 2: 驗證程式碼無錯誤**

Run: `flutter analyze lib/features/subscription/presentation/screens/settings_screen.dart`
Expected: No issues found

- [ ] **Step 3: Commit**

```bash
git add lib/features/subscription/presentation/screens/settings_screen.dart
git commit -m "[feat] SettingsScreen 顯示實際訂閱狀態 + 恢復購買"
git push
```

---

## Chunk 4: Webhook + 部署

### Task 9: 建立 RevenueCat Webhook Edge Function

**Files:**
- Create: `supabase/functions/revenuecat-webhook/index.ts`

- [ ] **Step 1: 建立 Webhook 函數**

```typescript
// supabase/functions/revenuecat-webhook/index.ts
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// RevenueCat Webhook 事件類型
type RevenueCatEventType =
  | "INITIAL_PURCHASE"
  | "RENEWAL"
  | "CANCELLATION"
  | "UNCANCELLATION"
  | "EXPIRATION"
  | "BILLING_ISSUE"
  | "PRODUCT_CHANGE"
  | "SUBSCRIBER_ALIAS"
  | "TRANSFER";

interface RevenueCatEvent {
  api_version: string;
  event: {
    type: RevenueCatEventType;
    app_user_id: string;
    product_id: string;
    entitlement_ids?: string[];
    period_type?: string;
    purchased_at_ms?: number;
    expiration_at_ms?: number;
    environment?: string;
    original_app_user_id?: string;
  };
}

// CORS headers
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-revenuecat-authorization",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// JSON response helper
function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// 從 product_id 判斷 tier
function getTierFromProductId(productId: string): string {
  if (productId.includes("essential")) return "essential";
  if (productId.includes("starter")) return "starter";
  return "free";
}

// 取得 tier 對應的額度
function getLimitsForTier(tier: string): { monthly: number; daily: number } {
  switch (tier) {
    case "essential":
      return { monthly: 1000, daily: 150 };
    case "starter":
      return { monthly: 300, daily: 50 };
    default:
      return { monthly: 30, daily: 15 };
  }
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    // 驗證 RevenueCat Authorization header (可選但建議)
    // const authHeader = req.headers.get("x-revenuecat-authorization");
    // if (authHeader !== Deno.env.get("REVENUECAT_WEBHOOK_SECRET")) {
    //   console.error("Invalid webhook secret");
    //   return jsonResponse({ error: "Unauthorized" }, 401);
    // }

    const body: RevenueCatEvent = await req.json();
    const { event } = body;

    console.log(`📥 RevenueCat webhook: ${event.type} for user ${event.app_user_id}`);
    console.log(`   Product: ${event.product_id}, Environment: ${event.environment}`);

    // 建立 Supabase client (使用 service role 以繞過 RLS)
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // 根據事件類型處理
    switch (event.type) {
      case "INITIAL_PURCHASE":
      case "RENEWAL":
      case "UNCANCELLATION":
      case "PRODUCT_CHANGE": {
        // 新訂閱、續訂、取消後恢復、換方案
        const tier = getTierFromProductId(event.product_id);
        const limits = getLimitsForTier(tier);

        const { error } = await supabase
          .from("subscriptions")
          .update({
            tier,
            status: "active",
            rc_customer_id: event.original_app_user_id || event.app_user_id,
            rc_entitlement_id: event.entitlement_ids?.[0] || null,
            monthly_messages_used: 0, // 重置額度
            daily_messages_used: 0,
            monthly_reset_at: new Date().toISOString(),
            daily_reset_at: new Date().toISOString(),
            started_at: event.purchased_at_ms
              ? new Date(event.purchased_at_ms).toISOString()
              : new Date().toISOString(),
            expires_at: event.expiration_at_ms
              ? new Date(event.expiration_at_ms).toISOString()
              : null,
          })
          .eq("user_id", event.app_user_id);

        if (error) {
          console.error("❌ Update subscription error:", error);
          return jsonResponse({ error: error.message }, 500);
        }

        console.log(`✅ Subscription updated: ${event.app_user_id} → ${tier}`);
        break;
      }

      case "CANCELLATION": {
        // 用戶取消訂閱（但還沒到期）
        const { error } = await supabase
          .from("subscriptions")
          .update({
            status: "cancelled",
          })
          .eq("user_id", event.app_user_id);

        if (error) {
          console.error("❌ Update cancellation error:", error);
          return jsonResponse({ error: error.message }, 500);
        }

        console.log(`✅ Subscription cancelled: ${event.app_user_id}`);
        break;
      }

      case "EXPIRATION": {
        // 訂閱到期，降級為 Free
        const freeLimits = getLimitsForTier("free");

        const { error } = await supabase
          .from("subscriptions")
          .update({
            tier: "free",
            status: "expired",
            monthly_messages_used: 0,
            daily_messages_used: 0,
          })
          .eq("user_id", event.app_user_id);

        if (error) {
          console.error("❌ Update expiration error:", error);
          return jsonResponse({ error: error.message }, 500);
        }

        console.log(`✅ Subscription expired: ${event.app_user_id} → free`);
        break;
      }

      case "BILLING_ISSUE": {
        // 付款問題
        const { error } = await supabase
          .from("subscriptions")
          .update({
            status: "billing_issue",
          })
          .eq("user_id", event.app_user_id);

        if (error) {
          console.error("❌ Update billing issue error:", error);
          return jsonResponse({ error: error.message }, 500);
        }

        console.log(`⚠️ Billing issue: ${event.app_user_id}`);
        break;
      }

      default:
        console.log(`ℹ️ Unhandled event type: ${event.type}`);
    }

    return jsonResponse({ success: true });
  } catch (error) {
    console.error("❌ Webhook error:", error);
    return jsonResponse({ error: String(error) }, 500);
  }
});
```

- [ ] **Step 2: Commit**

```bash
git add supabase/functions/revenuecat-webhook/index.ts
git commit -m "[feat] 新增 RevenueCat Webhook Edge Function"
git push
```

---

### Task 10: 部署 Webhook 並設定

- [ ] **Step 1: 部署 Edge Function**

```bash
cd /mnt/c/Users/eric1/OneDrive/Desktop/VibeSync
SUPABASE_ACCESS_TOKEN=sbp_xxx npx supabase functions deploy revenuecat-webhook --no-verify-jwt --project-ref fcmwrmwdoqiqdnbisdpg
```

Expected: `Function deployed: revenuecat-webhook`

- [ ] **Step 2: 在 RevenueCat 設定 Webhook URL**

1. 前往 RevenueCat Dashboard → Integrations → Webhooks
2. Webhook URL: `https://fcmwrmwdoqiqdnbisdpg.supabase.co/functions/v1/revenuecat-webhook`
3. 選擇事件: `INITIAL_PURCHASE`, `RENEWAL`, `CANCELLATION`, `EXPIRATION`, `BILLING_ISSUE`, `PRODUCT_CHANGE`, `UNCANCELLATION`
4. 點擊 "Save"

- [ ] **Step 3: 測試 Webhook**

在 RevenueCat Dashboard 的 Webhook 設定頁面，點擊 "Send Test Event"
Expected: 收到 200 OK 回應

---

### Task 11: Sandbox 測試

- [ ] **Step 1: 在 App Store Connect 建立 Sandbox Tester**

1. 前往 App Store Connect → Users and Access → Sandbox → Testers
2. 點擊 "+"
3. 填寫測試帳號資訊（使用假的 email，例如 `sandbox1@test.com`）
4. 點擊 "Invite"

- [ ] **Step 2: 在 iPhone 設定 Sandbox 帳號**

1. 設定 → App Store → 滾動到最下方 → Sandbox Account
2. 登入剛才建立的 Sandbox Tester 帳號

- [ ] **Step 3: Build 新版 TestFlight**

```bash
cd /mnt/c/Users/eric1/OneDrive/Desktop/VibeSync
# 觸發 GitHub Actions 手動 workflow
```

或在 GitHub Actions 頁面手動觸發 iOS release workflow

- [ ] **Step 4: 安裝並測試**

1. 在 TestFlight 安裝新版本
2. 登入 App
3. 前往 Paywall 點擊訂閱
4. 使用 Sandbox 帳號完成購買（不會真的扣錢）
5. 確認訂閱狀態更新

- [ ] **Step 5: 驗證 Supabase 資料**

在 Supabase Studio 檢查 `subscriptions` 表，確認：
- `tier` 已更新
- `status` = "active"
- `monthly_messages_used` = 0

---

## 測試檢查清單

| # | 測試案例 | 預期結果 |
|---|---------|---------|
| 1 | Free 用戶點擊訂閱 Starter | Sandbox 付款彈窗 → 成功 → tier 變 starter |
| 2 | Free 用戶點擊訂閱 Essential | Sandbox 付款彈窗 → 成功 → tier 變 essential |
| 3 | 已訂閱用戶前往 Paywall | 顯示目前方案 |
| 4 | 點擊「恢復購買」 | 還原之前的訂閱 |
| 5 | 在 Settings 查看用量 | 顯示實際月用量/上限 |
| 6 | Web 平台點擊訂閱 | 顯示「請在 iOS App 中訂閱」 |

---

## 完成後更新 CLAUDE.md

將以下內容加入 CLAUDE.md 的「已完成功能」區塊：

```markdown
| **RevenueCat 整合** | ✅ 完成 | iOS 月訂閱、購買/恢復、Webhook |
```
