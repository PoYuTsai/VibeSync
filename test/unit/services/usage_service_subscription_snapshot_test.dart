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

  test('批 B 訪客：本地快照跨日/月不歸零（總量制鏡像）', () {
    UsageService.debugIsGuestOverride = true;
    addTearDown(() => UsageService.debugIsGuestOverride = null);

    final box = StorageService.usageBox;
    box.put('monthly_used', 3);
    box.put('daily_used', 3);
    // 過期的 reset 時戳：一般帳號會被歸零，訪客必須保留。
    box.put('monthly_reset_at', DateTime(2020, 1, 1).toIso8601String());
    box.put('daily_reset_at', DateTime(2020, 1, 2).toIso8601String());

    final usage = UsageService().getLocalUsage();

    expect(usage.monthlyUsed, 3);
    expect(usage.dailyUsed, 3);
    expect(box.get('monthly_used'), 3);
    expect(box.get('daily_used'), 3);
  });

  test('批 B 回歸鎖：非訪客過期時戳照常歸零', () {
    UsageService.debugIsGuestOverride = false;
    addTearDown(() => UsageService.debugIsGuestOverride = null);

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
