// test/widget/features/partner/home_feature_entries_test.dart
//
// 首頁功能入口列（onboarding 轉化 Tier 2 批 1）：
// - 開場救援 → /opener。
// - 問教練＋有對象 → 最近互動對象（partners.first）的 coach 跟進 deep link。
// - 問教練＋沒對象 → /partner/new 建卡。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/partner_detail_screen.dart';
import 'package:vibesync/features/partner/presentation/widgets/home_feature_entries.dart';

Partner _partner(String id, String name) => Partner(
      id: id,
      name: name,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      ownerUserId: 'u-1',
    );

GoRouter _stubRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: HomeFeatureEntries()),
        ),
        GoRoute(
          path: '/opener',
          builder: (_, __) => const Scaffold(body: Text('opener-screen')),
        ),
        // literal '/partner/new' 必須排在 '/partner/:partnerId' 前（同 routes.dart）。
        GoRoute(
          path: '/partner/new',
          builder: (_, __) => const Scaffold(body: Text('partner-new-screen')),
        ),
        GoRoute(
          path: '/partner/:partnerId',
          builder: (_, state) => Scaffold(
            body: Text(
              'partner-detail-${state.pathParameters['partnerId']}'
              '-${state.uri.queryParameters[PartnerDetailScreen.focusQueryParam]}',
            ),
          ),
        ),
      ],
    );

Future<void> _pumpEntries(
  WidgetTester tester, {
  required List<Partner> partners,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [partnerListProvider.overrideWithValue(partners)],
      child: MaterialApp.router(routerConfig: _stubRouter()),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('開場救援 → /opener', (tester) async {
    await _pumpEntries(tester, partners: []);

    await tester.tap(find.text('開場救援'));
    await tester.pumpAndSettle();

    expect(find.text('opener-screen'), findsOneWidget);
  });

  testWidgets('問教練＋有對象 → 最近對象的 coach 跟進 deep link', (tester) async {
    // partnerListProvider 已按最後互動時間降冪，first＝最近互動對象。
    await _pumpEntries(
      tester,
      partners: [_partner('p-recent', '最近的'), _partner('p-old', '老的')],
    );

    await tester.tap(find.text('問教練'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'partner-detail-p-recent-${PartnerDetailScreen.coachFollowUpFocusValue}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('問教練＋沒對象 → /partner/new', (tester) async {
    await _pumpEntries(tester, partners: []);

    await tester.tap(find.text('問教練'));
    await tester.pumpAndSettle();

    expect(find.text('partner-new-screen'), findsOneWidget);
  });
}
