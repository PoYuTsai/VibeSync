import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/services/message_calculator.dart';
import 'package:vibesync/features/analysis/domain/errors/analysis_exceptions.dart';
import 'package:vibesync/features/analysis/presentation/helpers/analysis_quota_hints.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';
import 'package:vibesync/features/subscription/presentation/quota_copy.dart';

void main() {
  // 一般長度（2000 字以內）的分析最多扣 MessageCalculator.softCapUnits 則；短的片段
  // 扣得少，最短只扣 1 則。所以只能保證「至少」幾次（主審 r1 P2-2）。數字全部照常數
  // 算，計費規則或方案額度改了也不用改測試。
  const full = MessageCalculator.softCapUnits;
  const maxChars = MessageCalculator.softCapBandMaxChars;

  test('前提：一般長度最多扣 full 則，最短的片段只扣 1 則', () {
    expect(MessageCalculator.bandForBillableChars(maxChars).units, full);
    expect(MessageCalculator.bandForBillableChars(1).units, 1);
  });

  group('分析鈕那一行的補充：只說保證做得到的', () {
    test('還夠兩次以上：不寫', () {
      expect(analysisRemainingHint(full * 2), isNull);
      expect(analysisRemainingHint(full * 5), isNull);
    });

    test('夠一次一般長度：至少還能分析 1 次（2000 字以內）', () {
      expect(analysisRemainingHint(full * 2 - 1), '至少還能分析 1 次（$maxChars 字以內）');
      expect(analysisRemainingHint(full), '至少還能分析 1 次（$maxChars 字以內）');
    });

    test('不到一次一般長度：短的片段還能分析，長一點的可能不夠', () {
      expect(analysisRemainingHint(full - 1), '短的片段還能分析，長一點的可能不夠');
      expect(analysisRemainingHint(1), '短的片段還能分析，長一點的可能不夠');
    });

    test('剩 0（那一行已經寫「剩 0 則」）或負數：不寫', () {
      expect(analysisRemainingHint(0), isNull);
      expect(analysisRemainingHint(-1), isNull);
    });
  });

  test('額度用完：Starter 每天幾則、至少能分析幾次，照方案表與計費規則算', () {
    final daily =
        SubscriptionTierHelper.limitsFor(SubscriptionTierHelper.starter).daily;
    expect(
      starterCapacityLine(),
      'Starter 每天 $daily 則，至少能分析 ${daily ~/ full} 次（每次 $maxChars 字以內）',
    );
  });

  group('潤飾、微調撞到額度的說明：照目前方案（Eric 2026-10-18）', () {
    String message(String? tier, {required bool isMonthly}) =>
        polishQuotaMessage(tier: tier, isMonthly: isMonthly, used: 9, limit: 9);

    // Onboarding 第 3 步：每月那句以前只叫人升級，現在跟每天一樣先講恢復時間。
    test('免費、Starter：每天、每月都先說恢復時間，再說也可以升級', () {
      expect(
        message(SubscriptionTierHelper.free, isMonthly: false),
        '目前方案 Free：今日額度已用完 (9/9)，每天早上 8 點恢復；也可以升級取得更多額度。',
      );
      expect(
        message(SubscriptionTierHelper.free, isMonthly: true),
        '目前方案 Free：本月額度已用完 (9/9)，每月 1 號早上 8 點恢復；也可以升級取得更多額度。',
      );
      expect(
        message(SubscriptionTierHelper.starter, isMonthly: true),
        '目前方案 Starter：本月額度已用完 (9/9)，每月 1 號早上 8 點恢復；也可以升級取得更多額度。',
      );
    });

    test('Essential：不叫他升級，只說什麼時候恢復', () {
      final daily = message(SubscriptionTierHelper.essential, isMonthly: false);
      final monthly =
          message(SubscriptionTierHelper.essential, isMonthly: true);
      expect(daily, '目前方案 Essential：今日額度已用完 (9/9)，每天早上 8 點恢復。');
      expect(monthly, '目前方案 Essential：本月額度已用完 (9/9)，每月 1 號早上 8 點恢復。');
      expect(daily, isNot(contains('升級')));
      expect(monthly, isNot(contains('升級')));
    });

    test('不認得的方案代碼當免費（跟方案名一樣）', () {
      expect(
        message(null, isMonthly: true),
        message(SubscriptionTierHelper.free, isMonthly: true),
      );
    });
  });

  // Onboarding 第 3 步：例外類別拿不到目前方案，只講恢復時間（台灣早上 8 點，不說
  // 「明天」），升級交給接著打開的付費頁或錯誤卡的提示。
  test('分析額度例外的訊息：只講恢復時間，不提升級、不說明天', () {
    final daily = DailyLimitExceededException(dailyLimit: 15, used: 15);
    final monthly = MonthlyLimitExceededException(monthlyLimit: 30, used: 30);
    expect(daily.message, '今日額度已用完，$kDailyQuotaResetLine。');
    expect(monthly.message, '本月額度已用完，$kMonthlyQuotaResetLine。');
    for (final text in [daily.message, monthly.message]) {
      expect(text, isNot(contains('升級')));
      expect(text, isNot(contains('明天')));
    }
  });
}
