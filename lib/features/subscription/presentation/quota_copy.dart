/// 額度不夠時各處共用的說法（Eric 2026-10-18）：付費頁大標、分析的額度卡、分析前
/// 確認框、潤飾與微調的提示都從這裡拿，免得 Essential 在哪一處又被叫去升級。
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
