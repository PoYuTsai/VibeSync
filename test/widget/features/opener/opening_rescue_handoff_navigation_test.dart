// 「她回覆了，開始分析對話」的實際導航／返回堆疊測試
//（Eric-AI 2026-08-26 複審 #39 退回項 3：只驗 handoffLocationFor 回傳的網址
// 抓不到「疊出第二張相同對象卡」與「開場救星留在返回路徑上」這兩個回歸）。
//
// 跑的是真的 GoRouter、真的路由形狀（`/`、`/opener`、`/partner/new`、
// `/partner/:partnerId`），以及真的 production 導航函式
// `OpeningRescueScreen.navigateToHandoff`。斷言對象是堆疊本身：誰不見了、
// 對象卡剩幾張、再按返回會到哪。
//
// 為什麼 `/opener` 掛的是 stub 而不是真的 OpeningRescueScreen：真畫面要先
// 種草稿、按「回看」才進得了結果狀態，而按下 CTA 會觸發一筆 Hive 寫入
// （在草稿上蓋「已接續」章）。那筆真磁碟 I/O 在 testWidgets 的 fake-async
// zone 裡收不掉，實測會讓整支測試卡死到 10 分鐘 timeout（run 33027317044）。
// 導航語意與那筆 bookkeeping 無關，所以這裡只留導航；「CTA 真的接到
// navigateToHandoff」由 test/lint/opener_handoff_cta_wiring_guard_test.dart
// 靜態守門。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:vibesync/features/opener/presentation/screens/opening_rescue_screen.dart';

const _partnerId = 'p-1';

/// 各頁用可辨識的文字，斷言才數得出「對象卡剩幾張」。
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

/// 路由形狀與 lib/app/routes.dart 相同（`/partner/new` 必須排在
/// `/partner/:partnerId` 前面，否則 'new' 會被當成 partnerId 吃掉）。
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
        path: '/partner/new',
        builder: (_, __) => const _Stub('add-partner'),
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

void main() {
  testWidgets('已綁定對象：CTA 回到既有對象卡，不疊出第二張', (t) async {
    final router = await _pump(t);

    // 真實路徑：首頁 → 對象卡 →（分析新片段）→ 開場救星。
    router.push('/partner/$_partnerId');
    await t.pumpAndSettle();
    router.push('/opener?partnerId=$_partnerId');
    await t.pumpAndSettle();

    await _tapCta(t);

    // 開場救星退出堆疊，且只剩原本那一張對象卡（含 offstage：疊上第二張時
    // 舊的那張會變 offstage，不加這個參數就數不到重複）。
    expect(
      find.text('opener', skipOffstage: false),
      findsNothing,
      reason: '開場救星必須整個離開堆疊',
    );
    expect(
      find.text('partner:$_partnerId', skipOffstage: false),
      findsOneWidget,
      reason: '應該是回到既有那張對象卡，不是再 push 一張一模一樣的',
    );

    // 從對象卡按返回＝回首頁。
    router.pop();
    await t.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('未綁定對象：CTA 進新增對象，且開場救星不留在返回路徑上', (t) async {
    final router = await _pump(t);

    router.push('/opener');
    await t.pumpAndSettle();

    await _tapCta(t);

    expect(find.text('add-partner'), findsOneWidget);
    expect(
      find.text('opener', skipOffstage: false),
      findsNothing,
      reason: '開場救星必須整個離開堆疊',
    );

    // 新增對象頁下面是首頁。AddPartnerScreen 建立成功後 pushReplacement 到
    // /partner/:id 取代自己，所以新對象卡按返回同樣會回到首頁。
    router.pop();
    await t.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('深連結直開已綁定對象：沒得 pop 時退回 replace，不留下開場救星', (t) async {
    final router = _router();
    await t.pumpWidget(MaterialApp.router(routerConfig: router));
    await t.pumpAndSettle();

    // 從首頁 go（不是 push）到 opener：堆疊上沒有可 pop 的上一頁。
    router.go('/opener?partnerId=$_partnerId');
    await t.pumpAndSettle();
    expect(router.canPop(), isFalse);

    await _tapCta(t);

    expect(find.text('partner:$_partnerId'), findsOneWidget);
    expect(
      find.text('opener', skipOffstage: false),
      findsNothing,
      reason: '深連結路徑同樣不得把開場救星留在返回路徑上',
    );
  });
}
