import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/core/services/storage_service.dart';
import 'package:vibesync/core/services/usage_service.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';

void main() {
  setUpAll(() {
    Hive.init('./.dart_tool/test_hive_usage_subscription_snapshot');
  });

  setUp(() async {
    if (!Hive.isBoxOpen(AppConstants.usageBox)) {
      await Hive.openBox(AppConstants.usageBox);
    }
    await StorageService.usageBox.clear();
    UsageService.debugCurrentUserIdOverride = 'user-paid';
  });

  tearDown(() async {
    UsageService.debugCurrentUserIdOverride = null;
    if (Hive.isBoxOpen(AppConstants.usageBox)) {
      await StorageService.usageBox.clear();
    }
  });

  tearDownAll(() async {
    await Hive.close();
  });

  test('restores last known paid snapshot after transient free cache write',
      () {
    final essentialLimits =
        SubscriptionTierHelper.limitsFor(SubscriptionTierHelper.essential);

    UsageService.syncSubscriptionSnapshot(
      tier: SubscriptionTierHelper.essential,
      monthlyLimit: essentialLimits.monthly,
      dailyLimit: essentialLimits.daily,
      paidExpiresAt: DateTime.utc(2099, 1, 1),
    );
    UsageService.syncSubscriptionSnapshot(
      tier: SubscriptionTierHelper.free,
      monthlyLimit: AppConstants.freeMonthlyLimit,
      dailyLimit: AppConstants.freeDailyLimit,
    );

    final usage = UsageService().getLocalUsage();

    expect(usage.tier, SubscriptionTierHelper.essential);
    expect(usage.monthlyLimit, essentialLimits.monthly);
    expect(usage.dailyLimit, essentialLimits.daily);
  });

  test('does not restore paid snapshot after account changes', () {
    final starterLimits =
        SubscriptionTierHelper.limitsFor(SubscriptionTierHelper.starter);

    UsageService.syncSubscriptionSnapshot(
      tier: SubscriptionTierHelper.starter,
      monthlyLimit: starterLimits.monthly,
      dailyLimit: starterLimits.daily,
      paidExpiresAt: DateTime.utc(2099, 1, 1),
    );
    UsageService.debugCurrentUserIdOverride = 'user-other';

    final usage = UsageService().getLocalUsage();

    expect(usage.tier, SubscriptionTierHelper.free);
    expect(usage.monthlyLimit, AppConstants.freeMonthlyLimit);
    expect(usage.dailyLimit, AppConstants.freeDailyLimit);
  });

  test('does not restore expired paid snapshot', () {
    final starterLimits =
        SubscriptionTierHelper.limitsFor(SubscriptionTierHelper.starter);

    UsageService.syncSubscriptionSnapshot(
      tier: SubscriptionTierHelper.starter,
      monthlyLimit: starterLimits.monthly,
      dailyLimit: starterLimits.daily,
      paidExpiresAt: DateTime.utc(2000, 1, 1),
    );
    UsageService.syncSubscriptionSnapshot(
      tier: SubscriptionTierHelper.free,
      monthlyLimit: AppConstants.freeMonthlyLimit,
      dailyLimit: AppConstants.freeDailyLimit,
    );

    final usage = UsageService().getLocalUsage();

    expect(usage.tier, SubscriptionTierHelper.free);
    expect(usage.monthlyLimit, AppConstants.freeMonthlyLimit);
    expect(usage.dailyLimit, AppConstants.freeDailyLimit);
  });

  test('does not restore paid snapshot when expiration is unknown', () {
    final essentialLimits =
        SubscriptionTierHelper.limitsFor(SubscriptionTierHelper.essential);

    UsageService.syncSubscriptionSnapshot(
      tier: SubscriptionTierHelper.essential,
      monthlyLimit: essentialLimits.monthly,
      dailyLimit: essentialLimits.daily,
    );
    UsageService.syncSubscriptionSnapshot(
      tier: SubscriptionTierHelper.free,
      monthlyLimit: AppConstants.freeMonthlyLimit,
      dailyLimit: AppConstants.freeDailyLimit,
    );

    final usage = UsageService().getLocalUsage();

    expect(usage.tier, SubscriptionTierHelper.free);
    expect(usage.monthlyLimit, AppConstants.freeMonthlyLimit);
    expect(usage.dailyLimit, AppConstants.freeDailyLimit);
  });

  test('keeps valid paid snapshot when a later paid sync omits expiration', () {
    final essentialLimits =
        SubscriptionTierHelper.limitsFor(SubscriptionTierHelper.essential);

    UsageService.syncSubscriptionSnapshot(
      tier: SubscriptionTierHelper.essential,
      monthlyLimit: essentialLimits.monthly,
      dailyLimit: essentialLimits.daily,
      paidExpiresAt: DateTime.utc(2099, 1, 1),
    );
    UsageService.syncSubscriptionSnapshot(
      tier: SubscriptionTierHelper.essential,
      monthlyLimit: essentialLimits.monthly,
      dailyLimit: essentialLimits.daily,
    );
    UsageService.syncSubscriptionSnapshot(
      tier: SubscriptionTierHelper.free,
      monthlyLimit: AppConstants.freeMonthlyLimit,
      dailyLimit: AppConstants.freeDailyLimit,
    );

    final usage = UsageService().getLocalUsage();

    expect(usage.tier, SubscriptionTierHelper.essential);
    expect(usage.monthlyLimit, essentialLimits.monthly);
    expect(usage.dailyLimit, essentialLimits.daily);
  });
}
