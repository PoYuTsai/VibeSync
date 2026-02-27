import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vibesync/features/subscription/presentation/screens/settings_screen.dart';

void main() {
  late GoRouter testRouter;

  setUp(() {
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

  Widget buildTestWidget() {
    return ProviderScope(
      child: MaterialApp.router(
        routerConfig: testRouter,
      ),
    );
  }

  group('SettingsScreen', () {
    testWidgets('displays title in app bar', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('設定'), findsOneWidget);
    });

    testWidgets('displays account section', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('帳戶'), findsOneWidget);
      expect(find.text('訂閱方案'), findsOneWidget);
      expect(find.text('本月用量'), findsOneWidget);
      expect(find.text('帳號'), findsOneWidget);
    });

    testWidgets('displays privacy section', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('隱私與安全'), findsOneWidget);
      expect(find.text('清除所有對話資料'), findsOneWidget);
      expect(find.text('匯出我的資料'), findsOneWidget);
      expect(find.text('隱私權政策'), findsOneWidget);
    });

    testWidgets('displays about section', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('關於'), findsOneWidget);
      expect(find.text('版本'), findsOneWidget);
      expect(find.text('使用條款'), findsOneWidget);
      expect(find.text('意見回饋'), findsOneWidget);
    });

    testWidgets('displays Free tier as default', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Free'), findsOneWidget);
    });

    testWidgets('displays usage as 0/30', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('0/30 則'), findsOneWidget);
    });

    testWidgets('shows delete dialog when tapping clear data', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('清除所有對話資料'));
      await tester.pumpAndSettle();

      expect(find.text('確定要刪除所有對話？'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('刪除'), findsOneWidget);
    });

    testWidgets('can dismiss delete dialog', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('清除所有對話資料'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(find.text('確定要刪除所有對話？'), findsNothing);
    });
  });
}
