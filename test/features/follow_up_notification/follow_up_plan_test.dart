import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/follow_up_notification/domain/follow_up_opt_in.dart';
import 'package:vibesync/features/follow_up_notification/domain/follow_up_plan.dart';

void main() {
  final now = DateTime(2026, 7, 6, 10, 0);
  test('partnerId 為 null → 不排', () {
    expect(
      buildFollowUpPlan(
          partnerId: null,
          displayName: 'A',
          optIn: FollowUpOptIn.granted,
          now: now),
      isNull,
    );
  });
  test('未授權 → 不排', () {
    expect(
      buildFollowUpPlan(
          partnerId: 'p1',
          displayName: 'A',
          optIn: FollowUpOptIn.unknown,
          now: now),
      isNull,
    );
  });
  test('授權且綁 partner → 排 +48h，文案帶名', () {
    final plan = buildFollowUpPlan(
        partnerId: 'p1',
        displayName: '小美',
        optIn: FollowUpOptIn.granted,
        now: now)!;
    expect(plan.fireAt, now.add(const Duration(hours: 48)));
    expect(plan.body, contains('小美'));
    expect(plan.payload, 'p1');
  });
  test('displayName 空 → 用「這位對象」', () {
    final plan = buildFollowUpPlan(
        partnerId: 'p1',
        displayName: '',
        optIn: FollowUpOptIn.granted,
        now: now)!;
    expect(plan.body, contains('這位對象'));
  });
}
