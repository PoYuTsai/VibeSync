import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/coaching_memory/domain/entities/coaching_outcome_digest.dart';
import 'package:vibesync/features/coaching_memory/domain/entities/coaching_outcome_event.dart';

CoachingOutcomeEvent _event(
  String id, {
  String? partnerId = 'p-1',
  CoachingUserAction userAction = CoachingUserAction.unknown,
  CoachingOutcomeSignal outcome = CoachingOutcomeSignal.unknown,
  DateTime? createdAt,
  String summary = 'short move',
}) {
  return CoachingOutcomeEvent.create(
    id: id,
    partnerId: partnerId,
    source: CoachingOutcomeSource.coach,
    suggestedMoveSummary: summary,
    userAction: userAction,
    outcome: outcome,
    createdAt: createdAt ?? DateTime.utc(2026, 5, 15),
  );
}

void main() {
  test('empty digest has no signal and no insight lines', () {
    final digest = CoachingOutcomeDigest.fromEvents(
      partnerId: ' p-1 ',
      events: const [],
    );

    expect(digest.partnerId, 'p-1');
    expect(digest.hasEvents, isFalse);
    expect(digest.hasEnoughSignal, isFalse);
    expect(digest.engagementRate, 0);
    expect(digest.dominantOutcome, isNull);
    expect(digest.localInsightLines, isEmpty);
  });

  test('counts outcomes and actions using newest events first', () {
    final digest = CoachingOutcomeDigest.fromEvents(
      partnerId: 'p-1',
      maxEvents: 4,
      events: [
        _event(
          'old-ignored',
          outcome: CoachingOutcomeSignal.negative,
          createdAt: DateTime.utc(2026, 1),
          summary: 'old move',
        ),
        _event(
          'engaged-1',
          userAction: CoachingUserAction.sentAsIs,
          outcome: CoachingOutcomeSignal.engaged,
          createdAt: DateTime.utc(2026, 5, 5),
          summary: 'move A',
        ),
        _event(
          'engaged-2',
          userAction: CoachingUserAction.editedAndSent,
          outcome: CoachingOutcomeSignal.engaged,
          createdAt: DateTime.utc(2026, 5, 4),
          summary: 'move A',
        ),
        _event(
          'cold',
          userAction: CoachingUserAction.askedCoach,
          outcome: CoachingOutcomeSignal.cold,
          createdAt: DateTime.utc(2026, 5, 3),
          summary: 'move B',
        ),
        _event(
          'pending',
          userAction: CoachingUserAction.didNotSend,
          outcome: CoachingOutcomeSignal.pending,
          createdAt: DateTime.utc(2026, 5, 2),
          summary: 'move C',
        ),
      ],
    );

    expect(digest.totalEvents, 4);
    expect(digest.latestAt, DateTime.utc(2026, 5, 5));
    expect(digest.engagedCount, 2);
    expect(digest.coldCount, 1);
    expect(digest.pendingCount, 1);
    expect(digest.negativeCount, 0);
    expect(digest.sentOrEditedCount, 2);
    expect(digest.askedCoachCount, 1);
    expect(digest.didNotSendCount, 1);
    expect(digest.dominantOutcome, CoachingOutcomeSignal.engaged);
    expect(digest.dominantUserAction, isNull);
    expect(digest.recentMoveSummaries, ['move A', 'move B', 'move C']);
    expect(digest.engagementRate, closeTo(2 / 3, 0.001));
  });

  test('low sample digest keeps the caveat explicit', () {
    final digest = CoachingOutcomeDigest.fromEvents(
      partnerId: 'p-1',
      events: [
        _event('e-1', outcome: CoachingOutcomeSignal.engaged),
        _event('e-2', outcome: CoachingOutcomeSignal.cold),
      ],
    );

    expect(digest.hasEnoughSignal, isFalse);
    expect(
      digest.localInsightLines,
      contains('樣本還少，先當觀察，不要下定論。'),
    );
  });

  test('detects when the user often does not send the advice', () {
    final digest = CoachingOutcomeDigest.fromEvents(
      partnerId: 'p-1',
      events: [
        _event(
          'skip-1',
          userAction: CoachingUserAction.didNotSend,
          outcome: CoachingOutcomeSignal.pending,
        ),
        _event(
          'skip-2',
          userAction: CoachingUserAction.didNotSend,
          outcome: CoachingOutcomeSignal.pending,
        ),
        _event(
          'engaged',
          userAction: CoachingUserAction.sentAsIs,
          outcome: CoachingOutcomeSignal.engaged,
        ),
      ],
    );

    expect(digest.userOftenDoesNotSend, isTrue);
    expect(
      digest.localInsightLines,
      contains('使用者常在送出前猶豫，之後教練可優先降低行動門檻。'),
    );
  });

  test('detects high engagement and stalled patterns only with enough signal',
      () {
    final highEngagement = CoachingOutcomeDigest.fromEvents(
      partnerId: 'p-1',
      events: [
        _event('e-1', outcome: CoachingOutcomeSignal.engaged),
        _event('e-2', outcome: CoachingOutcomeSignal.engaged),
        _event('e-3', outcome: CoachingOutcomeSignal.cold),
      ],
    );
    final stalled = CoachingOutcomeDigest.fromEvents(
      partnerId: 'p-1',
      events: [
        _event('s-1', outcome: CoachingOutcomeSignal.cold),
        _event('s-2', outcome: CoachingOutcomeSignal.noReply),
        _event('s-3', outcome: CoachingOutcomeSignal.engaged),
      ],
    );

    expect(
      highEngagement.localInsightLines,
      contains('近期建議有效率偏高，可以保留目前互動節奏。'),
    );
    expect(
      stalled.localInsightLines,
      contains('近期回應偏卡，之後建議先調整節奏或降低推進感。'),
    );
  });
}
