import 'quota_copy.dart';

/// 從額度入口打開時，順便帶上開頁畫面的顯示方案（主審第 2 輪 P2-1）：大標照訂閱方案
/// 跟這個提示取高，跟畫面上的額度說明同一個方案。只有開場救星、新話題帶；其他入口照舊
/// 只傳 [PaywallEntry]。
class PaywallRequest {
  const PaywallRequest(this.entry, {this.tierHint});

  final PaywallEntry entry;
  final String? tierHint;
}

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

  /// 路由的 extra 不是入口（沒帶、舊的呼叫端）就當一般入口；[PaywallRequest] 取
  /// 裡面的入口。
  static PaywallEntry fromRouteExtra(Object? extra) => extra is PaywallEntry
      ? extra
      : extra is PaywallRequest
          ? extra.entry
          : PaywallEntry.general;

  /// 路由 extra 帶的方案提示：只有 [PaywallRequest] 有，其他都是 null。
  static String? tierHintFromRouteExtra(Object? extra) =>
      extra is PaywallRequest ? extra.tierHint : null;

  /// 付費頁最上面的大標；[tier] 是目前的方案。額度不夠時只說做得到的下一步（主審
  /// r1 P2-3）：免費、Starter 升級後額度更多；Essential 已經是最高方案，不承諾升級，
  /// 只說什麼時候恢復（恢復時間跟額度卡、確認框同一句，見 quota_copy.dart）。
  /// 換繳費週期不會補額度，不提。
  String headlineFor(String? tier) {
    final canUpgrade = canUpgradeQuota(tier);
    final dailyNext = canUpgrade ? '升級後每天能用更多' : kDailyQuotaResetLine;
    final monthlyNext = canUpgrade ? '升級後每月能用更多' : kMonthlyQuotaResetLine;
    return switch (this) {
      PaywallEntry.general => '完整教練帶路\n把她約出來更有把握',
      PaywallEntry.lockedCards => '每一輪的回覆卡\n全部看得到',
      PaywallEntry.dailyQuotaUsedUp => '今天的額度用完了\n$dailyNext',
      PaywallEntry.dailyQuotaShort => '今天的額度不夠這次用\n$dailyNext',
      PaywallEntry.monthlyQuotaUsedUp => '這個月的額度用完了\n$monthlyNext',
      PaywallEntry.monthlyQuotaShort => '這個月的額度不夠這次用\n$monthlyNext',
    };
  }

  /// 漏斗事件的 entry 值（docs/integrations/funnel-events-v1.md）。額度不夠的四種
  ///（今天／這個月、用完／不夠這次用）都記 quota_exhausted；server 只收這三個值，
  /// 加入口要同一批改字典與 server 白名單。
  String get funnelValue => switch (this) {
        PaywallEntry.general => 'general',
        PaywallEntry.lockedCards => 'locked_cards',
        PaywallEntry.dailyQuotaUsedUp ||
        PaywallEntry.dailyQuotaShort ||
        PaywallEntry.monthlyQuotaUsedUp ||
        PaywallEntry.monthlyQuotaShort =>
          'quota_exhausted',
      };
}
