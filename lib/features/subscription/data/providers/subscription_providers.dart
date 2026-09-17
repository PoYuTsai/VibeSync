import 'dart:async';

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

/// 鏡像 server `_shared/quota.ts` 的 UTC 窗判定（稽核 #1，2026-08-07）。
///
/// subscriptions row 的原始計數只在下一次扣費時被 server 歸零；client 直讀
/// row 時必須自己判窗——跨窗後 stale 計數視為 0，否則昨天用完日額度的免費
/// 用戶今天會被 client 守門擋進 paywall，請求根本到不了 server 的權威判定
///（額度沒真用完不得擋核心功能）。
@visibleForTesting
bool sameUtcDay(DateTime a, DateTime b) {
  final ua = a.toUtc();
  final ub = b.toUtc();
  return ua.year == ub.year && ua.month == ub.month && ua.day == ub.day;
}

@visibleForTesting
bool sameUtcMonth(DateTime a, DateTime b) {
  final ua = a.toUtc();
  final ub = b.toUtc();
  return ua.year == ub.year && ua.month == ub.month;
}

/// row 計數套窗：跨窗（或 reset_at 缺失＝server 視為 never reset）回 0。
@visibleForTesting
int usedCountRespectingWindow({
  required int used,
  required Object? resetAtRaw,
  required bool Function(DateTime a, DateTime b) sameWindow,
  DateTime? now,
}) {
  final resetAt = resetAtRaw is DateTime
      ? resetAtRaw
      : resetAtRaw is String
          ? DateTime.tryParse(resetAtRaw)
          : null;
  if (resetAt == null) return 0;
  return sameWindow(now ?? DateTime.now(), resetAt) ? used : 0;
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

  final candidateTier = SubscriptionTierHelper.normalizeTier(syncedTier);
  return candidateTier == SubscriptionTierHelper.free
      ? normalizedCurrentTier
      : candidateTier;
}

/// A server sync response only belongs to whichever account was current
/// when that specific sync attempt started. If the signed-in account changed
/// during the network round trip (logout + different login), the response
/// — even a "successful" one — must not be written into `state` or
/// `UsageService`'s local cache, since it would silently apply one
/// account's entitlement to whoever is using the app now.
@visibleForTesting
bool subscriptionSyncStillAppliesToAccount({
  required String? startedForUserId,
  required String? currentUserId,
}) {
  return startedForUserId == currentUserId;
}

/// Whether a fresh RevenueCat read should be adopted immediately in place of
/// the current tier. Deliberately one-directional: only an upgrade (higher
/// rank) is ever adopted this way. A RevenueCat read that is lower than the
/// current tier is never used to downgrade here — that could just be a
/// stale local SDK cache — and is left to the existing routine
/// `syncWithRevenueCat`/`_loadSubscription` reconciliation, which already
/// has its own (separately reviewed) rules for genuine revocation/expiry.
@visibleForTesting
bool shouldAdoptRevenueCatTier({
  required String currentTier,
  required String revenueCatTier,
}) {
  return SubscriptionTierHelper.rankOf(revenueCatTier) >
      SubscriptionTierHelper.rankOf(currentTier);
}

/// `minimumSyncedTier` alone only floors a response against the tier ITS
/// OWN call already confirmed — it says nothing about whether some OTHER,
/// more-recently-started operation has since produced a more current
/// result. Two concrete failures that rank-comparison alone cannot catch
/// (review round 4, requirement 一):
///   - An earlier, slow refresh finally resolves with a stale tier AFTER a
///     later, faster recovery already wrote a higher one — a floor never
///     rejects a response merely for being *lower*, so nothing stops this.
///   - An earlier "confirm at least X" call finally resolves with exactly
///     X, AFTER a later, genuine reload already discovered a real
///     revocation and wrote something lower — the response isn't below
///     its OWN floor, so `minimumSyncedTier` alone lets it through even
///     though a newer, more current answer already superseded it.
/// Every write-driving operation captures its own generation from a shared
/// per-notifier counter at the moment it starts, and refuses to write once
/// a *later-started* operation has already committed — regardless of which
/// direction (higher or lower) the ranks compare. This is orthogonal to
/// `minimumSyncedTier` (which stays for same-operation self-consistency)
/// and to `subscriptionSyncStillAppliesToAccount` (account identity); a
/// write must pass all that apply.
@visibleForTesting
bool subscriptionWriteIsCurrent({
  required int operationGeneration,
  required int lastCommittedGeneration,
}) {
  return operationGeneration >= lastCommittedGeneration;
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

  int get effectiveMonthlyLimit => monthlyLimit;
  int get effectiveDailyLimit => dailyLimit;

  int get monthlyRemaining => (effectiveMonthlyLimit - monthlyMessagesUsed)
      .clamp(0, effectiveMonthlyLimit);
  int get dailyRemaining =>
      (effectiveDailyLimit - dailyMessagesUsed).clamp(0, effectiveDailyLimit);
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

  /// Monotonic per-notifier operation/commit counters for
  /// [subscriptionWriteIsCurrent] (review round 4, requirement 一). Every
  /// write-driving operation (`_loadSubscription`, `forceSyncTier`,
  /// `adoptRevenueCatTierIfHigher`, `_attemptStartupPaidRescue`) claims a
  /// generation via `++_operationSequence` at its own start, and only
  /// writes if `_lastCommittedGeneration` hasn't already moved past it.
  /// Deliberately scoped to just these four — the ones reachable from the
  /// night-market paywall flow — not a blanket rule for every caller of
  /// `_syncSubscriptionViaEdgeFunction`.
  int _operationSequence = 0;
  int _lastCommittedGeneration = 0;

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
    // The account this specific call is for. Defaults to self-capturing
    // "whoever is current right now" for every existing caller that doesn't
    // pass one (unchanged behaviour) — but that self-capture happens at
    // THIS helper's own entry, which can already be later than the account
    // the calling operation actually started for (a gap between the
    // caller's own capture and this call). Callers with an account already
    // captured at their OWN entry (`forceSyncTier`, `_loadSubscription`,
    // [adoptRevenueCatTierIfHigher]'s confirmation step) must pass it here
    // explicitly so the whole operation — not just this helper's own
    // narrow window — shares one account of record.
    String? requiredUserId,
    // When set, a response tier ranked below this is treated as
    // inconclusive (returns null, writes nothing) instead of authoritative.
    // Only [adoptRevenueCatTierIfHigher]'s confirmation call sets this: its
    // purpose is to persist a tier already independently confirmed by
    // RevenueCat, so a lower/stale server read must not undo that — see the
    // review round 3 write-back-consistency fix.
    String? minimumSyncedTier,
    // This call's operation generation (see [subscriptionWriteIsCurrent],
    // review round 4). When set, a response is discarded if a later-started
    // operation already committed a write, regardless of tier rank —
    // `minimumSyncedTier` alone cannot catch a stale-but-not-below-floor
    // response arriving after a newer, genuinely different result.
    int? operationGeneration,
  }) async {
    final startedForUserId = requiredUserId ?? SupabaseService.currentUser?.id;
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
            if (!subscriptionSyncStillAppliesToAccount(
              startedForUserId: startedForUserId,
              currentUserId: SupabaseService.currentUser?.id,
            )) {
              debugPrint(
                '[sync-subscription] account changed mid-sync; discarding '
                'response for the account that started this attempt',
              );
              return null;
            }
            final tier = SubscriptionTierHelper.normalizeTier(
              data['tier'] as String?,
            );
            if (minimumSyncedTier != null &&
                SubscriptionTierHelper.rankOf(tier) <
                    SubscriptionTierHelper.rankOf(minimumSyncedTier)) {
              debugPrint(
                '[sync-subscription] response tier ($tier) is below the '
                'tier this call is confirming ($minimumSyncedTier); '
                'treating as inconclusive rather than downgrading',
              );
              return null;
            }
            if (operationGeneration != null &&
                !subscriptionWriteIsCurrent(
                  operationGeneration: operationGeneration,
                  lastCommittedGeneration: _lastCommittedGeneration,
                )) {
              debugPrint(
                '[sync-subscription] a later-started operation already '
                'committed a result; discarding this now-superseded '
                'response',
              );
              return null;
            }
            if (operationGeneration != null) {
              _lastCommittedGeneration = operationGeneration;
            }
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

  /// Test-only seam so [SubscriptionNotifier]'s real write paths (including
  /// [_loadSubscription]) can be exercised against a fake `subscriptions`
  /// row instead of a live Postgrest table. Never set outside tests.
  @visibleForTesting
  static Future<Map<String, dynamic>> Function({
    required String userId,
    required String tier,
  })? debugLoadOrCreateSubscriptionRecordOverride;

  Future<Map<String, dynamic>> _loadOrCreateSubscriptionRecord({
    required String userId,
    required String tier,
  }) async {
    final override = debugLoadOrCreateSubscriptionRecordOverride;
    if (override != null) return override(userId: userId, tier: tier);
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
      final myGeneration = ++_operationSequence;

      var customerInfo = await RevenueCatService.login(user.id);
      customerInfo ??= await RevenueCatService.getCustomerInfoForAppUserId(
        user.id,
      );

      final response = await _loadOrCreateSubscriptionRecord(
        userId: user.id,
        tier: SubscriptionTierHelper.free,
      );

      final initialTier = SubscriptionTierHelper.normalizeTier(
        response['tier'] as String?,
      );
      final renewsAt = _parseDateTime(response['expires_at']);
      // row 原始計數套窗（稽核 #1）：跨窗 stale 計數不得進 client 守門。
      final rowMonthlyUsed = usedCountRespectingWindow(
        used: _readInt(response['monthly_messages_used']),
        resetAtRaw: response['monthly_reset_at'],
        sameWindow: sameUtcMonth,
      );
      final rowDailyUsed = usedCountRespectingWindow(
        used: _readInt(response['daily_messages_used']),
        resetAtRaw: response['daily_reset_at'],
        sameWindow: sameUtcDay,
      );
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

      // The network round trips above (RevenueCat login, the subscriptions
      // row fetch) may have taken long enough for the signed-in account to
      // change (logout + different login) — this operation's own write must
      // not apply this account's data to whoever is signed in now.
      if (!subscriptionSyncStillAppliesToAccount(
        startedForUserId: user.id,
        currentUserId: SupabaseService.currentUser?.id,
      )) {
        return;
      }
      if (!subscriptionWriteIsCurrent(
        operationGeneration: myGeneration,
        lastCommittedGeneration: _lastCommittedGeneration,
      )) {
        return;
      }
      _lastCommittedGeneration = myGeneration;

      state = _applyPendingDowngradeMetadata(state.copyWith(
        tier: displayTier,
        monthlyMessagesUsed: rowMonthlyUsed,
        dailyMessagesUsed: rowDailyUsed,
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
        monthlyUsed: rowMonthlyUsed,
        dailyUsed: rowDailyUsed,
        paidExpiresAt: renewsAt,
        clearPaidSnapshot:
            displayTier == SubscriptionTierHelper.free && _isExpired(renewsAt),
      );

      final syncedDisplayTier = await _syncSubscriptionViaEdgeFunction(
        expectedTier: displayTier,
        resetUsage: initialTier != displayTier &&
            displayTier != SubscriptionTierHelper.free,
        requiredUserId: user.id,
        operationGeneration: myGeneration,
        revenueCatAppUserId: revenueCatAppUserId,
      );
      if (!subscriptionSyncStillAppliesToAccount(
        startedForUserId: user.id,
        currentUserId: SupabaseService.currentUser?.id,
      )) {
        return;
      }
      if (!subscriptionWriteIsCurrent(
        operationGeneration: myGeneration,
        lastCommittedGeneration: _lastCommittedGeneration,
      )) {
        return;
      }
      if (displayTier != SubscriptionTierHelper.free &&
          initialTier == SubscriptionTierHelper.free &&
          syncedDisplayTier == null) {
        debugPrint(
          'Startup paid display tier was not confirmed by server; reverting to free until subscription sync succeeds.',
        );
        const tier = SubscriptionTierHelper.free;
        final limits = SubscriptionTierHelper.limitsFor(tier);
        state = _applyPendingDowngradeMetadata(state.copyWith(
          tier: tier,
          monthlyLimit: limits.monthly,
          dailyLimit: limits.daily,
          activeProductId: null,
          isLoading: false,
          error: null,
        ));
        UsageService.syncSubscriptionSnapshot(
          tier: tier,
          monthlyLimit: limits.monthly,
          dailyLimit: limits.daily,
          monthlyUsed: rowMonthlyUsed,
          dailyUsed: rowDailyUsed,
          paidExpiresAt: renewsAt,
          clearPaidSnapshot: _isExpired(renewsAt),
        );
        await _attemptStartupPaidRescue(
          displayTier: tier,
          requiredUserId: user.id,
          operationGeneration: myGeneration,
        );
        return;
      }
      await _attemptStartupPaidRescue(
        displayTier: displayTier,
        requiredUserId: user.id,
        operationGeneration: myGeneration,
      );
    } catch (e) {
      debugPrint('Load subscription error: $e');
      state = _applyPendingDowngradeMetadata(
        state.copyWith(isLoading: false, error: e.toString()),
      );
    }
  }

  /// Reachable from `refresh()` -> `_loadSubscription()` whenever the
  /// resolved display tier is Free — not a dead branch, so (review round 4,
  /// requirement 二) it must honor the SAME account/operation-ordering
  /// rules as `_loadSubscription`'s own writes, sharing the caller's
  /// [requiredUserId]/[operationGeneration] rather than re-capturing
  /// "whoever is current right now" at its own entry.
  Future<void> _attemptStartupPaidRescue({
    required String displayTier,
    required String requiredUserId,
    required int operationGeneration,
  }) async {
    if (displayTier != SubscriptionTierHelper.free) {
      return;
    }

    final customerInfo =
        await RevenueCatService.syncPurchasesAndRefreshCustomerInfo(
      expectedAppUserId: requiredUserId,
    );
    if (!subscriptionSyncStillAppliesToAccount(
      startedForUserId: requiredUserId,
      currentUserId: SupabaseService.currentUser?.id,
    )) {
      return;
    }
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
      requiredUserId: requiredUserId,
      operationGeneration: operationGeneration,
      // Same contract as `forceSyncTier`: this call exists to confirm the
      // user has at least `rescuedTier`, so a slower/stale lower response
      // must not be accepted as a downgrade.
      minimumSyncedTier: rescuedTier,
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
    if (!subscriptionSyncStillAppliesToAccount(
      startedForUserId: requiredUserId,
      currentUserId: SupabaseService.currentUser?.id,
    )) {
      return;
    }
    if (!subscriptionWriteIsCurrent(
      operationGeneration: operationGeneration,
      lastCommittedGeneration: _lastCommittedGeneration,
    )) {
      return;
    }
    _lastCommittedGeneration = operationGeneration;

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
    final myGeneration = ++_operationSequence;

    debugPrint('[forceSyncTier] Starting sync: tier=$tier');
    final customerInfo = await RevenueCatService.getCustomerInfoForAppUserId(
      user.id,
    );
    final syncedTier = await _syncSubscriptionViaEdgeFunction(
      expectedTier: tier,
      resetUsage: tier != SubscriptionTierHelper.free,
      requiredUserId: user.id,
      operationGeneration: myGeneration,
      // This call's entire contract is "confirm the user now has at least
      // `tier`" (called right after a store purchase/restore resolves to
      // it). A slower, earlier-issued sync for the same account that
      // finally returns a lower/stale tier after this one already confirmed
      // it must not be allowed to silently undo it (review round 3,
      // requirement 一 — the same hazard as adoptRevenueCatTierIfHigher's
      // own background confirmation, just from a different caller).
      minimumSyncedTier: tier,
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

  /// Immediately adopts a fresh RevenueCat read when it outranks the current
  /// tier, without waiting for (or trusting) the server mirror to catch up.
  ///
  /// For a purchase/restore that just completed, the server's own
  /// `sync-subscription` response can still come back with its pre-webhook
  /// (stale) tier even though the call itself "succeeded" — `forceSyncTier`
  /// alone cannot be treated as having resolved that race. This reuses
  /// RevenueCat's local SDK cache directly as independent evidence, and is
  /// deliberately one-directional (see [shouldAdoptRevenueCatTier]): it can
  /// only raise the local tier, never lower it, so it can't be used to
  /// short-circuit a genuine revocation/expiry/downgrade. Returns whether it
  /// adopted a new tier.
  Future<bool> adoptRevenueCatTierIfHigher() async {
    final startedForUserId = SupabaseService.currentUser?.id;
    if (startedForUserId == null) return false;
    final myGeneration = ++_operationSequence;

    final customerInfo = await RevenueCatService.getCustomerInfoForAppUserId(
      startedForUserId,
    );
    if (customerInfo == null) return false;
    if (!subscriptionSyncStillAppliesToAccount(
      startedForUserId: startedForUserId,
      currentUserId: SupabaseService.currentUser?.id,
    )) {
      return false;
    }

    final rcTier = RevenueCatService.getTierFromCustomerInfo(customerInfo);
    if (!shouldAdoptRevenueCatTier(
      currentTier: state.tier,
      revenueCatTier: rcTier,
    )) {
      return false;
    }
    // A later-started operation (another adopt call, forceSyncTier, or a
    // fresh _loadSubscription reload) may have already committed a more
    // current result while the RevenueCat read above was in flight — this
    // adoption's own write must not clobber it either.
    if (!subscriptionWriteIsCurrent(
      operationGeneration: myGeneration,
      lastCommittedGeneration: _lastCommittedGeneration,
    )) {
      return false;
    }
    _lastCommittedGeneration = myGeneration;

    // Adopting a higher tier without its own expiry is exactly the "blank
    // or expired renewsAt" gap review round 3 flagged: `UsageService`'s
    // offline/cold-start cache reads `renewsAt` to decide whether a cached
    // paid tier still counts, so keeping whatever (possibly null/expired)
    // value predates this adoption would silently defeat that cache the
    // moment the app goes offline. Fetch RevenueCat's own expiry for the
    // tier we're adopting right now, same helper `_purchaseProduct`/
    // `restorePurchases` already use.
    final renewsAt =
        RevenueCatService.getPremiumExpirationDate(customerInfo) ??
            state.renewsAt;
    final limits = SubscriptionTierHelper.limitsFor(rcTier);
    state = _applyPendingDowngradeMetadata(state.copyWith(
      tier: rcTier,
      monthlyLimit: limits.monthly,
      dailyLimit: limits.daily,
      renewsAt: renewsAt,
      activeProductId: _cleanProductId(
            RevenueCatService.getActiveProductIdFromCustomerInfo(customerInfo),
          ) ??
          state.activeProductId,
    ));
    _syncUsageCache(rcTier, limits, paidExpiresAt: renewsAt);

    // Best-effort: tell the server too. `minimumSyncedTier` makes this the
    // one call site that refuses to let its own response regress below what
    // we just adopted — review round 3's finding: `unawaited` only means the
    // caller doesn't wait for this; it does NOT stop a stale-but-"successful"
    // server response (webhook not caught up yet) from later overwriting
    // `state`/`UsageService` back down through the shared write path. This
    // is not "always keep the higher tier" as a general rule (that would
    // hide a genuine revocation) — it only protects the specific tier this
    // call independently confirmed via RevenueCat a moment ago; every other
    // caller of `_syncSubscriptionViaEdgeFunction` is unaffected and a
    // genuine revocation/expiry still lands normally through the existing,
    // separately-reviewed `syncWithRevenueCat`/`_loadSubscription` paths on
    // their own next routine run.
    unawaited(_syncSubscriptionViaEdgeFunction(
      expectedTier: rcTier,
      resetUsage: false,
      requiredUserId: startedForUserId,
      operationGeneration: myGeneration,
      revenueCatAppUserId: RevenueCatService.getRevenueCatAppUserId(
        customerInfo,
      ),
      minimumSyncedTier: rcTier,
    ));
    return true;
  }

  Future<bool> restorePurchases() async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      var customerInfo = await RevenueCatService.restorePurchases();
      var restoredTier =
          RevenueCatService.getTierFromCustomerInfo(customerInfo);
      var restoredProductId = _cleanProductId(
        RevenueCatService.getActiveProductIdFromCustomerInfo(customerInfo),
      );
      var revenueCatAppUserId =
          RevenueCatService.getRevenueCatAppUserId(customerInfo);
      var renewsAt = RevenueCatService.getPremiumExpirationDate(customerInfo);
      final previousTier = state.tier;
      final isScheduledDowngradeSnapshot = _isScheduledPaidDowngradeSnapshot(
        currentTier: previousTier,
        revenueCatTier: restoredTier,
      );
      final shouldPreservePaidFreeSnapshot =
          previousTier != SubscriptionTierHelper.free &&
              restoredTier == SubscriptionTierHelper.free;
      var syncedTier = await _syncSubscriptionViaEdgeFunction(
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

      if (syncedTier == null &&
          restoredTier != SubscriptionTierHelper.free &&
          previousTier == SubscriptionTierHelper.free) {
        final user = SupabaseService.currentUser;
        if (user != null) {
          final refreshedCustomerInfo =
              await RevenueCatService.syncPurchasesAndRefreshCustomerInfo(
            expectedAppUserId: user.id,
          );
          if (refreshedCustomerInfo != null) {
            customerInfo = refreshedCustomerInfo;
            restoredTier =
                RevenueCatService.getTierFromCustomerInfo(customerInfo);
            restoredProductId = _cleanProductId(
              RevenueCatService.getActiveProductIdFromCustomerInfo(
                customerInfo,
              ),
            );
            revenueCatAppUserId =
                RevenueCatService.getRevenueCatAppUserId(customerInfo);
            renewsAt = RevenueCatService.getPremiumExpirationDate(customerInfo);
            syncedTier = await _syncSubscriptionViaEdgeFunction(
              expectedTier: restoredTier,
              resetUsage: restoredTier != SubscriptionTierHelper.free,
              revenueCatAppUserId: revenueCatAppUserId,
            );
          }
        }
      }

      if (syncedTier == null &&
          restoredTier != SubscriptionTierHelper.free &&
          previousTier == SubscriptionTierHelper.free) {
        debugPrint(
          'Restore purchases paid entitlement was not confirmed by server; keeping local free state until sync succeeds.',
        );
        final limits = SubscriptionTierHelper.limitsFor(previousTier);
        state = _applyPendingDowngradeMetadata(state.copyWith(
          tier: previousTier,
          monthlyLimit: limits.monthly,
          dailyLimit: limits.daily,
          isLoading: false,
          error: null,
        ));
        _syncUsageCache(previousTier, limits, paidExpiresAt: state.renewsAt);
        return false;
      }

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
      final user = SupabaseService.currentUser;
      if (user == null) return;

      final customerInfo = await RevenueCatService.getCustomerInfoForAppUserId(
        user.id,
      );
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
        if (rcTier != SubscriptionTierHelper.free) {
          await _syncSubscriptionViaEdgeFunction(
            expectedTier: rcTier,
            resetUsage: false,
            revenueCatAppUserId: revenueCatAppUserId,
          );
        }

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

  /// Best-effort server entitlement sync before a paid analysis request.
  ///
  /// The local RevenueCat SDK can show an active paid entitlement while the
  /// server-side `subscriptions` row is still stale. Since analyze-chat gates
  /// reply styles from the server row, force the sync path before analysis so a
  /// paid user does not receive a Free-tier one-style result.
  Future<void> ensureServerEntitlementSyncedForAnalysis() async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) return;

      var customerInfo = await RevenueCatService.getCustomerInfoForAppUserId(
        user.id,
      );
      var revenueCatTier = RevenueCatService.getTierFromCustomerInfo(
        customerInfo,
      );
      var expectedTier = _highestSubscriptionTier([
        state.tier,
        revenueCatTier,
      ]);
      if (expectedTier == SubscriptionTierHelper.free) {
        return;
      }

      var syncedTier = await _syncSubscriptionViaEdgeFunction(
        expectedTier: expectedTier,
        resetUsage: false,
        revenueCatAppUserId: RevenueCatService.getRevenueCatAppUserId(
          customerInfo,
        ),
      );

      if (syncedTier != null &&
          SubscriptionTierHelper.rankOf(syncedTier) >=
              SubscriptionTierHelper.rankOf(expectedTier)) {
        return;
      }

      customerInfo =
          await RevenueCatService.syncPurchasesAndRefreshCustomerInfo(
        expectedAppUserId: user.id,
      );
      revenueCatTier = RevenueCatService.getTierFromCustomerInfo(customerInfo);
      expectedTier = _highestSubscriptionTier([
        state.tier,
        revenueCatTier,
      ]);
      if (expectedTier == SubscriptionTierHelper.free) {
        return;
      }

      await _syncSubscriptionViaEdgeFunction(
        expectedTier: expectedTier,
        resetUsage: false,
        revenueCatAppUserId: RevenueCatService.getRevenueCatAppUserId(
          customerInfo,
        ),
      );
    } catch (e) {
      debugPrint('Ensure analysis entitlement sync error: $e');
    }
  }

  Future<bool> clearPendingDowngradeMetadata() async {
    if (!state.hasPendingDowngrade) {
      await syncWithRevenueCat();
      return true;
    }

    final currentTier = state.tier;
    final user = SupabaseService.currentUser;
    if (user == null) {
      return false;
    }

    final customerInfo = await RevenueCatService.getCustomerInfoForAppUserId(
      user.id,
    );
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
