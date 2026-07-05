import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_chat_result.dart';
import 'package:vibesync/features/coaching_memory/data/providers/coaching_outcome_providers.dart';
import 'package:vibesync/features/coaching_memory/domain/entities/coaching_outcome_event.dart';
import 'package:vibesync/features/coaching_memory/domain/repositories/coaching_outcome_repository.dart';

CoachChatResult _coachResult({
  String id = 'result-1',
  String? partnerId = 'partner-1',
  String conversationId = 'conversation-1',
  String nextStep = '先用一句輕鬆的話把球丟回去',
  String? suggestedLine = '你這句有點突然，但我可以接。',
  String headline = '先穩住節奏',
}) {
  return CoachChatResult(
    id: id,
    conversationId: conversationId,
    partnerId: partnerId,
    question: '我現在該怎麼回？',
    mode: 'replyCraft',
    headline: headline,
    answer: '先接住她的情緒，再丟一個好回的小球。',
    userState: '有點急著想推進',
    nextStep: nextStep,
    suggestedLine: suggestedLine,
    boundaryReminder: '不要急著把對話推太重。',
    needsReflection: false,
    generatedAt: DateTime.utc(2026, 5, 15, 8),
    provider: 'claude',
    modelUsed: 'claude-sonnet-4-20250514',
  );
}

class _MemoryOutcomeRepo implements CoachingOutcomeRepository {
  final _events = <String, CoachingOutcomeEvent>{};

  @override
  CoachingOutcomeEvent? get(String id) => _events[id.trim()];

  @override
  List<CoachingOutcomeEvent> listRecent({int? limit}) => _limit(
        _events.values.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
        limit,
      );

  @override
  List<CoachingOutcomeEvent> listByPartner(String partnerId, {int? limit}) {
    final normalized = CoachingOutcomeEvent.normalizeScope(partnerId);
    if (normalized == null) return const [];
    return _limit(
      listRecent()
          .where((event) =>
              CoachingOutcomeEvent.normalizeScope(event.partnerId) ==
              normalized)
          .toList(),
      limit,
    );
  }

  @override
  List<CoachingOutcomeEvent> listUnbound({int? limit}) {
    return _limit(
      listRecent()
          .where((event) =>
              CoachingOutcomeEvent.normalizeScope(event.partnerId) == null)
          .toList(),
      limit,
    );
  }

  @override
  List<CoachingOutcomeEvent> listByConversation(
    String conversationId, {
    int? limit,
  }) {
    final normalized = CoachingOutcomeEvent.normalizeScope(conversationId);
    if (normalized == null) return const [];
    return _limit(
      listRecent()
          .where((event) =>
              CoachingOutcomeEvent.normalizeScope(event.conversationId) ==
              normalized)
          .toList(),
      limit,
    );
  }

  @override
  Future<void> put(CoachingOutcomeEvent event) async {
    _events[event.id] = event;
  }

  @override
  Future<void> delete(String id) async {
    _events.remove(id.trim());
  }

  @override
  Future<int> deleteByPartner(String partnerId) async {
    final normalized = CoachingOutcomeEvent.normalizeScope(partnerId);
    if (normalized == null) return 0;
    final keys = _events.entries
        .where((entry) =>
            CoachingOutcomeEvent.normalizeScope(entry.value.partnerId) ==
            normalized)
        .map((entry) => entry.key)
        .toList();
    for (final key in keys) {
      _events.remove(key);
    }
    return keys.length;
  }

  @override
  Future<int> reassignPartner({
    required String fromPartnerId,
    required String toPartnerId,
  }) async {
    final from = CoachingOutcomeEvent.normalizeScope(fromPartnerId);
    final to = CoachingOutcomeEvent.normalizeScope(toPartnerId);
    if (from == null || to == null) {
      throw ArgumentError('partner ids must be non-empty');
    }
    var count = 0;
    for (final entry in _events.entries.toList()) {
      if (CoachingOutcomeEvent.normalizeScope(entry.value.partnerId) == from) {
        _events[entry.key] = entry.value.withPartnerId(to);
        count++;
      }
    }
    return count;
  }

  @override
  Future<void> clearAll() async {
    _events.clear();
  }

  List<CoachingOutcomeEvent> _limit(
    List<CoachingOutcomeEvent> events,
    int? limit,
  ) {
    if (limit == null || limit >= events.length) return events;
    if (limit <= 0) return const [];
    return events.take(limit).toList();
  }
}

ProviderContainer _container({
  required _MemoryOutcomeRepo repo,
  DateTime? now,
}) {
  return ProviderContainer(overrides: [
    coachingOutcomeRepositoryProvider.overrideWithValue(repo),
    coachingOutcomeNowProvider.overrideWithValue(
      () => now ?? DateTime.utc(2026, 5, 15, 9),
    ),
  ]);
}

void main() {
  test('records a coach result outcome with stable local event fields',
      () async {
    final repo = _MemoryOutcomeRepo();
    final c = _container(
      repo: repo,
      now: DateTime.utc(2026, 5, 15, 10),
    );
    addTearDown(c.dispose);

    expect(c.read(coachingOutcomeEventProvider('coach:result-1')), isNull);

    final event =
        await c.read(coachingOutcomeRecorderProvider).recordCoachResultOutcome(
              result: _coachResult(),
              userAction: CoachingUserAction.editedAndSent,
              outcome: CoachingOutcomeSignal.engaged,
            );

    expect(event.id, 'coach:result-1');
    expect(event.partnerId, 'partner-1');
    expect(event.conversationId, 'conversation-1');
    expect(event.source, CoachingOutcomeSource.coach);
    expect(event.adviceId, 'result-1');
    expect(event.adviceType, 'replyCraft');
    expect(event.userAction, CoachingUserAction.editedAndSent);
    expect(event.outcome, CoachingOutcomeSignal.engaged);
    expect(event.createdAt, DateTime.utc(2026, 5, 15, 10));
    expect(
      event.suggestedMoveSummary,
      '先用一句輕鬆的話把球丟回去 / 你這句有點突然，但我可以接。',
    );
    expect(c.read(coachingOutcomeEventProvider('coach:result-1'))?.id,
        'coach:result-1');
    final digest = c.read(coachingOutcomeDigestProvider('partner-1'));
    expect(digest.totalEvents, 1);
    expect(digest.engagedCount, 1);
    expect(digest.recentMoveSummaries.single, event.suggestedMoveSummary);
  });

  test('recording the same coach result overwrites the previous signal',
      () async {
    final repo = _MemoryOutcomeRepo();
    final c = _container(repo: repo);
    addTearDown(c.dispose);
    final recorder = c.read(coachingOutcomeRecorderProvider);

    await recorder.recordCoachResultOutcome(
      result: _coachResult(),
      userAction: CoachingUserAction.unknown,
      outcome: CoachingOutcomeSignal.engaged,
    );
    await recorder.recordCoachResultOutcome(
      result: _coachResult(),
      userAction: CoachingUserAction.didNotSend,
      outcome: CoachingOutcomeSignal.pending,
    );

    final events = repo.listRecent();
    expect(events, hasLength(1));
    expect(events.single.userAction, CoachingUserAction.didNotSend);
    expect(events.single.outcome, CoachingOutcomeSignal.pending);
  });

  test('falls back to headline when next step and suggested line are empty',
      () async {
    final repo = _MemoryOutcomeRepo();
    final c = _container(repo: repo);
    addTearDown(c.dispose);

    final event =
        await c.read(coachingOutcomeRecorderProvider).recordCoachResultOutcome(
              result: _coachResult(
                partnerId: null,
                nextStep: ' ',
                suggestedLine: ' ',
                headline: '先不要急著貼標籤',
              ),
              userAction: CoachingUserAction.askedCoach,
              outcome: CoachingOutcomeSignal.unknown,
            );

    expect(event.partnerId, isNull);
    expect(event.suggestedMoveSummary, '先不要急著貼標籤');
    expect(c.read(coachingUnboundOutcomesProvider).single.id, event.id);
    expect(c.read(coachingUnboundOutcomeDigestProvider).totalEvents, 1);
  });

  test('recordCoachResultReaction 保留第一段 userAction、只更新 outcome', () async {
    final repo = _MemoryOutcomeRepo();
    final c = _container(repo: repo);
    addTearDown(c.dispose);
    final recorder = c.read(coachingOutcomeRecorderProvider);

    final first = await recorder.recordCoachResultOutcome(
      result: _coachResult(),
      userAction: CoachingUserAction.editedAndSent,
      outcome: CoachingOutcomeSignal.pending,
    );

    final updated = await recorder.recordCoachResultReaction(
      result: _coachResult(),
      outcome: CoachingOutcomeSignal.cold,
    );

    expect(updated, isNotNull);
    expect(updated!.id, first.id);
    expect(updated.adviceId, first.adviceId);
    expect(updated.suggestedMoveSummary, first.suggestedMoveSummary);
    expect(updated.userAction, CoachingUserAction.editedAndSent);
    expect(updated.outcome, CoachingOutcomeSignal.cold);

    final events = repo.listRecent();
    expect(events, hasLength(1));
    expect(events.single.userAction, CoachingUserAction.editedAndSent);
    expect(events.single.outcome, CoachingOutcomeSignal.cold);
  });

  test('recordCoachResultReaction 在沒有第一段紀錄時不寫入', () async {
    final repo = _MemoryOutcomeRepo();
    final c = _container(repo: repo);
    addTearDown(c.dispose);

    final updated =
        await c.read(coachingOutcomeRecorderProvider).recordCoachResultReaction(
              result: _coachResult(),
              outcome: CoachingOutcomeSignal.engaged,
            );

    expect(updated, isNull);
    expect(repo.get('coach:result-1'), isNull);
  });

  test('recordCoachResultReaction 在 userAction=didNotSend 時不覆寫', () async {
    final repo = _MemoryOutcomeRepo();
    final c = _container(repo: repo);
    addTearDown(c.dispose);
    final recorder = c.read(coachingOutcomeRecorderProvider);

    await recorder.recordCoachResultOutcome(
      result: _coachResult(),
      userAction: CoachingUserAction.didNotSend,
      outcome: CoachingOutcomeSignal.unknown,
    );

    final updated = await recorder.recordCoachResultReaction(
      result: _coachResult(),
      outcome: CoachingOutcomeSignal.engaged,
    );

    expect(updated, isNull);
    final event = repo.get('coach:result-1');
    expect(event, isNotNull);
    expect(event!.userAction, CoachingUserAction.didNotSend);
    expect(event.outcome, CoachingOutcomeSignal.unknown);
  });
}
