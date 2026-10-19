// 結果頁的關係狀態卡與「為什麼這樣回」走真的 AnalysisScreen（Bruce 2026-10-19 路線二，A3）：
// 分析完成時畫在判讀下面與每張卡下面，存進快照；重開畫面從快照還原照樣看得到。
// 三種情況：v3 帶關係狀態、v3 沒帶（改版前）、v2。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/analysis/data/notifiers/streaming_analyze_notifier.dart';
import 'package:vibesync/features/analysis/data/providers/analysis_providers.dart';
import 'package:vibesync/features/analysis/data/services/analyze_stream_client.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/domain/entities/game_stage.dart';
import 'package:vibesync/features/analysis/domain/entities/guide_v3_result.dart';
import 'package:vibesync/features/analysis/presentation/helpers/analysis_stream_content_display.dart';
import 'package:vibesync/features/analysis/presentation/screens/analysis_screen.dart';
import 'package:vibesync/features/analysis_history/data/providers/analysis_history_providers.dart';
import 'package:vibesync/features/coach_chat/data/providers/coach_chat_providers.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_chat_result.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_scope.dart';
import 'package:vibesync/features/coach_chat/domain/entities/unified_coach_result.dart';
import 'package:vibesync/features/coach_chat/domain/repositories/coach_chat_repository.dart';
import 'package:vibesync/features/coaching_memory/data/providers/coaching_outcome_providers.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_archive_providers.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_archive_store.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_repository.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

import '../../../helpers/memory_analysis_history_repository.dart';
import '../../../helpers/memory_coaching_outcome_repository.dart';

const _conversationId = 'relation-result';

class _SeededStreamingAnalyzeNotifier extends StreamingAnalyzeNotifier {
  _SeededStreamingAnalyzeNotifier(this.seed);
  final StreamingAnalysisState seed;

  @override
  StreamingAnalysisState build(String conversationId) => seed;
}

class _InertAnalyzeStreamClient extends AnalyzeStreamClient {
  _InertAnalyzeStreamClient()
      : super(displayMapper: const AnalysisStreamContentDisplayMapper());

  @override
  Stream<AnalysisStreamUpdate> stream(AnalyzeStreamRequest request) =>
      const Stream.empty();
}

class _StubConversationRepository extends ConversationRepository {
  _StubConversationRepository(this.conversation);
  Conversation conversation;

  @override
  Conversation? getConversation(String id) =>
      id == conversation.id ? conversation : null;

  @override
  List<Conversation> listByPartner(String partnerId) => const [];

  @override
  Future<void> updateConversation(Conversation c) async {
    conversation = c;
  }
}

class _MemoryConversationArchiveStore implements ConversationArchiveStore {
  final Map<String, ConversationArchiveEntry> entries = {};

  @override
  ConversationArchiveEntry? entryFor(Conversation conversation) =>
      entries[conversation.id];

  @override
  Future<void> markActive(
    Conversation conversation, {
    DateTime? changedAt,
    String? analyzedContentRevision,
  }) async {
    entries[conversation.id] = ConversationArchiveEntry.active(
      changedAt: changedAt ?? DateTime.now(),
      contentRevision: analyzedContentRevision,
    );
  }

  @override
  Future<void> markArchived(
    Conversation conversation, {
    required DateTime archivedAt,
  }) async {}

  @override
  Future<void> remove(Conversation conversation) async {}
}

class _EmptyCoachChatRepository extends CoachChatRepository {
  @override
  List<CoachChatResult> listByConversation(String conversationId) => const [];
  @override
  CoachChatResult? latestForConversation(String conversationId) => null;
  @override
  Future<void> put(CoachChatResult result) async {}
  @override
  Future<ConversationDeleteOutcome> deleteConversation(
    String conversationId,
  ) async =>
      const ConversationDeleteOutcome(
        deleted: true,
        deletedOwnerUserId: 'stub-owner',
      );
  @override
  Future<void> clearAll() async {}
  @override
  List<UnifiedCoachResult> listByScope(String scopeType, String scopeId) =>
      const [];
  @override
  UnifiedCoachResult? latestForScope(String scopeType, String scopeId) => null;
  @override
  Future<void> putUnified(UnifiedCoachResult result) async {}
  @override
  Future<void> deleteScope(String scopeType, String scopeId) async {}
  @override
  Future<bool> deleteUnified(String id) async => false;
}

Conversation _conversation() => Conversation(
      id: _conversationId,
      name: '小安',
      messages: [
        Message(
          id: 'm1',
          content: '真的超好吃 你品味不錯欸',
          isFromMe: false,
          timestamp: DateTime(2026, 10, 19, 20),
        ),
      ],
      createdAt: DateTime(2026, 10, 19, 20),
      updatedAt: DateTime(2026, 10, 19, 20),
    );

const _relation = <String, dynamic>{
  'stage': 'premise',
  'heat': 72,
  'dimensions': {
    'heat': 72,
    'engagement': 70,
    'topicDepth': 45,
    'replyWillingness': 78,
    'emotionalConnection': 60,
  },
  'herMove': 'high_point',
  'willingness': 'high',
};

/// 形狀照伺服器 guide_v3/wire.ts 的 finalResult（已剝掉伺服器專用欄位）。
GuideV3Result _v3({Map<String, dynamic>? relation}) => GuideV3Result.fromJson({
      'guideVersion': 'v3.6',
      'read': {
        'guideVersion': 'v3.6',
        'decision': 'send',
        'light': 'green',
        'judgment': '她主動回來聊，還記得你說過的店。',
        'inviteReadiness': 'none',
        if (relation != null) 'relation': relation,
        'plannedCards': [
          {'slot': 1, 'task': 'accept', 'locked': false},
          {'slot': 2, 'task': 'resonate', 'locked': false},
        ],
      },
      'cards': [
        for (final (slot, task, text) in [
          (1, 'accept', '那當然 我挑的欸'),
          (2, 'resonate', '吃到好吃的那種開心我懂'),
        ])
          {
            'slot': slot,
            'task': task,
            'method': 'reaction',
            'voice': 'default',
            'messages': [text],
            'hasInventedDetail': false,
            'hasBlank': false,
          },
      ],
      'partial': false,
      'usage': {'messagesUsed': 1, 'shouldChargeQuota': true},
    })!;

/// 串流收到的說明在 done 時由 notifier 併進結果（見 streaming_analyze_notifier）。
const _explains = {1: '接住她誇你，用短短一句收下。'};

StreamingAnalysisState _done(Conversation conversation, GuideV3Result result) =>
    StreamingAnalysisState(
      phase: StreamingAnalyzePhase.done,
      analysisRunId: 'run_relation',
      isGuideV3Run: true,
      guideV3Read: result.read,
      guideV3Cards: result.cards,
      guideV3Result: result,
      guideV3CardExplains: result.cardExplains,
      previousAnalyzedCount: 0,
      analyzedMessageCount: conversation.messages.length,
      conversationMessageCount: conversation.messages.length,
      conversationContentRevision: conversationContentRevision(conversation),
      isReconnectContext: false,
    );

Future<_StubConversationRepository> _pump(
  WidgetTester tester, {
  required Conversation conversation,
  required StreamingAnalysisState seed,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final repository = _StubConversationRepository(conversation);
  // 換一個 ProviderScope 前先清空，overrides 的數量不同會出錯。
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coachingOutcomeRepositoryProvider
            .overrideWithValue(MemoryCoachingOutcomeRepository()),
        analysisHistoryRepositoryProvider
            .overrideWithValue(MemoryAnalysisHistoryRepository()),
        conversationArchiveStoreProvider
            .overrideWithValue(_MemoryConversationArchiveStore()),
        conversationRepositoryProvider.overrideWithValue(repository),
        conversationProvider(_conversationId).overrideWithValue(conversation),
        analyzeStreamClientProvider
            .overrideWithValue(_InertAnalyzeStreamClient()),
        coachChatRepositoryProvider
            .overrideWithValue(_EmptyCoachChatRepository()),
        coachChatHistoryProvider(const CoachScope.conversation(_conversationId))
            .overrideWithValue(const []),
        streamingAnalyzeProvider
            .overrideWith(() => _SeededStreamingAnalyzeNotifier(seed)),
      ],
      child: const MaterialApp(
        home: AnalysisScreen(conversationId: _conversationId),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  tester.takeException();
  return repository;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('v3 帶了關係狀態：判讀下面有關係狀態卡、卡下面有為什麼這樣回；存進快照，重開畫面照樣在', (tester) async {
    final conversation = _conversation();
    final result = _v3(relation: _relation).withCardExplains(_explains);
    final repository = await _pump(
      tester,
      conversation: conversation,
      seed: _done(conversation, result),
    );

    expect(find.byKey(const ValueKey('guide-v3-relation')), findsOneWidget);
    expect(find.text('分享開心的事'), findsOneWidget);
    expect(find.text('還沒提過見面'), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-v3-card-1-why')), findsOneWidget);
    expect(find.text('接住她誇你，用短短一句收下。'), findsOneWidget);
    // v2 的詳細分析不會因為有熱度就跑出來。
    expect(find.text('詳細分析'), findsNothing);

    final saved = repository.conversation;
    expect(saved.lastEnthusiasmScore, 65);
    expect(saved.currentGameStage, GameStage.premise.name);
    final snapshot =
        jsonDecode(saved.lastAnalysisSnapshotJson!) as Map<String, dynamic>;
    expect((snapshot['read'] as Map)['relation'], _relation);
    expect(snapshot[guideV3CardExplainsKey], [
      {'card': 1, 'text': '接住她誇你，用短短一句收下。'},
    ]);

    // 重開畫面：從存好的快照還原。
    await _pump(
      tester,
      conversation: saved,
      seed: const StreamingAnalysisState.idle(),
    );
    expect(find.byKey(const ValueKey('guide-v3-relation')), findsOneWidget);
    expect(find.text('分享開心的事'), findsOneWidget);
    expect(find.text('接住她誇你，用短短一句收下。'), findsOneWidget);
  });

  testWidgets('改版前的 v3（沒帶關係狀態、沒有說明）：結果頁照舊，沒有關係狀態卡與為什麼這樣回', (tester) async {
    final conversation = _conversation();
    final repository = await _pump(
      tester,
      conversation: conversation,
      seed: _done(conversation, _v3()),
    );

    expect(find.text('局面判讀'), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-v3-relation')), findsNothing);
    expect(find.text('為什麼這樣回'), findsNothing);
    expect(find.text('詳細分析'), findsNothing);
    expect(repository.conversation.lastEnthusiasmScore, isNull);
  });

  testWidgets('v2 結果：照舊是詳細分析，沒有關係狀態卡', (tester) async {
    final conversation = _conversation();
    final v2 = AnalysisResult.fromJson({
      'enthusiasm': {'score': 65, 'level': 'warm'},
      'gameStage': {
        'current': 'premise',
        'status': 'normal',
        'nextStep': '維持輕鬆互動',
      },
      'psychology': {'subtext': '她有興趣'},
      'topicDepth': {'current': 'event', 'suggestion': '先聊細節'},
      'replies': {'extend': '妳點了哪一碗？'},
      'finalRecommendation': {
        'pick': 'extend',
        'content': '妳點了哪一碗？',
        'reason': '接住分享',
        'psychology': '她想被接住',
      },
      'strategy': '先接住她的分享',
    });
    await _pump(
      tester,
      conversation: conversation,
      seed: StreamingAnalysisState(
        phase: StreamingAnalyzePhase.done,
        result: v2,
        analysisRunId: 'run_v2',
        previousAnalyzedCount: 0,
        analyzedMessageCount: conversation.messages.length,
        conversationMessageCount: conversation.messages.length,
        conversationContentRevision: conversationContentRevision(conversation),
        isReconnectContext: false,
      ),
    );

    expect(find.text('詳細分析'), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-v3-relation')), findsNothing);
    expect(find.text('關係狀態'), findsNothing);
  });
}
