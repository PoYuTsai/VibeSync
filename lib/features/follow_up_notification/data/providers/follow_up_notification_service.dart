import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/storage_service.dart';
import '../../domain/follow_up_opt_in.dart';
import '../../domain/follow_up_plan.dart';
import '../../domain/notification_id.dart';
import '../follow_up_opt_in_store.dart';
import '../notification_gateway.dart';

/// 串起 gateway + opt-in 持久化 + 排程計畫，供 UI 掛點呼叫。
/// 所有分支判斷委派給 domain 純函式，本層只做副作用編排。
class FollowUpNotificationService {
  final NotificationGateway _gateway;
  final FollowUpOptInStore _optInStore;
  final DateTime Function() _now;

  FollowUpNotificationService({
    required NotificationGateway gateway,
    required FollowUpOptInStore optInStore,
    DateTime Function()? now,
  })  : _gateway = gateway,
        _optInStore = optInStore,
        _now = now ?? DateTime.now;

  FollowUpOptIn get optIn => _optInStore.read();

  /// 綁 partner 的分析持久化完成後呼叫。
  /// 重排歸零：schedule 前先 cancel 同 id，避免同對象重複分析堆疊多則。
  Future<void> onPartnerAnalysisSaved({
    required String? partnerId,
    required String displayName,
  }) async {
    final plan = buildFollowUpPlan(
      partnerId: partnerId,
      displayName: displayName,
      optIn: _optInStore.read(),
      now: _now(),
    );
    if (plan == null) return;
    final id = followUpNotificationId(plan.payload);
    await _gateway.cancel(id);
    await _gateway.schedule(
      id: id,
      title: plan.title,
      body: plan.body,
      fireAt: plan.fireAt,
      payload: plan.payload,
    );
  }

  /// 軟卡「幫我提醒」後呼叫：向系統要權限，落 granted / denied。
  Future<bool> requestSoftOptIn() async {
    final granted = await _gateway.requestPermission();
    await _optInStore.write(
      granted ? FollowUpOptIn.granted : FollowUpOptIn.denied,
    );
    return granted;
  }

  /// 軟卡「不用」後呼叫：記錄 denied，之後不再顯示軟卡（不動系統權限）。
  Future<void> declineSoftOptIn() async {
    await _optInStore.write(FollowUpOptIn.denied);
  }

  /// 刪 conversation 時取消該對象的待發通知。
  Future<void> cancelForConversation(String? partnerId) async {
    if (partnerId == null || partnerId.isEmpty) return;
    await _gateway.cancel(followUpNotificationId(partnerId));
  }

  /// 設定頁總開關關閉：清掉全部待發通知，opt-in 落 denied。
  Future<void> disableAll() async {
    await _gateway.cancelAll();
    await _optInStore.write(FollowUpOptIn.denied);
  }
}

/// 真 gateway provider。實作在 Task 7（LocalNotificationGateway）注入覆寫；
/// 此處佔位，未覆寫即呼叫代表 init wiring 漏接。
final notificationGatewayProvider = Provider<NotificationGateway>(
  (ref) => throw UnimplementedError(
    'notificationGatewayProvider 未覆寫：應於 Task 7/8 的 init 注入 LocalNotificationGateway',
  ),
);

/// opt-in store：存現有 settings box。
final followUpOptInStoreProvider = Provider<FollowUpOptInStore>(
  (ref) => HiveFollowUpOptInStore(StorageService.settingsBox),
);

final followUpNotificationServiceProvider =
    Provider<FollowUpNotificationService>(
  (ref) => FollowUpNotificationService(
    gateway: ref.watch(notificationGatewayProvider),
    optInStore: ref.watch(followUpOptInStoreProvider),
  ),
);
