import 'package:flutter/foundation.dart';

/// 互動風格 — single select. Independent from legacy
/// `SessionContext.UserStyle` (typeId=7) on purpose: §13 forbids silent
/// migration from per-conversation data, and labels here drop the `型` suffix.
enum InteractionStyle { steady, direct, humorous, gentle, playful }

/// 練習目標 — multi select, max 3.
enum PracticeGoal {
  softInvite,
  reduceAnxiety,
  humorousReply,
  buildCloseness,
  explainLess,
}

/// 常聊話題 — multi select, max 5.
enum TopicSeed {
  fitness,
  travel,
  coffee,
  music,
  movies,
  photography,
  food,
  pets,
  reading,
  workLife,
}

@immutable
class UserProfile {
  static const int maxPracticeGoals = 3;
  static const int maxTopicSeeds = 5;
  static const int maxCustomTopicsLength = 60;
  static const int maxNotesLength = 100;

  final InteractionStyle? interactionStyle;
  final List<PracticeGoal> practiceGoals;
  final List<TopicSeed> topicSeeds;
  final String? customTopics;
  final String? notes;
  final DateTime updatedAt;

  /// Public raw constructor — used by Hive codegen and trusted call sites.
  /// Callers from UI / controller MUST use [UserProfile.create] instead so
  /// trimming + bounds are enforced. Permissive on purpose so generated
  /// adapters can rebuild rows without re-running validation that might
  /// reject data which legitimately existed before a future bound was
  /// tightened.
  const UserProfile({
    this.interactionStyle,
    this.practiceGoals = const [],
    this.topicSeeds = const [],
    this.customTopics,
    this.notes,
    required this.updatedAt,
  });

  /// Validates + normalizes inputs. Always use this from controllers,
  /// repository write-path, or any UI surface that builds a profile from
  /// user input. Throws [ArgumentError] on bound violation.
  factory UserProfile.create({
    InteractionStyle? interactionStyle,
    List<PracticeGoal> practiceGoals = const [],
    List<TopicSeed> topicSeeds = const [],
    String? customTopics,
    String? notes,
    required DateTime updatedAt,
  }) {
    if (practiceGoals.length > maxPracticeGoals) {
      throw ArgumentError('practiceGoals exceeds max $maxPracticeGoals');
    }
    if (topicSeeds.length > maxTopicSeeds) {
      throw ArgumentError('topicSeeds exceeds max $maxTopicSeeds');
    }
    final ct = customTopics?.trim();
    if (ct != null && ct.length > maxCustomTopicsLength) {
      throw ArgumentError('customTopics exceeds $maxCustomTopicsLength chars');
    }
    final n = notes?.trim();
    if (n != null && n.length > maxNotesLength) {
      throw ArgumentError('notes exceeds $maxNotesLength chars');
    }
    return UserProfile(
      interactionStyle: interactionStyle,
      practiceGoals: List.unmodifiable(practiceGoals),
      topicSeeds: List.unmodifiable(topicSeeds),
      customTopics: (ct == null || ct.isEmpty) ? null : ct,
      notes: (n == null || n.isEmpty) ? null : n,
      updatedAt: updatedAt,
    );
  }

  bool get isEmpty =>
      interactionStyle == null &&
      practiceGoals.isEmpty &&
      topicSeeds.isEmpty &&
      customTopics == null &&
      notes == null;
}
