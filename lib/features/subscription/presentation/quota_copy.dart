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

/// 還有更高的方案可以升級（免費、Starter）；Essential 回 false。
bool canUpgradeQuota(String? tier) =>
    SubscriptionTierHelper.normalizeTier(tier) !=
    SubscriptionTierHelper.essential;

/// 升級能選的方案：Starter 只剩 Essential，不叫他升級到 Starter。
String quotaUpgradeTargets(String? tier) =>
    SubscriptionTierHelper.normalizeTier(tier) == SubscriptionTierHelper.starter
        ? 'Essential'
        : 'Starter 或 Essential';

/// 額度 429 是本月還是今日擋下：伺服器先看本月、再看今天。共用額度 payload 的
/// error 會寫 Monthly／Daily；開場、新話題的額度閘只寫「額度不足」，改看本月剩的
/// 夠不夠這次用；都看不出來就當本月（同分析的 quotaExceptionFrom429）。
bool quotaPayloadIsMonthly(Map<dynamic, dynamic> data) {
  final error = data['error']?.toString().toLowerCase() ?? '';
  if (error.contains('monthly')) return true;
  if (error.contains('daily')) return false;
  final monthlyRemaining = (data['monthlyRemaining'] as num?)?.round();
  final quotaNeeded = (data['quotaNeeded'] as num?)?.round();
  if (monthlyRemaining == null || quotaNeeded == null) return true;
  return monthlyRemaining < quotaNeeded;
}

/// 開場救星、新話題撞到額度時的說明（Eric 2026-10-18）：免費、Starter 照舊說升級
/// 能多用；Essential 只說什麼時候恢復。[feature] 是本月那句點名的功能（「開場」、
/// 「新話題」）。伺服器 429 的 message 不分方案，不拿來顯示。
String quotaShortMessage({
  required String? tier,
  required bool isMonthly,
  required String feature,
}) {
  final canUpgrade = canUpgradeQuota(tier);
  if (isMonthly) {
    return canUpgrade
        ? '本月額度不足，升級方案可取得更多$feature與分析額度。'
        : '本月額度不足，$kMonthlyQuotaResetLine。';
  }
  return canUpgrade
      ? '今日額度不足，$kDailyQuotaResetLine；也可以升級取得更多額度。'
      : '今日額度不足，$kDailyQuotaResetLine。';
}
