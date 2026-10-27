import '../../../core/constants/app_constants.dart';
import '../domain/services/subscription_tier_helper.dart';
import 'quota_copy.dart';

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
  monthlyQuotaShort,

  /// 練習室翻牌撞牆（Onboarding 第 2 步）：免費首抽用掉後想再抽一位、付費方案今天的
  /// 翻牌用完。共用額度用完、續聊同一位被擋仍是一般入口。
  practiceDraw;

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
  /// r1 P2-3），而且先說什麼時候恢復（Onboarding 第 3 步：付錢不是唯一的路）：免費、
  /// Starter 再補升級後額度更多；Essential 已經是最高方案，不承諾升級，只說什麼時候
  /// 恢復（恢復時間跟額度卡、確認框同一句，見 quota_copy.dart）。
  /// 換繳費週期不會補額度，不提。
  String headlineFor(String? tier) {
    final dailyNext = quotaNextStepLine(
      tier: tier,
      isMonthly: false,
      upgrade: '升級後每天能用更多',
    );
    final monthlyNext = quotaNextStepLine(
      tier: tier,
      isMonthly: true,
      upgrade: '升級後每月能用更多',
    );
    return switch (this) {
      PaywallEntry.general => '完整教練帶路\n把她約出來更有把握',
      PaywallEntry.lockedCards => '每一輪的回覆卡\n全部看得到',
      PaywallEntry.dailyQuotaUsedUp => '今天的額度用完了\n$dailyNext',
      PaywallEntry.dailyQuotaShort => '今天的額度不夠這次用\n$dailyNext',
      PaywallEntry.monthlyQuotaUsedUp => '這個月的額度用完了\n$monthlyNext',
      PaywallEntry.monthlyQuotaShort => '這個月的額度不夠這次用\n$monthlyNext',
      PaywallEntry.practiceDraw => _practiceDrawHeadline(tier),
    };
  }

  /// 翻牌入口的大標（Onboarding 第 2 步）：免費版沒有每日翻牌，不寫恢復時間，直接講
  /// 升級後多了什麼；付費方案是今天的翻牌用完了，先講什麼時候恢復（台北中午 12 點，
  /// 跟一般額度的早上 8 點不同），Starter 再補升級 Essential 多幾位，Essential 只講
  /// 恢復時間。
  static String _practiceDrawHeadline(String? tier) {
    switch (SubscriptionTierHelper.normalizeTier(tier)) {
      case SubscriptionTierHelper.essential:
        return '今天的翻牌用完了\n$kPracticeDrawResetLine';
      case SubscriptionTierHelper.starter:
        return '今天的翻牌用完了\n$kPracticeDrawResetLine；'
            '升級 Essential 每天翻 ${AppConstants.essentialDailyDrawLimit} 位';
      default:
        return '想再練一位？\n免費版只有一次翻牌；'
            '升級後每天翻 ${AppConstants.starterDailyDrawLimit} 位，同一位能續聊';
    }
  }

  /// 漏斗事件的 entry 值（docs/integrations/funnel-events-v1.md）。額度不夠的四種
  ///（今天／這個月、用完／不夠這次用）都記 quota_exhausted；server 只收這四個值，
  /// 加入口要同一批改字典與 server 白名單。
  String get funnelValue => switch (this) {
        PaywallEntry.general => 'general',
        PaywallEntry.lockedCards => 'locked_cards',
        PaywallEntry.dailyQuotaUsedUp ||
        PaywallEntry.dailyQuotaShort ||
        PaywallEntry.monthlyQuotaUsedUp ||
        PaywallEntry.monthlyQuotaShort =>
          'quota_exhausted',
        PaywallEntry.practiceDraw => 'practice_draw',
      };
}
