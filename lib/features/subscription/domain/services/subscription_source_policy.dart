import 'subscription_product_contract.dart';
import 'subscription_tier_helper.dart';

/// A verified RevenueCat subscription row projected for client decisions.
///
/// The source is intentionally kept beside the product and expiry. Callers
/// must not combine fields from different stores into one entitlement.
class SubscriptionSourceState {
  const SubscriptionSourceState({
    required this.store,
    required this.productId,
    required this.basePlanId,
    required this.tier,
    required this.status,
    required this.expiresAt,
    required this.eventAt,
    required this.eventId,
    required this.verificationSource,
    required this.verificationStatus,
    required this.revenueCatEnvironment,
  });

  final String store;
  final String? productId;
  final String? basePlanId;
  final String tier;
  final String status;
  final DateTime? expiresAt;
  final DateTime eventAt;
  final String eventId;
  final String? verificationSource;
  final String verificationStatus;
  final String? revenueCatEnvironment;

  bool get isVerified => verificationStatus == 'verified';

  /// Returns true only while this exact source row proves access.
  bool isEffectiveAt(DateTime now) {
    if (!isVerified || status == 'expired' || tier == 'free') return false;
    final at = now.toUtc();
    if (eventAt.toUtc().isAfter(at)) return false;
    final expiry = expiresAt?.toUtc();
    if (expiry == null) return false;
    return expiry.isAfter(at);
  }

  String get storeLabel => subscriptionStoreLabel(store);

  String get tierLabel {
    switch (SubscriptionTierHelper.normalizeTier(tier)) {
      case SubscriptionTierHelper.essential:
        return 'Essential';
      case SubscriptionTierHelper.starter:
        return 'Starter';
      default:
        return 'Free';
    }
  }

  /// Converts the server row shape into the public client source projection.
  /// Invalid rows are discarded rather than guessed.
  static SubscriptionSourceState? fromRow(Map<String, dynamic> row) {
    final store = row['store'];
    if (store is! String || (store != 'app_store' && store != 'play_store')) {
      return null;
    }
    final tier = row['tier'];
    if (tier is! String ||
        (tier != SubscriptionTierHelper.free &&
            tier != SubscriptionTierHelper.starter &&
            tier != SubscriptionTierHelper.essential)) {
      return null;
    }
    final status = row['status'];
    if (status is! String ||
        (status != 'active' &&
            status != 'cancelled' &&
            status != 'expired' &&
            status != 'billing_issue')) {
      return null;
    }
    final verificationStatus = row['verification_status'];
    if (verificationStatus is! String ||
        (verificationStatus != 'verified' &&
            verificationStatus != 'unverified')) {
      return null;
    }
    final verificationSource = row['verification_source'];
    if (verificationSource is! String ||
        (verificationSource != 'revenuecat_webhook' &&
            verificationSource != 'revenuecat_api' &&
            verificationSource != 'legacy_backfill')) {
      return null;
    }
    if (verificationSource == 'legacy_backfill' &&
        verificationStatus == 'verified') {
      return null;
    }
    final eventId = row['event_id'];
    if (eventId is! String || eventId.trim().isEmpty) return null;
    final eventAt = _parseDate(row['event_at']);
    if (eventAt == null) return null;
    final expiresAtRaw = row['expires_at'];
    final expiresAt = expiresAtRaw == null ? null : _parseDate(expiresAtRaw);
    if (expiresAtRaw != null && expiresAt == null) return null;
    if (expiresAt == null &&
        !(tier == SubscriptionTierHelper.free && status == 'expired')) {
      return null;
    }
    final environment = row['revenuecat_environment'];
    if (environment != null &&
        (environment is! String ||
            environment != 'sandbox' && environment != 'production')) {
      return null;
    }

    String? optionalText(Object? value) {
      if (value == null) return null;
      if (value is! String || value.trim().isEmpty) return null;
      return value.trim();
    }

    final productId = optionalText(row['product_id']);
    if (tier != SubscriptionTierHelper.free && productId == null) {
      return null;
    }

    return SubscriptionSourceState(
      store: store,
      productId: productId,
      basePlanId: optionalText(row['base_plan_id']),
      tier: tier,
      status: status,
      expiresAt: expiresAt,
      eventAt: eventAt,
      eventId: eventId.trim(),
      verificationSource: verificationSource,
      verificationStatus: verificationStatus,
      revenueCatEnvironment: optionalText(environment),
    );
  }
}

DateTime? _parseDate(Object? value) {
  if (value is DateTime) return value.toUtc();
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.tryParse(value)?.toUtc();
  }
  return null;
}

String subscriptionStoreLabel(String? store) {
  switch (store) {
    case 'play_store':
      return 'Google Play';
    case 'app_store':
      return 'App Store';
    default:
      return '未知商店';
  }
}

int _sourceStoreOrder(String store) {
  switch (store) {
    case 'app_store':
      return 0;
    case 'play_store':
      return 1;
    default:
      return 2;
  }
}

int _compareSources(
    SubscriptionSourceState left, SubscriptionSourceState right) {
  final storeDifference =
      _sourceStoreOrder(left.store) - _sourceStoreOrder(right.store);
  if (storeDifference != 0) return storeDifference;
  return right.eventAt.compareTo(left.eventAt);
}

String sourceAwareManagementStoreLabel({
  required Iterable<SubscriptionSourceState> sources,
  required bool authoritative,
  String? fallbackStore,
  DateTime? now,
}) {
  final stores = <String>[];
  final projection = SourceAwareSubscriptionProjection(
    sources: List.unmodifiable(sources),
    authoritative: authoritative,
  );
  final visibleSources = authoritative ? projection.activeAt(now) : const [];
  for (final source in visibleSources) {
    if (!stores.contains(source.store)) stores.add(source.store);
  }
  if (stores.length > 1) return 'App Store 與 Google Play';
  return subscriptionStoreLabel(stores.singleOrNull ?? fallbackStore);
}

class SourceAwareSubscriptionProjection {
  const SourceAwareSubscriptionProjection({
    required this.sources,
    required this.authoritative,
  });

  final List<SubscriptionSourceState> sources;
  final bool authoritative;

  List<SubscriptionSourceState> activeAt([DateTime? now]) {
    final at = (now ?? DateTime.now()).toUtc();
    return sources.where((source) => source.isEffectiveAt(at)).toList(
          growable: false,
        );
  }

  SubscriptionSourceState? effectiveAt([DateTime? now]) {
    if (!authoritative) return null;
    final candidates = activeAt(now).toList(growable: true);
    candidates.sort((left, right) {
      final tierDifference = SubscriptionTierHelper.rankOf(right.tier) -
          SubscriptionTierHelper.rankOf(left.tier);
      if (tierDifference != 0) return tierDifference;
      final eventDifference = right.eventAt.compareTo(left.eventAt);
      if (eventDifference != 0) return eventDifference;
      return left.store.compareTo(right.store);
    });
    return candidates.firstOrNull;
  }

  bool hasMultipleActiveSources([DateTime? now]) => activeAt(now).length > 1;

  bool hasStore(String store) => sources.any((source) => source.store == store);
}

enum SourceAwarePurchaseBlockReason {
  originalStore,
  multipleStores,
  unknownSource,
  samePlan,
}

class SourceAwarePurchaseEligibility {
  const SourceAwarePurchaseEligibility({
    required this.targetStore,
    required this.activeSources,
    required this.replacement,
    required this.blockReason,
    required this.originalStore,
  });

  final String targetStore;
  final List<SubscriptionSourceState> activeSources;
  final AndroidSubscriptionReplacementDecision? replacement;
  final SourceAwarePurchaseBlockReason? blockReason;
  final String? originalStore;

  bool get canPurchase => blockReason == null;

  /// A management CTA is safe only when one verified source is the sole
  /// blocker. Multiple sources and unknown tuples must remain disabled rather
  /// than pretending there is one destination.
  bool get canManageOriginalStore =>
      blockReason == SourceAwarePurchaseBlockReason.originalStore &&
      activeSources.length == 1;

  String get message {
    switch (blockReason) {
      case SourceAwarePurchaseBlockReason.originalStore:
        return '你已有 ${subscriptionStoreLabel(originalStore)} 訂閱，請前往原購買商店管理。';
      case SourceAwarePurchaseBlockReason.multipleStores:
        return '目前同時有 App Store 與 Google Play 訂閱，請分別到原商店管理；這裡不會代為取消。';
      case SourceAwarePurchaseBlockReason.samePlan:
        return '這是目前正在使用的方案。';
      case SourceAwarePurchaseBlockReason.unknownSource:
        return '目前訂閱來源尚未完成驗證，為避免重複扣款已暫停購買。';
      case null:
        return replacementConfirmationMessage(replacement?.mode);
    }
  }
}

SourceAwarePurchaseEligibility resolveSourceAwarePurchaseEligibility({
  required String targetStore,
  required SubscriptionPlanDefinition targetPlan,
  required Iterable<SubscriptionSourceState> sources,
  required bool sourceStateAuthoritative,
  required bool hasActivePaidState,
  DateTime? now,
}) {
  if (targetStore != 'app_store' && targetStore != 'play_store') {
    return SourceAwarePurchaseEligibility(
      targetStore: targetStore,
      activeSources: const [],
      replacement: null,
      blockReason: SourceAwarePurchaseBlockReason.unknownSource,
      originalStore: null,
    );
  }

  final projection = SourceAwareSubscriptionProjection(
    sources: List.unmodifiable(sources),
    authoritative: sourceStateAuthoritative,
  );
  final activeSources = projection.activeAt(now);
  if (activeSources.isEmpty) {
    // A paid local tuple without a current verified source is not evidence
    // for a new purchase. Preserve the existing fail-closed behavior.
    if (hasActivePaidState && !sourceStateAuthoritative) {
      return SourceAwarePurchaseEligibility(
        targetStore: targetStore,
        activeSources: activeSources,
        replacement: null,
        blockReason: SourceAwarePurchaseBlockReason.unknownSource,
        originalStore: null,
      );
    }
    return SourceAwarePurchaseEligibility(
      targetStore: targetStore,
      activeSources: activeSources,
      replacement: null,
      blockReason: null,
      originalStore: null,
    );
  }

  if (activeSources.length > 1) {
    return SourceAwarePurchaseEligibility(
      targetStore: targetStore,
      activeSources: List.unmodifiable(activeSources),
      replacement: null,
      blockReason: SourceAwarePurchaseBlockReason.multipleStores,
      originalStore: null,
    );
  }

  final active = activeSources.single;
  if (active.store != targetStore) {
    return SourceAwarePurchaseEligibility(
      targetStore: targetStore,
      activeSources: List.unmodifiable(activeSources),
      replacement: null,
      blockReason: SourceAwarePurchaseBlockReason.originalStore,
      originalStore: active.store,
    );
  }

  final activePlan = targetStore == 'play_store'
      ? SubscriptionPlanDefinition.fromAuthoritativePlayIdentifiers(
          productId: active.productId,
          basePlanId: active.basePlanId,
        )
      : SubscriptionPlanDefinition.androidPlans
          .where((plan) => plan.matchesIosProductId(active.productId ?? ''))
          .singleOrNull;
  if (activePlan == null) {
    return SourceAwarePurchaseEligibility(
      targetStore: targetStore,
      activeSources: List.unmodifiable(activeSources),
      replacement: null,
      blockReason: SourceAwarePurchaseBlockReason.unknownSource,
      originalStore: active.store,
    );
  }
  final isSamePlan = activePlan.packageId == targetPlan.packageId;
  if (isSamePlan) {
    return SourceAwarePurchaseEligibility(
      targetStore: targetStore,
      activeSources: List.unmodifiable(activeSources),
      replacement: null,
      blockReason: SourceAwarePurchaseBlockReason.samePlan,
      originalStore: active.store,
    );
  }

  if (targetStore != 'play_store') {
    return SourceAwarePurchaseEligibility(
      targetStore: targetStore,
      activeSources: List.unmodifiable(activeSources),
      replacement: null,
      blockReason: null,
      originalStore: active.store,
    );
  }

  final replacement = resolveAndroidReplacement(
    target: targetPlan,
    activeStore: active.store,
    activeProductId: active.productId,
    activeBasePlanId: active.basePlanId,
    activeStateAuthoritative: sourceStateAuthoritative,
    hasActivePaidState: true,
  );
  return SourceAwarePurchaseEligibility(
    targetStore: targetStore,
    activeSources: List.unmodifiable(activeSources),
    replacement: replacement,
    blockReason:
        replacement.error == 'target is already the active subscription'
            ? SourceAwarePurchaseBlockReason.samePlan
            : replacement.isAllowed
                ? null
                : SourceAwarePurchaseBlockReason.unknownSource,
    originalStore: active.store,
  );
}

String sourceAwareEntitlementHeadline({
  required String tier,
  required Iterable<SubscriptionSourceState> sources,
  required bool authoritative,
  DateTime? now,
}) {
  final projection = SourceAwareSubscriptionProjection(
    sources: List.unmodifiable(sources),
    authoritative: authoritative,
  );
  final effective = projection.effectiveAt(now);
  if (!authoritative) {
    final normalized = SubscriptionTierHelper.normalizeTier(tier);
    final label = normalized == SubscriptionTierHelper.essential
        ? 'Essential'
        : normalized == SubscriptionTierHelper.starter
            ? 'Starter'
            : null;
    return label == null ? '目前沒有啟用中的訂閱權益' : '權益已啟用：$label';
  }
  if (effective == null) {
    return SubscriptionTierHelper.normalizeTier(tier) ==
            SubscriptionTierHelper.free
        ? '目前沒有啟用中的訂閱權益'
        : '訂閱權益來源確認中';
  }
  // Prefer the complete authoritative source tuple over a legacy aggregate
  // tier, which may be stale during cross-store reconciliation.
  final normalized = SubscriptionTierHelper.normalizeTier(effective.tier);
  final label = normalized == SubscriptionTierHelper.essential
      ? 'Essential'
      : normalized == SubscriptionTierHelper.starter
          ? 'Starter'
          : '付費';
  return '權益已啟用：$label';
}

List<String> sourceAwareSourceDetails(
  Iterable<SubscriptionSourceState> sources, {
  required bool authoritative,
  DateTime? now,
}) {
  if (!authoritative) return const [];
  final all =
      sources.where((source) => source.isVerified).toList(growable: false);
  final at = (now ?? DateTime.now()).toUtc();
  final active = all.where((source) => source.isEffectiveAt(at)).toList()
    ..sort(_compareSources);
  final inactive = all.where((source) => !source.isEffectiveAt(at)).toList()
    ..sort(_compareSources);
  final ordered = [
    ...active,
    ...inactive,
  ];
  final seen = <String>{};
  return ordered
      .where((source) => seen.add(source.store))
      .map((source) => '${source.storeLabel}：${source.tierLabel}')
      .toList(growable: false);
}

String sourceAwareAccountDeletionCopy(
  Iterable<SubscriptionSourceState> sources, {
  required bool authoritative,
  DateTime? now,
}) {
  final activeStores = <String>[];
  final projection = SourceAwareSubscriptionProjection(
    sources: List.unmodifiable(sources),
    authoritative: authoritative,
  );
  final visibleSources = authoritative ? projection.activeAt(now) : const [];
  for (final source in visibleSources) {
    if (!activeStores.contains(source.store)) activeStores.add(source.store);
  }
  activeStores.sort(
    (left, right) => _sourceStoreOrder(left) - _sourceStoreOrder(right),
  );

  if (activeStores.isEmpty) {
    return '刪除帳號會永久刪除你的帳號與本機資料。';
  }

  final labels =
      activeStores.map(subscriptionStoreLabel).toList(growable: false);
  final storeText = labels.length == 1
      ? labels.single
      : labels.length == 2
          ? '${labels[0]} 與 ${labels[1]}'
          : labels.join('、');
  return '刪除帳號不會自動取消 $storeText 訂閱，請另外到原商店的訂閱管理中取消自動續訂。';
}
