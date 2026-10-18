// 額度不夠時各處共用的說法（Eric 2026-10-18）：Essential 不承諾升級；Starter 只會被
// 叫去升級 Essential；付費頁大標的恢復時間跟額度卡、確認框是同一句。
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';
import 'package:vibesync/features/subscription/presentation/paywall_entry.dart';
import 'package:vibesync/features/subscription/presentation/quota_copy.dart';

void main() {
  test('只有 Essential 不能再升級；不認得的方案代碼當免費', () {
    expect(canUpgradeQuota(SubscriptionTierHelper.free), isTrue);
    expect(canUpgradeQuota(SubscriptionTierHelper.starter), isTrue);
    expect(canUpgradeQuota(SubscriptionTierHelper.essential), isFalse);
    expect(canUpgradeQuota(null), isTrue);
  });

  test('升級能選的方案：Starter 只剩 Essential', () {
    expect(
      quotaUpgradeTargets(SubscriptionTierHelper.free),
      'Starter 或 Essential',
    );
    expect(quotaUpgradeTargets(SubscriptionTierHelper.starter), 'Essential');
  });

  test('Essential 的付費頁額度大標，恢復時間就是這兩句', () {
    const essential = SubscriptionTierHelper.essential;
    expect(
      PaywallEntry.dailyQuotaUsedUp.headlineFor(essential),
      endsWith(kDailyQuotaResetLine),
    );
    expect(
      PaywallEntry.monthlyQuotaShort.headlineFor(essential),
      endsWith(kMonthlyQuotaResetLine),
    );
  });
}
