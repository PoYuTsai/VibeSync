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
  final Offerings? offerings;

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
    final packages = offerings?.current?.availablePackages;
    if (packages == null || packages.isEmpty) return null;

    return packages.cast<Package?>().firstWhere(
          (p) => p?.storeProduct.identifier.contains('starter') ?? false,
          orElse: () => null,
        );
  }

  /// 取得 Essential 的 Package
  Package? get essentialPackage {
    final packages = offerings?.current?.availablePackages;
    if (packages == null || packages.isEmpty) return null;

    return packages.cast<Package?>().firstWhere(
          (p) => p?.storeProduct.identifier.contains('essential') ?? false,
          orElse: () => null,
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
    // 同步 RevenueCat 狀態（捕捉 webhook 漏掉的更新）
    await syncWithRevenueCat();
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
      debugPrint('Load subscription error: $e');
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
        debugPrint(
            'Offerings loaded: ${offerings.current?.availablePackages.length} packages');
      }
    } catch (e) {
      debugPrint('Load offerings error: $e');
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

      debugPrint('=== PURCHASE START ===');
      debugPrint('Package: ${package.storeProduct.identifier}');

      // purchase() 直接返回更新後的 CustomerInfo
      final customerInfo = await RevenueCatService.purchase(package);

      debugPrint('=== PURCHASE RESULT ===');
      debugPrint('Active Subscriptions: ${customerInfo.activeSubscriptions}');
      debugPrint('All Purchased: ${customerInfo.allPurchasedProductIdentifiers}');
      debugPrint('Active Entitlements: ${customerInfo.entitlements.active.keys.toList()}');

      // 直接從購買結果取得 tier（不需要再呼叫 getCustomerInfo）
      String tier = RevenueCatService.getTierFromCustomerInfo(customerInfo);

      // 如果 RevenueCat 返回 free 但有購買紀錄，從 product ID 推測 tier
      if (tier == 'free' && customerInfo.allPurchasedProductIdentifiers.isNotEmpty) {
        debugPrint('[purchase] WARNING: tier is free but has purchases, inferring from product ID');
        final productId = package.storeProduct.identifier;
        if (productId.contains('essential')) {
          tier = 'essential';
        } else if (productId.contains('starter')) {
          tier = 'starter';
        }
        debugPrint('[purchase] Inferred tier from product ID: $tier');
      }

      final limits = _tierLimits[tier] ?? _tierLimits['free']!;

      debugPrint('Detected tier: $tier, limits: $limits');

      // 主動更新 Supabase（不依賴 webhook），重試最多 3 次
      bool syncSuccess = false;
      for (var attempt = 1; attempt <= 3; attempt++) {
        debugPrint('[purchase] Supabase sync attempt $attempt/3');
        syncSuccess = await _updateSupabaseTier(tier);
        if (syncSuccess) break;
        await Future.delayed(Duration(seconds: attempt));
      }

      if (!syncSuccess) {
        debugPrint('[purchase] WARNING: Supabase sync failed after 3 attempts, using forceSyncTier');
        await forceSyncTier(tier);
      }

      state = state.copyWith(
        tier: tier,
        monthlyLimit: limits['monthly']!,
        dailyLimit: limits['daily']!,
        isLoading: false,
      );

      debugPrint('State updated: tier=${state.tier}, monthlyLimit=${state.monthlyLimit}');
      debugPrint('=== PURCHASE END ===');

      return true;
    } catch (e) {
      debugPrint('Purchase error: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  /// 強制同步 tier 到 Supabase（含重置每日用量）
  Future<void> forceSyncTier(String tier) async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) {
        debugPrint('[forceSyncTier] ERROR: No user logged in');
        throw Exception('請先登入');
      }

      debugPrint('[forceSyncTier] Starting sync: tier=$tier, user=${user.id}');

      final limits = _tierLimits[tier] ?? _tierLimits['free']!;

      // 先檢查是否有 subscription record
      final existing = await SupabaseService.client
          .from('subscriptions')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      debugPrint('[forceSyncTier] Existing record: $existing');

      if (existing == null) {
        // 沒有記錄，插入新的
        debugPrint('[forceSyncTier] No existing record, inserting new one');
        await SupabaseService.client
            .from('subscriptions')
            .insert({
              'user_id': user.id,
              'tier': tier,
              'monthly_messages_used': 0,
              'daily_messages_used': 0,
            });
      } else {
        // 有記錄，更新
        debugPrint('[forceSyncTier] Updating existing record');
        await SupabaseService.client
            .from('subscriptions')
            .update({
              'tier': tier,
              'daily_messages_used': 0, // 重置每日用量
            })
            .eq('user_id', user.id);
      }

      debugPrint('[forceSyncTier] SUCCESS: Supabase force synced: tier=$tier, daily_messages_used=0');

      // 更新本地 state
      state = state.copyWith(
        tier: tier,
        monthlyLimit: limits['monthly']!,
        dailyLimit: limits['daily']!,
        dailyMessagesUsed: 0,
      );

      debugPrint('[forceSyncTier] Local state updated: tier=${state.tier}, limits=${limits}');

    } catch (e) {
      debugPrint('[forceSyncTier] ERROR: $e');
      rethrow;
    }
  }

  /// 主動更新 Supabase tier（作為 webhook 的 backup）
  Future<bool> _updateSupabaseTier(String tier) async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) {
        debugPrint('[_updateSupabaseTier] ERROR: No user logged in');
        return false;
      }

      debugPrint('[_updateSupabaseTier] Updating tier to "$tier" for user ${user.id}');

      final result = await SupabaseService.client
          .from('subscriptions')
          .update({'tier': tier})
          .eq('user_id', user.id)
          .select();

      debugPrint('[_updateSupabaseTier] Update result: $result');

      if (result.isEmpty) {
        debugPrint('[_updateSupabaseTier] WARNING: No rows updated - subscription record might not exist');
        // 嘗試 upsert
        await SupabaseService.client
            .from('subscriptions')
            .upsert({
              'user_id': user.id,
              'tier': tier,
              'monthly_messages_used': 0,
              'daily_messages_used': 0,
            });
        debugPrint('[_updateSupabaseTier] Upserted subscription record');
      }

      debugPrint('[_updateSupabaseTier] SUCCESS: Supabase tier updated to: $tier');
      return true;
    } catch (e) {
      // 更新失敗不影響主流程，webhook 會再試
      debugPrint('[_updateSupabaseTier] FAILED: $e');
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

      // 主動更新 Supabase
      if (tier != 'free') {
        await _updateSupabaseTier(tier);
      }

      state = state.copyWith(
        tier: tier,
        monthlyLimit: limits['monthly']!,
        dailyLimit: limits['daily']!,
        isLoading: false,
      );

      return tier != 'free';
    } catch (e) {
      debugPrint('Restore error: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  /// 同步 RevenueCat 狀態到本地和 Supabase
  /// 可在 App 啟動或進入設定頁時呼叫
  Future<void> syncWithRevenueCat() async {
    try {
      final customerInfo = await RevenueCatService.getCustomerInfo();
      if (customerInfo == null) return;

      final rcTier = RevenueCatService.getTierFromCustomerInfo(customerInfo);

      // 如果 RevenueCat 的 tier 和目前不同，更新
      if (rcTier != state.tier) {
        debugPrint('Tier mismatch: local=${state.tier}, RevenueCat=$rcTier');

        final limits = _tierLimits[rcTier] ?? _tierLimits['free']!;

        // 更新 Supabase
        await _updateSupabaseTier(rcTier);

        // 更新本地 state
        state = state.copyWith(
          tier: rcTier,
          monthlyLimit: limits['monthly']!,
          dailyLimit: limits['daily']!,
        );
      }
    } catch (e) {
      debugPrint('Sync with RevenueCat error: $e');
    }
  }
}

final subscriptionProvider =
    StateNotifierProvider<SubscriptionNotifier, SubscriptionState>((ref) {
  return SubscriptionNotifier();
});
