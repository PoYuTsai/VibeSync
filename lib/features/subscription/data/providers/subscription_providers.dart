// lib/features/subscription/data/providers/subscription_providers.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/services/revenuecat_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/usage_service.dart';
import '../../domain/services/subscription_tier_helper.dart';

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

  int get monthlyRemaining =>
      (monthlyLimit - monthlyMessagesUsed).clamp(0, monthlyLimit);
  int get dailyRemaining =>
      (dailyLimit - dailyMessagesUsed).clamp(0, dailyLimit);

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

  String _highestTier(Iterable<String> tiers) {
    final normalized =
        tiers.map(SubscriptionTierHelper.normalizeTier).toList(growable: false);

    if (normalized.contains(SubscriptionTierHelper.essential)) {
      return SubscriptionTierHelper.essential;
    }
    if (normalized.contains(SubscriptionTierHelper.starter)) {
      return SubscriptionTierHelper.starter;
    }
    return SubscriptionTierHelper.free;
  }

  String _resolvePurchasedTier({
    required Package package,
    required CustomerInfo customerInfo,
  }) {
    final revenueCatTier = RevenueCatService.getTierFromCustomerInfo(
      customerInfo,
    );
    final packageTier = SubscriptionTierHelper.tierFromProductId(
      package.storeProduct.identifier,
    );
    final resolvedTier = _highestTier([revenueCatTier, packageTier]);

    debugPrint(
      '[purchase] Resolved tier: revenueCat=$revenueCatTier, package=$packageTier, final=$resolvedTier',
    );

    return resolvedTier;
  }

  void _syncUsageCache(String tier, SubscriptionTierLimits limits) {
    UsageService.syncSubscriptionSnapshot(
      tier: tier,
      monthlyLimit: limits.monthly,
      dailyLimit: limits.daily,
    );
  }

  void syncUsageFromServer({
    required int monthlyRemaining,
    required int dailyRemaining,
    bool isTestAccount = false,
  }) {
    if (state.isLoading) {
      return;
    }

    if (isTestAccount) {
      final limits = SubscriptionTierHelper.limitsFor(state.tier);
      _syncUsageCache(state.tier, limits);
      return;
    }

    final normalizedMonthlyRemaining =
        monthlyRemaining.clamp(0, state.monthlyLimit);
    final normalizedDailyRemaining = dailyRemaining.clamp(0, state.dailyLimit);
    final monthlyUsed = (state.monthlyLimit - normalizedMonthlyRemaining)
        .clamp(0, state.monthlyLimit);
    final dailyUsed =
        (state.dailyLimit - normalizedDailyRemaining).clamp(0, state.dailyLimit);

    final limits = SubscriptionTierHelper.limitsFor(state.tier);
    state = state.copyWith(
      monthlyMessagesUsed: monthlyUsed,
      dailyMessagesUsed: dailyUsed,
    );
    UsageService.syncSubscriptionSnapshot(
      tier: state.tier,
      monthlyLimit: limits.monthly,
      dailyLimit: limits.daily,
      monthlyUsed: monthlyUsed,
      dailyUsed: dailyUsed,
    );
  }

  Map<String, dynamic> _buildFreshSubscriptionRecord({
    required String userId,
    required String tier,
  }) {
    final nowIso = DateTime.now().toIso8601String();
    return {
      'user_id': userId,
      'tier': tier,
      'monthly_messages_used': 0,
      'daily_messages_used': 0,
      'daily_reset_at': nowIso,
      'monthly_reset_at': nowIso,
      'started_at': nowIso,
    };
  }

  bool _isDuplicateSubscriptionError(Object error) {
    return error is PostgrestException && error.code == '23505';
  }

  Future<Map<String, dynamic>> _loadOrCreateSubscriptionRecord({
    required String userId,
    required String tier,
  }) async {
    final existing = await SupabaseService.client
        .from('subscriptions')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (existing != null) {
      return Map<String, dynamic>.from(existing);
    }

    try {
      final inserted = await SupabaseService.client
          .from('subscriptions')
          .insert(_buildFreshSubscriptionRecord(userId: userId, tier: tier))
          .select()
          .single();

      return Map<String, dynamic>.from(inserted);
    } on PostgrestException catch (error) {
      if (!_isDuplicateSubscriptionError(error)) {
        rethrow;
      }

      final recovered = await SupabaseService.client
          .from('subscriptions')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (recovered != null) {
        return Map<String, dynamic>.from(recovered);
      }

      rethrow;
    }
  }

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

      final response = await _loadOrCreateSubscriptionRecord(
        userId: user.id,
        tier: SubscriptionTierHelper.free,
      );

      final tier = SubscriptionTierHelper.normalizeTier(
        response['tier'] as String?,
      );
      final limits = SubscriptionTierHelper.limitsFor(tier);

      state = state.copyWith(
        tier: tier,
        monthlyMessagesUsed: response['monthly_messages_used'] as int? ?? 0,
        dailyMessagesUsed: response['daily_messages_used'] as int? ?? 0,
        monthlyLimit: limits.monthly,
        dailyLimit: limits.daily,
        isLoading: false,
      );
      _syncUsageCache(tier, limits);
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
      debugPrint(
          'All Purchased: ${customerInfo.allPurchasedProductIdentifiers}');
      debugPrint(
          'Active Entitlements: ${customerInfo.entitlements.active.keys.toList()}');

      // 直接從購買結果取得 tier（不需要再呼叫 getCustomerInfo）
      final resolvedTier = _resolvePurchasedTier(
        package: package,
        customerInfo: customerInfo,
      );

      final tier = resolvedTier;
      final limits = SubscriptionTierHelper.limitsFor(tier);

      debugPrint('Detected tier: $tier, limits: $limits');

      // 主動更新 Supabase（不依賴 webhook），重試最多 3 次
      bool syncSuccess = false;
      for (var attempt = 1; attempt <= 3; attempt++) {
        debugPrint('[purchase] Supabase sync attempt $attempt/3');
        syncSuccess = await _updateSupabaseTier(
          tier,
          resetUsage:
              state.tier != tier && tier != SubscriptionTierHelper.free,
        );
        if (syncSuccess) break;
        await Future.delayed(Duration(seconds: attempt));
      }

      if (!syncSuccess) {
        debugPrint(
            '[purchase] WARNING: Supabase sync failed after 3 attempts, using forceSyncTier');
        await forceSyncTier(tier);
      }

      state = state.copyWith(
        tier: tier,
        monthlyLimit: limits.monthly,
        dailyLimit: limits.daily,
        monthlyMessagesUsed:
            state.tier != tier ? 0 : state.monthlyMessagesUsed,
        dailyMessagesUsed: state.tier != tier ? 0 : state.dailyMessagesUsed,
        isLoading: false,
      );
      _syncUsageCache(tier, limits);

      debugPrint(
          'State updated: tier=${state.tier}, monthlyLimit=${state.monthlyLimit}');
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

      final limits = SubscriptionTierHelper.limitsFor(tier);

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
        try {
          await SupabaseService.client.from('subscriptions').insert(
                _buildFreshSubscriptionRecord(userId: user.id, tier: tier),
              );
        } on PostgrestException catch (error) {
          if (!_isDuplicateSubscriptionError(error)) {
            rethrow;
          }

          debugPrint(
            '[forceSyncTier] Insert raced with an existing row, retrying as update',
          );
          await SupabaseService.client.from('subscriptions').update({
            'tier': tier,
            'monthly_messages_used': 0,
            'daily_messages_used': 0,
          }).eq('user_id', user.id);
        }
      } else {
        // 有記錄，更新
        debugPrint('[forceSyncTier] Updating existing record');
        await SupabaseService.client.from('subscriptions').update({
          'tier': tier,
          'monthly_messages_used': 0,
          'daily_messages_used': 0, // 重置每日用量
        }).eq('user_id', user.id);
      }

      debugPrint(
          '[forceSyncTier] SUCCESS: Supabase force synced: tier=$tier, daily_messages_used=0');

      // 更新本地 state
      state = state.copyWith(
        tier: tier,
        monthlyLimit: limits.monthly,
        dailyLimit: limits.daily,
        monthlyMessagesUsed: 0,
        dailyMessagesUsed: 0,
      );
      _syncUsageCache(tier, limits);

      debugPrint(
          '[forceSyncTier] Local state updated: tier=${state.tier}, limits=$limits');
    } catch (e) {
      debugPrint('[forceSyncTier] ERROR: $e');
      rethrow;
    }
  }

  /// 主動更新 Supabase tier（作為 webhook 的 backup）
  Future<bool> _updateSupabaseTier(
    String tier, {
    bool resetUsage = false,
  }) async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) {
        debugPrint('[_updateSupabaseTier] ERROR: No user logged in');
        return false;
      }

      debugPrint(
          '[_updateSupabaseTier] Updating tier to "$tier" for user ${user.id}');

      final updatePayload = <String, dynamic>{'tier': tier};
      if (resetUsage) {
        updatePayload['monthly_messages_used'] = 0;
        updatePayload['daily_messages_used'] = 0;
      }

      final result = await SupabaseService.client
          .from('subscriptions')
          .update(updatePayload)
          .eq('user_id', user.id)
          .select();

      debugPrint('[_updateSupabaseTier] Update result: $result');

      if (result.isEmpty) {
        debugPrint(
            '[_updateSupabaseTier] WARNING: No rows updated - subscription record might not exist');
        // 嘗試 upsert
        try {
          await SupabaseService.client.from('subscriptions').insert(
                _buildFreshSubscriptionRecord(userId: user.id, tier: tier),
              );
          debugPrint(
            '[_updateSupabaseTier] Inserted missing subscription record',
          );
        } on PostgrestException catch (error) {
          if (!_isDuplicateSubscriptionError(error)) {
            rethrow;
          }

          debugPrint(
            '[_updateSupabaseTier] Insert raced with an existing row, retrying update',
          );
          final retryResult = await SupabaseService.client
              .from('subscriptions')
              .update(updatePayload)
              .eq('user_id', user.id)
              .select();

          if (retryResult.isEmpty) {
            throw StateError(
              'Subscription tier update could not find a row after duplicate insert race.',
            );
          }
        }
      }

      debugPrint(
          '[_updateSupabaseTier] SUCCESS: Supabase tier updated to: $tier');
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
      final limits = SubscriptionTierHelper.limitsFor(tier);

      // 主動更新 Supabase
      await _updateSupabaseTier(
        tier,
        resetUsage:
            state.tier != tier && tier != SubscriptionTierHelper.free,
      );

      state = state.copyWith(
        tier: tier,
        monthlyLimit: limits.monthly,
        dailyLimit: limits.daily,
        monthlyMessagesUsed:
            state.tier != tier ? 0 : state.monthlyMessagesUsed,
        dailyMessagesUsed: state.tier != tier ? 0 : state.dailyMessagesUsed,
        isLoading: false,
      );
      _syncUsageCache(tier, limits);

      return tier != SubscriptionTierHelper.free;
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

      if (state.isPremium && rcTier == SubscriptionTierHelper.free) {
        debugPrint(
          'Tier mismatch ignored: local=${state.tier}, RevenueCat=$rcTier (keep premium until sync stabilizes)',
        );
        return;
      }

      // 如果 RevenueCat 的 tier 和目前不同，更新
      if (rcTier != state.tier) {
        debugPrint('Tier mismatch: local=${state.tier}, RevenueCat=$rcTier');

        final limits = SubscriptionTierHelper.limitsFor(rcTier);

        // 更新 Supabase
        await _updateSupabaseTier(
          rcTier,
          resetUsage:
              state.tier != rcTier && rcTier != SubscriptionTierHelper.free,
        );

        // 更新本地 state
        state = state.copyWith(
          tier: rcTier,
          monthlyLimit: limits.monthly,
          dailyLimit: limits.daily,
          monthlyMessagesUsed:
              state.tier != rcTier ? 0 : state.monthlyMessagesUsed,
          dailyMessagesUsed:
              state.tier != rcTier ? 0 : state.dailyMessagesUsed,
        );
        _syncUsageCache(rcTier, limits);
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
