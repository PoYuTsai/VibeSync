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

  // 本月還是今日只看伺服器說的（主審第 1 輪 P2-1）：先看 quotaScope，再看共用額度 payload
  // 的 error，都沒有就當本月；不從剩餘數推（結算競態回的剩餘數是預查時的舊值）。
  test('429 是本月還是今日擋下：先看 quotaScope，再看 error，都沒有就當本月，不看剩餘數', () {
    // 結算競態：舊數字看起來還夠（本月剩 3、這次要 3），quotaScope 說本月。
    expect(
      quotaPayloadIsMonthly({
        'error': '額度不足',
        'quotaScope': 'monthly',
        'monthlyRemaining': 3,
        'quotaNeeded': 3,
      }),
      isTrue,
    );
    expect(
      quotaPayloadIsMonthly(
          {'error': 'Monthly limit exceeded', 'quotaScope': 'daily'}),
      isFalse,
    );
    expect(quotaPayloadIsMonthly({'error': 'Monthly limit exceeded'}), isTrue);
    expect(quotaPayloadIsMonthly({'error': 'Daily limit exceeded'}), isFalse);
    // 沒有 quotaScope 也沒有 Monthly／Daily：不從剩餘數推，當本月。
    expect(
      quotaPayloadIsMonthly(
          {'error': '額度不足', 'monthlyRemaining': 500, 'quotaNeeded': 3}),
      isTrue,
    );
    expect(quotaPayloadIsMonthly({'error': '額度不足'}), isTrue);
  });

  // Onboarding 第 3 步：每個「不夠了」都先講什麼時候恢復，能升級的方案才補升級說法。
  group('額度不足的下一步：先講恢復時間，再看能不能升級', () {
    const free = SubscriptionTierHelper.free;
    const starter = SubscriptionTierHelper.starter;
    const essential = SubscriptionTierHelper.essential;

    test('免費・每日：恢復時間＋預設升級說法', () {
      expect(
        quotaNextStepLine(tier: free, isMonthly: false),
        '每天早上 8 點恢復；也可以升級取得更多額度',
      );
    });

    test('免費・每月：恢復時間＋預設升級說法', () {
      expect(
        quotaNextStepLine(tier: free, isMonthly: true),
        '每月 1 號早上 8 點恢復；也可以升級取得更多額度',
      );
    });

    test('Starter・每日：還能升級，帶呼叫端給的升級說法', () {
      expect(
        quotaNextStepLine(
          tier: starter,
          isMonthly: false,
          upgrade: '升級後每天能用更多',
        ),
        '每天早上 8 點恢復；升級後每天能用更多',
      );
    });

    test('Starter・每月：還能升級，帶呼叫端給的升級說法', () {
      expect(
        quotaNextStepLine(
          tier: starter,
          isMonthly: true,
          upgrade: '也可以升級至 Essential',
        ),
        '每月 1 號早上 8 點恢復；也可以升級至 Essential',
      );
    });

    test('Essential・每日：只講恢復時間，給了升級說法也不加', () {
      expect(
        quotaNextStepLine(
          tier: essential,
          isMonthly: false,
          upgrade: '升級後每天能用更多',
        ),
        kDailyQuotaResetLine,
      );
    });

    test('Essential・每月：只講恢復時間', () {
      expect(
        quotaNextStepLine(tier: essential, isMonthly: true),
        kMonthlyQuotaResetLine,
      );
    });
  });

  test('開場、新話題的額度說明：Essential 只說什麼時候恢復，其他方案先說恢復再說升級', () {
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
        '本月額度不足，$kMonthlyQuotaResetLine；也可以升級取得更多新話題與分析額度。',
      );
      expect(
        quotaShortMessage(tier: tier, isMonthly: false, feature: '開場'),
        '今日額度不足，$kDailyQuotaResetLine；也可以升級取得更多額度。',
      );
    }
  });

  // Onboarding 第 2 步：翻牌照台北中午 12 點換窗（不是一般額度的早上 8 點），中午前
  // 用完也不能說「明天」；伺服器翻牌 429 講同一句。
  test('翻牌用完的說法：先講中午 12 點恢復；Starter 補升級，Essential 不提升級', () {
    expect(kPracticeDrawResetLine, '每天中午 12 點恢復');
    expect(
      practiceDrawUsedUpMessage(SubscriptionTierHelper.starter),
      '今天的翻牌用完了，每天中午 12 點恢復；也可以升級。',
    );
    expect(
      practiceDrawUsedUpMessage(SubscriptionTierHelper.essential),
      '今天的翻牌用完了，每天中午 12 點恢復。',
    );
    expect(
      practiceDrawUsedUpMessage(null),
      practiceDrawUsedUpMessage(SubscriptionTierHelper.free),
    );
    for (final tier in [
      SubscriptionTierHelper.free,
      SubscriptionTierHelper.starter,
      SubscriptionTierHelper.essential,
    ]) {
      final text = practiceDrawUsedUpMessage(tier);
      expect(text, isNot(contains('明天')), reason: tier);
      expect(text, isNot(contains(kDailyQuotaResetLine)), reason: tier);
    }
  });
}
