// lib/features/partner/domain/entities/partner.dart
import 'package:hive_ce/hive_ce.dart';

part 'partner.g.dart';

/// typeId=8 — verified free at 2026-04-25.
/// Occupied at the time of writing:
///   0 Conversation, 1 Message, 2 ConversationSummary,
///   3 MeetingContext, 4 AcquaintanceDuration, 5 UserGoal,
///   6 SessionContext, 7 UserStyle.
@HiveType(typeId: 8)
class Partner extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String? avatarPath;

  @HiveField(3)
  final DateTime createdAt;

  @HiveField(4)
  DateTime updatedAt;

  @HiveField(5)
  String? ownerUserId;

  @HiveField(6)
  String? customNote;

  Partner({
    required this.id,
    required this.name,
    this.avatarPath,
    required this.createdAt,
    required this.updatedAt,
    this.ownerUserId,
    this.customNote,
  });
}
