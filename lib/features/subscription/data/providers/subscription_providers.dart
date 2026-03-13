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
      debugPrint('Purchase error: $e');
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
      debugPrint('Restore error: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }
}

final subscriptionProvider =
    StateNotifierProvider<SubscriptionNotifier, SubscriptionState>((ref) {
  return SubscriptionNotifier();
});
