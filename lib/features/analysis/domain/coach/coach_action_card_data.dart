import 'package:flutter/foundation.dart';

/// 教練動作卡 view model（transient，不入 Hive）。
@immutable
class CoachActionCardData {
  const CoachActionCardData({
    required this.actionLabel,
    required this.whyNow,
    required this.task,
    required this.avoid,
    this.suggestedLine,
    this.learningLink,
  });

  final String actionLabel;
  final String whyNow;
  final String task;
  final String avoid;
  final String? suggestedLine;
  final String? learningLink;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CoachActionCardData &&
        other.actionLabel == actionLabel &&
        other.whyNow == whyNow &&
        other.task == task &&
        other.avoid == avoid &&
        other.suggestedLine == suggestedLine &&
        other.learningLink == learningLink;
  }

  @override
  int get hashCode => Object.hash(
        actionLabel,
        whyNow,
        task,
        avoid,
        suggestedLine,
        learningLink,
      );

  @override
  String toString() =>
      'CoachActionCardData(actionLabel: $actionLabel, whyNow: $whyNow, '
      'task: $task, avoid: $avoid, suggestedLine: $suggestedLine, '
      'learningLink: $learningLink)';
}
