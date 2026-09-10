import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vibesync/features/night_market/presentation/widgets/night_market_entry_card.dart';

void main() {
  testWidgets('entry card navigates to the independent night market route',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: NightMarketEntryCard()),
        ),
        GoRoute(
          path: '/practice-night-market',
          builder: (_, __) => const Scaffold(body: Text('night-market-page')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    expect(find.text('簡易搭訕流程詳解'), findsOneWidget);
    expect(find.text('夜市實戰版：從注意到她到加聯繫方式'), findsOneWidget);
    expect(find.textContaining('2 個選擇'), findsNothing);
    expect(find.text('查看復盤'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('night-market-entry-card')));
    await tester.pumpAndSettle();
    expect(find.text('night-market-page'), findsOneWidget);
  });

  testWidgets('review entry opens without playback and can return or restart',
      (tester) async {
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: NightMarketEntryCard()),
      ),
      GoRoute(
        path: '/practice-night-market',
        builder: (_, __) => const Scaffold(body: Text('night-market-page')),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('查看復盤'));
    await tester.pumpAndSettle();
    expect(find.text('復盤'), findsOneWidget);
    expect(find.text('帶著確信，走過去'), findsOneWidget);
    expect(find.text('night-market-page'), findsNothing);

    await tester.tap(find.byTooltip('回練習室'));
    await tester.pumpAndSettle();
    expect(find.text('查看復盤'), findsOneWidget);
    await tester.tap(find.text('查看復盤'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('再練一次'));
    await tester.tap(find.text('再練一次'));
    await tester.pumpAndSettle();
    expect(find.text('night-market-page'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('查看復盤'), findsOneWidget);
    expect(find.text('復盤'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
