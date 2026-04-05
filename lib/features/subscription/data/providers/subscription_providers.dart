import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/revenuecat_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/usage_service.dart';
import '../../domain/services/subscription_tier_helper.dart';

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
    this.tier = SubscriptionTierHelper.free,
    this.monthlyMessagesUsed = 0,
    this.dailyMessagesUsed = 0,
    this.monthlyLimit = 30,
    this.dailyLimit = 15,
    this.isLoading = false,
    this.error,
    this.offerings,
  });

  bool get isFreeUser => tier == SubscriptionTierHelper.free;
  bool get isStarter => tier == SubscriptionTierHelper.starter;
  bool get isEssential => tier == SubscriptionTierHelper.essential;
  bool get isPremium => isStarter || isEssential;

  int get monthlyRemaining =>
      (monthlyLimit - monthlyMessagesUsed).clamp(0, monthlyLimit);
  int get dailyRemaining =>
      (dailyLimit - dailyMessagesUsed).clamp(0, dailyLimit);

  Package? get starterPackage {
    final packages = offerings?.current?.availablePackages;
    if (packages == null || packages.isEmpty) return null;

    return packages.cast<Package?>().firstWhere(
          (p) => p?.storeProduct.identifier.contains('starter') ?? false,
          orElse: () => null,
        );
  }

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

class SubscriptionPurchaseResult {
  final bool success;
  final bool cancelled;
  final String requestedTier;
  final String activeTier;
  final PurchasesErrorCode? errorCode;
  final String? errorMessage;

  const SubscriptionPurchaseResult({
    required this.success,
    required this.cancelled,
    required this.requestedTier,
    required this.activeTier,
    this.errorCode,
    this.errorMessage,
  });

  bool get isDeferredDowngrade =>
      success &&
      SubscriptionTierHelper.isDowngrade(
        fromTier: activeTier,
        toTier: requestedTier,
      );
}

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

  int _readInt(dynamic value, {int fallback = 0}) {
    if (value is num) {
      return value.round();
    }
    return fallback;
  }

  Future<String?> _syncSubscriptionViaEdgeFunction({
    required String expectedTier,
    required bool resetUsage,
  }) async {
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        final response = await SupabaseService.invokeFunction(
          'sync-subscription',
          body: {
            'expectedTier': expectedTier,
            'resetUsage': resetUsage,
          },
        );

        if (response.status < 200 || response.status >= 300) {
          debugPrint(
            '[sync-subscription] failed attempt $attempt/3: status=${response.status}, data=${response.data}',
          );
        } else {
          final data = response.data;
          if (data is Map) {
            final tier = SubscriptionTierHelper.normalizeTier(
              data['tier'] as String?,
            );
            final limits = SubscriptionTierHelper.limitsFor(tier);
            final monthlyUsed = _readInt(data['monthlyMessagesUsed']);
            final dailyUsed = _readInt(data['dailyMessagesUsed']);

            state = state.copyWith(
              tier: tier,
              monthlyLimit: limits.monthly,
              dailyLimit: limits.daily,
              monthlyMessagesUsed: monthlyUsed,
              dailyMessagesUsed: dailyUsed,
              error: null,
            );
            UsageService.syncSubscriptionSnapshot(
              tier: tier,
              monthlyLimit: limits.monthly,
              dailyLimit: limits.daily,
              monthlyUsed: monthlyUsed,
              dailyUsed: dailyUsed,
            );

            debugPrint(
              '[sync-subscription] success: tier=$tier, monthlyUsed=$monthlyUsed, dailyUsed=$dailyUsed',
            );
            return tier;
          }

          debugPrint(
            '[sync-subscription] invalid payload attempt $attempt/3: $data',
          );
        }
      } catch (error) {
        debugPrint('[sync-subscription] exception attempt $attempt/3: $error');
      }

      if (attempt < 3) {
        await Future.delayed(Duration(milliseconds: 400 * attempt));
      }
    }

    return null;
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
    if (state.isLoading) return;

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
      if (_isDuplicateSubscriptionError(error)) {
        final recovered = await SupabaseService.client
            .from('subscriptions')
            .select()
            .eq('user_id', userId)
            .maybeSingle();

        if (recovered != null) {
          return Map<String, dynamic>.from(recovered);
        }
      }

      return _buildFreshSubscriptionRecord(userId: userId, tier: tier);
    }
  }

  Future<void> _initialize() async {
    await _loadSubscription();
    await _loadOfferings();
    await syncWithRevenueCat();
  }

  Future<void> _loadSubscription() async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) {
        state = const SubscriptionState(error: 'Not logged in');
        return;
      }

      await RevenueCatService.login(user.id);

      final response = await _loadOrCreateSubscriptionRecord(
        userId: user.id,
        tier: SubscriptionTierHelper.free,
      );

      final initialTier = SubscriptionTierHelper.normalizeTier(
        response['tier'] as String?,
      );
      final initialLimits = SubscriptionTierHelper.limitsFor(initialTier);

      state = state.copyWith(
        tier: initialTier,
        monthlyMessagesUsed: _readInt(response['monthly_messages_used']),
        dailyMessagesUsed: _readInt(response['daily_messages_used']),
        monthlyLimit: initialLimits.monthly,
        dailyLimit: initialLimits.daily,
        isLoading: false,
        error: null,
      );
      UsageService.syncSubscriptionSnapshot(
        tier: initialTier,
        monthlyLimit: initialLimits.monthly,
        dailyLimit: initialLimits.daily,
        monthlyUsed: _readInt(response['monthly_messages_used']),
        dailyUsed: _readInt(response['daily_messages_used']),
      );

      await _syncSubscriptionViaEdgeFunction(
        expectedTier: initialTier,
        resetUsage: false,
      );
    } catch (e) {
      debugPrint('Load subscription error: $e');
      state = SubscriptionState(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> _loadOfferings() async {
    try {
      final offerings = await RevenueCatService.getOfferings();
      if (offerings != null) {
        state = state.copyWith(offerings: offerings);
        debugPrint(
          'Offerings loaded: ${offerings.current?.availablePackages.length} packages',
        );
      }
    } catch (e) {
      debugPrint('Load offerings error: $e');
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    await _loadSubscription();
    await _loadOfferings();
  }

  Future<SubscriptionPurchaseResult> purchase(Package package) async {
    final requestedTier = SubscriptionTierHelper.tierFromProductId(
      package.storeProduct.identifier,
    );

    try {
      state = state.copyWith(isLoading: true, error: null);

      debugPrint('=== PURCHASE START ===');
      debugPrint('Package: ${package.storeProduct.identifier}');

      final customerInfo = await RevenueCatService.purchase(package);

      debugPrint('=== PURCHASE RESULT ===');
      debugPrint('Active Subscriptions: ${customerInfo.activeSubscriptions}');
      debugPrint(
        'All Purchased: ${customerInfo.allPurchasedProductIdentifiers}',
      );
      debugPrint(
        'Active Entitlements: ${customerInfo.entitlements.active.keys.toList()}',
      );

      final resolvedTier = _resolvePurchasedTier(
        package: package,
        customerInfo: customerInfo,
      );
      final previousTier = state.tier;
      final syncedTier = await _syncSubscriptionViaEdgeFunction(
        expectedTier: resolvedTier,
        resetUsage:
            previousTier != resolvedTier &&
            resolvedTier != SubscriptionTierHelper.free,
      );
      final tier = syncedTier ?? resolvedTier;
      final limits = SubscriptionTierHelper.limitsFor(tier);

      state = state.copyWith(
        tier: tier,
        monthlyLimit: limits.monthly,
        dailyLimit: limits.daily,
        isLoading: false,
        error: null,
      );
      _syncUsageCache(tier, limits);

      debugPrint(
        '[purchase] final tier=$tier, synced=${syncedTier ?? 'null'}, monthlyLimit=${state.monthlyLimit}',
      );
      debugPrint('=== PURCHASE END ===');

      return SubscriptionPurchaseResult(
        success: true,
        cancelled: false,
        requestedTier: requestedTier,
        activeTier: tier,
      );
    } on PlatformException catch (error) {
      final errorCode = PurchasesErrorHelper.getErrorCode(error);
      debugPrint('Purchase platform error: $errorCode / $error');
      state = state.copyWith(isLoading: false, error: null);
      return SubscriptionPurchaseResult(
        success: false,
        cancelled: errorCode == PurchasesErrorCode.purchaseCancelledError,
        requestedTier: requestedTier,
        activeTier: state.tier,
        errorCode: errorCode,
        errorMessage: error.message ?? error.toString(),
      );
    } catch (e) {
      debugPrint('Purchase error: $e');
      state = state.copyWith(isLoading: false, error: null);
      return SubscriptionPurchaseResult(
        success: false,
        cancelled: false,
        requestedTier: requestedTier,
        activeTier: state.tier,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> forceSyncTier(String tier) async {
    final user = SupabaseService.currentUser;
    if (user == null) {
      debugPrint('[forceSyncTier] ERROR: No user logged in');
      throw Exception('尚未登入');
    }

    debugPrint('[forceSyncTier] Starting sync: tier=$tier, user=${user.id}');
    final syncedTier = await _syncSubscriptionViaEdgeFunction(
      expectedTier: tier,
      resetUsage: tier != SubscriptionTierHelper.free,
    );
    if (syncedTier == null) {
      throw Exception('訂閱同步失敗');
    }

    debugPrint(
      '[forceSyncTier] SUCCESS: synced tier=${state.tier}, daily_messages_used=${state.dailyMessagesUsed}',
    );
  }

  Future<bool> _updateSupabaseTier(
    String tier, {
    bool resetUsage = false,
  }) async {
    final user = SupabaseService.currentUser;
    if (user == null) {
      debugPrint('[_updateSupabaseTier] ERROR: No user logged in');
      return false;
    }

    debugPrint(
      '[_updateSupabaseTier] Syncing tier "$tier" for user ${user.id}',
    );
    final syncedTier = await _syncSubscriptionViaEdgeFunction(
      expectedTier: tier,
      resetUsage: resetUsage,
    );
    final success = syncedTier != null;
    debugPrint(
      '[_updateSupabaseTier] ${success ? 'SUCCESS' : 'FAILED'}: syncedTier=${syncedTier ?? 'null'}',
    );
    return success;
  }

  Future<bool> restorePurchases() async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      final customerInfo = await RevenueCatService.restorePurchases();
      final restoredTier = RevenueCatService.getTierFromCustomerInfo(customerInfo);
      final previousTier = state.tier;
      final syncedTier = await _syncSubscriptionViaEdgeFunction(
        expectedTier: restoredTier,
        resetUsage:
            previousTier != restoredTier &&
            restoredTier != SubscriptionTierHelper.free,
      );
      final tier = syncedTier ?? restoredTier;
      final limits = SubscriptionTierHelper.limitsFor(tier);

      state = state.copyWith(
        tier: tier,
        monthlyLimit: limits.monthly,
        dailyLimit: limits.daily,
        isLoading: false,
        error: null,
      );
      _syncUsageCache(tier, limits);

      return tier != SubscriptionTierHelper.free;
    } catch (e) {
      debugPrint('Restore error: $e');
      state = state.copyWith(isLoading: false, error: null);
      rethrow;
    }
  }

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

      if (rcTier != state.tier) {
        debugPrint('Tier mismatch: local=${state.tier}, RevenueCat=$rcTier');

        final syncedTier = await _syncSubscriptionViaEdgeFunction(
          expectedTier: rcTier,
          resetUsage:
              state.tier != rcTier && rcTier != SubscriptionTierHelper.free,
        );
        final tier = syncedTier ?? rcTier;
        final limits = SubscriptionTierHelper.limitsFor(tier);

        state = state.copyWith(
          tier: tier,
          monthlyLimit: limits.monthly,
          dailyLimit: limits.daily,
        );
        _syncUsageCache(tier, limits);
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
