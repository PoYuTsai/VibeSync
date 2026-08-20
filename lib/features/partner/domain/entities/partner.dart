// lib/features/partner/domain/entities/partner.dart
import 'package:hive_ce/hive_ce.dart';

import '../../../conversation/domain/entities/session_context.dart';

part 'partner.g.dart';

/// typeId=8 — verified free at 2026-04-25.
/// Occupied at the time of writing:
///   0 Conversation, 1 Message, 2 ConversationSummary,
///   3 MeetingContext, 4 AcquaintanceDuration, 5 UserGoal,
///   6 SessionContext, 7 UserStyle.
// Next free HiveField index: 10. Never reuse retired indices (additive-only schema).
@HiveType(typeId: 8)
class Partner extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String? avatarPath;

  /// Stored in device local time (matching Conversation.createdAt convention).
  @HiveField(3)
  final DateTime createdAt;

  /// Stored in device local time (matching Conversation.updatedAt convention).
  @HiveField(4)
  DateTime updatedAt;

  @HiveField(5)
  String? ownerUserId;

  /// Partner-level manual context. Current UI stores allowlisted chips joined
  /// by `、`; legacy installs may still contain free text. Every AI consumer
  /// must pass this through `PartnerMemoryTagCatalog.sanitizedNote` first.
  @HiveField(6)
  String? customNote;

  /// Defaults for a new analysis involving this partner. Conversation-level
  /// [SessionContext] still wins once a specific conversation has one.
  @HiveField(7)
  MeetingContext? defaultMeetingContext;

  @HiveField(8)
  AcquaintanceDuration? defaultAcquaintanceDuration;

  @HiveField(9)
  UserGoal? defaultGoal;

  Partner({
    required this.id,
    required this.name,
    this.avatarPath,
    required this.createdAt,
    required this.updatedAt,
    this.ownerUserId,
    this.customNote,
    this.defaultMeetingContext,
    this.defaultAcquaintanceDuration,
    this.defaultGoal,
  });
}
