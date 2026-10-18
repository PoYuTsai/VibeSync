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

    // 免費額度要跟伺服器的額度表同一組：10/18 放寬成每月 50、每日 20，Bruce 在 PR #97
    // 決定改回 30／15，Eric 2026-10-19 照他決定。
    test('免費每月 30 則、每日 15 則（Eric 2026-10-19）', () {
      expect(AppConstants.freeMonthlyLimit, 30);
      expect(AppConstants.freeDailyLimit, 15);
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
          'vibesync_essential_monthly_v2',
        ),
        SubscriptionTierHelper.essential,
      );
    });

    test('infers essential tier from quarterly product identifier', () {
      expect(
        SubscriptionTierHelper.tierFromProductId(
          'vibesync_essential_quarterly_v2',
        ),
        SubscriptionTierHelper.essential,
      );
    });

    test('infers starter tier from product identifier', () {
      expect(
        SubscriptionTierHelper.tierFromProductId('vibesync_starter_monthly_v2'),
        SubscriptionTierHelper.starter,
      );
    });

    test('infers starter tier from quarterly product identifier', () {
      expect(
        SubscriptionTierHelper.tierFromProductId(
          'vibesync_starter_quarterly_v2',
        ),
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
        'vibesync_starter_monthly_v2',
        'vibesync_essential_monthly_v2',
      ]);

      expect(tier, SubscriptionTierHelper.essential);
    });

    test('returns starter when only starter products exist', () {
      final tier = SubscriptionTierHelper.tierFromProductIds([
        'vibesync_starter_monthly_v2',
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

  group('SubscriptionTierHelper rank helpers', () {
    test('rankOf orders free starter essential', () {
      expect(SubscriptionTierHelper.rankOf(SubscriptionTierHelper.free), 0);
      expect(SubscriptionTierHelper.rankOf(SubscriptionTierHelper.starter), 1);
      expect(
        SubscriptionTierHelper.rankOf(SubscriptionTierHelper.essential),
        2,
      );
    });

    test('isUpgrade returns true only when moving to higher tier', () {
      expect(
        SubscriptionTierHelper.isUpgrade(
          fromTier: SubscriptionTierHelper.free,
          toTier: SubscriptionTierHelper.starter,
        ),
        isTrue,
      );
      expect(
        SubscriptionTierHelper.isUpgrade(
          fromTier: SubscriptionTierHelper.starter,
          toTier: SubscriptionTierHelper.essential,
        ),
        isTrue,
      );
      expect(
        SubscriptionTierHelper.isUpgrade(
          fromTier: SubscriptionTierHelper.essential,
          toTier: SubscriptionTierHelper.starter,
        ),
        isFalse,
      );
    });

    test('displayName 給用戶看的方案名，未知或空值當 Free', () {
      expect(SubscriptionTierHelper.displayName('free'), 'Free');
      expect(SubscriptionTierHelper.displayName('starter'), 'Starter');
      expect(SubscriptionTierHelper.displayName('essential'), 'Essential');
      expect(SubscriptionTierHelper.displayName(null), 'Free');
      expect(SubscriptionTierHelper.displayName('legacy_tier'), 'Free');
    });

    test('isDowngrade returns true only when moving to lower tier', () {
      expect(
        SubscriptionTierHelper.isDowngrade(
          fromTier: SubscriptionTierHelper.essential,
          toTier: SubscriptionTierHelper.starter,
        ),
        isTrue,
      );
      expect(
        SubscriptionTierHelper.isDowngrade(
          fromTier: SubscriptionTierHelper.starter,
          toTier: SubscriptionTierHelper.free,
        ),
        isTrue,
      );
      expect(
        SubscriptionTierHelper.isDowngrade(
          fromTier: SubscriptionTierHelper.starter,
          toTier: SubscriptionTierHelper.essential,
        ),
        isFalse,
      );
    });
  });
}
