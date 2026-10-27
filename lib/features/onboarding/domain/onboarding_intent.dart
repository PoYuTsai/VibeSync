// lib/features/onboarding/domain/onboarding_intent.dart
//
// onboarding 轉換第 12 步：第 1 頁「你現在最想先搞定哪一件？」的答案。
// [OnboardingIntent.wire] 同時是漏斗事件 `onboarding_intent.intent` 的值（server
// 白名單 ONBOARDING_INTENTS、docs/integrations/funnel-events-v1.md）與登入前
// 暫存 JSON 的值：改值要 client、server、文件同一批改。

/// 第 1 頁的四種答案。
enum OnboardingIntent {
  /// 她回我了：建好對象卡直接選截圖。
  analyze('analyze'),

  /// 剛配對：開場救星。
  opener('opener'),

  /// 還沒有對象：練習室圖鑑（第一次進去發首抽，決策 C）。
  practice('practice'),

  /// 先逛逛：不選路徑，直接去登入。
  browse('browse');

  const OnboardingIntent(this.wire);

  /// 送到伺服器、存進暫存的值。
  final String wire;

  /// 暫存讀回來時用；不認得的值回 null。
  static OnboardingIntent? fromWire(Object? value) {
    for (final intent in values) {
      if (intent.wire == value) return intent;
    }
    return null;
  }
}
