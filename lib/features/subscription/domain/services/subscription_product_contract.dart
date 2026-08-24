import 'package:purchases_flutter/purchases_flutter.dart';

import 'subscription_tier_helper.dart';

/// The Play product/base-plan/package contract for the Android billing slice.
///
/// A Play subscription product and its base plan are deliberately kept as two
/// separate fields. RevenueCat's Flutter SDK exposes the combined
/// `product:basePlan` identifier on [SubscriptionOption.storeProductId], while
/// Google Play replacement requests require the bare subscription product ID.
class SubscriptionPlanDefinition {
  const SubscriptionPlanDefinition({
    required this.playProductId,
    required this.basePlanId,
    required this.packageId,
    required this.tier,
    required this.period,
    required this.iosProductIds,
  });

  final String playProductId;
  final String basePlanId;
  final String packageId;
  final String tier;
  final SubscriptionPlanPeriod period;

  /// Known App Store identifiers retained for the existing iOS purchase path.
  /// These are exact IDs, not a text-search fallback.
  final List<String> iosProductIds;

  String get playProductWithBasePlan => '$playProductId:$basePlanId';

  bool matchesIosProductId(String productId) =>
      iosProductIds.contains(productId.trim());

  /// Validates all three Android identifiers exposed by RevenueCat:
  /// package identifier, StoreProduct identifier, and base-plan option.
  ///
  /// Titles, descriptions, localized text, and inferred periods are never
  /// consulted here. A package with a malformed or ambiguous option is not
  /// safe to purchase.
  bool matchesAndroidPackage(Package package) {
    if (package.identifier.trim() != packageId) return false;

    final product = package.storeProduct;
    if (product.identifier.trim() != playProductWithBasePlan) return false;

    final matchingOptions = (product.subscriptionOptions ?? const [])
        .where(
          (option) =>
              option.isBasePlan &&
              option.id.trim() == basePlanId &&
              option.productId.trim() == playProductId &&
              option.storeProductId.trim() == playProductWithBasePlan,
        )
        .toList(growable: false);
    return matchingOptions.length == 1;
  }

  @override
  String toString() =>
      '$playProductWithBasePlan -> $packageId -> $tier (${period.name})';

  static const starterMonthly = SubscriptionPlanDefinition(
    playProductId: 'vibesync_starter',
    basePlanId: 'monthly',
    packageId: 'starter_monthly',
    tier: SubscriptionTierHelper.starter,
    period: SubscriptionPlanPeriod.monthly,
    iosProductIds: [
      'starter_monthly',
      'vibesync_starter_monthly',
      'vibesync_starter_monthly_v2',
    ],
  );

  static const starterQuarterly = SubscriptionPlanDefinition(
    playProductId: 'vibesync_starter',
    basePlanId: 'quarterly',
    packageId: 'starter_quarterly',
    tier: SubscriptionTierHelper.starter,
    period: SubscriptionPlanPeriod.quarterly,
    iosProductIds: [
      'starter_quarterly',
      'vibesync_starter_quarterly',
      'vibesync_starter_quarterly_v2',
    ],
  );

  static const essentialMonthly = SubscriptionPlanDefinition(
    playProductId: 'vibesync_essential',
    basePlanId: 'monthly',
    packageId: 'essential_monthly',
    tier: SubscriptionTierHelper.essential,
    period: SubscriptionPlanPeriod.monthly,
    iosProductIds: [
      'essential_monthly',
      'vibesync_essential_monthly',
      'vibesync_essential_monthly_v2',
    ],
  );

  static const essentialQuarterly = SubscriptionPlanDefinition(
    playProductId: 'vibesync_essential',
    basePlanId: 'quarterly',
    packageId: 'essential_quarterly',
    tier: SubscriptionTierHelper.essential,
    period: SubscriptionPlanPeriod.quarterly,
    iosProductIds: [
      'essential_quarterly',
      'vibesync_essential_quarterly',
      'vibesync_essential_quarterly_v2',
    ],
  );

  static const androidPlans = <SubscriptionPlanDefinition>[
    starterMonthly,
    starterQuarterly,
    essentialMonthly,
    essentialQuarterly,
  ];

  static SubscriptionPlanDefinition? fromPackageId(String packageId) {
    final normalized = packageId.trim();
    for (final plan in androidPlans) {
      if (plan.packageId == normalized) return plan;
    }
    return null;
  }

  /// Resolves a server/CustomerInfo product tuple without guessing.
  ///
  /// `productId` may be the bare Play subscription ID or the combined
  /// `product:basePlan` form used by RevenueCat. In both cases the explicit
  /// base-plan field must be present and agree with the frozen mapping.
  static SubscriptionPlanDefinition? fromAuthoritativePlayIdentifiers({
    required String? productId,
    required String? basePlanId,
  }) {
    final product = productId?.trim();
    final basePlan = basePlanId?.trim();
    if (product == null ||
        product.isEmpty ||
        basePlan == null ||
        basePlan.isEmpty) {
      return null;
    }

    for (final plan in androidPlans) {
      final isBare = product == plan.playProductId;
      final isCombined = product == plan.playProductWithBasePlan;
      if ((isBare || isCombined) && basePlan == plan.basePlanId) {
        return plan;
      }
    }
    return null;
  }
}

enum SubscriptionPlanPeriod { monthly, quarterly }

/// A complete, uniquely validated current Android offering.
class AndroidSubscriptionOfferingContract {
  const AndroidSubscriptionOfferingContract._(this.packages);

  final Map<String, Package> packages;

  Package? packageFor(String packageId) => packages[packageId];

  static AndroidSubscriptionOfferingContract? fromPackages(
    Iterable<Package> source,
  ) {
    final packages = source.toList(growable: false);
    final resolved = <String, Package>{};

    for (final plan in SubscriptionPlanDefinition.androidPlans) {
      final candidates = packages
          .where((package) => package.identifier.trim() == plan.packageId)
          .toList(growable: false);
      // Missing or duplicated package identifiers are an invalid whole
      // offering; never expose a partial paywall.
      if (candidates.length != 1 ||
          !plan.matchesAndroidPackage(candidates.single)) {
        return null;
      }
      resolved[plan.packageId] = candidates.single;
    }

    return AndroidSubscriptionOfferingContract._(Map.unmodifiable(resolved));
  }
}

/// Returns an exact iOS package for a known App Store product ID.
///
/// iOS packages do not expose Play base plans. The product allowlist is still
/// exact and intentionally does not inspect titles, descriptions, or periods.
Package? findKnownIosPackage(
  Iterable<Package> packages,
  SubscriptionPlanDefinition plan,
) {
  final candidates = packages
      .where((package) =>
          plan.matchesIosProductId(package.storeProduct.identifier))
      .toList(growable: false);
  if (candidates.length != 1) return null;
  return candidates.single;
}

enum AndroidSubscriptionReplacementMode {
  immediateAndChargeProratedPrice,
  deferred,
  immediateWithoutProration,
}

class AndroidSubscriptionReplacementDecision {
  const AndroidSubscriptionReplacementDecision._({
    required this.target,
    required this.previous,
    required this.mode,
    required this.oldProductIdentifier,
    required this.error,
  });

  final SubscriptionPlanDefinition target;
  final SubscriptionPlanDefinition? previous;
  final AndroidSubscriptionReplacementMode? mode;
  final String? oldProductIdentifier;
  final String? error;

  bool get isAllowed => error == null;
  bool get isReplacement => mode != null;

  static AndroidSubscriptionReplacementDecision newSubscription(
    SubscriptionPlanDefinition target,
  ) {
    return AndroidSubscriptionReplacementDecision._(
      target: target,
      previous: null,
      mode: null,
      oldProductIdentifier: null,
      error: null,
    );
  }
}

/// Computes the only allowed Android replacement modes.
///
/// A missing or unverified Play tuple is an error once the caller indicates
/// that an active subscription exists. The caller must not silently turn that
/// situation into a second new subscription.
AndroidSubscriptionReplacementDecision resolveAndroidReplacement({
  required SubscriptionPlanDefinition target,
  required String? activeStore,
  required String? activeProductId,
  required String? activeBasePlanId,
  required bool activeStateAuthoritative,
  required bool hasActivePaidState,
}) {
  if (!hasActivePaidState) {
    return AndroidSubscriptionReplacementDecision.newSubscription(target);
  }

  if (activeStore != 'play_store' || !activeStateAuthoritative) {
    return AndroidSubscriptionReplacementDecision._(
      target: target,
      previous: null,
      mode: null,
      oldProductIdentifier: null,
      error: 'authoritative Play subscription source is required',
    );
  }

  final previous = SubscriptionPlanDefinition.fromAuthoritativePlayIdentifiers(
    productId: activeProductId,
    basePlanId: activeBasePlanId,
  );
  if (previous == null) {
    return AndroidSubscriptionReplacementDecision._(
      target: target,
      previous: null,
      mode: null,
      oldProductIdentifier: null,
      error: 'active Play product/base plan is not an exact known mapping',
    );
  }

  if (previous.playProductWithBasePlan == target.playProductWithBasePlan) {
    return AndroidSubscriptionReplacementDecision._(
      target: target,
      previous: previous,
      mode: null,
      oldProductIdentifier: previous.playProductId,
      error: 'target is already the active subscription',
    );
  }

  final AndroidSubscriptionReplacementMode mode;
  if (previous.tier == SubscriptionTierHelper.starter &&
      target.tier == SubscriptionTierHelper.essential) {
    mode = AndroidSubscriptionReplacementMode.immediateAndChargeProratedPrice;
  } else if (previous.tier == SubscriptionTierHelper.essential &&
      target.tier == SubscriptionTierHelper.starter) {
    mode = AndroidSubscriptionReplacementMode.deferred;
  } else if (previous.tier == target.tier) {
    mode = AndroidSubscriptionReplacementMode.immediateWithoutProration;
  } else {
    return AndroidSubscriptionReplacementDecision._(
      target: target,
      previous: previous,
      mode: null,
      oldProductIdentifier: previous.playProductId,
      error: 'unsupported subscription replacement',
    );
  }

  return AndroidSubscriptionReplacementDecision._(
    target: target,
    previous: previous,
    mode: mode,
    oldProductIdentifier: previous.playProductId,
    error: null,
  );
}

GoogleProrationMode? googleProrationModeFor(
  AndroidSubscriptionReplacementMode? mode,
) {
  switch (mode) {
    case AndroidSubscriptionReplacementMode.immediateAndChargeProratedPrice:
      return GoogleProrationMode.immediateAndChargeProratedPrice;
    case AndroidSubscriptionReplacementMode.deferred:
      return GoogleProrationMode.deferred;
    case AndroidSubscriptionReplacementMode.immediateWithoutProration:
      return GoogleProrationMode.immediateWithoutProration;
    case null:
      return null;
  }
}

String replacementConfirmationMessage(
  AndroidSubscriptionReplacementMode? mode,
) {
  switch (mode) {
    case AndroidSubscriptionReplacementMode.immediateAndChargeProratedPrice:
      return '升級會立即生效，Google Play 會依剩餘期間計算補差額。';
    case AndroidSubscriptionReplacementMode.deferred:
      return '降級會在目前方案到期、下次續訂時生效。';
    case AndroidSubscriptionReplacementMode.immediateWithoutProration:
      return '同級週期方案會立即切換；新價格會在下次續訂時扣款。';
    case null:
      return '新訂閱會在 Google Play 訂閱頁確認。';
  }
}
