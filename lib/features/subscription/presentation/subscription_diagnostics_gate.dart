import 'package:flutter/foundation.dart';

/// 「複製訂閱診斷」是內部除錯工具：只在 debug build 顯示，
/// release（含 App Review 送審 build）一律隱藏。
class SubscriptionDiagnosticsGate {
  /// 測試 seam：flutter test 恆為 debug，覆寫才能驗 release 隱藏行為。
  @visibleForTesting
  static bool? debugVisibleOverride;

  static bool get isVisible => debugVisibleOverride ?? (!kIsWeb && kDebugMode);
}
