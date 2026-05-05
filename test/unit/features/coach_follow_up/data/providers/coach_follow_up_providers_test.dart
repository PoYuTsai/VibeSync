// Spec 5 C20 — coach-follow-up Riverpod providers TDD spec.
//
// Wires together the C17 partnerHint helper, C18 hint resolver, C19 API
// service, and B13 repository into the provider graph the UI will consume.
// Privacy contract carries through: partnerHintProvider is the SOLE place
// the API hint is built (via the C17 helper), and the controller is the
// SOLE writer to the local Hive box.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/game_stage.dart';
import 'package:vibesync/features/coach_follow_up/data/providers/coach_follow_up_providers.dart';
import 'package:vibesync/features/coach_follow_up/data/services/coach_follow_up_api_service.dart';
import 'package:vibesync/features/coach_follow_up/domain/entities/coach_follow_up_phase.dart';
import 'package:vibesync/features/coach_follow_up/domain/entities/coach_follow_up_result.dart';
import 'package:vibesync/features/coach_follow_up/domain/repositories/coach_follow_up_repository.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation_summary.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/user_profile/data/providers/data_quality_flag_provider.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────

const _now = '2026-05-02T18:30:00.000Z';

Partner _partner({String id = 'p-1', String name = 'Mia'}) => Partner(
      id: id,
      name: name,
      ownerUserId: 'u-1',
      createdAt: DateTime(2026, 5, 1),
      updatedAt: DateTime(2026, 5, 2),
    );

Message _msg(String content, {bool fromMe = false, DateTime? at}) => Message(
      id: 'm-${content.hashCode}',
      content: content,
      isFromMe: fromMe,
      timestamp: at ?? DateTime(2026, 5, 2, 17),
    );

Conversation _convo({
  String id = 'c-1',
  String partnerId = 'p-1',
  List<Message> messages = const [],
  List<ConversationSummary>? summaries,
  int? heatScore,
  String? gameStage,
  DateTime? updatedAt,
}) {
  final c = Conversation(
    id: id,
    name: '對話',
    messages: List.of(messages),
    createdAt: DateTime(2026, 5, 1),
    updatedAt: updatedAt ?? DateTime(2026, 5, 2),
    ownerUserId: 'u-1',
    partnerId: partnerId,
    lastEnthusiasmScore: heatScore,
    currentGameStage: gameStage,
  );
  if (summaries != null && summaries.isNotEmpty) {
    c.summaries = summaries;
  }
  return c;
}

ConversationSummary _summary(String content) => ConversationSummary(
      id: 's-${content.hashCode}',
      roundsCovered: 5,
      content: content,
      keyTopics: const [],
      sharedInterests: const [],
      relationshipStage: 'warming',
      createdAt: DateTime(2026, 5, 2, 16),
    );

CoachFollowUpResult _storedCard({
  String partnerId = 'p-1',
  String headline = '上次的提醒',
  String boundaryReminder = '不要連環追訊息',
}) =>
    CoachFollowUpResult(
      partnerId: partnerId,
      phase: 'prepareInvite',
      headline: headline,
      observation: '她回應仍在線',
      task: '丟一個輕量提案',
      suggestedLine: null,
      boundaryReminder: boundaryReminder,
      generatedAt: DateTime.parse(_now),
      modelUsed: 'claude-sonnet-4-20250514',
    );

// ── Test doubles ──────────────────────────────────────────────────────────

class _FakeRepo implements CoachFollowUpRepository {
  final Map<String, CoachFollowUpResult> _store = {};
  int putCalls = 0;
  int deleteCalls = 0;

  void seed(CoachFollowUpResult r) => _store[r.partnerId] = r;

  @override
  CoachFollowUpResult? get(String partnerId) => _store[partnerId];

  @override
  Future<void> put(CoachFollowUpResult r) async {
    putCalls++;
    _store[r.partnerId] = r;
  }

  @override
  Future<void> delete(String partnerId) async {
    deleteCalls++;
    _store.remove(partnerId);
  }

  @override
  Future<void> clearAll() async => _store.clear();
}

class _RecordedCall {
  final Map<String, dynamic> body;
  _RecordedCall(this.body);
}

CoachFollowUpInvoker _stubInvoker(
  CoachFollowUpInvokeResponse response, {
  List<_RecordedCall>? recorder,
  Duration? delay,
}) {
  return (String fn, {required Map<String, dynamic> body}) async {
    recorder?.add(_RecordedCall(Map<String, dynamic>.from(body)));
    if (delay != null) await Future.delayed(delay);
    return response;
  };
}

CoachFollowUpInvokeResponse _okResponse({String phase = 'prepareInvite'}) {
  return CoachFollowUpInvokeResponse(
    status: 200,
    data: <String, dynamic>{
      'phase': phase,
      'card': <String, dynamic>{
        'headline': '主動提一次',
        'observation': '她回應仍在線',
        'task': '丟一個輕量提案',
        'suggestedLine': '週六下午咖啡？',
        'boundaryReminder': '48 小時內不再追問',
      },
      'model': 'claude-sonnet-4-20250514',
      'generatedAt': _now,
    },
  );
}

ProviderContainer _container({
  required _FakeRepo repo,
  required CoachFollowUpInvoker invoker,
  Partner? partner,
  List<Conversation> conversations = const [],
  DataQualityFlag flag = const DataQualityFlag.unflagged(),
  String partnerId = 'p-1',
  Future<void> Function()? usageSync,
  String? styleContext,
}) {
  final container = ProviderContainer(overrides: [
    coachFollowUpRepositoryProvider.overrideWithValue(repo),
    coachFollowUpApiServiceProvider
        .overrideWithValue(CoachFollowUpApiService(invoker: invoker)),
    coachFollowUpNowProvider.overrideWithValue(() => DateTime(2026, 5, 2, 18)),
    coachFollowUpUsageSyncProvider.overrideWithValue(usageSync ?? () async {}),
    partnerByIdProvider(partnerId).overrideWithValue(partner),
    conversationsByPartnerProvider(partnerId).overrideWithValue(conversations),
    dataQualityFlagProvider(partnerId).overrideWithValue(flag),
    coachFollowUpStyleContextProvider(partnerId)
        .overrideWithValue(styleContext),
  ]);
  return container;
}

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  group('coachFollowUpResultProvider', () {
    test('returns null when no card is stored for partnerId', () {
      final repo = _FakeRepo();
      final c = _container(repo: repo, invoker: _stubInvoker(_okResponse()));
      addTearDown(c.dispose);

      expect(c.read(coachFollowUpResultProvider('p-1')), isNull);
    });

    test('returns the stored card from the repository', () {
      final repo = _FakeRepo()..seed(_storedCard(headline: '你好'));
      final c = _container(repo: repo, invoker: _stubInvoker(_okResponse()));
      addTearDown(c.dispose);

      final result = c.read(coachFollowUpResultProvider('p-1'));
      expect(result?.headline, '你好');
    });
  });

  group('coachFollowUpHintProvider — chip suggestion', () {
    test('returns null when partner has no conversations', () {
      final c = _container(
        repo: _FakeRepo(),
        invoker: _stubInvoker(_okResponse()),
        partner: _partner(),
        conversations: const [],
      );
      addTearDown(c.dispose);

      expect(c.read(coachFollowUpHintProvider('p-1')), isNull);
    });

    test('returns prepareInvite when GameStage.close + heat >= 61', () {
      final convo = _convo(
        gameStage: GameStage.close.name,
        heatScore: 75,
      );
      final c = _container(
        repo: _FakeRepo(),
        invoker: _stubInvoker(_okResponse()),
        partner: _partner(),
        conversations: [convo],
      );
      addTearDown(c.dispose);

      expect(
        c.read(coachFollowUpHintProvider('p-1')),
        CoachFollowUpPhase.prepareInvite,
      );
    });

    test('returns preDateReminder on "明天見面" keyword in recent messages', () {
      final convo = _convo(
        messages: [_msg('明天要見面囉')],
      );
      final c = _container(
        repo: _FakeRepo(),
        invoker: _stubInvoker(_okResponse()),
        partner: _partner(),
        conversations: [convo],
      );
      addTearDown(c.dispose);

      expect(
        c.read(coachFollowUpHintProvider('p-1')),
        CoachFollowUpPhase.preDateReminder,
      );
    });

    test(
        'returns postDateReflection when post-date keyword appears after a '
        'long quiet gap', () {
      final convo = _convo(
        messages: [
          _msg('昨天見完覺得氣氛還不錯', at: DateTime(2026, 5, 1, 18)),
          _msg('我也覺得蠻自然的', fromMe: true, at: DateTime(2026, 5, 2, 0)),
        ],
      );
      final c = _container(
        repo: _FakeRepo(),
        invoker: _stubInvoker(_okResponse()),
        partner: _partner(),
        conversations: [convo],
      );
      addTearDown(c.dispose);

      expect(
        c.read(coachFollowUpHintProvider('p-1')),
        CoachFollowUpPhase.postDateReflection,
      );
    });
  });

  group('coachFollowUpPartnerHintProvider — API payload (T17 helper)', () {
    test('returns null when partner does not exist (deleted / merged away)',
        () {
      final c = _container(
        repo: _FakeRepo(),
        invoker: _stubInvoker(_okResponse()),
        partner: null,
      );
      addTearDown(c.dispose);

      expect(c.read(coachFollowUpPartnerHintProvider('p-1')), isNull);
    });

    test(
        'builds hint with name + heatScore + gameStage from current conversation',
        () {
      final convo = _convo(
        gameStage: GameStage.qualification.name,
        heatScore: 72,
      );
      final c = _container(
        repo: _FakeRepo(),
        invoker: _stubInvoker(_okResponse()),
        partner: _partner(name: 'Mia'),
        conversations: [convo],
      );
      addTearDown(c.dispose);

      final hint = c.read(coachFollowUpPartnerHintProvider('p-1'))!;
      expect(hint.name, 'Mia');
      expect(hint.heatScore, 72);
      expect(hint.gameStage, 'qualification');
    });

    test('passes latest summary as lastConversationSummary', () {
      final convo = _convo(
        summaries: [_summary('上次聊到她想去九份')],
      );
      final c = _container(
        repo: _FakeRepo(),
        invoker: _stubInvoker(_okResponse()),
        partner: _partner(),
        conversations: [convo],
      );
      addTearDown(c.dispose);

      final hint = c.read(coachFollowUpPartnerHintProvider('p-1'))!;
      expect(hint.lastConversationSummary, '上次聊到她想去九份');
    });

    test(
        'forces lastConversationSummary to null when Spec 3 dataQualityFlag is '
        'flagged (privacy contract from T17 helper)', () {
      final convo = _convo(
        summaries: [_summary('上次聊到她想去九份')],
      );
      final c = _container(
        repo: _FakeRepo(),
        invoker: _stubInvoker(_okResponse()),
        partner: _partner(),
        conversations: [convo],
        flag: DataQualityFlag.flagged(null),
      );
      addTearDown(c.dispose);

      final hint = c.read(coachFollowUpPartnerHintProvider('p-1'))!;
      expect(hint.lastConversationSummary, isNull,
          reason: 'flagged conversation MUST NOT leak summary content');
      expect(hint.name, 'Mia',
          reason: 'flagged guard preserves identity fields');
    });

    test('uses the most-recently-updated conversation when partner has many',
        () {
      final older = _convo(
        id: 'c-old',
        heatScore: 30,
        updatedAt: DateTime(2026, 4, 1),
      );
      final newer = _convo(
        id: 'c-new',
        heatScore: 80,
        updatedAt: DateTime(2026, 5, 2),
      );
      // The C20 contract says: list.first is "current" — we pass them in
      // already sorted (matches partner_providers.dart sort).
      final c = _container(
        repo: _FakeRepo(),
        invoker: _stubInvoker(_okResponse()),
        partner: _partner(),
        conversations: [newer, older],
      );
      addTearDown(c.dispose);

      final hint = c.read(coachFollowUpPartnerHintProvider('p-1'))!;
      expect(hint.heatScore, 80);
    });
  });

  group('coachFollowUpControllerProvider — build()', () {
    test('initial state is the stored card from the box', () async {
      final repo = _FakeRepo()..seed(_storedCard(headline: '舊的'));
      final c = _container(repo: repo, invoker: _stubInvoker(_okResponse()));
      addTearDown(c.dispose);

      final value = await c.read(coachFollowUpControllerProvider('p-1').future);
      expect(value?.headline, '舊的');
    });

    test('initial state is null when no card stored', () async {
      final c =
          _container(repo: _FakeRepo(), invoker: _stubInvoker(_okResponse()));
      addTearDown(c.dispose);

      final value = await c.read(coachFollowUpControllerProvider('p-1').future);
      expect(value, isNull);
    });
  });

  group('coachFollowUpControllerProvider — generate()', () {
    test(
        'happy path: state goes loading → data; box gets the new card; '
        'partnerId + phase injected client-side', () async {
      final repo = _FakeRepo();
      final calls = <_RecordedCall>[];
      final c = _container(
        repo: repo,
        invoker: _stubInvoker(_okResponse(), recorder: calls),
        partner: _partner(),
      );
      addTearDown(c.dispose);

      await c.read(coachFollowUpControllerProvider('p-1').future);
      await c.read(coachFollowUpControllerProvider('p-1').notifier).generate(
            phase: CoachFollowUpPhase.prepareInvite,
            answers: const CoachFollowUpAnswers(q1: 'fuzzy'),
          );

      final state = c.read(coachFollowUpControllerProvider('p-1'));
      expect(state.value?.partnerId, 'p-1');
      expect(state.value?.phase, 'prepareInvite');
      expect(repo.putCalls, 1);
      expect(repo.get('p-1')?.headline, '主動提一次');
      expect(calls, hasLength(1));
      expect(calls.single.body['phase'], 'prepareInvite');
    });

    test('success refreshes subscription usage snapshot for paywall UI',
        () async {
      final repo = _FakeRepo();
      var syncCalls = 0;
      final c = _container(
        repo: repo,
        invoker: _stubInvoker(_okResponse()),
        partner: _partner(),
        usageSync: () async {
          syncCalls++;
        },
      );
      addTearDown(c.dispose);

      await c.read(coachFollowUpControllerProvider('p-1').future);
      await c.read(coachFollowUpControllerProvider('p-1').notifier).generate(
            phase: CoachFollowUpPhase.prepareInvite,
            answers: const CoachFollowUpAnswers(q1: 'fuzzy'),
          );

      expect(syncCalls, 1,
          reason: 'successful Edge deduction must be reflected in paywall UI');
      expect(repo.putCalls, 1);
    });

    test('success exposes card before usage refresh completes', () async {
      final repo = _FakeRepo();
      final syncStarted = Completer<void>();
      final syncGate = Completer<void>();
      final c = _container(
        repo: repo,
        invoker: _stubInvoker(_okResponse()),
        partner: _partner(),
        usageSync: () {
          if (!syncStarted.isCompleted) syncStarted.complete();
          return syncGate.future;
        },
      );
      addTearDown(c.dispose);

      await c.read(coachFollowUpControllerProvider('p-1').future);
      final generateFuture =
          c.read(coachFollowUpControllerProvider('p-1').notifier).generate(
                phase: CoachFollowUpPhase.prepareInvite,
                answers: const CoachFollowUpAnswers(q1: 'fuzzy'),
              );

      await syncStarted.future;

      final state = c.read(coachFollowUpControllerProvider('p-1'));
      expect(state.value?.headline, '主動提一次',
          reason: 'usage refresh is paywall-only and must not hide the card');
      expect(repo.putCalls, 1);

      syncGate.complete();
      await generateFuture;
    });

    test(
        'forwards partnerHint from coachFollowUpPartnerHintProvider into the '
        'API call (no inline rebuild — privacy contract)', () async {
      final repo = _FakeRepo();
      final calls = <_RecordedCall>[];
      final convo = _convo(
        gameStage: GameStage.close.name,
        heatScore: 88,
      );
      final c = _container(
        repo: repo,
        invoker: _stubInvoker(_okResponse(), recorder: calls),
        partner: _partner(name: 'Mia'),
        conversations: [convo],
      );
      addTearDown(c.dispose);

      await c.read(coachFollowUpControllerProvider('p-1').future);
      await c.read(coachFollowUpControllerProvider('p-1').notifier).generate(
            phase: CoachFollowUpPhase.prepareInvite,
            answers: const CoachFollowUpAnswers(q1: 'fuzzy'),
          );

      final body = calls.single.body;
      expect(body['partnerHint'], {
        'name': 'Mia',
        'heatScore': 88,
        'gameStage': 'close',
      });
    });

    test('forwards Spec 2.5 style context into the API call when present',
        () async {
      final repo = _FakeRepo();
      final calls = <_RecordedCall>[];
      final c = _container(
        repo: repo,
        invoker: _stubInvoker(_okResponse(), recorder: calls),
        partner: _partner(name: 'Mia'),
        styleContext: '- Preferred voice: 幽默；回覆要輕鬆、有留白',
      );
      addTearDown(c.dispose);

      await c.read(coachFollowUpControllerProvider('p-1').future);
      await c.read(coachFollowUpControllerProvider('p-1').notifier).generate(
            phase: CoachFollowUpPhase.prepareInvite,
            answers: const CoachFollowUpAnswers(q1: 'fuzzy'),
          );

      expect(
        calls.single.body['styleContext'],
        '- Preferred voice: 幽默；回覆要輕鬆、有留白',
      );
    });

    test('debounce: 2nd generate() while in-flight is a silent no-op',
        () async {
      final repo = _FakeRepo();
      final calls = <_RecordedCall>[];
      final c = _container(
        repo: repo,
        invoker: _stubInvoker(
          _okResponse(),
          recorder: calls,
          delay: const Duration(milliseconds: 50),
        ),
        partner: _partner(),
      );
      addTearDown(c.dispose);

      await c.read(coachFollowUpControllerProvider('p-1').future);

      final notifier = c.read(coachFollowUpControllerProvider('p-1').notifier);
      // Fire two without awaiting the first — second must not reach the API.
      final first = notifier.generate(
        phase: CoachFollowUpPhase.prepareInvite,
        answers: const CoachFollowUpAnswers(q1: 'fuzzy'),
      );
      final second = notifier.generate(
        phase: CoachFollowUpPhase.preDateReminder,
        answers: const CoachFollowUpAnswers(q1: 'fuzzy'),
      );
      await Future.wait([first, second]);

      expect(calls, hasLength(1),
          reason: 'in-flight generate must block subsequent calls');
      expect(repo.putCalls, 1);
    });

    test(
        'API failure: state goes error; box content is NOT mutated '
        '(rollback semantics — failed generation must not corrupt local cache)',
        () async {
      final existing = _storedCard(headline: '保留我');
      final repo = _FakeRepo()..seed(existing);
      final c = _container(
        repo: repo,
        invoker: _stubInvoker(const CoachFollowUpInvokeResponse(
          status: 500,
          data: {'error': 'AI 生成失敗：upstream'},
        )),
        partner: _partner(),
      );
      addTearDown(c.dispose);

      await c.read(coachFollowUpControllerProvider('p-1').future);

      await c.read(coachFollowUpControllerProvider('p-1').notifier).generate(
            phase: CoachFollowUpPhase.prepareInvite,
            answers: const CoachFollowUpAnswers(q1: 'fuzzy'),
          );

      final state = c.read(coachFollowUpControllerProvider('p-1'));
      expect(state.hasError, isTrue);
      expect(state.error, isA<GenerationFailedException>());
      expect(repo.putCalls, 0,
          reason: 'failed generation must never write to the box');
      expect(repo.get('p-1')?.headline, '保留我',
          reason: 'previous card stays intact on error');
    });

    test('API failure does not refresh usage snapshot', () async {
      final repo = _FakeRepo();
      var syncCalls = 0;
      final c = _container(
        repo: repo,
        invoker: _stubInvoker(const CoachFollowUpInvokeResponse(
          status: 500,
          data: {'error': 'schema_invalid'},
        )),
        partner: _partner(),
        usageSync: () async {
          syncCalls++;
        },
      );
      addTearDown(c.dispose);

      await c.read(coachFollowUpControllerProvider('p-1').future);
      await c.read(coachFollowUpControllerProvider('p-1').notifier).generate(
            phase: CoachFollowUpPhase.prepareInvite,
            answers: const CoachFollowUpAnswers(q1: 'fuzzy'),
          );

      expect(syncCalls, 0,
          reason: 'failed generation is not charged and must not alter usage');
      expect(repo.putCalls, 0);
    });

    test('quota exceeded: state goes error with QuotaExceededException',
        () async {
      final repo = _FakeRepo();
      final c = _container(
        repo: repo,
        invoker: _stubInvoker(const CoachFollowUpInvokeResponse(
          status: 429,
          data: {'error': 'Daily limit exceeded', 'used': 15, 'limit': 15},
        )),
        partner: _partner(),
      );
      addTearDown(c.dispose);

      await c.read(coachFollowUpControllerProvider('p-1').future);
      await c.read(coachFollowUpControllerProvider('p-1').notifier).generate(
            phase: CoachFollowUpPhase.prepareInvite,
            answers: const CoachFollowUpAnswers(q1: 'fuzzy'),
          );

      final state = c.read(coachFollowUpControllerProvider('p-1'));
      expect(state.error, isA<QuotaExceededException>());
      expect(repo.putCalls, 0);
    });

    test('after error, a subsequent generate() can succeed (state recovers)',
        () async {
      final repo = _FakeRepo();
      var callCount = 0;
      Future<CoachFollowUpInvokeResponse> flakyInvoker(
        String fn, {
        required Map<String, dynamic> body,
      }) async {
        callCount++;
        if (callCount == 1) {
          return const CoachFollowUpInvokeResponse(
            status: 500,
            data: {'error': 'transient'},
          );
        }
        return _okResponse();
      }

      final c = _container(
        repo: repo,
        invoker: flakyInvoker,
        partner: _partner(),
      );
      addTearDown(c.dispose);

      await c.read(coachFollowUpControllerProvider('p-1').future);

      final notifier = c.read(coachFollowUpControllerProvider('p-1').notifier);
      await notifier.generate(
        phase: CoachFollowUpPhase.prepareInvite,
        answers: const CoachFollowUpAnswers(q1: 'fuzzy'),
      );
      expect(c.read(coachFollowUpControllerProvider('p-1')).hasError, isTrue);

      await notifier.generate(
        phase: CoachFollowUpPhase.prepareInvite,
        answers: const CoachFollowUpAnswers(q1: 'fuzzy'),
      );
      expect(c.read(coachFollowUpControllerProvider('p-1')).value?.headline,
          '主動提一次');
      expect(repo.putCalls, 1);
      expect(callCount, 2);
    });
  });

  group('coachFollowUpControllerProvider — regenerate()', () {
    test('overwrites the previously-stored card on success', () async {
      final repo = _FakeRepo()..seed(_storedCard(headline: '舊的'));
      final c = _container(
        repo: repo,
        invoker: _stubInvoker(_okResponse()),
        partner: _partner(),
      );
      addTearDown(c.dispose);

      await c.read(coachFollowUpControllerProvider('p-1').future);
      await c.read(coachFollowUpControllerProvider('p-1').notifier).regenerate(
            phase: CoachFollowUpPhase.prepareInvite,
            answers: const CoachFollowUpAnswers(q1: 'fuzzy'),
          );

      expect(repo.get('p-1')?.headline, '主動提一次');
      expect(repo.putCalls, 1);
    });
  });
}
