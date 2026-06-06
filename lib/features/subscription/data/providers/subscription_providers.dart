import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/revenuecat_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/usage_service.dart';
import '../../domain/services/subscription_tier_helper.dart';

const _subscriptionStateUnset = Object();
const _starterMonthlyProductId = 'starter_monthly';
const _starterQuarterlyProductId = 'starter_quarterly';
const _essentialMonthlyProductId = 'essential_monthly';
const _essentialQuarterlyProductId = 'essential_quarterly';
const _starterMonthlyProductIds = [
  _starterMonthlyProductId,
  'vibesync_starter_monthly',
  'vibesync_starter_monthly_v2',
];
const _starterQuarterlyProductIds = [
  _starterQuarterlyProductId,
  'vibesync_starter_quarterly',
  'vibesync_starter_quarterly_v2',
];
const _essentialMonthlyProductIds = [
  _essentialMonthlyProductId,
  'vibesync_essential_monthly',
  'vibesync_essential_monthly_v2',
];
const _essentialQuarterlyProductIds = [
  _essentialQuarterlyProductId,
  'vibesync_essential_quarterly',
  'vibesync_essential_quarterly_v2',
];
const _subscriptionProductIds = [
  ..._starterMonthlyProductIds,
  ..._starterQuarterlyProductIds,
  ..._essentialMonthlyProductIds,
  ..._essentialQuarterlyProductIds,
];

String _highestSubscriptionTier(Iterable<String> tiers) {
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

bool _isExpired(DateTime? value, {DateTime? now}) {
  if (value == null) return false;
  return !value.toUtc().isAfter((now ?? DateTime.now()).toUtc());
}

@visibleForTesting
String resolveStartupSubscriptionTier({
  required String databaseTier,
  required String revenueCatTier,
  required String cachedTier,
  DateTime? serverExpiresAt,
  DateTime? now,
}) {
  final confirmedTier = _highestSubscriptionTier([
    databaseTier,
    revenueCatTier,
  ]);
  if (confirmedTier != SubscriptionTierHelper.free) {
    return confirmedTier;
  }

  final normalizedCachedTier = SubscriptionTierHelper.normalizeTier(cachedTier);
  if (normalizedCachedTier != SubscriptionTierHelper.free &&
      !_isExpired(serverExpiresAt, now: now)) {
    return normalizedCachedTier;
  }

  return SubscriptionTierHelper.free;
}

@visibleForTesting
SubscriptionState buildInitialSubscriptionStateFromUsage(UsageData usage) {
  final tier = SubscriptionTierHelper.normalizeTier(usage.tier);
  final limits = SubscriptionTierHelper.limitsFor(tier);
  return SubscriptionState(
    tier: tier,
    monthlyMessagesUsed: usage.monthlyUsed.clamp(0, limits.monthly),
    dailyMessagesUsed: usage.dailyUsed.clamp(0, limits.daily),
    monthlyLimit: limits.monthly,
    dailyLimit: limits.daily,
    isLoading: true,
  );
}

@visibleForTesting
String resolveStartupPaidRescueTier({
  required String currentTier,
  required String revenueCatTier,
  String? syncedTier,
}) {
  final normalizedCurrentTier =
      SubscriptionTierHelper.normalizeTier(currentTier);
  if (normalizedCurrentTier != SubscriptionTierHelper.free) {
    return normalizedCurrentTier;
  }

  final candidateTier = SubscriptionTierHelper.normalizeTier(
    syncedTier ?? revenueCatTier,
  );
  return candidateTier == SubscriptionTierHelper.free
      ? normalizedCurrentTier
      : candidateTier;
}

class SubscriptionState {
  final String tier;
  final int monthlyMessagesUsed;
  final int dailyMessagesUsed;
  final int monthlyLimit;
  final int dailyLimit;
  final bool isLoading;
  final String? error;
  final Offerings? offerings;
  final Map<String, StoreProduct> storeProducts;
  final String? pendingDowngradeToTier;
  final String? pendingDowngradeProductId;
  final DateTime? pendingDowngradeEffectiveAt;
  final DateTime? renewsAt;
  final String? activeProductId;

  const SubscriptionState({
    this.tier = SubscriptionTierHelper.free,
    this.monthlyMessagesUsed = 0,
    this.dailyMessagesUsed = 0,
    this.monthlyLimit = AppConstants.freeMonthlyLimit,
    this.dailyLimit = AppConstants.freeDailyLimit,
    this.isLoading = false,
    this.error,
    this.offerings,
    this.storeProducts = const {},
    this.pendingDowngradeToTier,
    this.pendingDowngradeProductId,
    this.pendingDowngradeEffectiveAt,
    this.renewsAt,
    this.activeProductId,
  });

  bool get isFreeUser => tier == SubscriptionTierHelper.free;
  bool get isStarter => tier == SubscriptionTierHelper.starter;
  bool get isEssential => tier == SubscriptionTierHelper.essential;
  bool get isPremium => isStarter || isEssential;

  int get monthlyRemaining =>
      (monthlyLimit - monthlyMessagesUsed).clamp(0, monthlyLimit);
  int get dailyRemaining =>
      (dailyLimit - dailyMessagesUsed).clamp(0, dailyLimit);
  bool get hasPendingDowngrade =>
      pendingDowngradeToTier != null && pendingDowngradeEffectiveAt != null;

  Package? get starterPackage {
    return starterMonthlyPackage ?? starterQuarterlyPackage;
  }

  Package? get essentialPackage {
    return essentialMonthlyPackage ?? essentialQuarterlyPackage;
  }

  String _packageSearchText(Package package) {
    return [
      package.identifier,
      package.storeProduct.identifier,
      package.storeProduct.title,
      package.storeProduct.description,
      package.storeProduct.subscriptionPeriod,
    ].whereType<String>().join(' ').toLowerCase();
  }

  bool _packageMatchesTier(Package package, String tierKeyword) {
    return _packageSearchText(package).contains(tierKeyword);
  }

  bool _productIdMatchesAny(String productId, List<String> productIds) {
    final normalized = productId.trim().toLowerCase();
    return productIds.any((id) => id.toLowerCase() == normalized);
  }

  bool _packageProductMatchesAny(Package package, List<String> productIds) {
    return _productIdMatchesAny(package.storeProduct.identifier, productIds);
  }

  String _normalizedPeriod(String? period) {
    return period?.trim().toUpperCase() ?? '';
  }

  bool _containsMonthlyToken(String text) {
    return text.contains('monthly') ||
        text.contains('p1m') ||
        text.contains('1 month') ||
        text.contains('1-month') ||
        text.contains('one month');
  }

  bool _containsQuarterlyToken(String text) {
    return text.contains('quarter') ||
        text.contains('quarterly') ||
        text.contains('three_month') ||
        text.contains('three month') ||
        text.contains('3month') ||
        text.contains('3 month') ||
        text.contains('3-month') ||
        text.contains('p3m');
  }

  bool _packageMatchesPeriod(Package package, String periodKeyword) {
    final text = _packageSearchText(package);
    final period = _normalizedPeriod(package.storeProduct.subscriptionPeriod);
    if (periodKeyword == 'monthly') {
      if (package.packageType == PackageType.threeMonth ||
          period == 'P3M' ||
          _containsQuarterlyToken(text)) {
        return false;
      }
      return package.packageType == PackageType.monthly ||
          period == 'P1M' ||
          _containsMonthlyToken(text);
    } else if (periodKeyword == 'quarterly') {
      if (package.packageType == PackageType.monthly ||
          period == 'P1M' ||
          _containsMonthlyToken(text)) {
        return false;
      }
      return package.packageType == PackageType.threeMonth ||
          period == 'P3M' ||
          _containsQuarterlyToken(text);
    }
    switch (periodKeyword) {
      case 'monthly':
        return package.packageType == PackageType.monthly ||
            package.storeProduct.subscriptionPeriod == 'P1M' ||
            text.contains('monthly') ||
            text.contains('month') ||
            text.contains('月');
      case 'quarterly':
        return package.packageType == PackageType.threeMonth ||
            package.storeProduct.subscriptionPeriod == 'P3M' ||
            text.contains('quarter') ||
            text.contains('three_month') ||
            text.contains('three month') ||
            text.contains('3month') ||
            text.contains('3 month') ||
            text.contains('3-month') ||
            text.contains('季');
      default:
        return text.contains(periodKeyword);
    }
  }

  Package? _findPackage(
    List<String> exactProductIds,
    String tierKeyword,
    String periodKeyword,
  ) {
    final packages = offerings?.current?.availablePackages;
    if (packages == null || packages.isEmpty) return null;

    final exact = packages.cast<Package?>().firstWhere(
          (p) => p != null && _packageProductMatchesAny(p, exactProductIds),
          orElse: () => null,
        );
    if (exact != null) return exact;

    return packages.cast<Package?>().firstWhere(
      (p) {
        if (p == null) return false;
        return _packageMatchesTier(p, tierKeyword) &&
            _packageMatchesPeriod(p, periodKeyword);
      },
      orElse: () => null,
    );
  }

  Package? get starterMonthlyPackage => _findPackage(
        _starterMonthlyProductIds,
        'starter',
        'monthly',
      );
  Package? get starterQuarterlyPackage => _findPackage(
        _starterQuarterlyProductIds,
        'starter',
        'quarterly',
      );
  Package? get essentialMonthlyPackage => _findPackage(
        _essentialMonthlyProductIds,
        'essential',
        'monthly',
      );
  Package? get essentialQuarterlyPackage =>
      _findPackage(_essentialQuarterlyProductIds, 'essential', 'quarterly');

  String _storeProductSearchText(StoreProduct product) {
    return [
      product.identifier,
      product.title,
      product.description,
      product.subscriptionPeriod,
    ].whereType<String>().join(' ').toLowerCase();
  }

  bool _storeProductMatchesTier(StoreProduct product, String tierKeyword) {
    return _storeProductSearchText(product).contains(tierKeyword);
  }

  bool _storeProductMatchesPeriod(
    StoreProduct product,
    String periodKeyword,
  ) {
    final text = _storeProductSearchText(product);
    final period = _normalizedPeriod(product.subscriptionPeriod);
    if (periodKeyword == 'monthly') {
      if (period == 'P3M' || _containsQuarterlyToken(text)) return false;
      return period == 'P1M' || _containsMonthlyToken(text);
    } else if (periodKeyword == 'quarterly') {
      if (period == 'P1M' || _containsMonthlyToken(text)) return false;
      return period == 'P3M' || _containsQuarterlyToken(text);
    }
    switch (periodKeyword) {
      case 'monthly':
        return period == 'P1M' ||
            text.contains('monthly') ||
            text.contains('month') ||
            text.contains('p1m');
      case 'quarterly':
        return period == 'P3M' ||
            text.contains('quarter') ||
            text.contains('three_month') ||
            text.contains('three month') ||
            text.contains('3month') ||
            text.contains('3 month') ||
            text.contains('3-month') ||
            text.contains('p3m');
      default:
        return text.contains(periodKeyword);
    }
  }

  StoreProduct? _findStoreProduct(
    List<String> exactProductIds,
    String tierKeyword,
    String periodKeyword,
  ) {
    for (final productId in exactProductIds) {
      final exact = storeProducts[productId];
      if (exact != null) return exact;
    }

    return storeProducts.values.cast<StoreProduct?>().firstWhere(
      (product) {
        if (product == null) return false;
        if (_productIdMatchesAny(product.identifier, exactProductIds)) {
          return true;
        }
        return _storeProductMatchesTier(product, tierKeyword) &&
            _storeProductMatchesPeriod(product, periodKeyword);
      },
      orElse: () => null,
    );
  }

  StoreProduct? get starterMonthlyStoreProduct => _findStoreProduct(
        _starterMonthlyProductIds,
        'starter',
        'monthly',
      );
  StoreProduct? get starterQuarterlyStoreProduct => _findStoreProduct(
        _starterQuarterlyProductIds,
        'starter',
        'quarterly',
      );
  StoreProduct? get essentialMonthlyStoreProduct => _findStoreProduct(
        _essentialMonthlyProductIds,
        'essential',
        'monthly',
      );
  StoreProduct? get essentialQuarterlyStoreProduct => _findStoreProduct(
        _essentialQuarterlyProductIds,
        'essential',
        'quarterly',
      );

  SubscriptionState copyWith({
    String? tier,
    int? monthlyMessagesUsed,
    int? dailyMessagesUsed,
    int? monthlyLimit,
    int? dailyLimit,
    bool? isLoading,
    String? error,
    Offerings? offerings,
    Map<String, StoreProduct>? storeProducts,
    Object? pendingDowngradeToTier = _subscriptionStateUnset,
    Object? pendingDowngradeProductId = _subscriptionStateUnset,
    Object? pendingDowngradeEffectiveAt = _subscriptionStateUnset,
    Object? renewsAt = _subscriptionStateUnset,
    Object? activeProductId = _subscriptionStateUnset,
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
      storeProducts: storeProducts ?? this.storeProducts,
      pendingDowngradeToTier: pendingDowngradeToTier == _subscriptionStateUnset
          ? this.pendingDowngradeToTier
          : pendingDowngradeToTier as String?,
      pendingDowngradeProductId:
          pendingDowngradeProductId == _subscriptionStateUnset
              ? this.pendingDowngradeProductId
              : pendingDowngradeProductId as String?,
      pendingDowngradeEffectiveAt:
          pendingDowngradeEffectiveAt == _subscriptionStateUnset
              ? this.pendingDowngradeEffectiveAt
              : pendingDowngradeEffectiveAt as DateTime?,
      renewsAt: renewsAt == _subscriptionStateUnset
          ? this.renewsAt
          : renewsAt as DateTime?,
      activeProductId: activeProductId == _subscriptionStateUnset
          ? this.activeProductId
          : activeProductId as String?,
    );
  }
}

class SubscriptionPurchaseResult {
  final bool success;
  final bool cancelled;
  final bool isDeferredDowngrade;
  final String requestedTier;
  final String previousTier;
  final String activeTier;
  final PurchasesErrorCode? errorCode;
  final String? errorMessage;
  final DateTime? effectiveAt;

  const SubscriptionPurchaseResult({
    required this.success,
    required this.cancelled,
    required this.isDeferredDowngrade,
    required this.requestedTier,
    required this.previousTier,
    required this.activeTier,
    this.errorCode,
    this.errorMessage,
    this.effectiveAt,
  });
}

class _PendingDowngrade {
  final String fromTier;
  final String toTier;
  final String? toProductId;
  final DateTime effectiveAt;

  const _PendingDowngrade({
    required this.fromTier,
    required this.toTier,
    this.toProductId,
    required this.effectiveAt,
  });
}

class SubscriptionNotifier extends StateNotifier<SubscriptionState> {
  static const _pendingDowngradeUserIdKey = 'pending_downgrade_user_id';
  static const _pendingDowngradeFromTierKey = 'pending_downgrade_from_tier';
  static const _pendingDowngradeToTierKey = 'pending_downgrade_to_tier';
  static const _pendingDowngradeToProductIdKey =
      'pending_downgrade_to_product_id';
  static const _pendingDowngradeEffectiveAtKey =
      'pending_downgrade_effective_at';

  SubscriptionNotifier() : super(_initialStateFromUsageSnapshot()) {
    _initialize();
  }

  static SubscriptionState _initialStateFromUsageSnapshot() {
    try {
      return buildInitialSubscriptionStateFromUsage(
        UsageService().getLocalUsage(),
      );
    } catch (error) {
      debugPrint(
        '[subscription] Failed to hydrate cached subscription snapshot: $error',
      );
      return const SubscriptionState(isLoading: true);
    }
  }

  _PendingDowngrade? _readPendingDowngrade() {
    final box = StorageService.settingsBox;
    final currentUserId = SupabaseService.currentUser?.id;
    final storedUserId = box.get(_pendingDowngradeUserIdKey) as String?;
    if (storedUserId != null &&
        currentUserId != null &&
        storedUserId != currentUserId) {
      _clearPendingDowngrade();
      return null;
    }

    final fromTier = SubscriptionTierHelper.normalizeTier(
      box.get(_pendingDowngradeFromTierKey) as String?,
    );
    final toTier = SubscriptionTierHelper.normalizeTier(
      box.get(_pendingDowngradeToTierKey) as String?,
    );
    final toProductId = box.get(_pendingDowngradeToProductIdKey) as String?;
    final effectiveAtRaw = box.get(_pendingDowngradeEffectiveAtKey) as String?;

    if (effectiveAtRaw == null || effectiveAtRaw.isEmpty) {
      return null;
    }

    final effectiveAt = DateTime.tryParse(effectiveAtRaw);
    if (effectiveAt == null) {
      _clearPendingDowngrade();
      return null;
    }

    return _PendingDowngrade(
      fromTier: fromTier,
      toTier: toTier,
      toProductId: toProductId?.trim().isEmpty == true ? null : toProductId,
      effectiveAt: effectiveAt,
    );
  }

  bool _isPendingDowngradeActive(_PendingDowngrade pending) {
    final now = DateTime.now().toUtc();
    return now.isBefore(pending.effectiveAt.toUtc());
  }

  void _storePendingDowngrade({
    required String fromTier,
    required String toTier,
    required String toProductId,
    required DateTime effectiveAt,
  }) {
    final box = StorageService.settingsBox;
    final currentUserId = SupabaseService.currentUser?.id;
    if (currentUserId != null && currentUserId.isNotEmpty) {
      box.put(_pendingDowngradeUserIdKey, currentUserId);
    }
    box.put(_pendingDowngradeFromTierKey, fromTier);
    box.put(_pendingDowngradeToTierKey, toTier);
    box.put(_pendingDowngradeToProductIdKey, toProductId);
    box.put(_pendingDowngradeEffectiveAtKey, effectiveAt.toIso8601String());
  }

  void _clearPendingDowngrade() {
    final box = StorageService.settingsBox;
    box.delete(_pendingDowngradeUserIdKey);
    box.delete(_pendingDowngradeFromTierKey);
    box.delete(_pendingDowngradeToTierKey);
    box.delete(_pendingDowngradeToProductIdKey);
    box.delete(_pendingDowngradeEffectiveAtKey);
  }

  SubscriptionState _applyPendingDowngradeMetadata(
      SubscriptionState nextState) {
    final pending = _readPendingDowngrade();
    if (pending == null) {
      return nextState.copyWith(
        pendingDowngradeToTier: null,
        pendingDowngradeProductId: null,
        pendingDowngradeEffectiveAt: null,
      );
    }

    final nextTier = SubscriptionTierHelper.normalizeTier(nextState.tier);
    if (nextTier == pending.toTier || nextTier != pending.fromTier) {
      _clearPendingDowngrade();
      return nextState.copyWith(
        pendingDowngradeToTier: null,
        pendingDowngradeProductId: null,
        pendingDowngradeEffectiveAt: null,
      );
    }

    if (!_isPendingDowngradeActive(pending)) {
      _clearPendingDowngrade();
      return nextState.copyWith(
        pendingDowngradeToTier: null,
        pendingDowngradeProductId: null,
        pendingDowngradeEffectiveAt: null,
      );
    }

    return nextState.copyWith(
      pendingDowngradeToTier: pending.toTier,
      pendingDowngradeProductId: pending.toProductId,
      pendingDowngradeEffectiveAt: pending.effectiveAt,
    );
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  String? _cleanProductId(String? productId) {
    final trimmed = productId?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  DateTime? _resolveDowngradeEffectiveAt({
    required CustomerInfo customerInfo,
    Package? package,
    StoreProduct? storeProduct,
  }) {
    return RevenueCatService.getPremiumExpirationDate(customerInfo) ??
        state.renewsAt ??
        RevenueCatService.estimateRenewalDateFromPeriod(
          package?.storeProduct.subscriptionPeriod ??
              storeProduct?.subscriptionPeriod,
          from: DateTime.now(),
        );
  }

  String _resolvePurchasedTier({
    required String productId,
    required CustomerInfo customerInfo,
  }) {
    final revenueCatTier = RevenueCatService.getTierFromCustomerInfo(
      customerInfo,
    );
    final packageTier = SubscriptionTierHelper.tierFromProductId(
      productId,
    );
    final resolvedTier =
        _highestSubscriptionTier([revenueCatTier, packageTier]);

    debugPrint(
      '[purchase] Resolved tier: revenueCat=$revenueCatTier, package=$packageTier, final=$resolvedTier',
    );

    return resolvedTier;
  }

  bool _isScheduledPaidDowngradeSnapshot({
    required String currentTier,
    required String revenueCatTier,
  }) {
    return state.hasPendingDowngrade &&
        revenueCatTier != SubscriptionTierHelper.free &&
        SubscriptionTierHelper.isDowngrade(
          fromTier: currentTier,
          toTier: revenueCatTier,
        );
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
    String? revenueCatAppUserId,
  }) async {
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        final body = <String, dynamic>{
          'expectedTier': expectedTier,
          'resetUsage': resetUsage,
        };
        final cleanedRevenueCatAppUserId = revenueCatAppUserId?.trim();
        if (cleanedRevenueCatAppUserId != null &&
            cleanedRevenueCatAppUserId.isNotEmpty) {
          body['revenueCatAppUserId'] = cleanedRevenueCatAppUserId;
        }

        final response = await SupabaseService.invokeFunction(
          'sync-subscription',
          body: body,
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
            final renewsAt = _parseDateTime(data['expiresAt']);
            final activeProductId = _cleanProductId(
              data['activeProductId'] as String?,
            );

            state = _applyPendingDowngradeMetadata(state.copyWith(
              tier: tier,
              monthlyLimit: limits.monthly,
              dailyLimit: limits.daily,
              monthlyMessagesUsed: monthlyUsed,
              dailyMessagesUsed: dailyUsed,
              renewsAt: renewsAt ?? state.renewsAt,
              activeProductId: tier == SubscriptionTierHelper.free
                  ? null
                  : activeProductId ?? state.activeProductId,
              error: null,
            ));
            UsageService.syncSubscriptionSnapshot(
              tier: tier,
              monthlyLimit: limits.monthly,
              dailyLimit: limits.daily,
              monthlyUsed: monthlyUsed,
              dailyUsed: dailyUsed,
              paidExpiresAt: renewsAt,
              clearPaidSnapshot:
                  tier == SubscriptionTierHelper.free && _isExpired(renewsAt),
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

  void _syncUsageCache(
    String tier,
    SubscriptionTierLimits limits, {
    DateTime? paidExpiresAt,
    bool clearPaidSnapshot = false,
  }) {
    UsageService.syncSubscriptionSnapshot(
      tier: tier,
      monthlyLimit: limits.monthly,
      dailyLimit: limits.daily,
      paidExpiresAt: paidExpiresAt,
      clearPaidSnapshot: clearPaidSnapshot,
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
      _syncUsageCache(state.tier, limits, paidExpiresAt: state.renewsAt);
      return;
    }

    final normalizedMonthlyRemaining =
        monthlyRemaining.clamp(0, state.monthlyLimit);
    final normalizedDailyRemaining = dailyRemaining.clamp(0, state.dailyLimit);
    final monthlyUsed = (state.monthlyLimit - normalizedMonthlyRemaining)
        .clamp(0, state.monthlyLimit);
    final dailyUsed = (state.dailyLimit - normalizedDailyRemaining)
        .clamp(0, state.dailyLimit);

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
      paidExpiresAt: state.renewsAt,
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
    await _loadStoreProducts();
    await syncWithRevenueCat();
  }

  Future<void> _loadSubscription() async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) {
        state = const SubscriptionState(error: 'Not logged in');
        return;
      }

      var customerInfo = await RevenueCatService.login(user.id);
      customerInfo ??= await RevenueCatService.getCustomerInfo();

      final response = await _loadOrCreateSubscriptionRecord(
        userId: user.id,
        tier: SubscriptionTierHelper.free,
      );

      final initialTier = SubscriptionTierHelper.normalizeTier(
        response['tier'] as String?,
      );
      final renewsAt = _parseDateTime(response['expires_at']);
      final revenueCatTier =
          RevenueCatService.getTierFromCustomerInfo(customerInfo);
      final revenueCatAppUserId =
          RevenueCatService.getRevenueCatAppUserId(customerInfo);
      final revenueCatProductId = _cleanProductId(
        RevenueCatService.getActiveProductIdFromCustomerInfo(customerInfo),
      );
      final cachedTier = state.tier;
      final displayTier = resolveStartupSubscriptionTier(
        databaseTier: initialTier,
        revenueCatTier: revenueCatTier,
        cachedTier: cachedTier,
        serverExpiresAt: renewsAt,
      );
      final displayLimits = SubscriptionTierHelper.limitsFor(displayTier);

      state = _applyPendingDowngradeMetadata(state.copyWith(
        tier: displayTier,
        monthlyMessagesUsed: _readInt(response['monthly_messages_used']),
        dailyMessagesUsed: _readInt(response['daily_messages_used']),
        monthlyLimit: displayLimits.monthly,
        dailyLimit: displayLimits.daily,
        renewsAt: renewsAt,
        activeProductId: displayTier == SubscriptionTierHelper.free
            ? null
            : revenueCatProductId ?? state.activeProductId,
        isLoading: false,
        error: null,
      ));
      UsageService.syncSubscriptionSnapshot(
        tier: displayTier,
        monthlyLimit: displayLimits.monthly,
        dailyLimit: displayLimits.daily,
        monthlyUsed: _readInt(response['monthly_messages_used']),
        dailyUsed: _readInt(response['daily_messages_used']),
        paidExpiresAt: renewsAt,
        clearPaidSnapshot:
            displayTier == SubscriptionTierHelper.free && _isExpired(renewsAt),
      );

      await _syncSubscriptionViaEdgeFunction(
        expectedTier: displayTier,
        resetUsage: initialTier != displayTier &&
            displayTier != SubscriptionTierHelper.free,
        revenueCatAppUserId: revenueCatAppUserId,
      );
      await _attemptStartupPaidRescue(displayTier: displayTier);
    } catch (e) {
      debugPrint('Load subscription error: $e');
      state = _applyPendingDowngradeMetadata(
        state.copyWith(isLoading: false, error: e.toString()),
      );
    }
  }

  Future<void> _attemptStartupPaidRescue({
    required String displayTier,
  }) async {
    if (displayTier != SubscriptionTierHelper.free) {
      return;
    }

    final customerInfo =
        await RevenueCatService.syncPurchasesAndRefreshCustomerInfo();
    final rescuedTier = RevenueCatService.getTierFromCustomerInfo(customerInfo);
    if (rescuedTier == SubscriptionTierHelper.free) {
      return;
    }

    final revenueCatAppUserId =
        RevenueCatService.getRevenueCatAppUserId(customerInfo);
    final activeProductId = _cleanProductId(
      RevenueCatService.getActiveProductIdFromCustomerInfo(customerInfo),
    );
    final renewsAt = RevenueCatService.getPremiumExpirationDate(customerInfo);
    final syncedTier = await _syncSubscriptionViaEdgeFunction(
      expectedTier: rescuedTier,
      resetUsage: true,
      revenueCatAppUserId: revenueCatAppUserId,
    );
    final tier = resolveStartupPaidRescueTier(
      currentTier: state.tier,
      revenueCatTier: rescuedTier,
      syncedTier: syncedTier,
    );
    if (tier == SubscriptionTierHelper.free) {
      return;
    }

    final limits = SubscriptionTierHelper.limitsFor(tier);
    state = _applyPendingDowngradeMetadata(state.copyWith(
      tier: tier,
      monthlyLimit: limits.monthly,
      dailyLimit: limits.daily,
      renewsAt: renewsAt ?? state.renewsAt,
      activeProductId: activeProductId ?? state.activeProductId,
      isLoading: false,
      error: null,
    ));
    _syncUsageCache(tier, limits, paidExpiresAt: state.renewsAt);
    debugPrint('[subscription] startup paid rescue applied: tier=$tier');
  }

  Future<void> _loadOfferings() async {
    try {
      final offerings = await RevenueCatService.getOfferings();
      if (offerings != null) {
        state = state.copyWith(offerings: offerings);
        final packages = offerings.current?.availablePackages ?? const [];
        debugPrint(
          'Offerings loaded: ${packages.length} packages',
        );
        for (final package in packages) {
          debugPrint(
            'Offering package: package=${package.identifier}, type=${package.packageType.name}, product=${package.storeProduct.identifier}, period=${package.storeProduct.subscriptionPeriod}, title=${package.storeProduct.title}',
          );
        }
      }
    } catch (e) {
      debugPrint('Load offerings error: $e');
    }
  }

  Future<void> _loadStoreProducts() async {
    try {
      final products = await RevenueCatService.getSubscriptionProducts(
          _subscriptionProductIds);
      if (products.isEmpty) {
        debugPrint('Store products loaded: 0 products');
        return;
      }

      state = state.copyWith(
        storeProducts: {
          ...state.storeProducts,
          for (final product in products) product.identifier: product,
        },
      );

      debugPrint('Store products loaded: ${products.length} products');
      for (final product in products) {
        debugPrint(
          'Store product: product=${product.identifier}, period=${product.subscriptionPeriod}, title=${product.title}, price=${product.priceString}',
        );
      }
    } catch (e) {
      debugPrint('Load store products error: $e');
    }
  }

  Future<void> refresh() async {
    state = _applyPendingDowngradeMetadata(
      state.copyWith(isLoading: true, error: null),
    );
    await _loadSubscription();
    await _loadOfferings();
    await _loadStoreProducts();
  }

  Future<SubscriptionPurchaseResult> purchase(Package package) async {
    return _purchaseProduct(package: package);
  }

  Future<SubscriptionPurchaseResult> purchaseStoreProduct(
    StoreProduct product,
  ) async {
    return _purchaseProduct(storeProduct: product);
  }

  Future<SubscriptionPurchaseResult> _purchaseProduct({
    Package? package,
    StoreProduct? storeProduct,
  }) async {
    final product = package?.storeProduct ?? storeProduct;
    if (product == null) {
      throw ArgumentError('A package or store product is required.');
    }

    final productId = product.identifier.trim();
    final requestedTier = SubscriptionTierHelper.tierFromProductId(
      productId,
    );
    final previousTier = state.tier;
    final requestedDowngrade = SubscriptionTierHelper.isDowngrade(
      fromTier: previousTier,
      toTier: requestedTier,
    );

    try {
      state = _applyPendingDowngradeMetadata(
        state.copyWith(isLoading: true, error: null),
      );

      debugPrint('=== PURCHASE START ===');
      debugPrint('Product: ${product.identifier}');

      final customerInfo = package != null
          ? await RevenueCatService.purchase(package)
          : await RevenueCatService.purchaseStoreProduct(product);

      debugPrint('=== PURCHASE RESULT ===');
      debugPrint('Active Subscriptions: ${customerInfo.activeSubscriptions}');
      debugPrint(
        'All Purchased: ${customerInfo.allPurchasedProductIdentifiers}',
      );
      debugPrint(
        'Active Entitlements: ${customerInfo.entitlements.active.keys.toList()}',
      );

      if (requestedDowngrade) {
        final effectiveAt = _resolveDowngradeEffectiveAt(
          customerInfo: customerInfo,
          package: package,
          storeProduct: product,
        );
        if (effectiveAt != null) {
          _storePendingDowngrade(
            fromTier: previousTier,
            toTier: requestedTier,
            toProductId: productId,
            effectiveAt: effectiveAt,
          );
        }

        final currentLimits = SubscriptionTierHelper.limitsFor(previousTier);
        state = _applyPendingDowngradeMetadata(state.copyWith(
          tier: previousTier,
          monthlyLimit: currentLimits.monthly,
          dailyLimit: currentLimits.daily,
          isLoading: false,
          error: null,
        ));
        _syncUsageCache(
          previousTier,
          currentLimits,
          paidExpiresAt: effectiveAt ?? state.renewsAt,
        );

        debugPrint(
          '[purchase] Scheduled downgrade preserved current tier: from=$previousTier to=$requestedTier effectiveAt=$effectiveAt',
        );

        return SubscriptionPurchaseResult(
          success: true,
          cancelled: false,
          isDeferredDowngrade: true,
          requestedTier: requestedTier,
          previousTier: previousTier,
          activeTier: previousTier,
          effectiveAt: effectiveAt,
        );
      }

      final resolvedTier = _resolvePurchasedTier(
        productId: productId,
        customerInfo: customerInfo,
      );
      final purchasedProductId = _cleanProductId(
            RevenueCatService.getActiveProductIdFromCustomerInfo(customerInfo),
          ) ??
          productId;
      final revenueCatAppUserId =
          RevenueCatService.getRevenueCatAppUserId(customerInfo);
      final purchasedRenewsAt =
          RevenueCatService.getPremiumExpirationDate(customerInfo);
      final syncedTier = await _syncSubscriptionViaEdgeFunction(
        expectedTier: resolvedTier,
        resetUsage: previousTier != resolvedTier &&
            resolvedTier != SubscriptionTierHelper.free,
        revenueCatAppUserId: revenueCatAppUserId,
      );
      final tier = syncedTier ?? resolvedTier;
      final limits = SubscriptionTierHelper.limitsFor(tier);

      state = _applyPendingDowngradeMetadata(state.copyWith(
        tier: tier,
        monthlyLimit: limits.monthly,
        dailyLimit: limits.daily,
        renewsAt: purchasedRenewsAt ?? state.renewsAt,
        activeProductId:
            tier == SubscriptionTierHelper.free ? null : purchasedProductId,
        isLoading: false,
        error: null,
      ));
      _syncUsageCache(tier, limits, paidExpiresAt: state.renewsAt);

      debugPrint(
        '[purchase] final tier=$tier, synced=${syncedTier ?? 'null'}, monthlyLimit=${state.monthlyLimit}',
      );
      debugPrint('=== PURCHASE END ===');

      return SubscriptionPurchaseResult(
        success: true,
        cancelled: false,
        isDeferredDowngrade: false,
        requestedTier: requestedTier,
        previousTier: previousTier,
        activeTier: tier,
      );
    } on PlatformException catch (error) {
      final errorCode = PurchasesErrorHelper.getErrorCode(error);
      debugPrint('Purchase platform error: $errorCode / $error');
      state = _applyPendingDowngradeMetadata(
        state.copyWith(isLoading: false, error: null),
      );
      return SubscriptionPurchaseResult(
        success: false,
        cancelled: errorCode == PurchasesErrorCode.purchaseCancelledError,
        isDeferredDowngrade: false,
        requestedTier: requestedTier,
        previousTier: previousTier,
        activeTier: state.tier,
        errorCode: errorCode,
        errorMessage: error.message ?? error.toString(),
      );
    } catch (e) {
      debugPrint('Purchase error: $e');
      state = _applyPendingDowngradeMetadata(
        state.copyWith(isLoading: false, error: null),
      );
      return SubscriptionPurchaseResult(
        success: false,
        cancelled: false,
        isDeferredDowngrade: false,
        requestedTier: requestedTier,
        previousTier: previousTier,
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
    final customerInfo = await RevenueCatService.getCustomerInfo();
    final syncedTier = await _syncSubscriptionViaEdgeFunction(
      expectedTier: tier,
      resetUsage: tier != SubscriptionTierHelper.free,
      revenueCatAppUserId:
          RevenueCatService.getRevenueCatAppUserId(customerInfo),
    );
    if (syncedTier == null) {
      throw Exception('訂閱同步失敗');
    }

    debugPrint(
      '[forceSyncTier] SUCCESS: synced tier=${state.tier}, daily_messages_used=${state.dailyMessagesUsed}',
    );
  }

  Future<bool> restorePurchases() async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      final customerInfo = await RevenueCatService.restorePurchases();
      final restoredTier =
          RevenueCatService.getTierFromCustomerInfo(customerInfo);
      final restoredProductId = _cleanProductId(
        RevenueCatService.getActiveProductIdFromCustomerInfo(customerInfo),
      );
      final revenueCatAppUserId =
          RevenueCatService.getRevenueCatAppUserId(customerInfo);
      final renewsAt = RevenueCatService.getPremiumExpirationDate(customerInfo);
      final previousTier = state.tier;
      final isScheduledDowngradeSnapshot = _isScheduledPaidDowngradeSnapshot(
        currentTier: previousTier,
        revenueCatTier: restoredTier,
      );
      final shouldPreservePaidFreeSnapshot =
          previousTier != SubscriptionTierHelper.free &&
              restoredTier == SubscriptionTierHelper.free;
      final syncedTier = await _syncSubscriptionViaEdgeFunction(
        expectedTier:
            isScheduledDowngradeSnapshot || shouldPreservePaidFreeSnapshot
                ? previousTier
                : restoredTier,
        resetUsage: !isScheduledDowngradeSnapshot &&
            !shouldPreservePaidFreeSnapshot &&
            previousTier != restoredTier &&
            restoredTier != SubscriptionTierHelper.free,
        revenueCatAppUserId: revenueCatAppUserId,
      );
      final tier =
          isScheduledDowngradeSnapshot || shouldPreservePaidFreeSnapshot
              ? previousTier
              : syncedTier ?? restoredTier;
      final limits = SubscriptionTierHelper.limitsFor(tier);

      state = _applyPendingDowngradeMetadata(state.copyWith(
        tier: tier,
        monthlyLimit: limits.monthly,
        dailyLimit: limits.daily,
        renewsAt: renewsAt ?? state.renewsAt,
        activeProductId: tier == SubscriptionTierHelper.free
            ? null
            : isScheduledDowngradeSnapshot || shouldPreservePaidFreeSnapshot
                ? state.activeProductId
                : restoredProductId ?? state.activeProductId,
        isLoading: false,
        error: null,
      ));
      _syncUsageCache(tier, limits, paidExpiresAt: state.renewsAt);

      return tier != SubscriptionTierHelper.free;
    } catch (e) {
      debugPrint('Restore error: $e');
      state = _applyPendingDowngradeMetadata(
        state.copyWith(isLoading: false, error: null),
      );
      rethrow;
    }
  }

  Future<void> syncWithRevenueCat() async {
    try {
      final customerInfo = await RevenueCatService.getCustomerInfo();
      if (customerInfo == null) return;

      final rcTier = RevenueCatService.getTierFromCustomerInfo(customerInfo);
      final activeProductId = _cleanProductId(
        RevenueCatService.getActiveProductIdFromCustomerInfo(customerInfo),
      );
      final revenueCatAppUserId =
          RevenueCatService.getRevenueCatAppUserId(customerInfo);
      final renewsAt = RevenueCatService.getPremiumExpirationDate(customerInfo);

      if (_isScheduledPaidDowngradeSnapshot(
        currentTier: state.tier,
        revenueCatTier: rcTier,
      )) {
        debugPrint(
          'Scheduled downgrade snapshot ignored: local=${state.tier}, RevenueCat=$rcTier',
        );
        await _syncSubscriptionViaEdgeFunction(
          expectedTier: state.tier,
          resetUsage: false,
          revenueCatAppUserId: revenueCatAppUserId,
        );
        if (renewsAt != null && renewsAt != state.renewsAt) {
          state = _applyPendingDowngradeMetadata(state.copyWith(
            renewsAt: renewsAt,
          ));
        }
        final limits = SubscriptionTierHelper.limitsFor(state.tier);
        _syncUsageCache(state.tier, limits, paidExpiresAt: state.renewsAt);
        return;
      }

      if (state.isPremium && rcTier == SubscriptionTierHelper.free) {
        debugPrint(
          'Tier mismatch ignored: local=${state.tier}, RevenueCat=$rcTier (keep premium until sync stabilizes)',
        );
        final limits = SubscriptionTierHelper.limitsFor(state.tier);
        _syncUsageCache(state.tier, limits, paidExpiresAt: state.renewsAt);
        return;
      }

      if (rcTier != state.tier) {
        debugPrint('Tier mismatch: local=${state.tier}, RevenueCat=$rcTier');

        final syncedTier = await _syncSubscriptionViaEdgeFunction(
          expectedTier: rcTier,
          resetUsage:
              state.tier != rcTier && rcTier != SubscriptionTierHelper.free,
          revenueCatAppUserId: revenueCatAppUserId,
        );
        final tier = syncedTier ?? rcTier;
        final limits = SubscriptionTierHelper.limitsFor(tier);

        state = _applyPendingDowngradeMetadata(state.copyWith(
          tier: tier,
          monthlyLimit: limits.monthly,
          dailyLimit: limits.daily,
          renewsAt: renewsAt ?? state.renewsAt,
          activeProductId: tier == SubscriptionTierHelper.free
              ? null
              : activeProductId ?? state.activeProductId,
        ));
        _syncUsageCache(tier, limits, paidExpiresAt: state.renewsAt);
      } else {
        final shouldRefreshMetadata = (activeProductId != null &&
                activeProductId != state.activeProductId) ||
            (renewsAt != null && renewsAt != state.renewsAt);
        if (shouldRefreshMetadata) {
          state = _applyPendingDowngradeMetadata(state.copyWith(
            activeProductId: activeProductId ?? state.activeProductId,
            renewsAt: renewsAt ?? state.renewsAt,
          ));
          final limits = SubscriptionTierHelper.limitsFor(state.tier);
          _syncUsageCache(state.tier, limits, paidExpiresAt: state.renewsAt);
        }
      }
    } catch (e) {
      debugPrint('Sync with RevenueCat error: $e');
    }
  }

  Future<bool> clearPendingDowngradeMetadata() async {
    if (!state.hasPendingDowngrade) {
      await syncWithRevenueCat();
      return true;
    }

    final currentTier = state.tier;
    final customerInfo = await RevenueCatService.getCustomerInfo();
    if (customerInfo == null) {
      return false;
    }

    final revenueCatTier =
        RevenueCatService.getTierFromCustomerInfo(customerInfo);
    if (SubscriptionTierHelper.isDowngrade(
      fromTier: currentTier,
      toTier: revenueCatTier,
    )) {
      debugPrint(
        'Pending downgrade not cleared: RevenueCat still reports $revenueCatTier while local is $currentTier',
      );
      return false;
    }

    final activeProductId = _cleanProductId(
      RevenueCatService.getActiveProductIdFromCustomerInfo(customerInfo),
    );
    final renewsAt = RevenueCatService.getPremiumExpirationDate(customerInfo);

    _clearPendingDowngrade();
    state = state.copyWith(
      pendingDowngradeToTier: null,
      pendingDowngradeProductId: null,
      pendingDowngradeEffectiveAt: null,
      activeProductId: activeProductId ?? state.activeProductId,
      renewsAt: renewsAt ?? state.renewsAt,
    );
    await syncWithRevenueCat();
    return true;
  }
}

final subscriptionProvider =
    StateNotifierProvider<SubscriptionNotifier, SubscriptionState>((ref) {
  return SubscriptionNotifier();
});

/// Testable seam for screens that should refresh the server-backed usage
/// snapshot when they become visible. Keeping this as a provider lets widget
/// tests override the network-heavy refresh with a no-op.
final subscriptionScreenRefreshProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    await ref.read(subscriptionProvider.notifier).refresh();
  },
);
