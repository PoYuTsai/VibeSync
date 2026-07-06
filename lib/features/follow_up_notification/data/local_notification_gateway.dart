import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'notification_gateway.dart';

/// 真 [NotificationGateway]，包住 `flutter_local_notifications`。
///
/// 無單元測試（純原生橋接），靠 Task 11 手動 smoke 驗證。
/// 時區 MVP hardcode `Asia/Taipei`（用戶全在台灣）；若日後跨時區再引 `flutter_timezone`。
class LocalNotificationGateway implements NotificationGateway {
  static const String _channelId = 'follow_up_reminder';
  static const String _channelName = '跟進提醒';
  static const String _channelDescription = '48 小時後提醒你跟進聊天對象';
  static const String _timeZone = 'Asia/Taipei';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// tap 導航回呼，由 Task 8 的 init wiring 傳入（payload = partnerId）。
  final void Function(String payload)? onDidTap;

  LocalNotificationGateway({this.onDidTap});

  void _handleResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      onDidTap?.call(payload);
    }
  }

  @override
  Future<void> init() async {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(_timeZone));

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    // 權限延後到軟卡「幫我提醒」才要，init 時不主動請求。
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _handleResponse,
    );
  }

  @override
  Future<bool> requestPermission() async {
    if (Platform.isIOS) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return granted ?? false;
    }
    if (Platform.isAndroid) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      return granted ?? false;
    }
    return false;
  }

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime fireAt,
    required String payload,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(fireAt, tz.local),
      details,
      // 48h 跟進提醒不需秒級精準；用 inexact 避免 Android 12+ 需宣告
      // SCHEDULE_EXACT_ALARM 權限，否則 exact 模式會 throw exact_alarms_not_permitted
      // 被上層 best-effort 吞成「靜默無通知」（Codex 案4 F1）。
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id);

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Future<String?> launchPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp ?? false) {
      return details?.notificationResponse?.payload;
    }
    return null;
  }
}
