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

  test('存著的免費上限跟現在的方案表不一樣：照現在的方案表，已用量照舊', () {
    // 方案還在載入時，分析確認框用的是這份本機快照，上限一律照現在的方案表重算（例：10/18
    // 的建置存過 50／20，Eric 2026-10-19 改回 30／15）。存的上限故意跟方案表不一樣。
    // 先讀一次，讓今日與本月的重置時間就位。
    UsageService().getLocalUsage();
    UsageService.syncSubscriptionSnapshot(
      tier: SubscriptionTierHelper.free,
      monthlyLimit: AppConstants.freeMonthlyLimit + 20,
      dailyLimit: AppConstants.freeDailyLimit + 5,
      monthlyUsed: 10,
      dailyUsed: 4,
    );

    final usage = UsageService().getLocalUsage();

    expect(usage.tier, SubscriptionTierHelper.free);
    expect(usage.monthlyLimit, AppConstants.freeMonthlyLimit);
    expect(usage.dailyLimit, AppConstants.freeDailyLimit);
    expect(usage.monthlyUsed, 10);
    expect(usage.dailyUsed, 4);
    expect(usage.monthlyRemaining, AppConstants.freeMonthlyLimit - 10);
    expect(usage.dailyRemaining, AppConstants.freeDailyLimit - 4);
  });

  test('照較高的舊上限用得比現在的免費上限多：剩 0 則、不是負數，也不能再扣', () {
    UsageService().getLocalUsage();
    UsageService.syncSubscriptionSnapshot(
      tier: SubscriptionTierHelper.free,
      monthlyLimit: AppConstants.freeMonthlyLimit + 20,
      dailyLimit: AppConstants.freeDailyLimit + 5,
      monthlyUsed: AppConstants.freeMonthlyLimit + 5,
      dailyUsed: AppConstants.freeDailyLimit + 2,
    );

    final usage = UsageService().getLocalUsage();

    expect(usage.monthlyLimit, AppConstants.freeMonthlyLimit);
    expect(usage.dailyLimit, AppConstants.freeDailyLimit);
    expect(usage.monthlyRemaining, 0);
    expect(usage.dailyRemaining, 0);
    expect(usage.canAnalyze, isFalse);
    expect(usage.canAfford(1), isFalse);
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

  test('過期時戳照常歸零', () {
    final box = StorageService.usageBox;
    box.put('monthly_used', 7);
    box.put('daily_used', 5);
    box.put('monthly_reset_at', DateTime(2020, 1, 1).toIso8601String());
    box.put('daily_reset_at', DateTime(2020, 1, 2).toIso8601String());

    final usage = UsageService().getLocalUsage();

    expect(usage.monthlyUsed, 0);
    expect(usage.dailyUsed, 0);
  });
}
