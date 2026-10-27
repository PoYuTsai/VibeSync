// test/widget/features/onboarding/onboarding_branching_page_test.dart
//
// 案 3 冷啟動分流（docs/plans/2026-07-06-case3-cold-start-branching-design.md）：
// onboarding 第 5 頁是分流頁——「你現在有正在聊的對象嗎？」。
//   - 主按鈕「有，幫我分析對話」→ markCompleted → go('/') →
//     push('/partner/new?next=screenshot')（onboarding 轉換第 10 步：建好對象卡
//     直接到選截圖）
//   - 次按鈕「還沒，先去練習」→ markCompleted → go('/') → push('/practice-collection?guide=1')
//   - 底部「下一步」在分流頁隱藏（分流按鈕在頁內）；「略過」行為不變。
// 用無 redirect 的 stub GoRouter 驗證真實導流落點＋SharedPreferences 寫入。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/onboarding/data/onboarding_service.dart';
import 'package:vibesync/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:vibesync/features/user_profile/data/providers/user_profile_providers.dart';

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
          // 帶出 next 參數讓測試驗證：分流「有」必須帶 next=screenshot（建好
          // 對象卡直接到選截圖，onboarding 轉換第 10 步）。
          builder: (_, state) => Scaffold(
            body: Text(
              'partner-new-screen '
              'next=${state.uri.queryParameters['next']}',
            ),
          ),
        ),
        GoRoute(
          path: '/practice-collection',
          // 帶出 guide 參數讓測試驗證：分流「還沒」必須帶 guide=1（圖鑑落地
          // 引導的唯一觸發源）。
          builder: (_, state) => Scaffold(
            body: Text(
              'practice-collection-screen '
              'guide=${state.uri.queryParameters['guide']}',
            ),
          ),
        ),
      ],
    );

/// 預設模擬已登入（覆寫 auth scope）：分流按鈕走「直接種＋push」的原路。
/// 未登入的暫存交接路徑另有專測。
Future<void> _pumpOnboarding(
  WidgetTester tester, {
  bool loggedIn = true,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      if (loggedIn)
        authUserProfileScopeProvider
            .overrideWith((ref) => Stream.value('test-uid')),
    ],
    child: MaterialApp.router(routerConfig: _stubRouter()),
  ));
  await tester.pumpAndSettle();
}

Future<void> _swipeToNextPage(WidgetTester tester) async {
  // fling（帶速度）等同真人滑動手勢；原本的 drag(-400) 在 800 寬測試視窗
  // 剛好踩在 50% 換頁閾值邊界，頁面內容一變就翻車，不是穩定的換頁模擬。
  await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
  await tester.pumpAndSettle();
}

/// 從第 1 頁滑 8 次抵達第 9 頁分流頁（6 賣點/定位頁＋問卷＋隱私之後）。
Future<void> _swipeToBranchingPage(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await _swipeToNextPage(tester);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('onboarding 第 5 頁分流頁（案 3）', () {
    // 對話分析 v3（Eric 2026-10-17）：新流程沒有投入度分數，第 2 頁改講燈號。
    testWidgets('第 2 頁用燈號講她的訊號，不再寫投入度分數', (tester) async {
      await _pumpOnboarding(tester);
      await _swipeToNextPage(tester);

      expect(find.text('即時看懂她的訊號'), findsOneWidget);
      expect(
        find.text('燈號看她現在有多熱\n教練再告訴你：該回、先別回，還是收尾'),
        findsOneWidget,
      );
      expect(find.textContaining('投入度'), findsNothing);
      expect(find.textContaining('熱度分析'), findsNothing);
    });

    testWidgets('第 6 頁不再寫「熱度多少」（對話分析 v3 不產生熱度）', (tester) async {
      await _pumpOnboarding(tester);
      for (var i = 0; i < 5; i++) {
        await _swipeToNextPage(tester);
      }

      expect(find.text('不只教你回這句'), findsOneWidget);
      expect(
        find.text('它認得你聊的每一個她——聊到哪、她現在冷還熱、什麼時候該約\n教練帶你從曖昧一路走到約出來'),
        findsOneWidget,
      );
      expect(find.textContaining('熱度多少'), findsNothing);
    });

    testWidgets('分流頁顯示標題＋兩顆按鈕，底部「下一步」隱藏、指示點 9 顆', (tester) async {
      await _pumpOnboarding(tester);
      await _swipeToBranchingPage(tester);

      expect(find.text('你現在有正在聊的對象嗎？'), findsOneWidget);
      expect(find.text('有，幫我分析對話'), findsOneWidget);
      expect(find.text('還沒，先去練習'), findsOneWidget);
      expect(find.text('下一步'), findsNothing);
      expect(find.text('開始使用'), findsNothing);
      // 指示點 9 顆（6 賣點/定位頁 + 問卷 + 隱私 + 分流）。
      expect(
        find.byWidgetPredicate(
          (w) => w is AnimatedContainer && w.margin != null,
        ),
        findsNWidgets(9),
      );
    });

    testWidgets('主按鈕「有，幫我分析對話」→ 完成 onboarding 並落在 /partner/new?next=screenshot',
        (tester) async {
      await _pumpOnboarding(tester);
      await _swipeToBranchingPage(tester);

      await tester.tap(find.text('有，幫我分析對話'));
      await tester.pumpAndSettle();

      expect(find.text('partner-new-screen next=screenshot'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding_completed'), isTrue);
    });

    testWidgets('次按鈕「還沒，先去練習」→ 完成 onboarding 並落在 /practice-collection',
        (tester) async {
      await _pumpOnboarding(tester);
      await _swipeToBranchingPage(tester);

      await tester.tap(find.text('還沒，先去練習'));
      await tester.pumpAndSettle();

      expect(find.text('practice-collection-screen guide=1'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding_completed'), isTrue);
    });

    testWidgets('兩顆分流按鈕下各有一行去向說明小字', (tester) async {
      await _pumpOnboarding(tester);
      await _swipeToBranchingPage(tester);

      expect(find.text('先幫你把她這輪的訊號讀懂'), findsOneWidget);
      expect(find.text('先抽一位練習夥伴，把手感練起來'), findsOneWidget);
    });

    testWidgets('主按鈕導流後 back 可退回首頁（go / 再 push，不卡死）', (tester) async {
      await _pumpOnboarding(tester);
      await _swipeToBranchingPage(tester);

      await tester.tap(find.text('有，幫我分析對話'));
      await tester.pumpAndSettle();
      expect(find.text('partner-new-screen next=screenshot'), findsOneWidget);

      // push 在 go('/') 之上 → pop 應回主殼，不是 onboarding。
      final router = GoRouter.of(
        tester.element(find.text('partner-new-screen next=screenshot')),
      );
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('main-shell'), findsOneWidget);
    });

    testWidgets('前 4 頁底部一律顯示「下一步」，末頁不再有「開始使用」', (tester) async {
      await _pumpOnboarding(tester);

      for (var page = 0; page < 4; page++) {
        expect(find.text('下一步'), findsOneWidget, reason: '第 ${page + 1} 頁');
        expect(find.text('開始使用'), findsNothing, reason: '第 ${page + 1} 頁');
        await _swipeToNextPage(tester);
      }
    });

    testWidgets('第 8 頁按「下一步」進入分流頁（不再直接完成 onboarding）', (tester) async {
      await _pumpOnboarding(tester);
      for (var i = 0; i < 7; i++) {
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

  group('未登入完成 onboarding（onboarding 先於登入，2026-08-18）', () {
    testWidgets('分流答「有」→ 暫存目的地與目標、markCompleted、不直接 push', (tester) async {
      await _pumpOnboarding(tester, loggedIn: false);
      await _swipeToBranchingPage(tester);

      // 先在問卷頁選目標會被暫存——這裡直接按分流即可驗 route 暫存。
      await tester.tap(find.text('有，幫我分析對話'));
      await tester.pumpAndSettle();

      // 未登入：只回到 '/'（真實 app 會被 auth gate 轉去 /login），
      // 不 push 目的地。
      expect(find.text('main-shell'), findsOneWidget);
      expect(find.textContaining('partner-new-screen'), findsNothing);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding_completed'), isTrue);
      // 暫存原樣保存整串（含 next=screenshot），登入後 applier 照原樣 push。
      expect(
        prefs.getString('onboarding_pending_route'),
        '/partner/new?next=screenshot',
      );

      // 暫存取走即清（登入後 MainShell applier 消費的契約）。
      final pending = await OnboardingService.takePendingHandoff();
      expect(pending?.route, '/partner/new?next=screenshot');
      expect(await OnboardingService.takePendingHandoff(), isNull);
    });
  });
}
