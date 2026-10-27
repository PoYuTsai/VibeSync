// test/widget/app_keyboard_quota_signal_test.dart
//
// onboarding 轉換第 6 步：鍵盤轉來「伺服器確認額度用完」的訊號時，記一筆
// quota_block_shown（feature=keyboard；訊號分不出每日或每月，scope=unknown；
// source=server）。只是記錄，付費頁照舊（在 splash 之後才開）。
// App 的起手式照 test/widget_test.dart：splash 跑完前就拆掉，不進真的路由。

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/app/app.dart';
import 'package:vibesync/core/config/environment.dart';
import 'package:vibesync/core/services/funnel_tracker.dart';
import 'package:vibesync/core/services/supabase_service.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/follow_up_notification/data/providers/follow_up_notification_service.dart';

import '../features/follow_up_notification/fake_notification_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SupabaseService.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
  });

  tearDown(() => App.debugKeyboardQuotaSignalOverride = null);

  /// 掛上 App [launches] 次（每次 initState 都會檢查一次鍵盤訊號），共用同一個
  /// tracker（同一次執行），回傳送出的額度不足事件。
  Future<List<Object?>> launchApp(
    WidgetTester tester, {
    required bool Function() signal,
    int launches = 1,
  }) async {
    final sent = <Map<String, dynamic>>[];
    final tracker = FunnelTracker(
      invoker: (fn, {required body}) async {
        sent.add(body['event'] as Map<String, dynamic>);
        return 200;
      },
      currentUserId: () => 'keyboard-user',
    );
    App.debugKeyboardQuotaSignalOverride = () async => signal();
    for (var i = 0; i < launches; i++) {
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            conversationsProvider.overrideWithValue([]),
            notificationGatewayProvider.overrideWithValue(
              FakeNotificationGateway(),
            ),
            funnelTrackerProvider.overrideWithValue(tracker),
          ],
          child: const App(),
        ),
      );
      await tester.pump();
      // splash 跑完前拆掉（同 widget_test.dart），不進真的路由。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    }
    return [
      for (final e in sent)
        if (e['event'] == 'quota_block_shown') e['properties'],
    ];
  }

  testWidgets('鍵盤的額度訊號：記一筆 keyboard／unknown／server；同一次執行又收到一次不重記',
      (tester) async {
    var checks = 0;
    final quotaBlocks = await launchApp(tester, launches: 2, signal: () {
      checks++;
      return true;
    });

    expect(checks, 2);
    expect(quotaBlocks, [
      {'feature': 'keyboard', 'scope': 'unknown', 'block_source': 'server'},
    ]);
  });

  testWidgets('沒有額度訊號：不記', (tester) async {
    var checks = 0;
    final quotaBlocks = await launchApp(tester, launches: 2, signal: () {
      checks++;
      return false;
    });

    expect(checks, 2);
    expect(quotaBlocks, isEmpty);
  });
}
