/// 額度提示（Eric 2026-10-18，審查「讓人看到付費價值的時機」）：只放在顯示的地方
/// （分析鈕下那一行、額度用完的升級卡），數字全部照常數算，不寫死。
/// 一次完整分析＝一般長度（2000 字以內）最多扣的則數，見
/// [MessageCalculator.softCapUnits]。
library;

import '../../../../core/services/message_calculator.dart';
import '../../../subscription/domain/services/subscription_tier_helper.dart';

/// 分析鈕那一行的補充：用完這次之後剩 [remainingAfter] 則，大約只夠一次完整分析、
/// 或一次都不夠時才寫；還夠兩次以上回 null。
String? analysisRemainingHint(int remainingAfter) {
  if (remainingAfter < 0) return null;
  final fullRuns = remainingAfter ~/ MessageCalculator.softCapUnits;
  if (fullRuns >= 2) return null;
  if (fullRuns == 1) return '大約還能完整分析 $fullRuns 次';
  return '剩下的不夠一次完整分析';
}

/// 額度用完時給免費用戶看的 Starter 的量（每日上限照方案表）。
String starterCapacityLine() {
  final daily =
      SubscriptionTierHelper.limitsFor(SubscriptionTierHelper.starter).daily;
  final runs = daily ~/ MessageCalculator.softCapUnits;
  return 'Starter 每天 $daily 則，大約 $runs 次完整分析'
      '（每次 ${MessageCalculator.softCapBandMaxChars} 字以內）';
}
