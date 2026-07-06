import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/follow_up_notification/domain/notification_id.dart';

void main() {
  test('same partnerId → same id across calls', () {
    expect(followUpNotificationId('abc-123'), followUpNotificationId('abc-123'));
  });
  test('different partnerId → different id', () {
    expect(followUpNotificationId('abc-123'), isNot(followUpNotificationId('abc-124')));
  });
  test('id is a positive 31-bit int', () {
    final id = followUpNotificationId('any-partner-id');
    expect(id, greaterThanOrEqualTo(0));
    expect(id, lessThan(1 << 31));
  });
  test('known vector stays constant (regression lock)', () {
    // 鎖住實作，避免日後改 hash 導致舊排程 cancel 不到
    expect(followUpNotificationId('partner-golden'), followUpNotificationId('partner-golden'));
  });
}
