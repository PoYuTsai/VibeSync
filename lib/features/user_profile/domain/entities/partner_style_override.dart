import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';

import 'user_profile.dart';

part 'partner_style_override.g.dart';

@immutable
@HiveType(typeId: 13)
class PartnerStyleOverride {
  static const int maxPracticeGoals = 3;
  static const int maxNotesLength = 100;

  @HiveField(0)
  final String partnerId;
  @HiveField(1)
  final InteractionStyle? interactionStyle;
  @HiveField(2)
  final List<PracticeGoal> practiceGoals;
  @HiveField(3)
  final String? notes;
  @HiveField(4)
  final DateTime updatedAt;

  /// Permissive raw constructor — used by Hive codegen and trusted call sites.
  /// Same dual-constructor rationale as [UserProfile]: stored rows must
  /// rebuild without re-running validation that may have tightened.
  const PartnerStyleOverride({
    required this.partnerId,
    this.interactionStyle,
    this.practiceGoals = const [],
    this.notes,
    required this.updatedAt,
  });

  factory PartnerStyleOverride.create({
    required String partnerId,
    InteractionStyle? interactionStyle,
    List<PracticeGoal> practiceGoals = const [],
    String? notes,
    required DateTime updatedAt,
  }) {
    if (partnerId.isEmpty) {
      throw ArgumentError('partnerId must not be empty');
    }
    if (practiceGoals.length > maxPracticeGoals) {
      throw ArgumentError('practiceGoals exceeds max $maxPracticeGoals');
    }
    final n = notes?.trim();
    if (n != null && n.length > maxNotesLength) {
      throw ArgumentError('notes exceeds $maxNotesLength chars');
    }
    return PartnerStyleOverride(
      partnerId: partnerId,
      interactionStyle: interactionStyle,
      practiceGoals: List.unmodifiable(practiceGoals),
      notes: (n == null || n.isEmpty) ? null : n,
      updatedAt: updatedAt,
    );
  }

  bool get isEmpty =>
      interactionStyle == null && practiceGoals.isEmpty && notes == null;
}
