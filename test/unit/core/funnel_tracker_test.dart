// test/unit/core/funnel_tracker_test.dart
//
// FunnelTracker（Tier 2 批 1.5）：best-effort 去識別化漏斗埋點封裝。
// - wire payload 只帶 client 白名單鍵；字典外事件根本不出手機。
// - 非 2xx／invoker 炸掉一律吞掉不 throw。
// - trackOnce 用 SharedPreferences once-flag 去重。

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/core/services/funnel_tracker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('wire payload：kind=funnel、事件與白名單鍵、clientTs', () async {
    Map<String, dynamic>? captured;
    final tracker = FunnelTracker(
      invoker: (fn, {required body}) async {
        expect(fn, 'submit-feedback');
        captured = body;
        return 200;
      },
    );

    await tracker.track(
      'coach_entry_tap',
      properties: {'has_partner': true, 'partnerName': '小美'},
    );

    expect(captured, isNotNull);
    expect(captured!['kind'], 'funnel');
    final event = captured!['event'] as Map<String, dynamic>;
    expect(event['event'], 'coach_entry_tap');
    expect(event['properties'], {'has_partner': true});
    expect(event['clientTs'], isA<String>());
  });

  test('字典外事件：invoker 不被呼叫', () async {
    var calls = 0;
    final tracker = FunnelTracker(
      invoker: (fn, {required body}) async {
        calls++;
        return 200;
      },
    );

    await tracker.track('made_up_event');

    expect(calls, 0);
  });

  test('非 2xx 不 throw', () async {
    final tracker = FunnelTracker(invoker: (fn, {required body}) async => 500);

    await tracker.track('quota_strip_tap');
  });

  test('invoker 炸掉不 throw', () async {
    final tracker = FunnelTracker(
      invoker: (fn, {required body}) async => throw StateError('boom'),
    );

    await tracker.track('quota_strip_tap');
  });

  test('trackOnce：同事件只送一次，跨 instance 也擋', () async {
    var calls = 0;
    FunnelTracker build() => FunnelTracker(
          invoker: (fn, {required body}) async {
            calls++;
            return 200;
          },
        );

    await build().trackOnce('first_analysis_completed');
    await build().trackOnce('first_analysis_completed');

    expect(calls, 1);
  });
}
