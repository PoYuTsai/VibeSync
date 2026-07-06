import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/follow_up_notification/data/follow_up_opt_in_store.dart';
import 'package:vibesync/features/follow_up_notification/data/providers/follow_up_notification_service.dart';
import 'package:vibesync/features/follow_up_notification/domain/follow_up_opt_in.dart';
import 'package:vibesync/features/follow_up_notification/domain/notification_id.dart';

import 'fake_notification_gateway.dart';

/// 記憶體 opt-in store，避免測試碰真 Hive。
class InMemoryOptInStore implements FollowUpOptInStore {
  FollowUpOptIn value;
  InMemoryOptInStore([this.value = FollowUpOptIn.unknown]);
  @override
  FollowUpOptIn read() => value;
  @override
  Future<void> write(FollowUpOptIn v) async => value = v;
}

void main() {
  final now = DateTime(2026, 7, 6, 10, 0);
  late FakeNotificationGateway gateway;
  late InMemoryOptInStore store;

  FollowUpNotificationService build(FollowUpOptIn initial) {
    gateway = FakeNotificationGateway();
    store = InMemoryOptInStore(initial);
    return FollowUpNotificationService(
      gateway: gateway,
      optInStore: store,
      now: () => now,
    );
  }

  test('granted 綁 partner → 先 cancel(id) 再 schedule +48h（重排歸零）', () async {
    final service = build(FollowUpOptIn.granted);
    await service.onPartnerAnalysisSaved(partnerId: 'p1', displayName: '小美');

    final id = followUpNotificationId('p1');
    expect(gateway.cancelled, contains(id));
    expect(gateway.scheduled, hasLength(1));
    expect(gateway.scheduled.single.id, id);
    expect(gateway.scheduled.single.fireAt, now.add(const Duration(hours: 48)));
    expect(gateway.scheduled.single.payload, 'p1');
  });

  test('optIn=unknown → 不排程', () async {
    final service = build(FollowUpOptIn.unknown);
    await service.onPartnerAnalysisSaved(partnerId: 'p1', displayName: '小美');
    expect(gateway.scheduled, isEmpty);
  });

  test('cancelForConversation(partnerId) → cancelled 含該 id', () async {
    final service = build(FollowUpOptIn.granted);
    await service.cancelForConversation('p1');
    expect(gateway.cancelled, contains(followUpNotificationId('p1')));
  });

  test('cancelForConversation(null/空) → 不呼叫 cancel', () async {
    final service = build(FollowUpOptIn.granted);
    await service.cancelForConversation(null);
    await service.cancelForConversation('');
    expect(gateway.cancelled, isEmpty);
  });

  test('disableAll() → cancelAll 且 optIn 落為 denied', () async {
    final service = build(FollowUpOptIn.granted);
    await service.disableAll();
    expect(gateway.cancelAllCalled, isTrue);
    expect(store.read(), FollowUpOptIn.denied);
  });

  test('requestSoftOptIn 授權成功 → optIn=granted 回 true', () async {
    final service = build(FollowUpOptIn.unknown);
    gateway.permissionGranted = true;
    final ok = await service.requestSoftOptIn();
    expect(ok, isTrue);
    expect(store.read(), FollowUpOptIn.granted);
  });

  test('requestSoftOptIn 被拒 → optIn=denied 回 false', () async {
    final service = build(FollowUpOptIn.unknown);
    gateway.permissionGranted = false;
    final ok = await service.requestSoftOptIn();
    expect(ok, isFalse);
    expect(store.read(), FollowUpOptIn.denied);
  });
}
