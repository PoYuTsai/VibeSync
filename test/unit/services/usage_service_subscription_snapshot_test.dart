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

  test('舊版 App 存的免費上限 30／15：更新後照現在的方案表 50／20，已用量照舊', () {
    // 免費 30／15 → 50／20（Eric 2026-10-18）：方案還在載入時，分析確認框用的是這份本機
    // 快照；存著的舊上限不能把還有額度的人擋掉。先讀一次，讓今日與本月的重置時間就位。
    UsageService().getLocalUsage();
    UsageService.syncSubscriptionSnapshot(
      tier: SubscriptionTierHelper.free,
      monthlyLimit: 30,
      dailyLimit: 15,
      monthlyUsed: 30,
      dailyUsed: 15,
    );

    final usage = UsageService().getLocalUsage();

    expect(usage.tier, SubscriptionTierHelper.free);
    expect(usage.monthlyLimit, 50);
    expect(usage.dailyLimit, 20);
    expect(usage.monthlyUsed, 30);
    expect(usage.dailyUsed, 15);
    expect(usage.monthlyRemaining, 20);
    expect(usage.dailyRemaining, 5);
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
