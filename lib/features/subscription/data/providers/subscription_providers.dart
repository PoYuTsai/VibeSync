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

      // purchase() 直接返回更新後的 CustomerInfo
      final customerInfo = await RevenueCatService.purchase(package);

      debugPrint('Purchase successful, checking tier from CustomerInfo...');

      // 直接從購買結果取得 tier（不需要再呼叫 getCustomerInfo）
      final tier = RevenueCatService.getTierFromCustomerInfo(customerInfo);
      final limits = _tierLimits[tier] ?? _tierLimits['free']!;

      debugPrint('Detected tier: $tier, limits: $limits');

      // 主動更新 Supabase（不依賴 webhook）
      await _updateSupabaseTier(tier);

      state = state.copyWith(
        tier: tier,
        monthlyLimit: limits['monthly']!,
        dailyLimit: limits['daily']!,
        isLoading: false,
      );

      debugPrint('State updated: tier=${state.tier}, monthlyLimit=${state.monthlyLimit}');

      return true;
    } catch (e) {
      debugPrint('Purchase error: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  /// 主動更新 Supabase tier（作為 webhook 的 backup）
  Future<void> _updateSupabaseTier(String tier) async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) return;

      await SupabaseService.client
          .from('subscriptions')
          .update({'tier': tier})
          .eq('user_id', user.id);

      debugPrint('Supabase tier updated to: $tier');
    } catch (e) {
      // 更新失敗不影響主流程，webhook 會再試
      debugPrint('Failed to update Supabase tier: $e');
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
