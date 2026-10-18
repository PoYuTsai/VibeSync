/// 付費頁從哪裡打開（Eric 2026-10-18）：標題跟著入口換，方案、價格、比較表都一樣。
/// 用 go_router 的 extra 帶過去；沒帶的入口都是一般入口，標題照舊。
enum PaywallEntry {
  /// 一般入口：沿用定位句（2026-08-18 拍板）。
  general,

  /// 分析結果裡鎖住的卡（免費方案只看得到前幾張）。
  lockedCards,

  /// 額度用完（每日或每月）。
  quotaExhausted;

  /// 路由的 extra 不是入口（沒帶、舊的呼叫端）就當一般入口。
  static PaywallEntry fromRouteExtra(Object? extra) =>
      extra is PaywallEntry ? extra : PaywallEntry.general;

  /// 付費頁最上面的大標。
  String get headline => switch (this) {
        PaywallEntry.general => '完整教練帶路\n把她約出來更有把握',
        PaywallEntry.lockedCards => '每一輪的回覆卡\n全部看得到',
        PaywallEntry.quotaExhausted => '額度用完了\n升級就能繼續分析',
      };

  /// 漏斗事件的 entry 值（docs/integrations/funnel-events-v1.md）。server 只收這三個；
  /// 加入口要同一批改字典與 server 白名單。
  String get funnelValue => switch (this) {
        PaywallEntry.general => 'general',
        PaywallEntry.lockedCards => 'locked_cards',
        PaywallEntry.quotaExhausted => 'quota_exhausted',
      };
}
