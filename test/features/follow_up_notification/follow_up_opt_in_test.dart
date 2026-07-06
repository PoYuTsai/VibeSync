import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/follow_up_notification/domain/follow_up_opt_in.dart';

void main() {
  test('unknown 才顯示軟卡', () {
    expect(shouldShowSoftCard(FollowUpOptIn.unknown), isTrue);
    expect(shouldShowSoftCard(FollowUpOptIn.granted), isFalse);
    expect(shouldShowSoftCard(FollowUpOptIn.denied), isFalse);
  });
  test('只有 granted 才排程', () {
    expect(canSchedule(FollowUpOptIn.granted), isTrue);
    expect(canSchedule(FollowUpOptIn.unknown), isFalse);
    expect(canSchedule(FollowUpOptIn.denied), isFalse);
  });
}
