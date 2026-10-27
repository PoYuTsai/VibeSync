// test/widget/features/onboarding/onboarding_handoff_applier_test.dart
//
// 登入後落地 MainShell 的交接收尾（OnboardingHandoffApplier）：
// - onboarding 轉換第 4 步：每次進首頁都補送登入前排隊的漏斗事件，
//   有沒有交接暫存都一樣，而且不擋導頁。
// - 有交接暫存時照舊導到分流目的地。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/core/services/funnel_tracker.dart';
import 'package:vibesync/features/onboarding/data/onboarding_service.dart';
import 'package:vibesync/features/onboarding/presentation/widgets/onboarding_handoff_applier.dart';

class _FlushSpyTracker extends FunnelTracker {
  _FlushSpyTracker()
      : super(
          invoker: (fn, {required body}) async => 200,
          currentUserId: () => 'user-a',
        );

  var flushCalls = 0;

  @override
  Future<void> flushPending() async {
    flushCalls++;
  }
}

GoRouter _router() => GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(
            body: Stack(
              children: [
                OnboardingHandoffApplier(),
                Text('home-screen'),
              ],
            ),
          ),
        ),
        GoRoute(
          path: '/partner/new',
          builder: (_, __) => const Scaffold(body: Text('partner-new-screen')),
        ),
      ],
    );

Future<void> _pumpHome(WidgetTester tester, FunnelTracker tracker) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [funnelTrackerProvider.overrideWithValue(tracker)],
      child: MaterialApp.router(routerConfig: _router()),
    ),
  );
  // initState 排的 post-frame callback 跑完。
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('登入後進首頁：沒有交接暫存也會補送一次', (tester) async {
    final tracker = _FlushSpyTracker();

    await _pumpHome(tester, tracker);

    expect(tracker.flushCalls, 1);
    expect(find.text('home-screen'), findsOneWidget);
  });

  testWidgets('有交接暫存：照樣補送，也照舊導到分流目的地', (tester) async {
    await OnboardingService.stashPendingHandoff(
      goalNames: const [],
      route: '/partner/new',
    );
    final tracker = _FlushSpyTracker();

    await _pumpHome(tester, tracker);

    expect(tracker.flushCalls, 1);
    expect(find.text('partner-new-screen'), findsOneWidget);
    expect(await OnboardingService.takePendingHandoff(), isNull);
  });

  testWidgets('真的補送：登入前排隊的 onboarding 事件，進首頁後照原本的時間送出', (tester) async {
    String? uid;
    final sent = <Map<String, dynamic>>[];
    final queuedAt = DateTime.utc(2026, 10, 27, 1);
    var now = queuedAt;
    final tracker = FunnelTracker(
      invoker: (fn, {required body}) async {
        sent.add(body['event'] as Map<String, dynamic>);
        return 200;
      },
      currentUserId: () => uid,
      clock: () => now,
    );
    // onboarding 走在登入前：先排隊、不送。
    await tracker.track('onboarding_page_view', properties: {'page_index': 0});
    await tracker.track(
      'onboarding_branch_answer',
      properties: {'has_partner': false},
    );
    expect(sent, isEmpty);

    uid = 'user-a';
    now = queuedAt.add(const Duration(minutes: 3));
    await _pumpHome(tester, tracker);

    expect([
      for (final e in sent) e['event']
    ], [
      'onboarding_page_view',
      'onboarding_branch_answer',
    ]);
    expect(
      [for (final e in sent) e['clientTs']],
      everyElement(queuedAt.toIso8601String()),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(FunnelTracker.pendingQueueKey), isFalse);
  });
}
