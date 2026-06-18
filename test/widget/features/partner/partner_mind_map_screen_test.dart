// test/widget/features/partner/partner_mind_map_screen_test.dart
//
// Hermetic widget tests for PartnerMindMapScreen.
// Mirrors partner_detail_screen_test.dart's ProviderScope-override pattern:
// override the three narrow providers; no Hive required.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/partner_detail_screen.dart';
import 'package:vibesync/features/partner/presentation/screens/partner_mind_map_screen.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_mind_map_view.dart';

Partner _p() => Partner(
      id: 'p1',
      name: 'Alice',
      createdAt: DateTime(2026, 6, 1),
      updatedAt: DateTime(2026, 6, 1),
      ownerUserId: 'u1',
    );

/// 與 mind_map_builder_test 同 shape 的最小可解析快照。
String _snapshot() => jsonEncode({
      'gameStage': {
        'current': 'premise',
        'status': 'normal',
        'nextStep': '約她週末喝咖啡',
      },
      'topicDepth': {'current': 'personal', 'suggestion': ''},
      'strategy': '維持神祕感',
      'targetProfile': {
        'interests': ['爬山'],
        'traits': ['幽默'],
        'notes': <String>[],
      },
    });

Conversation _analyzedConv() => Conversation(
      id: 'c1',
      name: '第 c1 段',
      messages: const [],
      createdAt: DateTime(2026, 6, 1),
      updatedAt: DateTime(2026, 6, 1),
      partnerId: 'p1',
      lastAnalysisSnapshotJson: _snapshot(),
    );

void main() {
  testWidgets('partner missing (deleted/merged) shows fallback, no ghost page',
      (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerByIdProvider('ghost').overrideWith((_) => null),
        partnerAggregateProvider('ghost')
            .overrideWith((_) => PartnerAggregateView.empty()),
        conversationsByPartnerProvider('ghost')
            .overrideWith((_) => const <Conversation>[]),
      ],
      child: const MaterialApp(home: PartnerMindMapScreen(partnerId: 'ghost')),
    ));
    await t.pumpAndSettle();

    expect(find.text('找不到對象（可能已被合併或刪除）'), findsOneWidget);
    expect(find.textContaining('的作戰板'), findsNothing,
        reason: 'null partner must early-return before the map scaffold');
  });

  testWidgets('partner exists, no analysis data → empty state + titled AppBar',
      (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
      ],
      child: const MaterialApp(home: PartnerMindMapScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    expect(find.text('完成一次對話分析，解鎖她的作戰板'), findsOneWidget);
    expect(find.text('Alice 的作戰板'), findsOneWidget);
    expect(find.byType(PartnerMindMapView), findsNothing);
  });

  testWidgets('partner with valid analysis snapshot → renders mind map view',
      (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => [_analyzedConv()]),
      ],
      child: const MaterialApp(home: PartnerMindMapScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    expect(find.byType(PartnerMindMapView), findsOneWidget);
    // premise → '💫 建立男女感'（mind_map_builder：'${stage.emoji} ${stage.label}'）
    expect(find.textContaining('建立男女感'), findsOneWidget);
    expect(find.text('完成一次對話分析，解鎖她的作戰板'), findsNothing);
  });

  testWidgets('內頁底部拆解 panel：關係信號 + 下一步行動全文 + 問教練', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => [_analyzedConv()]),
      ],
      child: const MaterialApp(home: PartnerMindMapScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    expect(find.text('作戰重點'), findsOneWidget);
    expect(find.text('關係信號'), findsOneWidget);
    // 圖節點只放短標籤；全文在 panel 的「下一步行動」列。
    expect(find.text('下一步行動'), findsWidgets);
    expect(find.text('約她週末喝咖啡'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '問教練'), findsOneWidget);
  });

  testWidgets('單擊 nextStep 葉節點 → 導航到對象頁教練跟進區（目的地改自 Coach 1:1）', (t) async {
    final captured = <Uri>[];
    final router = GoRouter(
      initialLocation: '/partner/p1/mindmap',
      routes: [
        GoRoute(
          path: '/partner/:partnerId/mindmap',
          builder: (_, state) => PartnerMindMapScreen(
            partnerId: state.pathParameters['partnerId']!,
          ),
        ),
        GoRoute(
          path: '/partner/:partnerId',
          builder: (_, state) {
            captured.add(state.uri);
            return Scaffold(
              body: Text('對象頁 ${state.pathParameters['partnerId']}'),
            );
          },
        ),
      ],
    );

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => [_analyzedConv()]),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await t.pumpAndSettle();

    // 圖節點短標籤 '下一步行動' 也出現在底部 panel 列，tap 要鎖定圖內節點。
    await t.tap(find.descendant(
      of: find.byType(PartnerMindMapView),
      matching: find.text('下一步行動'),
    ));
    // 單擊與背景雙擊重置並存 → 等競技場 timeout 裁決。
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();

    expect(captured, hasLength(1));
    expect(captured.single.path, '/partner/p1');
    expect(
      captured.single.queryParameters['focus'],
      'coachFollowUp',
    );
    expect(
      captured
          .single.queryParameters[PartnerDetailScreen.focusActionQueryParam],
      PartnerDetailScreen.openCoachInputFocusActionValue,
    );
  });
}
