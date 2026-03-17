import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';

void main() {
  group('SubscriptionTierHelper.limitsFor', () {
    test('returns expected limits for each tier', () {
      final free = SubscriptionTierHelper.limitsFor(SubscriptionTierHelper.free);
      final starter =
          SubscriptionTierHelper.limitsFor(SubscriptionTierHelper.starter);
      final essential =
          SubscriptionTierHelper.limitsFor(SubscriptionTierHelper.essential);

      expect(free.monthly, AppConstants.freeMonthlyLimit);
      expect(free.daily, AppConstants.freeDailyLimit);
      expect(starter.monthly, AppConstants.starterMonthlyLimit);
      expect(starter.daily, AppConstants.starterDailyLimit);
      expect(essential.monthly, AppConstants.essentialMonthlyLimit);
      expect(essential.daily, AppConstants.essentialDailyLimit);
    });

    test('falls back to free limits for unknown tiers', () {
      final limits = SubscriptionTierHelper.limitsFor('unknown');

      expect(limits.monthly, AppConstants.freeMonthlyLimit);
      expect(limits.daily, AppConstants.freeDailyLimit);
    });
  });

  group('SubscriptionTierHelper.tierFromProductId', () {
    test('infers essential tier from product identifier', () {
      expect(
        SubscriptionTierHelper.tierFromProductId(
          'vibesync_essential_monthly',
        ),
        SubscriptionTierHelper.essential,
      );
    });

    test('infers starter tier from product identifier', () {
      expect(
        SubscriptionTierHelper.tierFromProductId('vibesync_starter_monthly'),
        SubscriptionTierHelper.starter,
      );
    });

    test('returns free when no tier keyword is present', () {
      expect(
        SubscriptionTierHelper.tierFromProductId('some_random_product'),
        SubscriptionTierHelper.free,
      );
      expect(
        SubscriptionTierHelper.tierFromProductId(null),
        SubscriptionTierHelper.free,
      );
    });
  });

  group('SubscriptionTierHelper.tierFromProductIds', () {
    test('prefers essential when multiple purchased products exist', () {
      final tier = SubscriptionTierHelper.tierFromProductIds([
        'vibesync_starter_monthly',
        'vibesync_essential_monthly',
      ]);

      expect(tier, SubscriptionTierHelper.essential);
    });

    test('returns starter when only starter products exist', () {
      final tier = SubscriptionTierHelper.tierFromProductIds([
        'vibesync_starter_monthly',
      ]);

      expect(tier, SubscriptionTierHelper.starter);
    });

    test('returns free when collection has no matching product ids', () {
      final tier = SubscriptionTierHelper.tierFromProductIds([
        'unknown_product',
      ]);

      expect(tier, SubscriptionTierHelper.free);
    });
  });
}
