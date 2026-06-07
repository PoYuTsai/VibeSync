import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/presentation/screens/settings_screen.dart';

void main() {
  late GoRouter testRouter;

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'VibeSync',
      packageName: 'com.poyutsai.vibesync',
      version: '1.0.0',
      buildNumber: '165',
      buildSignature: '',
    );

    testRouter = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/paywall',
          builder: (context, state) => const Scaffold(
            body: Center(child: Text('Paywall')),
          ),
        ),
      ],
    );
  });

  Future<void> pumpSettings(
    WidgetTester tester, {
    Future<void> Function()? refreshUsage,
  }) async {
    await tester.binding.setSurfaceSize(const Size(430, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          subscriptionScreenRefreshProvider.overrideWithValue(
            refreshUsage ?? () async {},
          ),
        ],
        child: MaterialApp.router(routerConfig: testRouter),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('formatSettingsRenewalDate', () {
    test('shows time instead of a bare date when renewal is today', () {
      final now = DateTime(2026, 6, 7, 12, 43);
      final renewsAt = DateTime(2026, 6, 7, 14, 5);

      expect(
        formatSettingsRenewalDate(renewsAt, now: now),
        '今天 14:05',
      );
    });

    test('shows date for future renewal days', () {
      final now = DateTime(2026, 6, 7, 12, 43);
      final renewsAt = DateTime(2026, 6, 8, 14, 5);

      expect(
        formatSettingsRenewalDate(renewsAt, now: now),
        '2026/6/8',
      );
    });
  });

  group('SettingsScreen', () {
    testWidgets('refreshes subscription usage snapshot on entry',
        (tester) async {
      var refreshCalls = 0;
      await pumpSettings(tester, refreshUsage: () async {
        refreshCalls++;
      });

      expect(refreshCalls, 1);
    });

    testWidgets('shows settings title and quota summary', (tester) async {
      await pumpSettings(tester);

      expect(find.text('設定'), findsOneWidget);
      expect(find.text('目前方案與額度'), findsOneWidget);
      expect(find.text('目前方案：Free'), findsOneWidget);
      expect(find.text('本月剩餘'), findsNWidgets(2));
      expect(find.text('今日剩餘'), findsNWidgets(2));
      expect(find.text('30/30'), findsNWidgets(2));
      expect(find.text('15/15'), findsNWidgets(2));
    });

    testWidgets('shows clear plan and account rows', (tester) async {
      await pumpSettings(tester);

      expect(find.text('方案與帳號'), findsOneWidget);
      expect(find.text('目前方案'), findsOneWidget);
      expect(find.text('本月已使用'), findsOneWidget);
      expect(find.text('0/30'), findsOneWidget);
      expect(find.text('帳號'), findsOneWidget);
      expect(find.text('尚未登入'), findsOneWidget);
      expect(find.text('管理訂閱'), findsOneWidget);
      expect(find.text('恢復購買'), findsOneWidget);
    });

    testWidgets('shows privacy and support rows with launch copy',
        (tester) async {
      await pumpSettings(tester);

      expect(find.text('隱私與資料'), findsOneWidget);
      expect(find.text('刪除帳號'), findsOneWidget);
      expect(find.text('隱私政策'), findsOneWidget);
      expect(find.text('其他'), findsOneWidget);
      expect(find.text('App 版本'), findsOneWidget);
      expect(find.text('1.0.0 (165)'), findsOneWidget);
      expect(find.text('服務條款'), findsOneWidget);
      expect(find.text('客服與支援'), findsOneWidget);
      expect(find.text('登出'), findsOneWidget);
    });

    testWidgets('opens paywall when tapping current plan row', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text('目前方案'));
      await tester.pumpAndSettle();

      expect(find.text('Paywall'), findsOneWidget);
    });

    testWidgets('delete account dialog requires explicit DELETE confirmation',
        (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text('刪除帳號'));
      await tester.pump();

      expect(find.text('刪除帳號'), findsNWidgets(2));
      expect(find.textContaining('Apple 訂閱管理'), findsOneWidget);
      expect(find.text('輸入 DELETE 以確認'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('刪除'), findsOneWidget);

      final deleteButton =
          tester.widget<TextButton>(find.widgetWithText(TextButton, '刪除'));
      expect(deleteButton.onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pump();

      final enabledDeleteButton =
          tester.widget<TextButton>(find.widgetWithText(TextButton, '刪除'));
      expect(enabledDeleteButton.onPressed, isNotNull);
    });
  });
}
