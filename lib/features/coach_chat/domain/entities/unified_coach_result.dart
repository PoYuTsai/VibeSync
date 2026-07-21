import 'package:hive_ce/hive_ce.dart';

part 'unified_coach_result.g.dart';

/// Phase D unified coach local result (typeId 26).
///
/// Merges the two legacy coach records — typeId 17 `CoachChatResult`
/// (conversation scope) and typeId 16 `CoachFollowUpResult` (partner scope) —
/// into one entity. Fields 0-24 mirror `CoachChatResult` with the same
/// HiveField numbers; only [conversationId] became nullable because the
/// partner scope has no conversation.
///
/// [scopeType] and [scopeId] are required:
///   - scopeType == 'conversation' → scopeId == conversationId
///   - scopeType == 'partner'      → scopeId == partnerId
@HiveType(typeId: 26)
class UnifiedCoachResult {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String? conversationId;

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

  @HiveField(16)
  final String responseType;

  @HiveField(17)
  final String? sessionId;

  @HiveField(18)
  final String? userTruth;

  @HiveField(19)
  final String? rewriteDecision;

  @HiveField(20)
  final String? rewriteReason;

  @HiveField(21)
  final int costDeducted;

  @HiveField(22)
  final String frictionType;

  @HiveField(23)
  final String? earlierSummary;

  @HiveField(24)
  final int earlierResultCount;

  @HiveField(25)
  final String scopeType;

  @HiveField(26)
  final String scopeId;

  @HiveField(27)
  final String? lifecyclePhase;

  const UnifiedCoachResult({
    required this.id,
    this.conversationId,
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
    this.responseType = 'coachAnswer',
    this.sessionId,
    this.userTruth,
    this.rewriteDecision,
    this.rewriteReason,
    this.costDeducted = 1,
    this.frictionType = 'unclearIntent',
    this.earlierSummary,
    this.earlierResultCount = 0,
    required this.scopeType,
    required this.scopeId,
    this.lifecyclePhase,
  });

  bool get isClarifyingQuestion => responseType == 'clarifyingQuestion';

  bool get isCoachAnswer => responseType == 'coachAnswer';

  UnifiedCoachResult copyWith({
    String? earlierSummary,
    int? earlierResultCount,
  }) {
    return UnifiedCoachResult(
      id: id,
      conversationId: conversationId,
      partnerId: partnerId,
      question: question,
      mode: mode,
      headline: headline,
      answer: answer,
      userState: userState,
      nextStep: nextStep,
      suggestedLine: suggestedLine,
      boundaryReminder: boundaryReminder,
      needsReflection: needsReflection,
      reflectionQuestion: reflectionQuestion,
      generatedAt: generatedAt,
      provider: provider,
      modelUsed: modelUsed,
      responseType: responseType,
      sessionId: sessionId,
      userTruth: userTruth,
      rewriteDecision: rewriteDecision,
      rewriteReason: rewriteReason,
      costDeducted: costDeducted,
      frictionType: frictionType,
      earlierSummary: earlierSummary ?? this.earlierSummary,
      earlierResultCount: earlierResultCount ?? this.earlierResultCount,
      scopeType: scopeType,
      scopeId: scopeId,
      lifecyclePhase: lifecyclePhase,
    );
  }
}
