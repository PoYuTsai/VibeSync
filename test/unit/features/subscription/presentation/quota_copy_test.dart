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

  // 開場救星、新話題的 429（Eric 2026-10-18）：共用額度 payload 的 error 寫明
  // Monthly／Daily；額度閘只寫「額度不足」，改看本月剩的夠不夠這次用。
  test('429 是本月還是今日擋下：先看 error，再看本月剩的夠不夠，看不出來當本月', () {
    expect(quotaPayloadIsMonthly({'error': 'Monthly limit exceeded'}), isTrue);
    expect(
      quotaPayloadIsMonthly({
        'error': 'Daily limit exceeded',
        'monthlyRemaining': 0,
        'quotaNeeded': 3,
      }),
      isFalse,
    );
    expect(
      quotaPayloadIsMonthly(
          {'error': '額度不足', 'monthlyRemaining': 2, 'quotaNeeded': 3}),
      isTrue,
    );
    expect(
      quotaPayloadIsMonthly(
          {'error': '額度不足', 'monthlyRemaining': 3, 'quotaNeeded': 3}),
      isFalse,
    );
    expect(quotaPayloadIsMonthly({'error': '額度不足'}), isTrue);
  });

  test('開場、新話題的額度說明：Essential 只說什麼時候恢復，其他方案照舊說升級', () {
    for (final (isMonthly, resetLine, otherResetLine) in [
      (false, kDailyQuotaResetLine, kMonthlyQuotaResetLine),
      (true, kMonthlyQuotaResetLine, kDailyQuotaResetLine),
    ]) {
      final essential = quotaShortMessage(
        tier: SubscriptionTierHelper.essential,
        isMonthly: isMonthly,
        feature: '開場',
      );
      expect(essential, contains(resetLine));
      expect(essential, isNot(contains(otherResetLine)));
      expect(essential, isNot(contains('升級')));
    }
    for (final tier in [
      SubscriptionTierHelper.free,
      SubscriptionTierHelper.starter,
      null,
    ]) {
      expect(
        quotaShortMessage(tier: tier, isMonthly: true, feature: '新話題'),
        '本月額度不足，升級方案可取得更多新話題與分析額度。',
      );
      expect(
        quotaShortMessage(tier: tier, isMonthly: false, feature: '開場'),
        '今日額度不足，$kDailyQuotaResetLine；也可以升級取得更多額度。',
      );
    }
  });
}
