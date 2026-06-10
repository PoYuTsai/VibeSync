import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
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
}) =>
    jsonEncode({
      'gameStage': {'current': stage, 'status': 'normal', 'nextStep': nextStep},
      'topicDepth': {'current': depth, 'suggestion': ''},
      'strategy': strategy,
      'targetProfile': {
        'interests': ['爬山', '咖啡'],
        'traits': ['幽默'],
        'notes': <String>[],
      },
    });

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
      expect(next.children.single.label, '約她週末喝咖啡');
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
      expect(next.children.single.label, '維持神秘感');
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
