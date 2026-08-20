import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_record.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/domain/mindmap/mind_map_builder.dart';
import 'package:vibesync/features/partner/domain/mindmap/mind_map_models.dart';

Conversation _convo({
  required String id,
  required DateTime updatedAt,
  String? snapshotJson,
  String? currentGameStage,
}) =>
    Conversation(
      id: id,
      name: 'c-$id',
      messages: const [],
      createdAt: updatedAt,
      updatedAt: updatedAt,
      currentGameStage: currentGameStage,
      lastAnalysisSnapshotJson: snapshotJson,
    );

String _snapshot({
  String stage = 'premise',
  String nextStep = '約她週末喝咖啡',
  String depth = 'personal',
  String strategy = '維持神秘感',
  String? catchablePoint,
  String confidence = 'high',
}) =>
    jsonEncode({
      'gameStage': {'current': stage, 'status': 'normal', 'nextStep': nextStep},
      'topicDepth': {'current': depth, 'suggestion': ''},
      'strategy': strategy,
      'targetProfile': {
        'provenanceVersion': 1,
        'interests': ['爬山', '咖啡'],
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
          'confidence': confidence,
        },
    });

AnalysisRecord _record({
  required String id,
  required String conversationId,
  required DateTime createdAt,
  required String snapshotJson,
}) =>
    AnalysisRecord(
      id: id,
      ownerUserId: 'u1',
      conversationId: conversationId,
      partnerId: 'p1',
      subjectName: 'Vivi',
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

PartnerAggregateView _aggregate({
  List<String> interests = const ['爬山', '咖啡'],
  List<String> traits = const ['幽默'],
}) =>
    PartnerAggregateView(
      unionInterests: interests,
      unionTraits: traits,
      unionNotes: null,
      latestHeat: null,
      totalRounds: 0,
      totalMessages: 0,
      lastInteraction: null,
    );

void main() {
  group('buildPartnerMindMap', () {
    test('完整快照 → 根節點 + 五主枝', () {
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(),
        conversations: [
          _convo(
              id: 'c1',
              updatedAt: DateTime(2026, 6, 1),
              snapshotJson: _snapshot()),
        ],
      );
      expect(map.hasAnalysisData, isTrue);
      expect(map.root.label, 'Vivi');
      final branches = map.root.children.map((n) => n.branch).toList();
      expect(branches, [
        MindMapBranch.stage,
        MindMapBranch.topicDepth,
        MindMapBranch.interests,
        MindMapBranch.traits,
        MindMapBranch.nextStep,
      ]);
      final stage =
          map.root.children.firstWhere((n) => n.branch == MindMapBranch.stage);
      expect(stage.children.single.label, contains('建立男女感'));
      final depth = map.root.children
          .firstWhere((n) => n.branch == MindMapBranch.topicDepth);
      expect(depth.children.single.label, contains('個人層'));
      final interests = map.root.children
          .firstWhere((n) => n.branch == MindMapBranch.interests);
      expect(interests.children.map((n) => n.label), ['爬山', '咖啡']);
      final next = map.root.children
          .firstWhere((n) => n.branch == MindMapBranch.nextStep);
      // 節點本身改短（IA 去重：不在圖節點塞整句），全文移到 map 詳情欄位。
      expect(next.children.single.label, '下一步行動');
      expect(map.fullNextStep, '約她週末喝咖啡');
      // 關係信號 = 階段描述（premise）；可接話題 = 聚合興趣。
      expect(map.relationshipSignal, contains('男女'));
      expect(map.topics, ['爬山', '咖啡']);
    });

    test('AI oriented 快照在作戰板保留正確話題深度', () {
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(),
        conversations: [
          _convo(
            id: 'c1',
            updatedAt: DateTime(2026, 6, 1),
            snapshotJson: _snapshot(depth: 'Personal-oriented'),
          ),
        ],
      );

      final depth = map.root.children
          .firstWhere((node) => node.branch == MindMapBranch.topicDepth);
      expect(depth.children.single.label, '個人層');
    });

    test('取最新一筆可解析快照（依 updatedAt 降冪）', () {
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(),
        conversations: [
          _convo(
              id: 'old',
              updatedAt: DateTime(2026, 5, 1),
              snapshotJson: _snapshot(stage: 'opening', nextStep: '舊建議')),
          _convo(
              id: 'new',
              updatedAt: DateTime(2026, 6, 1),
              snapshotJson: _snapshot(stage: 'close', nextStep: '新建議')),
        ],
      );
      final stage =
          map.root.children.firstWhere((n) => n.branch == MindMapBranch.stage);
      expect(stage.children.single.label, contains('準備邀約'));
    });

    test('兩次分析顯示上次 → 這次；Conversation 鏡像不會被誤算成第三次', () {
      final oldSnapshot = _snapshot(stage: 'premise', depth: 'event');
      final newSnapshot = _snapshot(
        stage: 'close',
        depth: 'personal',
        catchablePoint: '她說週末想去看展',
      );
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(interests: [], traits: []),
        conversations: [
          _convo(
            id: 'c1',
            updatedAt: DateTime(2026, 6, 2),
            snapshotJson: newSnapshot,
          ),
        ],
        analysisRecords: [
          _record(
            id: 'new',
            conversationId: 'c1',
            createdAt: DateTime(2026, 6, 2),
            snapshotJson: newSnapshot,
          ),
          _record(
            id: 'old',
            conversationId: 'c1',
            createdAt: DateTime(2026, 6, 1),
            snapshotJson: oldSnapshot,
          ),
        ],
      );

      final stage =
          map.root.children.firstWhere((n) => n.branch == MindMapBranch.stage);
      final depth = map.root.children
          .firstWhere((n) => n.branch == MindMapBranch.topicDepth);
      expect(stage.children.single.label, '建立男女感 → 準備邀約');
      expect(depth.children.single.label, '事件層 → 個人層');
      expect(map.currentSignal, '她說週末想去看展');
      expect(map.nextStepSourceConversationId, 'c1');
    });

    test('最近兩次判定相同時，明確標示連續 2 次', () {
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(interests: [], traits: []),
        conversations: const [],
        analysisRecords: [
          _record(
            id: 'new',
            conversationId: 'c2',
            createdAt: DateTime(2026, 6, 2),
            snapshotJson: _snapshot(stage: 'close', depth: 'personal'),
          ),
          _record(
            id: 'old',
            conversationId: 'c1',
            createdAt: DateTime(2026, 6, 1),
            snapshotJson: _snapshot(stage: 'close', depth: 'personal'),
          ),
        ],
      );

      final stage =
          map.root.children.firstWhere((n) => n.branch == MindMapBranch.stage);
      final depth = map.root.children
          .firstWhere((n) => n.branch == MindMapBranch.topicDepth);
      expect(stage.children.single.label, '準備邀約（連續 2 次）');
      expect(depth.children.single.label, '個人層（連續 2 次）');
    });

    test('連續四次判定相同時，顯示實際連續次數', () {
      final snapshot = _snapshot(stage: 'narrative', depth: 'personal');
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(interests: [], traits: []),
        conversations: const [],
        analysisRecords: [
          for (var day = 4; day >= 1; day--)
            _record(
              id: 'record-$day',
              conversationId: 'c1',
              createdAt: DateTime(2026, 6, day),
              snapshotJson: snapshot,
            ),
        ],
      );

      final stage =
          map.root.children.firstWhere((n) => n.branch == MindMapBranch.stage);
      final depth = map.root.children
          .firstWhere((n) => n.branch == MindMapBranch.topicDepth);
      expect(stage.children.single.label, '展現個人魅力（連續 4 次）');
      expect(depth.children.single.label, '個人層（連續 4 次）');
    });

    test('只顯示最新且可用的本輪訊號；低信心訊號 fail closed', () {
      final usable = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(interests: [], traits: []),
        conversations: [
          _convo(
            id: 'c1',
            updatedAt: DateTime(2026, 6, 1),
            snapshotJson: _snapshot(catchablePoint: '她主動提到最近開始爬山'),
          ),
        ],
      );
      final signal = usable.root.children
          .firstWhere((n) => n.branch == MindMapBranch.currentSignal);
      expect(signal.children.single.label, '她主動提到最近開始爬山');
      expect(usable.currentSignal, '她主動提到最近開始爬山');

      final lowConfidence = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(interests: [], traits: []),
        conversations: [
          _convo(
            id: 'c1',
            updatedAt: DateTime(2026, 6, 1),
            snapshotJson: _snapshot(
              catchablePoint: '訊號太少，沒有明確可接球點',
              confidence: 'low',
            ),
          ),
        ],
      );
      expect(
        lowConfidence.root.children.map((n) => n.branch),
        isNot(contains(MindMapBranch.currentSignal)),
      );
      expect(lowConfidence.currentSignal, isNull);
    });

    test('「關於她」只接入 allowlist chips；舊自由文字不進作戰板', () {
      final confirmed = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(interests: [], traits: []),
        conversations: [
          _convo(
            id: 'c1',
            updatedAt: DateTime(2026, 6, 1),
            snapshotJson: _snapshot(),
          ),
        ],
        partnerCustomNote: '慢熱、喜歡旅行',
      );
      final facts = confirmed.root.children
          .firstWhere((n) => n.branch == MindMapBranch.confirmedFacts);
      expect(facts.children.map((n) => n.label), ['慢熱', '喜歡旅行']);
      expect(confirmed.confirmedFacts, ['慢熱', '喜歡旅行']);

      final legacyFreeText = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(interests: [], traits: []),
        conversations: [
          _convo(
            id: 'c1',
            updatedAt: DateTime(2026, 6, 1),
            snapshotJson: _snapshot(),
          ),
        ],
        partnerCustomNote: '她其實很慢熱，可能是內向的人',
      );
      expect(
        legacyFreeText.root.children.map((n) => n.branch),
        isNot(contains(MindMapBranch.confirmedFacts)),
      );
      expect(legacyFreeText.confirmedFacts, isEmpty);
    });

    test('nextStep 空字串 → fallback 到 strategy', () {
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(),
        conversations: [
          _convo(
              id: 'c1',
              updatedAt: DateTime(2026, 6, 1),
              snapshotJson: _snapshot(nextStep: '', strategy: '維持神秘感')),
        ],
      );
      final next = map.root.children
          .firstWhere((n) => n.branch == MindMapBranch.nextStep);
      expect(next.children.single.label, '下一步行動');
      expect(map.fullNextStep, '維持神秘感');
    });

    test('興趣/特質空 → 該枝整枝省略，不產生空枝', () {
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(interests: [], traits: []),
        conversations: [
          _convo(
              id: 'c1',
              updatedAt: DateTime(2026, 6, 1),
              snapshotJson: _snapshot()),
        ],
      );
      final branches = map.root.children.map((n) => n.branch);
      expect(branches, isNot(contains(MindMapBranch.interests)));
      expect(branches, isNot(contains(MindMapBranch.traits)));
    });

    test('無快照但有 currentGameStage → 退化為僅階段枝、hasAnalysisData true', () {
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(interests: [], traits: []),
        conversations: [
          _convo(
              id: 'c1',
              updatedAt: DateTime(2026, 6, 1),
              currentGameStage: 'qualification'),
        ],
      );
      expect(map.hasAnalysisData, isTrue);
      final stage =
          map.root.children.firstWhere((n) => n.branch == MindMapBranch.stage);
      expect(stage.children.single.label, contains('互相評估'));
      expect(map.root.children.map((n) => n.branch),
          isNot(contains(MindMapBranch.nextStep)));
      // 僅 fallback 階段 → 仍有關係信號（階段描述），但無下一步全文。
      expect(map.relationshipSignal, isNotNull);
      expect(map.fullNextStep, isNull);
    });

    test('完全沒分析過 → hasAnalysisData false、不 crash', () {
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: PartnerAggregateView.empty(),
        conversations: [
          _convo(id: 'c1', updatedAt: DateTime(2026, 6, 1)),
        ],
      );
      expect(map.hasAnalysisData, isFalse);
      expect(map.root.children, isEmpty);
    });

    test('malformed JSON 快照 → 安全跳過，不 crash', () {
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: PartnerAggregateView.empty(),
        conversations: [
          _convo(
              id: 'c1',
              updatedAt: DateTime(2026, 6, 1),
              snapshotJson: '{not json'),
        ],
      );
      expect(map.hasAnalysisData, isFalse);
    });

    test('最新快照 malformed、較舊快照可解析 → 用較舊那筆', () {
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(),
        conversations: [
          _convo(
              id: 'old',
              updatedAt: DateTime(2026, 5, 1),
              snapshotJson: _snapshot(stage: 'narrative')),
          _convo(
              id: 'new',
              updatedAt: DateTime(2026, 6, 1),
              snapshotJson: '{not json'),
        ],
      );
      expect(map.hasAnalysisData, isTrue);
      final stage =
          map.root.children.firstWhere((n) => n.branch == MindMapBranch.stage);
      expect(stage.children.single.label, contains('展現個人魅力'));
    });

    test('合法 JSON 但 gameStage 是字串（錯 shape）→ 不 crash，跳過該快照', () {
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: PartnerAggregateView.empty(),
        conversations: [
          _convo(
              id: 'c1',
              updatedAt: DateTime(2026, 6, 1),
              snapshotJson: jsonEncode({'gameStage': 'premise'})),
        ],
      );
      expect(map.hasAnalysisData, isFalse);
    });

    test('nextStepSourceConversationId = 被消費快照的對話 id', () {
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(),
        conversations: [
          _convo(
              id: 'old',
              updatedAt: DateTime(2026, 5, 1),
              snapshotJson: _snapshot(nextStep: '舊建議')),
          _convo(
              id: 'new',
              updatedAt: DateTime(2026, 6, 1),
              snapshotJson: _snapshot(nextStep: '新建議')),
        ],
      );
      expect(map.nextStepSourceConversationId, 'new');
    });

    test('最新快照 malformed → nextStepSourceConversationId 指向實際消費的較舊對話', () {
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(),
        conversations: [
          _convo(
              id: 'old',
              updatedAt: DateTime(2026, 5, 1),
              snapshotJson: _snapshot()),
          _convo(
              id: 'new',
              updatedAt: DateTime(2026, 6, 1),
              snapshotJson: '{not json'),
        ],
      );
      expect(map.nextStepSourceConversationId, 'old');
    });

    test(
        '無可解析快照（僅 currentGameStage fallback）→ nextStepSourceConversationId null',
        () {
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(interests: [], traits: []),
        conversations: [
          _convo(
              id: 'c1',
              updatedAt: DateTime(2026, 6, 1),
              currentGameStage: 'qualification'),
        ],
      );
      expect(map.nextStepSourceConversationId, isNull);
    });

    test('節點 id 全樹唯一（graphview Node.Id 要求）', () {
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(),
        conversations: [
          _convo(
              id: 'c1',
              updatedAt: DateTime(2026, 6, 1),
              snapshotJson: _snapshot()),
        ],
      );
      final ids = <String>[];
      void walk(MindMapNode n) {
        ids.add(n.id);
        n.children.forEach(walk);
      }

      walk(map.root);
      expect(ids.toSet().length, ids.length);
    });
  });
}
