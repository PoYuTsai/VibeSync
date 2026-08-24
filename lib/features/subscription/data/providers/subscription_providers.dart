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
import '../../../../core/utils/platform_info.dart';
import '../../domain/services/subscription_tier_helper.dart';
import '../../domain/services/subscription_product_contract.dart';

const _subscriptionStateUnset = Object();

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
Map<String, dynamic>? resolveEffectiveSubscriptionStoreState(
  Iterable<Map<String, dynamic>> rows, {
  String? userId,
  DateTime? now,
}) {
  final at = (now ?? DateTime.now()).toUtc();
  final candidates = <Map<String, dynamic>>[];
  for (final row in rows) {
    if (userId != null && row['user_id'] != userId) continue;
    if (row['store'] != 'app_store' && row['store'] != 'play_store') {
      continue;
    }
    if (row['verification_status'] != 'verified') continue;

    final rawTier = row['tier'];
    if (rawTier != SubscriptionTierHelper.free &&
        rawTier != SubscriptionTierHelper.starter &&
        rawTier != SubscriptionTierHelper.essential) {
      continue;
    }
    final status = row['status'];
    if (status != 'active' &&
        status != 'cancelled' &&
        status != 'expired' &&
        status != 'billing_issue') {
      continue;
    }
    final eventAt = _parseSubscriptionStateDate(row['event_at']);
    if (eventAt == null || eventAt.isAfter(at)) continue;
    final expiresAt = _parseSubscriptionStateDate(row['expires_at']);
    if (status == 'expired') continue;
    if (expiresAt == null) {
      if (status != 'active') continue;
    } else if (!expiresAt.isAfter(at)) {
      continue;
    }
    final eventId = row['event_id'];
    if (eventId is! String || eventId.trim().isEmpty) continue;
    candidates.add(row);
  }

  candidates.sort((left, right) {
    final tierDifference =
        SubscriptionTierHelper.rankOf(right['tier'] as String?) -
            SubscriptionTierHelper.rankOf(left['tier'] as String?);
    if (tierDifference != 0) return tierDifference;

    final rightEvent = _parseSubscriptionStateDate(right['event_at'])!;
    final leftEvent = _parseSubscriptionStateDate(left['event_at'])!;
    final eventDifference = rightEvent.compareTo(leftEvent);
    if (eventDifference != 0) return eventDifference;
    return (left['store'] as String).compareTo(right['store'] as String);
  });
  return candidates.firstOrNull;
}

DateTime? _parseSubscriptionStateDate(Object? value) {
  if (value is DateTime) return value.toUtc();
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.tryParse(value)?.toUtc();
  }
  return null;
}

bool _isParseableSubscriptionStoreStateRow(
  Map<String, dynamic> row,
  String userId,
) {
  if (row['user_id'] != userId) return false;
  if (row['store'] != 'app_store' && row['store'] != 'play_store') {
    return false;
  }
  if (row['tier'] != SubscriptionTierHelper.free &&
      row['tier'] != SubscriptionTierHelper.starter &&
      row['tier'] != SubscriptionTierHelper.essential) {
    return false;
  }
  if (row['status'] != 'active' &&
      row['status'] != 'cancelled' &&
      row['status'] != 'expired' &&
      row['status'] != 'billing_issue') {
    return false;
  }
  if (row['verification_status'] != 'verified' &&
      row['verification_status'] != 'unverified') {
    return false;
  }
  final eventId = row['event_id'];
  if (eventId is! String || eventId.trim().isEmpty) return false;
  if (_parseSubscriptionStateDate(row['event_at']) == null) return false;
  if (row['expires_at'] != null &&
      _parseSubscriptionStateDate(row['expires_at']) == null) {
    return false;
  }
  for (final key in const ['product_id', 'base_plan_id']) {
    final value = row[key];
    if (value != null && value is! String) return false;
  }
  final source = row['verification_source'];
  if (source != 'revenuecat_webhook' &&
      source != 'revenuecat_api' &&
      source != 'legacy_backfill') {
    return false;
  }
  // The database contract requires legacy backfill rows to remain unverified.
  if (source == 'legacy_backfill' && row['verification_status'] == 'verified') {
    return false;
  }
  if (row['tier'] != SubscriptionTierHelper.free &&
      (row['product_id'] as String?)?.trim().isEmpty != false) {
    return false;
  }
  final environment = row['revenuecat_environment'];
  if (environment != null &&
      environment != 'sandbox' &&
      environment != 'production') {
    return false;
  }
  return true;
}

@visibleForTesting
List<Map<String, dynamic>> filterVerifiedSubscriptionStoreStateRows(
  Iterable<Map<String, dynamic>> rows, {
  required String userId,
  DateTime? now,
}) {
  final at = (now ?? DateTime.now()).toUtc();
  return rows
      .where((row) => _isParseableSubscriptionStoreStateRow(row, userId))
      .where((row) {
    final eventAt = _parseSubscriptionStateDate(row['event_at']);
    return row['verification_status'] == 'verified' &&
        eventAt != null &&
        !eventAt.isAfter(at);
  }).toList(growable: false);
}

@visibleForTesting
Map<String, dynamic> mergeSourceAwareSubscriptionState({
  required Map<String, dynamic> legacy,
  Map<String, dynamic>? source,
}) {
  if (source == null) return legacy;
  final rawStatus = source['status'];
  return {
    ...legacy,
    'tier': source['tier'],
    'status': rawStatus == 'billing_issue' ? 'active' : rawStatus,
    'expires_at': source['expires_at'],
    'active_product_id': source['product_id'],
    'store': source['store'],
    'base_plan_id': source['base_plan_id'],
    'verification_source': source['verification_source'],
    'revenuecat_environment': source['revenuecat_environment'],
  };
}

class SourceAwareSubscriptionStateRead {
  final Map<String, dynamic>? effective;
  final List<Map<String, dynamic>> sources;
  final bool hasVerifiedSource;
  final String cutoverStatus;
  final String? error;

  const SourceAwareSubscriptionStateRead({
    required this.effective,
    this.sources = const [],
    required this.hasVerifiedSource,
    this.cutoverStatus = 'pending',
    this.error,
  });

  bool get canOverrideLegacy =>
      error == null &&
      hasVerifiedSource &&
      (cutoverStatus == 'complete' || cutoverStatus == 'auto');

  bool canSafelyUpgradeLegacy(Map<String, dynamic> legacy) {
    if (error != null || !hasVerifiedSource || effective == null) return false;
    return SubscriptionTierHelper.rankOf(effective!['tier'] as String?) >
        SubscriptionTierHelper.rankOf(legacy['tier'] as String?);
  }
}

@visibleForTesting
bool shouldApplySourceAwareSubscriptionMetadata({
  required Map<String, dynamic> legacy,
  required SourceAwareSubscriptionStateRead read,
}) {
  return read.error == null &&
      (read.canOverrideLegacy || read.canSafelyUpgradeLegacy(legacy));
}

@visibleForTesting
bool resolveSourceStateAuthorityAfterRead({
  required bool current,
  required Map<String, dynamic> legacy,
  required SourceAwareSubscriptionStateRead read,
}) {
  if (read.error != null) return current;
  return shouldApplySourceAwareSubscriptionMetadata(
    legacy: legacy,
    read: read,
  );
}

@visibleForTesting
String resolveSubscriptionTierAfterSourceAwareSync({
  required String currentTier,
  required String revenueCatTier,
  String? syncedTier,
  required bool sourceAuthoritative,
}) {
  if (sourceAuthoritative) {
    return SubscriptionTierHelper.normalizeTier(currentTier);
  }
  return SubscriptionTierHelper.normalizeTier(syncedTier ?? revenueCatTier);
}

@visibleForTesting
Map<String, dynamic> applySourceAwareSubscriptionStateRead({
  required Map<String, dynamic> legacy,
  required SourceAwareSubscriptionStateRead read,
}) {
  if (read.error != null || !read.hasVerifiedSource) return legacy;
  if (!read.canOverrideLegacy && !read.canSafelyUpgradeLegacy(legacy)) {
    return legacy;
  }
  final source = read.effective;
  if (source != null) {
    return mergeSourceAwareSubscriptionState(
      legacy: legacy,
      source: source,
    );
  }

  // A successful read with a valid verified source but no currently effective
  // row is an authoritative free/expired result. Do not retain legacy paid
  // metadata while the source row is expired.
  return {
    ...legacy,
    'tier': SubscriptionTierHelper.free,
    'status': 'expired',
    'expires_at': null,
    'active_product_id': null,
    'store': null,
    'base_plan_id': null,
    'verification_source': null,
    'revenuecat_environment': null,
  };
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

class SubscriptionState {
  final String tier;
  final int monthlyMessagesUsed;
  final int dailyMessagesUsed;
  final int monthlyLimit;
  final int dailyLimit;
  final bool isLoading;
  final String? error;
  final Offerings? offerings;
  final String? pendingDowngradeToTier;
  final String? pendingDowngradeProductId;
  final DateTime? pendingDowngradeEffectiveAt;
  final DateTime? renewsAt;
  final String? activeProductId;
  final String? activeStore;
  final String? activeBasePlanId;
  final String? activeVerificationSource;
  final String? activeRevenueCatEnvironment;
  final List<String> sourceStores;
  final bool sourceStateAuthoritative;

  const SubscriptionState({
    this.tier = SubscriptionTierHelper.free,
    this.monthlyMessagesUsed = 0,
    this.dailyMessagesUsed = 0,
    this.monthlyLimit = AppConstants.freeMonthlyLimit,
    this.dailyLimit = AppConstants.freeDailyLimit,
    this.isLoading = false,
    this.error,
    this.offerings,
    this.pendingDowngradeToTier,
    this.pendingDowngradeProductId,
    this.pendingDowngradeEffectiveAt,
    this.renewsAt,
    this.activeProductId,
    this.activeStore,
    this.activeBasePlanId,
    this.activeVerificationSource,
    this.activeRevenueCatEnvironment,
    this.sourceStores = const [],
    this.sourceStateAuthoritative = false,
  });

  bool get isFreeUser => tier == SubscriptionTierHelper.free;
  bool get isStarter => tier == SubscriptionTierHelper.starter;
  bool get isEssential => tier == SubscriptionTierHelper.essential;
  bool get isPremium => isStarter || isEssential;

  /// Whether an Android purchase must be treated as a replacement attempt.
  ///
  /// Keep source metadata in this check: a paid entitlement can temporarily
  /// have a free tier snapshot while its authoritative store tuple is still
  /// present. In that case starting a second subscription is not safe.
  bool get hasActivePaidState =>
      !isFreeUser ||
      activeStore != null ||
      activeProductId != null ||
      activeBasePlanId != null;

  int get effectiveMonthlyLimit => monthlyLimit;
  int get effectiveDailyLimit => dailyLimit;

  int get monthlyRemaining => (effectiveMonthlyLimit - monthlyMessagesUsed)
      .clamp(0, effectiveMonthlyLimit);
  int get dailyRemaining =>
      (effectiveDailyLimit - dailyMessagesUsed).clamp(0, effectiveDailyLimit);
  bool get hasPendingDowngrade =>
      pendingDowngradeToTier != null && pendingDowngradeEffectiveAt != null;

  AndroidSubscriptionOfferingContract? get androidOfferingContract {
    final packages = offerings?.current?.availablePackages;
    if (packages == null) return null;
    return AndroidSubscriptionOfferingContract.fromPackages(packages);
  }

  Package? _knownIosPackage(SubscriptionPlanDefinition plan) {
    final packages = offerings?.current?.availablePackages;
    if (packages == null) return null;
    return findKnownIosPackage(packages, plan);
  }

  Package? _packageFor(SubscriptionPlanDefinition plan) {
    if (isAndroidPlatform) {
      return androidOfferingContract?.packageFor(plan.packageId);
    }
    return _knownIosPackage(plan);
  }

  Package? get starterPackage =>
      starterMonthlyPackage ?? starterQuarterlyPackage;
  Package? get essentialPackage =>
      essentialMonthlyPackage ?? essentialQuarterlyPackage;
  Package? get starterMonthlyPackage => _packageFor(
        SubscriptionPlanDefinition.starterMonthly,
      );
  Package? get starterQuarterlyPackage => _packageFor(
        SubscriptionPlanDefinition.starterQuarterly,
      );
  Package? get essentialMonthlyPackage => _packageFor(
        SubscriptionPlanDefinition.essentialMonthly,
      );
  Package? get essentialQuarterlyPackage => _packageFor(
        SubscriptionPlanDefinition.essentialQuarterly,
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
    Object? pendingDowngradeToTier = _subscriptionStateUnset,
    Object? pendingDowngradeProductId = _subscriptionStateUnset,
    Object? pendingDowngradeEffectiveAt = _subscriptionStateUnset,
    Object? renewsAt = _subscriptionStateUnset,
    Object? activeProductId = _subscriptionStateUnset,
    Object? activeStore = _subscriptionStateUnset,
    Object? activeBasePlanId = _subscriptionStateUnset,
    Object? activeVerificationSource = _subscriptionStateUnset,
    Object? activeRevenueCatEnvironment = _subscriptionStateUnset,
    Object? sourceStores = _subscriptionStateUnset,
    bool? sourceStateAuthoritative,
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
      activeStore: activeStore == _subscriptionStateUnset
          ? this.activeStore
          : activeStore as String?,
      activeBasePlanId: activeBasePlanId == _subscriptionStateUnset
          ? this.activeBasePlanId
          : activeBasePlanId as String?,
      activeVerificationSource:
          activeVerificationSource == _subscriptionStateUnset
              ? this.activeVerificationSource
              : activeVerificationSource as String?,
      activeRevenueCatEnvironment:
          activeRevenueCatEnvironment == _subscriptionStateUnset
              ? this.activeRevenueCatEnvironment
              : activeRevenueCatEnvironment as String?,
      sourceStores: sourceStores == _subscriptionStateUnset
          ? this.sourceStores
          : List<String>.from(sourceStores as List),
      sourceStateAuthoritative:
          sourceStateAuthoritative ?? this.sourceStateAuthoritative,
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
  final AndroidSubscriptionReplacementMode? replacementMode;

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
    this.replacementMode,
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

  // RevenueCat CustomerInfo product/expiry fields have no per-subscription
  // store provenance. Once a verified source row is applied, keep its
  // complete metadata tuple intact until the server returns a new winner.
  bool get _hasAuthoritativeSourceMetadata => state.sourceStateAuthoritative;

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
  }) {
    return RevenueCatService.getPremiumExpirationDate(customerInfo) ??
        state.renewsAt ??
        RevenueCatService.estimateRenewalDateFromPeriod(
          package?.storeProduct.subscriptionPeriod,
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
            final returnedRow = <String, dynamic>{
              ...Map<String, dynamic>.from(data),
              'status': data['tier'] == SubscriptionTierHelper.free
                  ? 'expired'
                  : 'active',
              'expires_at': data['expiresAt'],
              'active_product_id': data['activeProductId'],
              'store': data['store'],
              'revenuecat_environment': data['revenueCatEnvironment'],
            };
            final userId = SupabaseService.currentUser?.id;
            final sourceRead = userId == null
                ? const SourceAwareSubscriptionStateRead(
                    effective: null,
                    hasVerifiedSource: false,
                    error: 'not logged in',
                  )
                : await _loadEffectiveSubscriptionStoreState(userId);
            final sourceAuthoritative = resolveSourceStateAuthorityAfterRead(
              current: state.sourceStateAuthoritative,
              legacy: returnedRow,
              read: sourceRead,
            );
            final sourceReadUnavailableWhileAuthoritative =
                sourceRead.error != null && state.sourceStateAuthoritative;
            final mergedRow = sourceReadUnavailableWhileAuthoritative
                ? {
                    ...returnedRow,
                    'tier': state.tier,
                    'status': state.tier == SubscriptionTierHelper.free
                        ? 'expired'
                        : 'active',
                    'expires_at': state.renewsAt?.toIso8601String(),
                    'active_product_id': state.activeProductId,
                    'store': state.activeStore,
                    'base_plan_id': state.activeBasePlanId,
                    'verification_source': state.activeVerificationSource,
                    'revenuecat_environment': state.activeRevenueCatEnvironment,
                  }
                : applySourceAwareSubscriptionStateRead(
                    legacy: returnedRow,
                    read: sourceRead,
                  );
            final sourceMetadataAvailable =
                sourceRead.error == null && sourceAuthoritative;
            final sourceRowsAvailable =
                sourceRead.error == null && sourceRead.hasVerifiedSource;
            final tier = sourceReadUnavailableWhileAuthoritative
                ? state.tier
                : SubscriptionTierHelper.normalizeTier(
                    mergedRow['tier'] as String?,
                  );
            final limits = SubscriptionTierHelper.limitsFor(tier);
            final monthlyUsed = _readInt(mergedRow['monthlyMessagesUsed']);
            final dailyUsed = _readInt(mergedRow['dailyMessagesUsed']);
            final renewsAt = sourceReadUnavailableWhileAuthoritative
                ? state.renewsAt
                : _parseDateTime(mergedRow['expires_at']);
            final activeProductId = _cleanProductId(
              mergedRow['active_product_id'] as String?,
            );

            state = _applyPendingDowngradeMetadata(state.copyWith(
              tier: tier,
              monthlyLimit: limits.monthly,
              dailyLimit: limits.daily,
              monthlyMessagesUsed: monthlyUsed,
              dailyMessagesUsed: dailyUsed,
              renewsAt: sourceMetadataAvailable
                  ? renewsAt
                  : renewsAt ?? state.renewsAt,
              activeProductId: sourceMetadataAvailable
                  ? activeProductId
                  : tier == SubscriptionTierHelper.free
                      ? null
                      : activeProductId ?? state.activeProductId,
              activeStore: sourceMetadataAvailable
                  ? mergedRow['store'] as String?
                  : sourceReadUnavailableWhileAuthoritative
                      ? state.activeStore
                      : _subscriptionStateUnset,
              activeBasePlanId: sourceMetadataAvailable
                  ? mergedRow['base_plan_id'] as String?
                  : sourceReadUnavailableWhileAuthoritative
                      ? state.activeBasePlanId
                      : _subscriptionStateUnset,
              activeVerificationSource: sourceMetadataAvailable
                  ? mergedRow['verification_source'] as String?
                  : sourceReadUnavailableWhileAuthoritative
                      ? state.activeVerificationSource
                      : _subscriptionStateUnset,
              activeRevenueCatEnvironment: sourceMetadataAvailable
                  ? mergedRow['revenuecat_environment'] as String?
                  : sourceReadUnavailableWhileAuthoritative
                      ? state.activeRevenueCatEnvironment
                      : _subscriptionStateUnset,
              sourceStores: sourceRowsAvailable
                  ? sourceRead.sources
                      .map((row) => row['store'])
                      .whereType<String>()
                      .toSet()
                      .toList(growable: false)
                  : _subscriptionStateUnset,
              sourceStateAuthoritative: sourceAuthoritative,
              error: null,
            ));
            UsageService.syncSubscriptionSnapshot(
              tier: tier,
              monthlyLimit: limits.monthly,
              dailyLimit: limits.daily,
              monthlyUsed: monthlyUsed,
              dailyUsed: dailyUsed,
              paidExpiresAt: renewsAt,
              clearPaidSnapshot: tier == SubscriptionTierHelper.free &&
                  (sourceAuthoritative || _isExpired(renewsAt)),
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

  Future<SourceAwareSubscriptionStateRead> _loadEffectiveSubscriptionStoreState(
    String userId,
  ) async {
    try {
      var cutoverStatus = 'pending';
      try {
        final reconciliation = await SupabaseService.client
            .from('subscription_store_state_reconciliations')
            .select('status')
            .eq('user_id', userId)
            .maybeSingle();
        final reconciliationStatus = reconciliation?['status'];
        if (reconciliationStatus == 'complete' ||
            reconciliationStatus == 'auto') {
          cutoverStatus = reconciliationStatus as String;
        }
      } catch (error) {
        // Treat an unavailable cutover marker as a read failure, not a normal
        // pending result. A fresh session still falls back to legacy, while an
        // already-authoritative state keeps its exact source tuple until the
        // marker can be read again.
        debugPrint(
          '[subscription] reconciliation status unavailable: $error',
        );
        return SourceAwareSubscriptionStateRead(
          effective: null,
          hasVerifiedSource: false,
          error: 'reconciliation status unavailable: $error',
        );
      }

      final dynamic result = await SupabaseService.client
          .from('subscription_store_states')
          .select(
            'user_id, store, product_id, base_plan_id, tier, status, '
            'expires_at, event_at, event_id, verification_source, '
            'verification_status, revenuecat_environment',
          )
          .eq('user_id', userId);
      if (result is! List) {
        return const SourceAwareSubscriptionStateRead(
          effective: null,
          hasVerifiedSource: false,
          error: 'invalid source-aware state response',
        );
      }

      final rows = result
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
      final readAt = DateTime.now().toUtc();
      final validRows = rows
          .where((row) => _isParseableSubscriptionStoreStateRow(row, userId))
          .toList(growable: false);
      final verifiedRows = filterVerifiedSubscriptionStoreStateRows(
        validRows,
        userId: userId,
        now: readAt,
      );
      return SourceAwareSubscriptionStateRead(
        effective: resolveEffectiveSubscriptionStoreState(
          validRows,
          userId: userId,
          now: readAt,
        ),
        // Only verified rows whose authoritative event has happened may be
        // exposed as source provenance. Future/unverified rows stay internal
        // until a later reconciliation.
        sources: verifiedRows,
        hasVerifiedSource: verifiedRows.isNotEmpty,
        cutoverStatus: cutoverStatus,
      );
    } catch (error) {
      debugPrint(
        '[subscription] source-aware state read unavailable; using legacy row: $error',
      );
      return SourceAwareSubscriptionStateRead(
        effective: null,
        hasVerifiedSource: false,
        error: error.toString(),
      );
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

      var customerInfo = await RevenueCatService.login(user.id);
      customerInfo ??= await RevenueCatService.getCustomerInfoForAppUserId(
        user.id,
      );

      final legacyResponse = await _loadOrCreateSubscriptionRecord(
        userId: user.id,
        tier: SubscriptionTierHelper.free,
      );
      final sourceRead = await _loadEffectiveSubscriptionStoreState(user.id);
      final response = applySourceAwareSubscriptionStateRead(
        legacy: legacyResponse,
        read: sourceRead,
      );
      final sourceAuthoritative = resolveSourceStateAuthorityAfterRead(
        current: state.sourceStateAuthoritative,
        legacy: legacyResponse,
        read: sourceRead,
      );
      final sourceReadUnavailableWhileAuthoritative =
          sourceRead.error != null && state.sourceStateAuthoritative;
      final sourceMetadataAvailable =
          sourceRead.error == null && sourceAuthoritative;
      final sourceRowsAvailable =
          sourceRead.error == null && sourceRead.hasVerifiedSource;

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
      // A complete cutover or a safe free-baseline upgrade may use the source
      // row as a trusted projection. RevenueCat's Flutter CustomerInfo does
      // not expose per-product store provenance, so its product id must not
      // be mixed into a verified multi-store winner.
      final displayTier = sourceMetadataAvailable
          ? initialTier
          : sourceReadUnavailableWhileAuthoritative
              ? state.tier
              : resolveStartupSubscriptionTier(
                  databaseTier: initialTier,
                  revenueCatTier: revenueCatTier,
                  cachedTier: cachedTier,
                  serverExpiresAt: renewsAt,
                );
      final displayLimits = SubscriptionTierHelper.limitsFor(displayTier);
      final sourceProductId = _cleanProductId(
        response['active_product_id'] as String?,
      );

      state = _applyPendingDowngradeMetadata(state.copyWith(
        tier: displayTier,
        monthlyMessagesUsed: rowMonthlyUsed,
        dailyMessagesUsed: rowDailyUsed,
        monthlyLimit: displayLimits.monthly,
        dailyLimit: displayLimits.daily,
        renewsAt:
            sourceReadUnavailableWhileAuthoritative ? state.renewsAt : renewsAt,
        activeProductId: sourceMetadataAvailable
            ? sourceProductId
            : sourceReadUnavailableWhileAuthoritative
                ? state.activeProductId
                : displayTier == SubscriptionTierHelper.free
                    ? null
                    : revenueCatProductId ?? state.activeProductId,
        activeStore: sourceMetadataAvailable
            ? response['store'] as String?
            : sourceReadUnavailableWhileAuthoritative
                ? state.activeStore
                : _subscriptionStateUnset,
        activeBasePlanId: sourceMetadataAvailable
            ? response['base_plan_id'] as String?
            : sourceReadUnavailableWhileAuthoritative
                ? state.activeBasePlanId
                : _subscriptionStateUnset,
        activeVerificationSource: sourceMetadataAvailable
            ? response['verification_source'] as String?
            : sourceReadUnavailableWhileAuthoritative
                ? state.activeVerificationSource
                : _subscriptionStateUnset,
        activeRevenueCatEnvironment: sourceMetadataAvailable
            ? response['revenuecat_environment'] as String?
            : sourceReadUnavailableWhileAuthoritative
                ? state.activeRevenueCatEnvironment
                : _subscriptionStateUnset,
        sourceStores: sourceRowsAvailable
            ? sourceRead.sources
                .map((row) => row['store'])
                .whereType<String>()
                .toSet()
                .toList(growable: false)
            : _subscriptionStateUnset,
        sourceStateAuthoritative: sourceAuthoritative,
        isLoading: false,
        error: null,
      ));
      UsageService.syncSubscriptionSnapshot(
        tier: displayTier,
        monthlyLimit: displayLimits.monthly,
        dailyLimit: displayLimits.daily,
        monthlyUsed: rowMonthlyUsed,
        dailyUsed: rowDailyUsed,
        paidExpiresAt: state.renewsAt,
        clearPaidSnapshot: displayTier == SubscriptionTierHelper.free &&
            (sourceAuthoritative || _isExpired(state.renewsAt)),
      );

      final syncedDisplayTier = await _syncSubscriptionViaEdgeFunction(
        expectedTier: displayTier,
        resetUsage: initialTier != displayTier &&
            displayTier != SubscriptionTierHelper.free,
        revenueCatAppUserId: revenueCatAppUserId,
      );
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
        await _attemptStartupPaidRescue(displayTier: tier);
        return;
      }
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

    final currentUserId = SupabaseService.currentUser?.id;
    final customerInfo =
        await RevenueCatService.syncPurchasesAndRefreshCustomerInfo(
      expectedAppUserId: currentUserId,
    );
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
    final preserveSourceMetadata = _hasAuthoritativeSourceMetadata;
    state = _applyPendingDowngradeMetadata(state.copyWith(
      tier: tier,
      monthlyLimit: limits.monthly,
      dailyLimit: limits.daily,
      renewsAt:
          preserveSourceMetadata ? state.renewsAt : renewsAt ?? state.renewsAt,
      activeProductId: preserveSourceMetadata
          ? state.activeProductId
          : activeProductId ?? state.activeProductId,
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

  Future<void> refresh() async {
    state = _applyPendingDowngradeMetadata(
      state.copyWith(isLoading: true, error: null),
    );
    await _loadSubscription();
    await _loadOfferings();
  }

  Future<SubscriptionPurchaseResult> purchase(Package package) async {
    final plan = _definitionForPackage(package);
    if (plan == null) {
      return _failedPurchaseResult(
        requestedTier: SubscriptionTierHelper.free,
        previousTier: state.tier,
        message: '方案未通過目前 Offering 的精確商品契約。',
      );
    }
    return _purchaseProduct(package: package, plan: plan);
  }

  SubscriptionPlanDefinition? _definitionForPackage(Package package) {
    final packages = state.offerings?.current?.availablePackages;
    if (packages == null || packages.isEmpty) return null;

    if (isAndroidPlatform) {
      final contract = state.androidOfferingContract;
      if (contract == null) return null;
      for (final plan in SubscriptionPlanDefinition.androidPlans) {
        final resolved = contract.packageFor(plan.packageId);
        if (resolved?.identifier == package.identifier &&
            resolved?.storeProduct.identifier ==
                package.storeProduct.identifier) {
          return plan;
        }
      }
      return null;
    }

    for (final plan in SubscriptionPlanDefinition.androidPlans) {
      final resolved = findKnownIosPackage(packages, plan);
      if (resolved?.identifier == package.identifier &&
          resolved?.storeProduct.identifier ==
              package.storeProduct.identifier) {
        return plan;
      }
    }
    return null;
  }

  SubscriptionPurchaseResult _failedPurchaseResult({
    required String requestedTier,
    required String previousTier,
    required String message,
  }) {
    return SubscriptionPurchaseResult(
      success: false,
      cancelled: false,
      isDeferredDowngrade: false,
      requestedTier: requestedTier,
      previousTier: previousTier,
      activeTier: state.tier,
      errorMessage: message,
    );
  }

  Future<SubscriptionPurchaseResult> _purchaseProduct({
    required Package package,
    required SubscriptionPlanDefinition plan,
  }) async {
    final product = package.storeProduct;
    final productId = product.identifier.trim();
    final requestedTier = plan.tier;
    final previousTier = state.tier;
    final requestedDowngrade = SubscriptionTierHelper.isDowngrade(
      fromTier: previousTier,
      toTier: requestedTier,
    );

    AndroidSubscriptionReplacementDecision? replacement;
    GoogleProductChangeInfo? googleProductChangeInfo;
    if (isAndroidPlatform) {
      replacement = resolveAndroidReplacement(
        target: plan,
        activeStore: state.activeStore,
        activeProductId: state.activeProductId,
        activeBasePlanId: state.activeBasePlanId,
        activeStateAuthoritative: state.sourceStateAuthoritative,
        hasActivePaidState: state.hasActivePaidState,
      );
      if (!replacement.isAllowed) {
        return _failedPurchaseResult(
          requestedTier: requestedTier,
          previousTier: previousTier,
          message: '目前訂閱來源尚未完成驗證，為避免重複扣款已暫停換方案。',
        );
      }
      final mode = googleProrationModeFor(replacement.mode);
      if (mode != null && replacement.oldProductIdentifier != null) {
        googleProductChangeInfo = GoogleProductChangeInfo(
          replacement.oldProductIdentifier!,
          prorationMode: mode,
        );
      }
    }

    try {
      state = _applyPendingDowngradeMetadata(
        state.copyWith(isLoading: true, error: null),
      );

      debugPrint('=== PURCHASE START ===');
      debugPrint('Product: ${product.identifier}');

      final customerInfo = await RevenueCatService.purchase(
        package,
        googleProductChangeInfo: googleProductChangeInfo,
      );

      debugPrint('=== PURCHASE RESULT ===');
      debugPrint('Active Subscriptions: ${customerInfo.activeSubscriptions}');
      debugPrint(
        'All Purchased: ${customerInfo.allPurchasedProductIdentifiers}',
      );
      debugPrint(
        'Active Entitlements: ${customerInfo.entitlements.active.keys.toList()}',
      );

      final isDeferredDowngrade =
          replacement?.mode == AndroidSubscriptionReplacementMode.deferred ||
              (!isAndroidPlatform && requestedDowngrade);
      if (isDeferredDowngrade) {
        final effectiveAt = _resolveDowngradeEffectiveAt(
          customerInfo: customerInfo,
          package: package,
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
          replacementMode: replacement?.mode,
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
      final preserveSourceMetadata = _hasAuthoritativeSourceMetadata;
      final tier = resolveSubscriptionTierAfterSourceAwareSync(
        currentTier: state.tier,
        revenueCatTier: resolvedTier,
        syncedTier: syncedTier,
        sourceAuthoritative: preserveSourceMetadata,
      );
      final limits = SubscriptionTierHelper.limitsFor(tier);

      state = _applyPendingDowngradeMetadata(state.copyWith(
        tier: tier,
        monthlyLimit: limits.monthly,
        dailyLimit: limits.daily,
        renewsAt: preserveSourceMetadata
            ? state.renewsAt
            : purchasedRenewsAt ?? state.renewsAt,
        activeProductId: tier == SubscriptionTierHelper.free
            ? null
            : preserveSourceMetadata
                ? state.activeProductId
                : purchasedProductId,
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
        replacementMode: replacement?.mode,
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

    debugPrint('[forceSyncTier] Starting sync: tier=$tier');
    final customerInfo = await RevenueCatService.getCustomerInfoForAppUserId(
      user.id,
    );
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

      final preserveSourceMetadata = _hasAuthoritativeSourceMetadata;
      final tier =
          isScheduledDowngradeSnapshot || shouldPreservePaidFreeSnapshot
              ? previousTier
              : resolveSubscriptionTierAfterSourceAwareSync(
                  currentTier: state.tier,
                  revenueCatTier: restoredTier,
                  syncedTier: syncedTier,
                  sourceAuthoritative: preserveSourceMetadata,
                );
      final limits = SubscriptionTierHelper.limitsFor(tier);

      state = _applyPendingDowngradeMetadata(state.copyWith(
        tier: tier,
        monthlyLimit: limits.monthly,
        dailyLimit: limits.daily,
        renewsAt: preserveSourceMetadata
            ? state.renewsAt
            : renewsAt ?? state.renewsAt,
        activeProductId: tier == SubscriptionTierHelper.free
            ? null
            : preserveSourceMetadata ||
                    isScheduledDowngradeSnapshot ||
                    shouldPreservePaidFreeSnapshot
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
        if (!_hasAuthoritativeSourceMetadata &&
            renewsAt != null &&
            renewsAt != state.renewsAt) {
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
        final preserveSourceMetadata = _hasAuthoritativeSourceMetadata;
        final tier =
            syncedTier ?? (preserveSourceMetadata ? state.tier : rcTier);
        final limits = SubscriptionTierHelper.limitsFor(tier);

        state = _applyPendingDowngradeMetadata(state.copyWith(
          tier: tier,
          monthlyLimit: limits.monthly,
          dailyLimit: limits.daily,
          renewsAt: preserveSourceMetadata
              ? state.renewsAt
              : renewsAt ?? state.renewsAt,
          activeProductId: tier == SubscriptionTierHelper.free
              ? null
              : preserveSourceMetadata
                  ? state.activeProductId
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

        final shouldRefreshMetadata = !_hasAuthoritativeSourceMetadata &&
            ((activeProductId != null &&
                    activeProductId != state.activeProductId) ||
                (renewsAt != null && renewsAt != state.renewsAt));
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
    final preserveSourceMetadata = _hasAuthoritativeSourceMetadata;
    state = state.copyWith(
      pendingDowngradeToTier: null,
      pendingDowngradeProductId: null,
      pendingDowngradeEffectiveAt: null,
      activeProductId: preserveSourceMetadata
          ? state.activeProductId
          : activeProductId ?? state.activeProductId,
      renewsAt:
          preserveSourceMetadata ? state.renewsAt : renewsAt ?? state.renewsAt,
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
