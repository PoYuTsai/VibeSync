import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_record.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/domain/mindmap/mind_map_builder.dart';
import 'package:vibesync/features/partner/domain/mindmap/mind_map_models.dart';

Conversation _convo({
  required String id,
  required DateTime updatedAt,
  String? snapshotJson,
  String? currentGameStage,
  List<Message> messages = const [],
}) =>
    Conversation(
      id: id,
      name: 'c-$id',
      messages: messages,
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
  String message = '測試訊息',
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
          content: message,
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
    test('第一次分析直接顯示分析次數與本輪互動脈絡', () {
      final snapshot = _snapshot(
        catchablePoint: '她主動提到最近開始爬山',
      );
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(interests: [], traits: []),
        conversations: const [],
        analysisRecords: [
          _record(
            id: 'first',
            conversationId: 'c1',
            createdAt: DateTime(2026, 6, 1),
            snapshotJson: snapshot,
          ),
        ],
      );

      expect(map.root.label, 'Vivi・已分析 1 次');
      final history = map.root.children.firstWhere(
        (node) => node.branch == MindMapBranch.interactionHistory,
      );
      expect(history.label, '互動脈絡');
      expect(history.children.single.label, '本輪｜她主動提到最近開始爬山');
    });

    test('第二、三次分析依序顯示本輪、上輪、上上輪', () {
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(interests: [], traits: []),
        conversations: const [],
        analysisRecords: [
          _record(
            id: 'third',
            conversationId: 'c3',
            createdAt: DateTime(2026, 6, 3),
            snapshotJson: _snapshot(catchablePoint: '主動分享最近開始爬山'),
          ),
          _record(
            id: 'second',
            conversationId: 'c2',
            createdAt: DateTime(2026, 6, 2),
            snapshotJson: _snapshot(catchablePoint: '聊到週末常去看展'),
          ),
          _record(
            id: 'first',
            conversationId: 'c1',
            createdAt: DateTime(2026, 6, 1),
            snapshotJson: _snapshot(catchablePoint: '回覆你的加班故事'),
          ),
        ],
      );

      final history = map.root.children.firstWhere(
        (node) => node.branch == MindMapBranch.interactionHistory,
      );
      expect(history.children.map((node) => node.label), [
        '本輪｜主動分享最近開始爬山',
        '上輪｜聊到週末常去看展',
        '上上輪｜回覆你的加班故事',
      ]);
    });

    test('第四次以後只展開最近三次，較舊分析濃縮成可讀歷程', () {
      const stagesOldestFirst = [
        'opening',
        'premise',
        'premise',
        'narrative',
        'narrative',
        'narrative',
        'narrative',
        'narrative',
      ];
      const depthsOldestFirst = [
        'event',
        'event',
        'personal',
        'personal',
        'personal',
        'personal',
        'personal',
        'personal',
      ];
      final records = [
        for (var day = 8; day >= 1; day--)
          _record(
            id: 'record-$day',
            conversationId: 'c$day',
            createdAt: DateTime(2026, 6, day),
            snapshotJson: _snapshot(
              stage: stagesOldestFirst[day - 1],
              depth: depthsOldestFirst[day - 1],
              catchablePoint: '第 $day 次互動',
            ),
          ),
      ];

      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(interests: [], traits: []),
        conversations: const [],
        analysisRecords: records,
      );

      expect(map.root.label, 'Vivi・已分析 8 次');
      final history = map.root.children.firstWhere(
        (node) => node.branch == MindMapBranch.interactionHistory,
      );
      expect(history.children, hasLength(4));
      expect(history.children.take(3).map((node) => node.label), [
        '本輪｜第 8 次互動',
        '上輪｜第 7 次互動',
        '上上輪｜第 6 次互動',
      ]);
      expect(
        history.children.last.label,
        '前 5 次｜關係：破冰階段 → 建立男女感 → 展現個人魅力；話題：事件層 → 個人層',
      );
    });

    test('分析沒有高信心訊號時，互動脈絡退回真實聊天摘錄而不消失', () {
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(interests: [], traits: []),
        conversations: const [],
        analysisRecords: [
          _record(
            id: 'record-1',
            conversationId: 'c1',
            createdAt: DateTime(2026, 6, 1),
            snapshotJson: _snapshot(),
            message: '我最近開始養一隻貓',
          ),
        ],
      );

      final history = map.root.children.firstWhere(
        (node) => node.branch == MindMapBranch.interactionHistory,
      );
      expect(history.children.single.label, '本輪｜她說：「我最近開始養一隻貓」');
      expect(map.currentSignal, isNull, reason: '聊天摘錄只能補歷史節點，不能偽裝成模型確認的本輪訊號');
    });

    test('舊版只有 Conversation 快照時，也用真實聊天補上互動脈絡', () {
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(interests: [], traits: []),
        conversations: [
          _convo(
            id: 'legacy',
            updatedAt: DateTime(2026, 6, 1),
            snapshotJson: _snapshot(),
            messages: [
              Message(
                id: 'm1',
                content: '週末跟朋友去看展了',
                isFromMe: false,
                timestamp: DateTime(2026, 6, 1),
              ),
            ],
          ),
        ],
      );

      final history = map.root.children.firstWhere(
        (node) => node.branch == MindMapBranch.interactionHistory,
      );
      expect(history.children.single.label, '本輪｜她說：「週末跟朋友去看展了」');
    });

    test('關係階段與話題深度分開顯示目前狀態和累積歷程', () {
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(interests: [], traits: []),
        conversations: const [],
        analysisRecords: [
          _record(
            id: 'new',
            conversationId: 'c3',
            createdAt: DateTime(2026, 6, 3),
            snapshotJson: _snapshot(stage: 'narrative', depth: 'personal'),
          ),
          _record(
            id: 'middle',
            conversationId: 'c2',
            createdAt: DateTime(2026, 6, 2),
            snapshotJson: _snapshot(stage: 'premise', depth: 'event'),
          ),
          _record(
            id: 'old',
            conversationId: 'c1',
            createdAt: DateTime(2026, 6, 1),
            snapshotJson: _snapshot(stage: 'opening', depth: 'event'),
          ),
        ],
      );

      final stage = map.root.children.firstWhere(
        (node) => node.branch == MindMapBranch.stage,
      );
      expect(stage.children.map((node) => node.label), [
        '展現個人魅力',
        '歷程：破冰階段 → 建立男女感 → 展現個人魅力',
      ]);

      final depth = map.root.children.firstWhere(
        (node) => node.branch == MindMapBranch.topicDepth,
      );
      expect(depth.children.map((node) => node.label), [
        '個人層',
        '歷程：事件層 → 個人層',
      ]);
    });

    test('判定反覆變動時濃縮歷程，避免心智圖節點無限變長', () {
      const stagesOldestFirst = [
        'opening',
        'premise',
        'qualification',
        'narrative',
        'close',
        'opening',
      ];
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(interests: [], traits: []),
        conversations: const [],
        analysisRecords: [
          for (var day = 6; day >= 1; day--)
            _record(
              id: 'record-$day',
              conversationId: 'c$day',
              createdAt: DateTime(2026, 6, day),
              snapshotJson: _snapshot(stage: stagesOldestFirst[day - 1]),
            ),
        ],
      );

      final stage = map.root.children.firstWhere(
        (node) => node.branch == MindMapBranch.stage,
      );
      expect(
        stage.children.last.label,
        '歷程：破冰階段 → … → 準備邀約 → 破冰階段',
      );
    });

    test('下一步直接顯示全文，並標示本輪沿用上次建議', () {
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(interests: [], traits: []),
        conversations: const [],
        analysisRecords: [
          _record(
            id: 'new',
            conversationId: 'c2',
            createdAt: DateTime(2026, 6, 2),
            snapshotJson: _snapshot(nextStep: '延續爬山話題，再自然邀約喝咖啡'),
          ),
          _record(
            id: 'old',
            conversationId: 'c1',
            createdAt: DateTime(2026, 6, 1),
            snapshotJson: _snapshot(nextStep: '延續爬山話題，再自然邀約喝咖啡'),
          ),
        ],
      );

      final next = map.root.children.firstWhere(
        (node) => node.branch == MindMapBranch.nextStep,
      );
      expect(
        next.children.single.label,
        '沿用上輪｜延續爬山話題，再自然邀約喝咖啡',
      );
      expect(map.fullNextStep, '延續爬山話題，再自然邀約喝咖啡');
    });

    test('完整快照 → 根節點 + 五主枝', () {
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(),
        conversations: [
          _convo(
              id: 'c1',
              updatedAt: DateTime(2026, 6, 1),
              snapshotJson: _snapshot(catchablePoint: '她主動分享爬山計畫')),
        ],
        partnerCustomNote: '慢熱、喜歡旅行',
      );
      expect(map.hasAnalysisData, isTrue);
      expect(map.root.label, 'Vivi・已分析 1 次');
      final branches = map.root.children.map((n) => n.branch).toList();
      expect(branches, [
        MindMapBranch.stage,
        MindMapBranch.topicDepth,
        MindMapBranch.interactionHistory,
        MindMapBranch.confirmedFacts,
        MindMapBranch.nextStep,
      ]);
      final stage =
          map.root.children.firstWhere((n) => n.branch == MindMapBranch.stage);
      expect(stage.children.single.label, contains('建立男女感'));
      final depth = map.root.children
          .firstWhere((n) => n.branch == MindMapBranch.topicDepth);
      expect(depth.children.single.label, contains('個人層'));
      final facts = map.root.children
          .firstWhere((n) => n.branch == MindMapBranch.confirmedFacts);
      expect(facts.label, '關於她（已確認）');
      expect(facts.children.map((n) => n.label), ['慢熱', '喜歡旅行']);
      final next = map.root.children
          .firstWhere((n) => n.branch == MindMapBranch.nextStep);
      expect(next.children.single.label, '本輪更新｜約她週末喝咖啡');
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
      expect(stage.children.first.label, '準備邀約');
      expect(
        stage.children.last.label,
        '歷程：破冰階段 → 準備邀約',
      );
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
      expect(stage.children.first.label, '準備邀約');
      expect(stage.children.last.label, '歷程：建立男女感 → 準備邀約');
      expect(depth.children.first.label, '個人層');
      expect(depth.children.last.label, '歷程：事件層 → 個人層');
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
      final history = usable.root.children
          .firstWhere((n) => n.branch == MindMapBranch.interactionHistory);
      expect(history.children.single.label, '本輪｜她主動提到最近開始爬山');
      expect(
        usable.root.children.map((node) => node.branch),
        isNot(contains(MindMapBranch.currentSignal)),
      );
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
      final lowConfidenceHistory = lowConfidence.root.children.firstWhere(
        (node) => node.branch == MindMapBranch.interactionHistory,
      );
      expect(
        lowConfidenceHistory.children.single.label,
        '本輪｜沒有足夠可確認的聊天摘錄',
      );
      expect(
        lowConfidenceHistory.children.single.branch,
        MindMapBranch.interactionHistory,
        reason: '沒有可信訊號時不能用橘色假裝成「本輪訊號」',
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
      final emptyFacts = legacyFreeText.root.children.firstWhere(
        (node) => node.branch == MindMapBranch.confirmedFacts,
      );
      expect(emptyFacts.label, '關於她（已確認）');
      expect(emptyFacts.children.single.label, '尚無已確認資料');
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
      expect(next.children.single.label, '本輪更新｜維持神秘感');
      expect(map.fullNextStep, '維持神秘感');
    });

    test('沒有確認 chips 時仍保留關於她主枝，但不帶入 AI 興趣或特質', () {
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(
          interests: ['爬山'],
          traits: ['很負責任'],
        ),
        conversations: [
          _convo(
              id: 'c1',
              updatedAt: DateTime(2026, 6, 1),
              snapshotJson: _snapshot()),
        ],
      );
      final branches = map.root.children.map((n) => n.branch).toList();
      expect(branches, contains(MindMapBranch.confirmedFacts));
      expect(branches, isNot(contains(MindMapBranch.interests)));
      expect(branches, isNot(contains(MindMapBranch.traits)));
      final facts = map.root.children.firstWhere(
        (node) => node.branch == MindMapBranch.confirmedFacts,
      );
      expect(facts.label, '關於她（已確認）');
      expect(facts.children.single.label, '尚無已確認資料');
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
