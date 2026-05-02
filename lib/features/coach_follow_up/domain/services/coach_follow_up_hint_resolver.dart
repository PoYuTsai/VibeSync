import '../../../analysis/domain/entities/game_stage.dart';
import '../entities/coach_follow_up_phase.dart';

/// Input for the low-pressure Coach Follow-up hint.
///
/// This stays deliberately tiny and local-only. Raw message bodies can help
/// derive an in-app chip hint, but they must never be sent to the Edge function.
class CoachFollowUpHintInput {
  final GameStage? gameStage;
  final int? heatScore;
  final List<String> recentMessageBodies;
  final Duration? timeSinceLastMessage;
  final Duration? averageMessageInterval;

  const CoachFollowUpHintInput({
    this.gameStage,
    this.heatScore,
    this.recentMessageBodies = const [],
    this.timeSinceLastMessage,
    this.averageMessageInterval,
  });
}

/// Pure policy for selecting which follow-up phase to gently suggest.
///
/// The hint is only a UI nudge; users can still pick any phase. Keep this
/// deterministic and conservative so it does not make anxious guesses.
class CoachFollowUpHintResolver {
  static const _upcomingMeetingKeywords = [
    '明天',
    '今晚',
    '今天',
    '週末',
    '周末',
    '見面',
    '碰面',
    '約會',
  ];

  static const _metRecentlyKeywords = [
    '剛見完',
    '剛剛見',
    '剛約完',
    '昨天見',
    '昨天約',
    '上次見',
    '見完',
    '約完',
    '吃完飯',
    '喝完',
    '回到家',
    '到家了',
  ];

  static CoachFollowUpPhase? resolve(CoachFollowUpHintInput input) {
    final messages = input.recentMessageBodies;

    if (_isLongQuiet(input) && _containsAny(messages, _metRecentlyKeywords)) {
      return CoachFollowUpPhase.postDateReflection;
    }

    if (_containsAny(messages, _upcomingMeetingKeywords)) {
      return CoachFollowUpPhase.preDateReminder;
    }

    final heatScore = input.heatScore;
    if (input.gameStage == GameStage.close &&
        heatScore != null &&
        heatScore >= 61) {
      return CoachFollowUpPhase.prepareInvite;
    }

    return null;
  }

  static bool _isLongQuiet(CoachFollowUpHintInput input) {
    final since = input.timeSinceLastMessage;
    final average = input.averageMessageInterval;
    if (since == null || average == null || average <= Duration.zero) {
      return false;
    }
    return since.inMilliseconds >= average.inMilliseconds * 1.5;
  }

  static bool _containsAny(List<String> bodies, List<String> keywords) {
    final joined = bodies.join('\n').toLowerCase();
    if (joined.trim().isEmpty) return false;
    return keywords.any((keyword) => joined.contains(keyword.toLowerCase()));
  }
}
