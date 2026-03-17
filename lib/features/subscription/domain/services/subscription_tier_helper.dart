import '../../../../core/constants/app_constants.dart';

class SubscriptionTierLimits {
  final int monthly;
  final int daily;

  const SubscriptionTierLimits({
    required this.monthly,
    required this.daily,
  });
}

class SubscriptionTierHelper {
  static const free = 'free';
  static const starter = 'starter';
  static const essential = 'essential';

  static const _freeLimits = SubscriptionTierLimits(
    monthly: AppConstants.freeMonthlyLimit,
    daily: AppConstants.freeDailyLimit,
  );
  static const _starterLimits = SubscriptionTierLimits(
    monthly: AppConstants.starterMonthlyLimit,
    daily: AppConstants.starterDailyLimit,
  );
  static const _essentialLimits = SubscriptionTierLimits(
    monthly: AppConstants.essentialMonthlyLimit,
    daily: AppConstants.essentialDailyLimit,
  );

  static String normalizeTier(String? tier) {
    switch (tier) {
      case starter:
      case essential:
        return tier!;
      case free:
      default:
        return free;
    }
  }

  static SubscriptionTierLimits limitsFor(String? tier) {
    switch (normalizeTier(tier)) {
      case starter:
        return _starterLimits;
      case essential:
        return _essentialLimits;
      case free:
      default:
        return _freeLimits;
    }
  }

  static String tierFromProductId(String? productId) {
    if (productId == null) {
      return free;
    }

    final normalized = productId.toLowerCase();
    if (normalized.contains(essential)) {
      return essential;
    }
    if (normalized.contains(starter)) {
      return starter;
    }
    return free;
  }

  static String tierFromProductIds(Iterable<String> productIds) {
    for (final productId in productIds) {
      if (tierFromProductId(productId) == essential) {
        return essential;
      }
    }

    for (final productId in productIds) {
      if (tierFromProductId(productId) == starter) {
        return starter;
      }
    }

    return free;
  }
}
