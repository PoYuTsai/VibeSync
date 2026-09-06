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
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    expect(find.text('和 Sydney 逛夜市'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('night-market-entry-card')));
    await tester.pumpAndSettle();
    expect(find.text('night-market-page'), findsOneWidget);
  });
}
