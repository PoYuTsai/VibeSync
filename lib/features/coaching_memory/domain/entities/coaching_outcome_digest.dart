import 'package:flutter/foundation.dart';

import 'coaching_outcome_event.dart';

/// Small, local-only summary of recent coaching outcomes for one partner.
///
/// This is intentionally derived data. It is not written back to Hive. Only a
/// compact, high-signal summary may be used as coach context; raw events stay
/// local until a later long-term strategy memory phase exists.
@immutable
class CoachingOutcomeDigest {
  static const defaultMaxEvents = 20;
  static const defaultMaxRecentMoves = 3;

  final String? partnerId;
  final int totalEvents;
  final int engagedCount;
  final int coldCount;
  final int noReplyCount;
  final int negativeCount;
  final int pendingCount;
  final int unknownOutcomeCount;
  final int sentAsIsCount;
  final int editedAndSentCount;
  final int didNotSendCount;
  final int askedCoachCount;
  final int unknownActionCount;
  final DateTime? latestAt;
  final List<String> recentMoveSummaries;

  const CoachingOutcomeDigest({
    required this.partnerId,
    required this.totalEvents,
    required this.engagedCount,
    required this.coldCount,
    required this.noReplyCount,
    required this.negativeCount,
    required this.pendingCount,
    required this.unknownOutcomeCount,
    required this.sentAsIsCount,
    required this.editedAndSentCount,
    required this.didNotSendCount,
    required this.askedCoachCount,
    required this.unknownActionCount,
    required this.latestAt,
    required this.recentMoveSummaries,
  });

  factory CoachingOutcomeDigest.empty({String? partnerId}) {
    return CoachingOutcomeDigest(
      partnerId: CoachingOutcomeEvent.normalizeScope(partnerId),
      totalEvents: 0,
      engagedCount: 0,
      coldCount: 0,
      noReplyCount: 0,
      negativeCount: 0,
      pendingCount: 0,
      unknownOutcomeCount: 0,
      sentAsIsCount: 0,
      editedAndSentCount: 0,
      didNotSendCount: 0,
      askedCoachCount: 0,
      unknownActionCount: 0,
      latestAt: null,
      recentMoveSummaries: const [],
    );
  }

  factory CoachingOutcomeDigest.fromEvents({
    required String? partnerId,
    required Iterable<CoachingOutcomeEvent> events,
    int maxEvents = defaultMaxEvents,
    int maxRecentMoves = defaultMaxRecentMoves,
  }) {
    final sorted = events.toList(growable: false)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final scoped = maxEvents <= 0
        ? const <CoachingOutcomeEvent>[]
        : sorted.take(maxEvents).toList(growable: false);
    if (scoped.isEmpty) {
      return CoachingOutcomeDigest.empty(partnerId: partnerId);
    }

    var engaged = 0;
    var cold = 0;
    var noReply = 0;
    var negative = 0;
    var pending = 0;
    var unknownOutcome = 0;
    var sentAsIs = 0;
    var editedAndSent = 0;
    var didNotSend = 0;
    var askedCoach = 0;
    var unknownAction = 0;

    for (final event in scoped) {
      switch (event.outcome) {
        case CoachingOutcomeSignal.engaged:
          engaged++;
        case CoachingOutcomeSignal.cold:
          cold++;
        case CoachingOutcomeSignal.noReply:
          noReply++;
        case CoachingOutcomeSignal.negative:
          negative++;
        case CoachingOutcomeSignal.pending:
          pending++;
        case CoachingOutcomeSignal.unknown:
          unknownOutcome++;
      }

      switch (event.userAction) {
        case CoachingUserAction.sentAsIs:
          sentAsIs++;
        case CoachingUserAction.editedAndSent:
          editedAndSent++;
        case CoachingUserAction.didNotSend:
          didNotSend++;
        case CoachingUserAction.askedCoach:
          askedCoach++;
        case CoachingUserAction.unknown:
          unknownAction++;
      }
    }

    final recentMoves = <String>[];
    for (final event in scoped) {
      final summary = event.suggestedMoveSummary.trim();
      if (summary.isEmpty || recentMoves.contains(summary)) continue;
      recentMoves.add(summary);
      if (recentMoves.length >= maxRecentMoves) break;
    }

    return CoachingOutcomeDigest(
      partnerId: CoachingOutcomeEvent.normalizeScope(partnerId),
      totalEvents: scoped.length,
      engagedCount: engaged,
      coldCount: cold,
      noReplyCount: noReply,
      negativeCount: negative,
      pendingCount: pending,
      unknownOutcomeCount: unknownOutcome,
      sentAsIsCount: sentAsIs,
      editedAndSentCount: editedAndSent,
      didNotSendCount: didNotSend,
      askedCoachCount: askedCoach,
      unknownActionCount: unknownAction,
      latestAt: scoped.first.createdAt,
      recentMoveSummaries: List.unmodifiable(recentMoves),
    );
  }

  bool get hasEvents => totalEvents > 0;

  int get sentOrEditedCount => sentAsIsCount + editedAndSentCount;

  int get resolvedOutcomeCount =>
      engagedCount + coldCount + noReplyCount + negativeCount;

  int get stalledOutcomeCount => coldCount + noReplyCount + negativeCount;

  double get engagementRate {
    final resolved = resolvedOutcomeCount;
    if (resolved == 0) return 0;
    return engagedCount / resolved;
  }

  bool get hasEnoughSignal => totalEvents >= 3;

  bool get userOftenDoesNotSend =>
      totalEvents >= 3 &&
      didNotSendCount >= 2 &&
      didNotSendCount >= sentOrEditedCount;

  bool get oftenReturnsToCoach =>
      totalEvents >= 3 &&
      askedCoachCount >= 2 &&
      askedCoachCount >= sentOrEditedCount;

  CoachingOutcomeSignal? get dominantOutcome {
    final counts = <CoachingOutcomeSignal, int>{
      CoachingOutcomeSignal.engaged: engagedCount,
      CoachingOutcomeSignal.cold: coldCount,
      CoachingOutcomeSignal.noReply: noReplyCount,
      CoachingOutcomeSignal.negative: negativeCount,
      CoachingOutcomeSignal.pending: pendingCount,
      CoachingOutcomeSignal.unknown: unknownOutcomeCount,
    };
    return _dominant(counts);
  }

  CoachingUserAction? get dominantUserAction {
    final counts = <CoachingUserAction, int>{
      CoachingUserAction.sentAsIs: sentAsIsCount,
      CoachingUserAction.editedAndSent: editedAndSentCount,
      CoachingUserAction.didNotSend: didNotSendCount,
      CoachingUserAction.askedCoach: askedCoachCount,
      CoachingUserAction.unknown: unknownActionCount,
    };
    return _dominant(counts);
  }

  List<String> get localInsightLines {
    if (!hasEvents) return const [];

    final lines = <String>[
      '最近 $totalEvents 次教練建議結果：有接 $engagedCount、冷回 $coldCount、沒回 $noReplyCount。',
    ];

    if (!hasEnoughSignal) {
      lines.add('樣本還少，先當觀察，不要下定論。');
    } else if (userOftenDoesNotSend) {
      lines.add('使用者常在送出前猶豫，之後教練可優先降低行動門檻。');
    } else if (oftenReturnsToCoach) {
      lines.add('使用者常回來問教練，之後可提供更明確的下一步選項。');
    } else if (engagementRate >= 0.6 && resolvedOutcomeCount >= 3) {
      lines.add('近期建議有效率偏高，可以保留目前互動節奏。');
    } else if (stalledOutcomeCount >= engagedCount &&
        resolvedOutcomeCount >= 3) {
      lines.add('近期回應偏卡，之後建議先調整節奏或降低推進感。');
    }

    if (recentMoveSummaries.isNotEmpty) {
      lines.add('最近嘗試：${recentMoveSummaries.first}');
    }
    return List.unmodifiable(lines);
  }

  static T? _dominant<T>(Map<T, int> counts) {
    T? bestKey;
    var bestValue = 0;
    var tie = false;
    for (final entry in counts.entries) {
      if (entry.value <= 0) continue;
      if (entry.value > bestValue) {
        bestKey = entry.key;
        bestValue = entry.value;
        tie = false;
      } else if (entry.value == bestValue) {
        tie = true;
      }
    }
    if (tie) return null;
    return bestKey;
  }
}
