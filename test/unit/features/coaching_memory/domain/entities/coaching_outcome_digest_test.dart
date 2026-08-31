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
    expect(digest.investmentTrend, isNull);
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

  test(
      'tracks rising, steady, and falling investment after three resolved rounds',
      () {
    CoachingOutcomeDigest digestFor(List<CoachingOutcomeSignal> chronological) {
      return CoachingOutcomeDigest.fromEvents(
        partnerId: 'p-1',
        events: [
          for (var i = 0; i < chronological.length; i++)
            _event(
              'trend-$i',
              outcome: chronological[i],
              createdAt: DateTime.utc(2026, 8, i + 1),
            ),
        ],
      );
    }

    final rising = digestFor([
      CoachingOutcomeSignal.noReply,
      CoachingOutcomeSignal.cold,
      CoachingOutcomeSignal.engaged,
    ]);
    final steady = digestFor([
      CoachingOutcomeSignal.cold,
      CoachingOutcomeSignal.engaged,
      CoachingOutcomeSignal.cold,
    ]);
    final falling = digestFor([
      CoachingOutcomeSignal.engaged,
      CoachingOutcomeSignal.cold,
      CoachingOutcomeSignal.noReply,
    ]);

    expect(rising.investmentTrend, CoachingInvestmentTrend.rising);
    expect(steady.investmentTrend, CoachingInvestmentTrend.steady);
    expect(falling.investmentTrend, CoachingInvestmentTrend.falling);
    expect(
      rising.statisticalInsightLines,
      contains('最近三輪對方投入有回升；可以小幅順勢，但仍看下一輪是否持續。'),
    );
    expect(
      falling.statisticalInsightLines,
      contains('最近三輪對方投入往下；先降投入，不要用更用力的訊息補位。'),
    );
  });

  test('pending/unknown rounds do not fabricate a three-round trend', () {
    final digest = CoachingOutcomeDigest.fromEvents(
      partnerId: 'p-1',
      events: [
        _event('e-1', outcome: CoachingOutcomeSignal.engaged),
        _event('e-2', outcome: CoachingOutcomeSignal.pending),
        _event('e-3', outcome: CoachingOutcomeSignal.unknown),
        _event('e-4', outcome: CoachingOutcomeSignal.cold),
      ],
    );

    expect(digest.investmentTrend, isNull);
    expect(
      digest.statisticalInsightLines.any((line) => line.contains('最近三輪')),
      isFalse,
    );
  });

  // Codex 批4 finding：注入 prompt 的洞察行絕不能夾帶自由文字建議摘要
  // （複製/生成的回覆原文）。statisticalInsightLines 只含統計/類別句；
  // 「最近嘗試：<摘要>」只准出現在本機 UI 的 localInsightLines。
  test('statisticalInsightLines never carries free-text move summaries', () {
    const secret = '被妳發現了我會在飲料櫃前思考人生要不要一起亂逛';
    final digest = CoachingOutcomeDigest.fromEvents(
      partnerId: 'p-1',
      events: [
        _event('m-1',
            userAction: CoachingUserAction.sentAsIs,
            outcome: CoachingOutcomeSignal.engaged,
            summary: secret),
        _event('m-2', outcome: CoachingOutcomeSignal.cold),
        _event('m-3', outcome: CoachingOutcomeSignal.noReply),
      ],
    );

    // 注入路徑：不得含建議原文，任一行都不得出現 secret。
    for (final line in digest.statisticalInsightLines) {
      expect(line.contains(secret), isFalse);
      expect(line.startsWith('最近嘗試'), isFalse);
    }
    // 本機 UI 路徑：才顯示「最近嘗試：<摘要>」。
    expect(
      digest.localInsightLines.any((l) => l.contains('最近嘗試：$secret')),
      isTrue,
    );
    // 統計首句在兩者都在。
    expect(
      digest.statisticalInsightLines.first.startsWith('最近 3 次教練建議結果'),
      isTrue,
    );
  });
}
