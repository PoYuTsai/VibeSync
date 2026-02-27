// lib/features/conversation/domain/entities/conversation_summary.dart
import 'package:hive_ce/hive_ce.dart';

part 'conversation_summary.g.dart';

/// Summary of older conversation history
/// Used to maintain context without keeping all messages
@HiveType(typeId: 2)
class ConversationSummary extends HiveObject {
  @HiveField(0)
  final String id;

  /// Number of rounds this summary covers
  @HiveField(1)
  final int roundsCovered;

  /// AI-generated summary content
  @HiveField(2)
  final String content;

  /// Key topics discussed in this segment
  @HiveField(3)
  final List<String> keyTopics;

  /// Shared interests discovered
  @HiveField(4)
  final List<String> sharedInterests;

  /// Relationship stage at this point
  @HiveField(5)
  final String relationshipStage;

  @HiveField(6)
  final DateTime createdAt;

  ConversationSummary({
    required this.id,
    required this.roundsCovered,
    required this.content,
    required this.keyTopics,
    required this.sharedInterests,
    required this.relationshipStage,
    required this.createdAt,
  });

  /// Create from AI response JSON
  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    return ConversationSummary(
      id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      roundsCovered: json['roundsCovered'] as int? ?? 0,
      content: json['content'] as String? ?? '',
      keyTopics: (json['keyTopics'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      sharedInterests: (json['sharedInterests'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      relationshipStage: json['relationshipStage'] as String? ?? 'unknown',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'roundsCovered': roundsCovered,
        'content': content,
        'keyTopics': keyTopics,
        'sharedInterests': sharedInterests,
        'relationshipStage': relationshipStage,
        'createdAt': createdAt.toIso8601String(),
      };
}
