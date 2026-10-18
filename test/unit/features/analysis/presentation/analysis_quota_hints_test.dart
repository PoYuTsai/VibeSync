import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/services/message_calculator.dart';
import 'package:vibesync/features/analysis/presentation/helpers/analysis_quota_hints.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';

void main() {
  // 一次完整分析＝一般長度（2000 字以內）最多扣的則數。數字全部照常數算，計費規則
  // 或方案額度改了也不用改測試（Eric 2026-10-18）。
  const full = MessageCalculator.softCapUnits;

  group('分析鈕那一行的補充：用完這次之後大約只剩一次完整分析或更少才寫', () {
    test('還夠兩次以上：不寫', () {
      expect(analysisRemainingHint(full * 2), isNull);
      expect(analysisRemainingHint(full * 5), isNull);
    });

    test('一次到兩次之間：大約還能完整分析 1 次', () {
      expect(analysisRemainingHint(full * 2 - 1), '大約還能完整分析 1 次');
      expect(analysisRemainingHint(full), '大約還能完整分析 1 次');
    });

    test('不到一次：直接說不夠', () {
      expect(analysisRemainingHint(full - 1), '剩下的不夠一次完整分析');
      expect(analysisRemainingHint(0), '剩下的不夠一次完整分析');
    });

    test('負數（不該發生）：不寫', () {
      expect(analysisRemainingHint(-1), isNull);
    });
  });

  test('額度用完：Starter 每天幾則、大約幾次完整分析，照方案表與計費規則算', () {
    final daily =
        SubscriptionTierHelper.limitsFor(SubscriptionTierHelper.starter).daily;
    expect(
      starterCapacityLine(),
      'Starter 每天 $daily 則，大約 ${daily ~/ full} 次完整分析'
      '（每次 ${MessageCalculator.softCapBandMaxChars} 字以內）',
    );
  });
}
