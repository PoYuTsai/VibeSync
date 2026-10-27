/// 額度不夠時各處共用的說法（Eric 2026-10-18）：付費頁大標、分析的額度卡、分析前
/// 確認框、潤飾與微調的提示，還有開場救星、新話題、教練都從這裡拿，免得 Essential
/// 在哪一處又被叫去升級。
/// Essential 已經是最高方案，不承諾升級，只說什麼時候恢復。伺服器照 UTC 換日、換月
/// 重算額度（`_shared/quota.ts` 的 sameUtcDay／sameUtcMonth），台灣是早上 8 點。
library;

import '../domain/services/subscription_tier_helper.dart';

/// 每日額度什麼時候恢復。
const kDailyQuotaResetLine = '每天早上 8 點恢復';

/// 每月額度什麼時候恢復。
const kMonthlyQuotaResetLine = '每月 1 號早上 8 點恢復';

/// 練習室翻牌什麼時候恢復：翻牌照台北中午 12 點換窗（`practice-chat/draw_decision.ts`），
/// 跟一般額度的早上 8 點不同；中午前用完也不能說「明天」。
const kPracticeDrawResetLine = '每天中午 12 點恢復';

/// 付費方案今天的翻牌用完了（每日免費翻牌用完、加抽又不夠額度）時的說明（Onboarding
/// 第 2 步）：先講什麼時候恢復；Starter 還能升級就補一句，Essential 只講恢復時間。
/// 伺服器翻牌 429 的訊息（`practice-chat/draw_handler.ts` 的
/// drawQuotaExceededMessage）講同一句。
String practiceDrawUsedUpMessage(String? tier) => canUpgradeQuota(tier)
    ? '今天的翻牌用完了，$kPracticeDrawResetLine；也可以升級。'
    : '今天的翻牌用完了，$kPracticeDrawResetLine。';

/// 還有更高的方案可以升級（免費、Starter）；Essential 回 false。
bool canUpgradeQuota(String? tier) =>
    SubscriptionTierHelper.normalizeTier(tier) !=
    SubscriptionTierHelper.essential;

/// 額度不足時的下一步（Onboarding 第 3 步）：一律先講恢復時間；可升級的方案（免費、
/// Starter）再補升級說法 [upgrade]（各處原本那句），Essential 只講恢復時間。
/// 回傳不含句尾標點，由呼叫端接。
String quotaNextStepLine({
  required String? tier,
  required bool isMonthly,
  String upgrade = '也可以升級取得更多額度',
}) {
  final reset = isMonthly ? kMonthlyQuotaResetLine : kDailyQuotaResetLine;
  return canUpgradeQuota(tier) ? '$reset；$upgrade' : reset;
}

/// 升級能選的方案：Starter 只剩 Essential，不叫他升級到 Starter。
String quotaUpgradeTargets(String? tier) =>
    SubscriptionTierHelper.normalizeTier(tier) == SubscriptionTierHelper.starter
        ? 'Essential'
        : 'Starter 或 Essential';

/// 額度 429 是本月還是今日擋下，只看伺服器說的（主審第 1 輪 P2-1）：先看
/// quotaScope（開場、新話題的額度 429 都帶），再看共用額度 payload 的 error
/// （Monthly／Daily limit exceeded）；都沒有就當本月（同分析的
/// quotaExceptionFrom429）。不從剩餘數推：結算競態回的剩餘數是預查時的舊值。
bool quotaPayloadIsMonthly(Map<dynamic, dynamic> data) {
  final scope = data['quotaScope'];
  if (scope == 'monthly') return true;
  if (scope == 'daily') return false;
  final error = data['error']?.toString().toLowerCase() ?? '';
  if (error.contains('monthly')) return true;
  if (error.contains('daily')) return false;
  return true;
}

/// 開場救星、新話題、練習對話撞到額度時的說明（Eric 2026-10-18；練習對話是 Onboarding
/// 第 3 步補）：先說什麼時候恢復，免費、Starter 再說升級能多用（Onboarding 第 3 步：
/// 本月那句以前只叫人升級）；Essential 只說什麼時候恢復。[feature] 是本月那句點名的
/// 功能（「開場」、「新話題」、「練習」）。伺服器 429 的 message 不分方案，不拿來顯示。
String quotaShortMessage({
  required String? tier,
  required bool isMonthly,
  required String feature,
}) {
  final next = quotaNextStepLine(
    tier: tier,
    isMonthly: isMonthly,
    upgrade: isMonthly ? '也可以升級取得更多$feature與分析額度' : '也可以升級取得更多額度',
  );
  return '${isMonthly ? '本月' : '今日'}額度不足，$next。';
}
