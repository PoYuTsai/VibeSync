import '../domain/services/subscription_tier_helper.dart';

/// 付費頁從哪裡打開（Eric 2026-10-18）：大標跟著入口換，方案、價格、比較表都一樣。
/// 用 go_router 的 extra 帶過去；沒帶的入口都是一般入口，標題照舊。
enum PaywallEntry {
  /// 一般入口：沿用定位句（2026-08-18 拍板）。
  general,

  /// 分析結果裡鎖住的卡（免費方案只看得到前幾張）。
  lockedCards,

  /// 今天的額度用完了（剩 0 則）。
  dailyQuotaUsedUp,

  /// 今天還有額度，但不夠這次用。
  dailyQuotaShort,

  /// 這個月的額度用完了（剩 0 則）。
  monthlyQuotaUsedUp,

  /// 這個月還有額度，但不夠這次用。
  monthlyQuotaShort;

  /// 額度不夠時的入口（主審 r1 P2-3）：剩 0 則才算用完；還有剩、或不知道剩幾則，
  /// 只說不夠這次用。
  static PaywallEntry forQuota({required bool isMonthly, int? remaining}) {
    final usedUp = remaining != null && remaining <= 0;
    if (isMonthly) return usedUp ? monthlyQuotaUsedUp : monthlyQuotaShort;
    return usedUp ? dailyQuotaUsedUp : dailyQuotaShort;
  }

  /// 路由的 extra 不是入口（沒帶、舊的呼叫端）就當一般入口。
  static PaywallEntry fromRouteExtra(Object? extra) =>
      extra is PaywallEntry ? extra : PaywallEntry.general;

  /// 付費頁最上面的大標；[tier] 是目前的方案。額度不夠時只說做得到的下一步（主審
  /// r1 P2-3）：免費、Starter 升級後額度更多；Essential 已經是最高方案，不承諾升級，
  /// 只說什麼時候恢復（伺服器照 UTC 換日、換月重算，台灣是早上 8 點，見
  /// `_shared/quota.ts`）。換繳費週期不會補額度，不提。
  String headlineFor(String? tier) {
    final canUpgrade = SubscriptionTierHelper.normalizeTier(tier) !=
        SubscriptionTierHelper.essential;
    final dailyNext = canUpgrade ? '升級後每天能用更多' : '每天早上 8 點恢復';
    final monthlyNext = canUpgrade ? '升級後每月能用更多' : '每月 1 號早上 8 點恢復';
    return switch (this) {
      PaywallEntry.general => '完整教練帶路\n把她約出來更有把握',
      PaywallEntry.lockedCards => '每一輪的回覆卡\n全部看得到',
      PaywallEntry.dailyQuotaUsedUp => '今天的額度用完了\n$dailyNext',
      PaywallEntry.dailyQuotaShort => '今天的額度不夠這次用\n$dailyNext',
      PaywallEntry.monthlyQuotaUsedUp => '這個月的額度用完了\n$monthlyNext',
      PaywallEntry.monthlyQuotaShort => '這個月的額度不夠這次用\n$monthlyNext',
    };
  }
}
