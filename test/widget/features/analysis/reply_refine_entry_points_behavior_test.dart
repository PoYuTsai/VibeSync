// 取代 reply_refine_entry_points 的 source scan：以渲染行為釘住
// 「再調一下」的入口配置——每個單一回覆各有一個入口、整組合併的
// 文字沒有入口。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/presentation/screens/analysis_screen.dart';
import 'package:vibesync/features/coaching_memory/data/providers/coaching_outcome_providers.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_repository.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_archive_store.dart'
    show conversationContentRevision;
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

import '../../../helpers/memory_coaching_outcome_repository.dart';

const _conversationId = 'refine-entry-conv';

class _StubConversationRepository extends ConversationRepository {
  _StubConversationRepository(this._conversation);

  final Conversation _conversation;

  @override
  Conversation? getConversation(String id) {
    if (id != _conversation.id) return null;
    return _conversation;
  }

  @override
  Future<void> updateConversation(Conversation c) async {}
}

Map<String, dynamic> _resultJson({
  required String recommendationContent,
  List<Map<String, String>>? replySegments,
}) {
  return {
    'enthusiasm': {'score': 70, 'level': 'warm'},
    'gameStage': {'current': 'premise', 'status': 'normal', 'nextStep': '繼續'},
    'psychology': {'subtext': '有興趣', 'qualificationSignal': true},
    'topicDepth': {'current': 'personal', 'suggestion': '可深入'},
    'replies': {
      'extend': '延伸回覆',
      'resonate': '共鳴回覆',
      'tease': '挑逗回覆',
      'humor': '幽默回覆',
      'coldRead': '冷讀回覆',
    },
    'finalRecommendation': {
      'pick': 'tease',
      'content': recommendationContent,
      'reason': '理由',
      'psychology': '心理',
      if (replySegments != null) 'replySegments': replySegments,
    },
    'strategy': '保持沉穩',
    'reminder': '記得用你的方式說',
  };
}

/// 以「已還原的完成分析」姿態 pump 畫面：snapshot 內嵌 client meta，
/// 還原路徑不需要 archive store，也不會觸發補寫持久化。
Future<void> _pumpWithRestoredResult(
  WidgetTester tester, {
  required String recommendationContent,
  List<Map<String, String>>? replySegments,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 2800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final base = Conversation(
    id: _conversationId,
    name: '小雲',
    messages: [
      Message(
        id: 'm1',
        content: '今天加班好累喔',
        isFromMe: false,
        timestamp: DateTime(2026, 5, 28, 12),
      ),
    ],
    createdAt: DateTime(2026, 5, 28, 12),
    updatedAt: DateTime(2026, 5, 28, 12),
  );
  final snapshot = _resultJson(
    recommendationContent: recommendationContent,
    replySegments: replySegments,
  )..['__vibesync_snapshot_meta_v1'] = {
      'contentRevision': conversationContentRevision(base, messageCount: 1),
      'messageCount': 1,
    };
  final conversation = Conversation(
    id: base.id,
    name: base.name,
    messages: base.messages,
    createdAt: base.createdAt,
    updatedAt: base.updatedAt,
    lastAnalyzedMessageCount: 1,
    lastEnthusiasmScore: 70,
    lastAnalysisSnapshotJson: jsonEncode(snapshot),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coachingOutcomeRepositoryProvider
            .overrideWithValue(MemoryCoachingOutcomeRepository()),
        conversationRepositoryProvider
            .overrideWithValue(_StubConversationRepository(conversation)),
        conversationProvider(_conversationId).overrideWithValue(conversation),
      ],
      child: const MaterialApp(
        home: AnalysisScreen(conversationId: _conversationId),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('單一建議回覆掛一個「再調一下」入口；五張風格卡各有自己的入口', (tester) async {
    await _pumpWithRestoredResult(
      tester,
      recommendationContent: '就用這句回她',
    );

    // AI 推薦回覆（單段）：一個文字入口。
    expect(find.text('再調一下'), findsOneWidget);
    // 風格卡的入口是 icon button（tooltip 同名）。橫向卡列 lazy build，
    // 只驗證已建出的卡都有入口（卡內入口的完整行為由 ReplyStyleCard 自測）。
    expect(find.byTooltip('再調一下'), findsAtLeastNWidgets(3));
  });

  testWidgets('整組合併的文字不給微調：分段各有入口，複製整組按鈕上沒有', (tester) async {
    await _pumpWithRestoredResult(
      tester,
      recommendationContent: '①先接住她的情緒\n②再約週末咖啡',
      replySegments: [
        {'sourceMessage': '今天加班好累喔', 'reply': '先接住她的情緒', 'reason': '共感'},
        {'sourceMessage': '今天加班好累喔', 'reply': '再約週末咖啡', 'reason': '推進'},
      ],
    );

    // 兩個分段各一個入口；沒有第三個屬於整組文字的入口。
    expect(find.text('再調一下'), findsNWidgets(2));

    final copyAll = find.widgetWithText(ElevatedButton, '複製整組訊息');
    expect(copyAll, findsOneWidget);
    expect(
      find.descendant(of: copyAll, matching: find.text('再調一下')),
      findsNothing,
    );
  });
}
