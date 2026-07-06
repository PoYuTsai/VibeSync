import 'package:vibesync/features/follow_up_notification/data/notification_gateway.dart';

class ScheduledCall {
  final int id;
  final DateTime fireAt;
  final String payload;
  ScheduledCall(this.id, this.fireAt, this.payload);
}

/// 記錄呼叫的測試假實作，讓排程邏輯可在純 Dart 下驗證。
class FakeNotificationGateway implements NotificationGateway {
  final List<ScheduledCall> scheduled = [];
  final List<int> cancelled = [];
  bool cancelAllCalled = false;
  bool permissionGranted = true;
  String? initialPayload;

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime fireAt,
    required String payload,
  }) async {
    scheduled.add(ScheduledCall(id, fireAt, payload));
  }

  @override
  Future<void> cancel(int id) async => cancelled.add(id);

  @override
  Future<void> cancelAll() async => cancelAllCalled = true;

  @override
  Future<String?> launchPayload() async => initialPayload;
}
