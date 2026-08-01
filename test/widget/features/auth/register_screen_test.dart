// test/widget/features/auth/register_screen_test.dart
//
// 批 B 訪客模式：RegisterScreen widget 測試。
// 注意：GradientBackground 有動態 bokeh（repeat 動畫），一律用 pump 步進，
// 絕不 pumpAndSettle（repo 鐵則）。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/services/funnel_tracker.dart';
import 'package:vibesync/features/auth/presentation/screens/register_screen.dart';

class _CapturedEvent {
  _CapturedEvent(this.event, this.properties);
  final String event;
  final Map<String, dynamic> properties;
}

void main() {
  late List<_CapturedEvent> captured;

  Widget buildScreen({String? source}) {
    captured = [];
    final tracker = FunnelTracker(
      invoker: (fn, {required body}) async {
        final event = body['event'] as Map<String, dynamic>;
        captured.add(
          _CapturedEvent(
            event['event'] as String,
            (event['properties'] as Map).cast<String, dynamic>(),
          ),
        );
        return 200;
      },
    );
    return ProviderScope(
      overrides: [funnelTrackerProvider.overrideWithValue(tracker)],
      child: MaterialApp(home: RegisterScreen(source: source)),
    );
  }

  testWidgets('渲染權益文案＋email 表單，進頁 track guest_register_view（source 正規化）',
      (tester) async {
    await tester.pumpWidget(buildScreen(source: 'not_in_enum'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('免費註冊，解鎖完整額度'), findsOneWidget);
    expect(
      find.text('註冊解鎖每月 30 則免費額度，訪客期間的紀錄全部保留。'),
      findsOneWidget,
    );
    expect(find.text('免費註冊'), findsOneWidget);
    expect(find.text('已有帳號？改用登入'), findsOneWidget);

    expect(captured, hasLength(1));
    expect(captured.single.event, 'guest_register_view');
    expect(captured.single.properties, {'source': 'unknown'});
  });

  testWidgets('已知 source 原樣送出', (tester) async {
    await tester.pumpWidget(buildScreen(source: 'quota_exhausted'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(captured.single.properties, {'source': 'quota_exhausted'});
  });

  testWidgets('email 格式不合法 → 顯示驗證錯誤，不打 service', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(find.byType(TextField).first, 'not-an-email');
    await tester.tap(find.text('免費註冊'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('請輸入有效的 Email。'), findsOneWidget);
  });

  testWidgets('密碼太弱 → 顯示密碼規則錯誤', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pump(const Duration(milliseconds: 100));

    final fields = find.byType(TextField);
    await tester.enterText(fields.first, 'you@example.com');
    await tester.enterText(fields.at(1), 'short');
    await tester.tap(find.text('免費註冊'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('密碼至少 8 個字元，且需包含英文字母與數字。'),
      findsOneWidget,
    );
  });

  testWidgets('「已有帳號？改用登入」→ 彈警告 dialog 明講訪客資料不帶過去，可取消',
      (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(
      find.byKey(const Key('register_switch_to_login_button')),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('改用既有帳號登入？'), findsOneWidget);
    expect(
      find.textContaining('登入其他帳號後不會帶過去'),
      findsOneWidget,
    );

    await tester.tap(find.text('取消'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('改用既有帳號登入？'), findsNothing);
  });
}
