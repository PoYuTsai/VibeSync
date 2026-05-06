import 'package:hive_ce/hive_ce.dart';

part 'coach_chat_result.g.dart';

/// Spec 6A Coach 1:1 local result.
///
/// Persistence is encrypted local-only. We keep recent results per
/// conversation so the analysis page can show the latest coach answer without
/// turning this into an infinite chat transcript.
@HiveType(typeId: 17)
class CoachChatResult {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String conversationId;

  @HiveField(2)
  final String? partnerId;

  @HiveField(3)
  final String question;

  @HiveField(4)
  final String mode;

  @HiveField(5)
  final String headline;

  @HiveField(6)
  final String answer;

  @HiveField(7)
  final String userState;

  @HiveField(8)
  final String nextStep;

  @HiveField(9)
  final String? suggestedLine;

  @HiveField(10)
  final String boundaryReminder;

  @HiveField(11)
  final bool needsReflection;

  @HiveField(12)
  final String? reflectionQuestion;

  @HiveField(13)
  final DateTime generatedAt;

  @HiveField(14)
  final String provider;

  @HiveField(15)
  final String modelUsed;

  const CoachChatResult({
    required this.id,
    required this.conversationId,
    this.partnerId,
    required this.question,
    required this.mode,
    required this.headline,
    required this.answer,
    required this.userState,
    required this.nextStep,
    this.suggestedLine,
    required this.boundaryReminder,
    required this.needsReflection,
    this.reflectionQuestion,
    required this.generatedAt,
    required this.provider,
    required this.modelUsed,
  });
}
