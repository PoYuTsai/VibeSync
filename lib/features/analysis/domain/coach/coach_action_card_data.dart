import 'package:flutter/foundation.dart';

import '../../../learning/domain/models/learning_link_target.dart';

/// 教練動作卡 view model（transient，不入 Hive）。
@immutable
class CoachActionCardData {
  const CoachActionCardData({
    required this.actionLabel,
    required this.whyNow,
    required this.task,
    required this.avoid,
    this.avoidLabel = '先不要',
    this.suggestedLine,
    this.learningLink,
  });

  final String actionLabel;
  final String whyNow;
  final String task;
  final String avoid;
  final String avoidLabel;
  final String? suggestedLine;

  /// Dating Knowledge Library 的深連目標；null 表示這個動作沒有對應章節，
  /// 卡片隱藏「看 3 分鐘教學」CTA。
  final LearningLinkTarget? learningLink;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CoachActionCardData &&
        other.actionLabel == actionLabel &&
        other.whyNow == whyNow &&
        other.task == task &&
        other.avoid == avoid &&
        other.avoidLabel == avoidLabel &&
        other.suggestedLine == suggestedLine &&
        other.learningLink == learningLink;
  }

  @override
  int get hashCode => Object.hash(
        actionLabel,
        whyNow,
        task,
        avoid,
        avoidLabel,
        suggestedLine,
        learningLink,
      );

  @override
  String toString() =>
      'CoachActionCardData(actionLabel: $actionLabel, whyNow: $whyNow, '
      'task: $task, avoidLabel: $avoidLabel, avoid: $avoid, '
      'suggestedLine: $suggestedLine, learningLink: $learningLink)';
}
