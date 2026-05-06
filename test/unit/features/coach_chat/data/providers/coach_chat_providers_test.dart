import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/coach_chat/data/providers/coach_chat_providers.dart';
import 'package:vibesync/features/coach_chat/data/services/coach_chat_api_service.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_chat_result.dart';
import 'package:vibesync/features/coach_chat/domain/repositories/coach_chat_repository.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation_summary.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/user_profile/data/providers/data_quality_flag_provider.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_data_quality_state.dart';

const _generatedAt = '2026-05-07T12:00:00.000Z';

Message _msg(String content, {bool fromMe = false, DateTime? at}) => Message(
      id: 'm-${content.hashCode}',
      content: content,
      isFromMe: fromMe,
      timestamp: at ?? DateTime(2026, 5, 7, 10),
    );

Conversation _conversation({
  String id = 'c-1',
  String partnerId = 'p-1',
  List<Message> messages = const [],
  List<ConversationSummary>? summaries,
}) {
  final c = Conversation(
    id: id,
    name: 'Mia',
    messages: List.of(messages),
    createdAt: DateTime(2026, 5, 7, 9),
    updatedAt: DateTime(2026, 5, 7, 10),
    ownerUserId: 'u-1',
    partnerId: partnerId,
  );
  if (summaries != null) c.summaries = summaries;
  return c;
}

ConversationSummary _summary(String content) => ConversationSummary(
      id: 's-${content.hashCode}',
      roundsCovered: 8,
      content: content,
      keyTopics: const [],
      sharedInterests: const [],
      relationshipStage: 'warming',
      createdAt: DateTime(2026, 5, 7, 9),
    );

Partner _partner() => Partner(
      id: 'p-1',
      name: 'Mia',
      ownerUserId: 'u-1',
      createdAt: DateTime(2026, 5, 1),
      updatedAt: DateTime(2026, 5, 7),
    );

Map<String, dynamic> _edgeSuccess({
  String headline = '接住她的觀察',
}) {
  return <String, dynamic>{
    'card': <String, dynamic>{
      'mode': 'replyCraft',
      'headline': headline,
      'answer': '她是在丟一個觀察，不是要你立刻證明自己。',
      'userState': '你可能急著解釋，反而把輕鬆感弄重。',
      'nextStep': '承認一半，補一個畫面，再把球丟回她。',
      'suggestedLine': '被妳發現了，我會在飲料櫃前思考人生。妳也是亂逛派嗎？',
      'boundaryReminder': '不要把一句觀察放大成考試。',
      'needsReflection': false,
      'reflectionQuestion': null,
    },
    'provider': 'claude',
    'model': 'claude-sonnet-4-20250514',
    'generatedAt': _generatedAt,
  };
}

class _FakeRepo implements CoachChatRepository {
  final _store = <String, CoachChatResult>{};
  int putCalls = 0;

  void seed(CoachChatResult result) => _store[result.id] = result;

  @override
  List<CoachChatResult> listByConversation(String conversationId) {
    return _store.values
        .where((result) => result.conversationId == conversationId)
        .toList()
      ..sort((a, b) => b.generatedAt.compareTo(a.generatedAt));
  }

  @override
  CoachChatResult? latestForConversation(String conversationId) {
    final list = listByConversation(conversationId);
    return list.isEmpty ? null : list.first;
  }

  @override
  Future<void> put(CoachChatResult result) async {
    putCalls++;
    _store[result.id] = result;
  }

  @override
  Future<void> deleteConversation(String conversationId) async {
    _store.removeWhere((_, result) => result.conversationId == conversationId);
  }

  @override
  Future<void> clearAll() async => _store.clear();
}

class _RecordedCall {
  final String fn;
  final Map<String, dynamic> body;

  const _RecordedCall(this.fn, this.body);
}

CoachChatInvoker _invoker({
  CoachChatInvokeResponse? response,
  List<_RecordedCall>? calls,
  Duration? delay,
}) {
  return (String fn, {required Map<String, dynamic> body}) async {
    calls?.add(_RecordedCall(fn, Map<String, dynamic>.from(body)));
    if (delay != null) await Future.delayed(delay);
    return response ??
        CoachChatInvokeResponse(status: 200, data: _edgeSuccess());
  };
}

ProviderContainer _container({
  required _FakeRepo repo,
  required CoachChatInvoker invoker,
  Conversation? conversation,
  Partner? partner,
  PartnerAggregateView aggregate = const PartnerAggregateView(
    unionInterests: [],
    unionTraits: ['活潑', '慢熟'],
    unionNotes: null,
    latestHeat: 68,
    totalRounds: 5,
    totalMessages: 8,
    lastInteraction: null,
  ),
  DataQualityFlag flag = const DataQualityFlag.unflagged(),
  String? styleContext = '- Preferred voice: 幽默；回覆要輕鬆、有留白',
  Future<void> Function()? usageSync,
}) {
  return ProviderContainer(overrides: [
    coachChatRepositoryProvider.overrideWithValue(repo),
    coachChatApiServiceProvider
        .overrideWithValue(CoachChatApiService(invoker: invoker)),
    coachChatUsageSyncProvider.overrideWithValue(usageSync ?? () async {}),
    conversationProvider('c-1').overrideWithValue(conversation),
    partnerByIdProvider('p-1').overrideWithValue(partner),
    partnerAggregateProvider('p-1').overrideWithValue(aggregate),
    dataQualityFlagProvider('p-1').overrideWithValue(flag),
    coachChatStyleContextResolverProvider.overrideWithValue(({
      required String? partnerId,
      required bool includePartnerOverride,
    }) {
      if (partnerId != 'p-1') return null;
      if (includePartnerOverride == flag.isFlagged) return null;
      return styleContext;
    }),
  ]);
}

CoachChatAnalysisSnapshot _snapshot() => const CoachChatAnalysisSnapshot(
      heatScore: 68,
      stage: 'warming',
      summary: '她丟人格觀察句。',
      nextStep: '承認一半再反問。',
      coachActionType: 'extendTopicStoryFrame',
      keySignals: ['人格觀察', '可接球'],
    );

CoachChatResult _storedResult() => CoachChatResult(
      id: 'old',
      conversationId: 'c-1',
      partnerId: 'p-1',
      question: '她是什麼意思？',
      mode: 'replyCraft',
      headline: '舊答案',
      answer: '舊答案內容',
      userState: '穩住',
      nextStep: '再看',
      boundaryReminder: '不要急',
      needsReflection: false,
      generatedAt: DateTime(2026, 5, 7, 11),
      provider: 'claude',
      modelUsed: 'claude-sonnet-4-20250514',
    );

void main() {
  group('coachChatControllerProvider', () {
    test('build returns the latest stored coach answer', () async {
      final repo = _FakeRepo()..seed(_storedResult());
      final c = _container(repo: repo, invoker: _invoker());
      addTearDown(c.dispose);

      final result = await c.read(coachChatControllerProvider('c-1').future);

      expect(result?.headline, '舊答案');
    });

    test('ask persists the result and sends compact conversation context',
        () async {
      final repo = _FakeRepo();
      final calls = <_RecordedCall>[];
      final c = _container(
        repo: repo,
        invoker: _invoker(calls: calls),
        conversation: _conversation(
          messages: [
            _msg('感覺你是個很有故事的人'),
            _msg('哈哈哪有', fromMe: true),
          ],
          summaries: [_summary('前面在聊旅行和工作生活。')],
        ),
        partner: _partner(),
        styleContext: '- Preferred voice: 幽默；回覆要輕鬆、有留白',
      );
      addTearDown(c.dispose);

      await c.read(coachChatControllerProvider('c-1').future);
      await c.read(coachChatControllerProvider('c-1').notifier).ask(
            question: '她這句話是真的有興趣嗎？',
            analysisSnapshot: _snapshot(),
          );

      final state = c.read(coachChatControllerProvider('c-1'));
      expect(state.value?.headline, '接住她的觀察');
      expect(repo.putCalls, 1);
      expect(calls.single.fn, 'coach-chat');
      expect(
        calls.single.body['effectiveStyleContext'],
        contains('Preferred voice'),
      );
      expect(calls.single.body['partnerHint'], {
        'name': 'Mia',
        'traits': ['活潑', '慢熟'],
      });
      expect(calls.single.body['recentMessages'], [
        {
          'sender': 'partner',
          'text': '感覺你是個很有故事的人',
          'createdAt': isA<String>()
        },
        {'sender': 'me', 'text': '哈哈哪有', 'createdAt': isA<String>()},
      ]);
      expect(calls.single.body['conversationSummary'], '前面在聊旅行和工作生活。');
    });

    test('dataQuality flagged card strips partner traits from the API payload',
        () async {
      final repo = _FakeRepo();
      final calls = <_RecordedCall>[];
      final c = _container(
        repo: repo,
        invoker: _invoker(calls: calls),
        conversation: _conversation(),
        partner: _partner(),
        flag: DataQualityFlag.flagged(NamePair.canonical('Mia', 'Anna')),
        styleContext: null,
      );
      addTearDown(c.dispose);

      await c.read(coachChatControllerProvider('c-1').future);
      await c.read(coachChatControllerProvider('c-1').notifier).ask(
            question: '她到底是誰？',
            analysisSnapshot: _snapshot(),
          );

      expect(calls.single.body['dataQualityFlagged'], isTrue);
      expect(calls.single.body['partnerHint'], {'name': 'Mia'});
      expect(calls.single.body.containsKey('effectiveStyleContext'), isFalse);
    });

    test('success exposes answer before usage refresh completes', () async {
      final repo = _FakeRepo();
      final syncStarted = Completer<void>();
      final syncGate = Completer<void>();
      final c = _container(
        repo: repo,
        invoker: _invoker(),
        conversation: _conversation(),
        partner: _partner(),
        usageSync: () {
          if (!syncStarted.isCompleted) syncStarted.complete();
          return syncGate.future;
        },
      );
      addTearDown(c.dispose);

      await c.read(coachChatControllerProvider('c-1').future);
      final askFuture = c.read(coachChatControllerProvider('c-1').notifier).ask(
            question: '我是不是太急？',
            analysisSnapshot: _snapshot(),
          );

      await syncStarted.future;

      expect(
          c.read(coachChatControllerProvider('c-1')).value?.headline, '接住她的觀察');
      expect(repo.putCalls, 1);

      syncGate.complete();
      await askFuture;
    });

    test('API failure does not persist or refresh usage', () async {
      final repo = _FakeRepo();
      var syncCalls = 0;
      final c = _container(
        repo: repo,
        invoker: _invoker(
          response: const CoachChatInvokeResponse(
            status: 500,
            data: {'error': 'schema_invalid'},
          ),
        ),
        conversation: _conversation(),
        partner: _partner(),
        usageSync: () async => syncCalls++,
      );
      addTearDown(c.dispose);

      await c.read(coachChatControllerProvider('c-1').future);
      await c.read(coachChatControllerProvider('c-1').notifier).ask(
            question: '怎麼辦？',
            analysisSnapshot: _snapshot(),
          );

      expect(c.read(coachChatControllerProvider('c-1')).hasError, isTrue);
      expect(repo.putCalls, 0);
      expect(syncCalls, 0);
    });
  });
}
