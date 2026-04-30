import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';

part 'user_profile.g.dart';

/// 互動風格 — single select. Independent from legacy
/// `SessionContext.UserStyle` (typeId=7) on purpose: §13 forbids silent
/// migration from per-conversation data, and labels here drop the `型` suffix.
@HiveType(typeId: 10)
enum InteractionStyle {
  @HiveField(0) steady,
  @HiveField(1) direct,
  @HiveField(2) humorous,
  @HiveField(3) gentle,
  @HiveField(4) playful,
}

/// 練習目標 — multi select, max 3.
@HiveType(typeId: 11)
enum PracticeGoal {
  @HiveField(0) softInvite,
  @HiveField(1) reduceAnxiety,
  @HiveField(2) humorousReply,
  @HiveField(3) buildCloseness,
  @HiveField(4) explainLess,
}

/// 常聊話題 — multi select, max 5.
@HiveType(typeId: 12)
enum TopicSeed {
  @HiveField(0) fitness,
  @HiveField(1) travel,
  @HiveField(2) coffee,
  @HiveField(3) music,
  @HiveField(4) movies,
  @HiveField(5) photography,
  @HiveField(6) food,
  @HiveField(7) pets,
  @HiveField(8) reading,
  @HiveField(9) workLife,
}

@immutable
@HiveType(typeId: 9)
class UserProfile {
  static const int maxPracticeGoals = 3;
  static const int maxTopicSeeds = 5;
  static const int maxCustomTopicsLength = 60;
  static const int maxNotesLength = 100;

  @HiveField(0)
  final InteractionStyle? interactionStyle;
  @HiveField(1)
  final List<PracticeGoal> practiceGoals;
  @HiveField(2)
  final List<TopicSeed> topicSeeds;
  @HiveField(3)
  final String? customTopics;
  @HiveField(4)
  final String? notes;
  @HiveField(5)
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
