/// 隔離 `flutter_local_notifications` 的最小介面，讓排程邏輯可測。
///
/// 核心服務只依賴此介面 + clock + opt-in 狀態，plugin 的原生呼叫全被隔離在
/// [LocalNotificationGateway]（Task 7），測試用 `FakeNotificationGateway` 注入。
abstract class NotificationGateway {
  Future<void> init();

  /// 回傳系統是否授權（軟卡點「幫我提醒」後呼叫）。
  Future<bool> requestPermission();

  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime fireAt,
    required String payload,
  });

  Future<void> cancel(int id);

  Future<void> cancelAll();

  /// 冷啟動：若 app 由點通知啟動，回傳其 payload，否則 null。
  Future<String?> launchPayload();
}
