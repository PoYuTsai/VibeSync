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

import 'package:vibesync/features/analysis/data/providers/analysis_record_providers.dart';
import 'package:vibesync/features/analysis/data/repositories/analysis_record_store.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_record.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/partner_mind_map_screen.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_mind_map_view.dart';

Partner _p({String? customNote}) => Partner(
      id: 'p1',
      name: 'Alice',
      createdAt: DateTime(2026, 6, 1),
      updatedAt: DateTime(2026, 6, 1),
      ownerUserId: 'u1',
      customNote: customNote,
    );

/// 與 mind_map_builder_test 同 shape 的最小可解析快照。
String _snapshot({
  String stage = 'premise',
  String depth = 'personal',
  String? catchablePoint,
}) =>
    jsonEncode({
      'gameStage': {
        'current': stage,
        'status': 'normal',
        'nextStep': '約她週末喝咖啡',
      },
      'topicDepth': {'current': depth, 'suggestion': ''},
      'strategy': '維持神祕感',
      'targetProfile': {
        'provenanceVersion': 1,
        'interests': ['爬山'],
        'traits': ['幽默'],
        'notes': <String>[],
      },
      if (catchablePoint != null)
        'coachActionHint': {
          'catchablePoint': catchablePoint,
          'read': '她主動提供了可延伸的具體內容',
          'microMove': '接住這個內容，多問一小步',
          'avoid': '不要突然換話題',
          'actionType': 'extendTopicStoryFrame',
          'confidence': 'high',
        },
    });

Conversation _analyzedConv({String? snapshotJson}) => Conversation(
      id: 'c1',
      name: '第 c1 段',
      messages: const [],
      createdAt: DateTime(2026, 6, 1),
      updatedAt: DateTime(2026, 6, 1),
      partnerId: 'p1',
      lastAnalysisSnapshotJson: snapshotJson ?? _snapshot(),
    );

AnalysisRecord _record({
  required String id,
  required DateTime createdAt,
  required String snapshotJson,
}) =>
    AnalysisRecord(
      id: id,
      ownerUserId: 'u1',
      conversationId: 'c1',
      partnerId: 'p1',
      subjectName: 'Alice',
      segmentStart: 0,
      segmentEnd: 1,
      createdAt: createdAt,
      messages: [
        AnalysisRecordMessage(
          id: 'm-$id',
          content: '測試訊息',
          isFromMe: false,
          timestamp: createdAt,
        ),
      ],
      analysisSnapshotJson: snapshotJson,
      analyzedContentRevision: 'revision-$id',
      completionKey: 'completion-$id',
      sourcePlatform: 'LINE',
      enthusiasmScore: 60,
      gameStageLabel: '測試階段',
    );

class _StaticAnalysisRecordStore extends Fake implements AnalysisRecordStore {
  _StaticAnalysisRecordStore(this.records);

  final List<AnalysisRecord> records;

  @override
  List<AnalysisRecord> listArchived({
    required String ownerUserId,
    required Iterable<String> conversationIds,
  }) {
    final ids = conversationIds.toSet();
    return records
        .where(
          (record) =>
              record.ownerUserId == ownerUserId &&
              ids.contains(record.conversationId),
        )
        .toList(growable: false);
  }

  @override
  AnalysisRecord? currentFor({
    required String ownerUserId,
    required String conversationId,
  }) =>
      null;
}

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
    // premise →「建立男女感」。
    expect(find.textContaining('建立男女感'), findsOneWidget);
    expect(find.text('完成一次對話分析，解鎖她的作戰板'), findsNothing);
  });

  testWidgets('作戰板接入真實分析歷史、最新訊號與使用者確認 chips', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final oldSnapshot = _snapshot(stage: 'premise', depth: 'event');
    final newSnapshot = _snapshot(
      stage: 'close',
      depth: 'personal',
      catchablePoint: '她說週末想去看展',
    );
    final records = [
      _record(
        id: 'new',
        createdAt: DateTime(2026, 6, 2),
        snapshotJson: newSnapshot,
      ),
      _record(
        id: 'old',
        createdAt: DateTime(2026, 6, 1),
        snapshotJson: oldSnapshot,
      ),
    ];

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerByIdProvider('p1')
            .overrideWith((_) => _p(customNote: '慢熱、喜歡旅行')),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => [_analyzedConv(snapshotJson: newSnapshot)]),
        analysisRecordOwnerProvider.overrideWithValue('u1'),
        analysisRecordStoreProvider
            .overrideWithValue(_StaticAnalysisRecordStore(records)),
      ],
      child: const MaterialApp(home: PartnerMindMapScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    expect(find.text('Alice・已分析 2 次'), findsOneWidget);
    expect(find.text('準備邀約'), findsOneWidget);
    expect(find.text('歷程：建立男女感 → 準備邀約'), findsOneWidget);
    expect(find.text('個人層'), findsOneWidget);
    expect(find.text('歷程：事件層 → 個人層'), findsOneWidget);
    expect(find.text('互動脈絡'), findsOneWidget);
    expect(find.text('本輪｜她說週末想去看展'), findsOneWidget);
    expect(find.text('上輪｜她說：「測試訊息」'), findsOneWidget);
    expect(find.text('她說週末想去看展'), findsWidgets);
    expect(find.text('關於她（已確認）'), findsOneWidget);
    expect(find.text('慢熱'), findsOneWidget);
    expect(find.text('喜歡旅行'), findsOneWidget);
  });

  testWidgets('內頁底部拆解 panel：互動重點 + 下一步行動全文 + 問教練', (t) async {
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
    expect(find.text('互動重點'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PartnerMindMapView),
        matching: find.text('本輪更新｜約她週末喝咖啡'),
      ),
      findsOneWidget,
      reason: '使用者打開作戰板就能在心智圖看到完整下一步，不必點節點',
    );
    // 底部既有作戰重點仍保留純全文，作為大字摘要與問教練入口。
    expect(find.text('約她週末喝咖啡'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '問教練'), findsOneWidget);
  });

  testWidgets('單擊 nextStep 葉節點 → 直達問教練 Sydney 視窗（鎖定本對象）', (t) async {
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
          path: '/coach',
          builder: (_, state) {
            captured.add(state.uri);
            return Scaffold(
              body: Text(
                '教練視窗 ${state.uri.queryParameters['partnerId']}',
              ),
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

    // 完整下一步已直接顯示在圖內；tap 只是額外問教練入口，不是閱讀必要步驟。
    await t.tap(find.descendant(
      of: find.byType(PartnerMindMapView),
      matching: find.text('本輪更新｜約她週末喝咖啡'),
    ));
    // 單擊與背景雙擊重置並存 → 等競技場 timeout 裁決。
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();

    expect(captured, hasLength(1));
    expect(captured.single.path, '/coach');
    expect(captured.single.queryParameters['partnerId'], 'p1');
  });
}
