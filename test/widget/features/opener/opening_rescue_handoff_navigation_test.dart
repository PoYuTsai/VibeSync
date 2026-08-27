// 「她回覆了，開始分析對話」的實際導航／返回堆疊測試。
//
// 第一輪（Eric-AI 2026-08-26 退回項 3）：只驗 handoffLocationFor 回傳的網址
// 抓不到「疊出第二張相同對象卡」與「開場救星留在返回路徑上」。
// 第二輪（Eric-AI 2026-08-27）：第一版只建了「理想堆疊」（首頁→對象卡→
// 開場救星），漏掉真正的 production 入口——所以這裡把**每一個**入口都建出來。
//
// 帶 partnerId 的入口（都經由 NewConversationSheet(partnerId) push
// `/opener?partnerId=`）：
//   1. PartnerDetail（對象卡 FAB／空狀態）
//   2. AnalysisScreen（分析頁「分析新片段」）
//   3. PartnerAnalysisArchiveScreen（封存頁）
// 未綁定的入口（push `/opener`）：
//   4. 首頁 HomeFeatureEntries
//   5. ArticleDetailScreen（文章頁「實戰練習」）
// 外加深連結直開 `/opener`（堆疊上沒有可 pop 的上一頁）。
//
// 驗收條件（ADR #44）：所有入口都落到唯一一張對象卡（未綁定則是新增對象頁，
// 建立後由 AddPartnerScreen 自己 pushReplacement 成對象卡），下面是首頁，
// 按返回回首頁；不回舊的分析頁／封存頁／文章頁，也不疊重複對象卡。
//
// 跑的是真的 GoRouter、真的路由形狀與真的 production `navigateToHandoff`。
// `/opener` 掛 stub 的理由見 test/lint/opener_handoff_cta_wiring_guard_test.dart
// 檔頭（真畫面的 CTA 會觸發 Hive 寫入，在 fake-async zone 裡收不掉）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:vibesync/features/opener/presentation/screens/opening_rescue_screen.dart';

const _partnerId = 'p-1';

/// 各頁用可辨識的文字，斷言才數得出「對象卡剩幾張」、「舊頁有沒有留下」。
class _Stub extends StatelessWidget {
  const _Stub(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(label)));
  }
}

/// 開場救星的替身：只保留 CTA，按下去走的是 production 的那一個導航入口。
class _OpenerStub extends StatelessWidget {
  const _OpenerStub({this.partnerId});

  final String? partnerId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('opener'),
            ElevatedButton(
              onPressed: () => OpeningRescueScreen.navigateToHandoff(
                context,
                partnerId: partnerId,
              ),
              child: const Text('她回覆了，開始分析對話'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 路由形狀與 lib/app/routes.dart 相同，含本測試會建到堆疊上的每一個真實入口
/// （`/partner/new` 必須排在 `/partner/:partnerId` 前面，否則 'new' 會被當成
/// partnerId 吃掉）。
GoRouter _router() {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => const _Stub('home')),
      GoRoute(
        path: '/opener',
        builder: (context, state) => _OpenerStub(
          partnerId: state.uri.queryParameters['partnerId'],
        ),
      ),
      GoRoute(
        path: '/conversation/:id',
        builder: (_, state) =>
            _Stub('analysis:${state.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/article/:id',
        builder: (_, state) => _Stub('article:${state.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/partner/new',
        builder: (_, __) => const _Stub('add-partner'),
      ),
      GoRoute(
        path: '/partner/:partnerId/analysis-archive',
        builder: (_, state) =>
            _Stub('archive:${state.pathParameters['partnerId']}'),
      ),
      GoRoute(
        path: '/partner/:partnerId',
        builder: (_, state) =>
            _Stub('partner:${state.pathParameters['partnerId']}'),
      ),
    ],
  );
}

Future<GoRouter> _pump(WidgetTester t) async {
  final router = _router();
  await t.pumpWidget(MaterialApp.router(routerConfig: router));
  await t.pumpAndSettle();
  return router;
}

Future<void> _tapCta(WidgetTester t) async {
  await t.tap(find.text('她回覆了，開始分析對話'));
  await t.pumpAndSettle();
}

/// 堆疊上任何一層都不該再出現這些頁（含 offstage——被蓋住的頁只是 offstage，
/// 不加這個參數就等於沒在數）。
void _expectGone(Iterable<String> labels) {
  for (final label in labels) {
    expect(
      find.text(label, skipOffstage: false),
      findsNothing,
      reason: '$label 不該留在返回路徑上',
    );
  }
}

/// 帶 partnerId 的入口共同驗收：唯一一張對象卡、舊頁全清、返回回首頁。
Future<void> _expectLandsOnPartnerCardOverHome(
  WidgetTester t,
  GoRouter router, {
  required Iterable<String> gone,
}) async {
  expect(
    find.text('partner:$_partnerId', skipOffstage: false),
    findsOneWidget,
    reason: '只能有一張對象卡：疊出第二張時舊的會變 offstage，這裡會抓到兩個',
  );
  _expectGone(['opener', ...gone]);

  router.pop();
  await t.pumpAndSettle();
  expect(find.text('home'), findsOneWidget);
}

void main() {
  group('帶 partnerId 的入口（NewConversationSheet(partnerId) → /opener?partnerId=）',
      () {
    testWidgets('對象卡進來：落到同一張卡，不疊第二張', (t) async {
      final router = await _pump(t);
      router.push('/partner/$_partnerId');
      await t.pumpAndSettle();
      router.push('/opener?partnerId=$_partnerId');
      await t.pumpAndSettle();

      await _tapCta(t);
      await _expectLandsOnPartnerCardOverHome(t, router, gone: const []);
    });

    testWidgets('分析頁進來：落到對象卡，不回舊的分析頁', (t) async {
      final router = await _pump(t);
      router.push('/conversation/c-1');
      await t.pumpAndSettle();
      router.push('/opener?partnerId=$_partnerId');
      await t.pumpAndSettle();

      await _tapCta(t);
      await _expectLandsOnPartnerCardOverHome(
        t,
        router,
        gone: const ['analysis:c-1'],
      );
    });

    testWidgets('封存頁進來：落到對象卡，不回舊的封存頁', (t) async {
      final router = await _pump(t);
      router.push('/partner/$_partnerId/analysis-archive');
      await t.pumpAndSettle();
      router.push('/opener?partnerId=$_partnerId');
      await t.pumpAndSettle();

      await _tapCta(t);
      await _expectLandsOnPartnerCardOverHome(
        t,
        router,
        gone: const ['archive:$_partnerId'],
      );
    });

    testWidgets('深連結直開：沒得 pop 也一樣落到對象卡＋首頁在下面', (t) async {
      final router = await _pump(t);
      router.go('/opener?partnerId=$_partnerId');
      await t.pumpAndSettle();
      expect(router.canPop(), isFalse);

      await _tapCta(t);
      await _expectLandsOnPartnerCardOverHome(t, router, gone: const []);
    });
  });

  group('未綁定的入口（/opener）', () {
    testWidgets('首頁進來：落到新增對象頁，下面是首頁', (t) async {
      final router = await _pump(t);
      router.push('/opener');
      await t.pumpAndSettle();

      await _tapCta(t);

      expect(find.text('add-partner'), findsOneWidget);
      _expectGone(const ['opener']);

      router.pop();
      await t.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('文章頁進來：建立完成後從新對象卡返回是回首頁，不是回文章', (t) async {
      final router = await _pump(t);
      router.push('/article/a-1');
      await t.pumpAndSettle();
      router.push('/opener');
      await t.pumpAndSettle();

      await _tapCta(t);
      expect(find.text('add-partner'), findsOneWidget);
      _expectGone(const ['opener', 'article:a-1']);

      // AddPartnerScreen 建立成功後的動作：pushReplacement 到 /partner/:id
      // 取代自己（lib/features/partner/.../add_partner_screen.dart）。
      router.pushReplacement('/partner/$_partnerId');
      await t.pumpAndSettle();

      await _expectLandsOnPartnerCardOverHome(
        t,
        router,
        gone: const ['article:a-1', 'add-partner'],
      );
    });
  });
}
