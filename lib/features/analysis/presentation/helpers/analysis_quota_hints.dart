/// 額度提示（Eric 2026-10-18，審查「讓人看到付費價值的時機」）：只放在顯示的地方
/// （分析鈕下那一行、額度用完的升級卡），數字全部照常數算，不寫死。
/// 一般長度（2000 字以內）的分析最多扣 [MessageCalculator.softCapUnits] 則，短的片段
/// 扣得少、最短只扣 1 則，所以只說保證做得到的「至少」（主審 r1 P2-2）。
library;

import '../../../../core/services/message_calculator.dart';
import '../../../subscription/domain/services/subscription_tier_helper.dart';
import '../../../subscription/presentation/quota_copy.dart';

/// 分析鈕那一行的補充：用完這次之後剩 [remainingAfter] 則、不到兩次一般長度分析時才寫；
/// 還夠兩次以上、或剩 0（那一行已經寫「剩 0 則」）回 null。
String? analysisRemainingHint(int remainingAfter) {
  if (remainingAfter <= 0) return null;
  final guaranteed = remainingAfter ~/ MessageCalculator.softCapUnits;
  if (guaranteed >= 2) return null;
  if (guaranteed == 1) {
    return '至少還能分析 $guaranteed 次'
        '（${MessageCalculator.softCapBandMaxChars} 字以內）';
  }
  return '短的片段還能分析，長一點的可能不夠';
}

/// 額度用完時給免費用戶看的 Starter 的量（每日上限照方案表；每次照一般長度的最高
/// 扣費算，所以是「至少」）。
String starterCapacityLine() {
  final daily =
      SubscriptionTierHelper.limitsFor(SubscriptionTierHelper.starter).daily;
  final runs = daily ~/ MessageCalculator.softCapUnits;
  return 'Starter 每天 $daily 則，至少能分析 $runs 次'
      '（每次 ${MessageCalculator.softCapBandMaxChars} 字以內）';
}

/// 草稿潤飾、回覆微調撞到額度時的說明（Eric 2026-10-18）：[tier] 是目前方案。先說
/// 什麼時候恢復（Onboarding 第 3 步：本月那句以前只叫人升級），免費、Starter 再說
/// 也可以升級；Essential 已經是最高方案，只說什麼時候恢復（跟付費頁大標同一句）。
/// [used]／[limit] 是伺服器 429 帶回來的那個額度。
String polishQuotaMessage({
  required String? tier,
  required bool isMonthly,
  required int used,
  required int limit,
}) {
  final plan = SubscriptionTierHelper.displayName(tier);
  final scope = isMonthly ? '本月' : '今日';
  final next = quotaNextStepLine(tier: tier, isMonthly: isMonthly);
  return '目前方案 $plan：$scope額度已用完 ($used/$limit)，$next。';
}
