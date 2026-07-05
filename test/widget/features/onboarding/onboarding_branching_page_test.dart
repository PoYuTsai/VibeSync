// test/widget/features/onboarding/onboarding_branching_page_test.dart
//
// 案 3 冷啟動分流（docs/plans/2026-07-06-case3-cold-start-branching-design.md）：
// onboarding 第 5 頁是分流頁——「你現在有正在聊的對象嗎？」。
//   - 主按鈕「有，幫我分析對話」→ markCompleted → go('/') → push('/partner/new')
//   - 次按鈕「還沒，先去練習」→ markCompleted → go('/') → push('/practice-collection')
//   - 底部「下一步」在分流頁隱藏（分流按鈕在頁內）；「略過」行為不變。
// 用無 redirect 的 stub GoRouter 驗證真實導流落點＋SharedPreferences 寫入。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/onboarding/presentation/screens/onboarding_screen.dart';

GoRouter _stubRouter() => GoRouter(
      initialLocation: '/onboarding',
      routes: [
        GoRoute(
          path: '/onboarding',
          builder: (_, __) => const OnboardingScreen(),
        ),
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('main-shell')),
        ),
        GoRoute(
          path: '/partner/new',
          builder: (_, __) =>
              const Scaffold(body: Text('partner-new-screen')),
        ),
        GoRoute(
          path: '/practice-collection',
          builder: (_, __) =>
              const Scaffold(body: Text('practice-collection-screen')),
        ),
      ],
    );

Future<void> _pumpOnboarding(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp.router(routerConfig: _stubRouter()));
  await tester.pumpAndSettle();
}

Future<void> _swipeToNextPage(WidgetTester tester) async {
  await tester.drag(find.byType(PageView), const Offset(-400, 0));
  await tester.pumpAndSettle();
}

/// 從第 1 頁滑 4 次抵達第 5 頁（分流頁）。
Future<void> _swipeToBranchingPage(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await _swipeToNextPage(tester);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('onboarding 第 5 頁分流頁（案 3）', () {
    testWidgets('分流頁顯示標題＋兩顆按鈕，底部「下一步」隱藏、指示點 5 顆',
        (tester) async {
      await _pumpOnboarding(tester);
      await _swipeToBranchingPage(tester);

      expect(find.text('你現在有正在聊的對象嗎？'), findsOneWidget);
      expect(find.text('有，幫我分析對話'), findsOneWidget);
      expect(find.text('還沒，先去練習'), findsOneWidget);
      expect(find.text('下一步'), findsNothing);
      expect(find.text('開始使用'), findsNothing);
      // 指示點 5 顆（4 頁 + 分流頁）。
      expect(
        find.byWidgetPredicate(
          (w) => w is AnimatedContainer && w.margin != null,
        ),
        findsNWidgets(5),
      );
    });

    testWidgets('主按鈕「有，幫我分析對話」→ 完成 onboarding 並落在 /partner/new',
        (tester) async {
      await _pumpOnboarding(tester);
      await _swipeToBranchingPage(tester);

      await tester.tap(find.text('有，幫我分析對話'));
      await tester.pumpAndSettle();

      expect(find.text('partner-new-screen'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding_completed'), isTrue);
    });

    testWidgets('次按鈕「還沒，先去練習」→ 完成 onboarding 並落在 /practice-collection',
        (tester) async {
      await _pumpOnboarding(tester);
      await _swipeToBranchingPage(tester);

      await tester.tap(find.text('還沒，先去練習'));
      await tester.pumpAndSettle();

      expect(find.text('practice-collection-screen'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding_completed'), isTrue);
    });

    testWidgets('主按鈕導流後 back 可退回首頁（go / 再 push，不卡死）',
        (tester) async {
      await _pumpOnboarding(tester);
      await _swipeToBranchingPage(tester);

      await tester.tap(find.text('有，幫我分析對話'));
      await tester.pumpAndSettle();
      expect(find.text('partner-new-screen'), findsOneWidget);

      // push 在 go('/') 之上 → pop 應回主殼，不是 onboarding。
      final router = GoRouter.of(
        tester.element(find.text('partner-new-screen')),
      );
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('main-shell'), findsOneWidget);
    });

    testWidgets('前 4 頁底部一律顯示「下一步」，末頁不再有「開始使用」',
        (tester) async {
      await _pumpOnboarding(tester);

      for (var page = 0; page < 4; page++) {
        expect(find.text('下一步'), findsOneWidget, reason: '第 ${page + 1} 頁');
        expect(find.text('開始使用'), findsNothing, reason: '第 ${page + 1} 頁');
        await _swipeToNextPage(tester);
      }
    });

    testWidgets('第 4 頁按「下一步」進入分流頁（不再直接完成 onboarding）',
        (tester) async {
      await _pumpOnboarding(tester);
      for (var i = 0; i < 3; i++) {
        await _swipeToNextPage(tester);
      }

      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();

      expect(find.text('你現在有正在聊的對象嗎？'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding_completed'), isNull);
    });

    testWidgets('「略過」行為不變：markCompleted 並落在 /', (tester) async {
      await _pumpOnboarding(tester);

      await tester.tap(find.text('略過'));
      await tester.pumpAndSettle();

      expect(find.text('main-shell'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding_completed'), isTrue);
    });

    testWidgets('分流頁右上仍有「略過」可逃生', (tester) async {
      await _pumpOnboarding(tester);
      await _swipeToBranchingPage(tester);

      await tester.tap(find.text('略過'));
      await tester.pumpAndSettle();

      expect(find.text('main-shell'), findsOneWidget);
    });
  });
}
