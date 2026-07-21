import 'package:hive_ce/hive_ce.dart';

import '../../../coach_follow_up/domain/entities/coach_follow_up_result.dart';
import 'coach_chat_result.dart';

part 'unified_coach_result.g.dart';

/// [UnifiedCoachResult.scopeType] 的合法值（review P2-2 抽共用常數）。
///
/// 這兩個字串是 Hive 持久化值，**絕不可改**；所有讀寫/清理謂詞與
/// scopeType assert 一律引用此處，不得手寫裸字串（typo 會靜默漏清）。
class CoachScopeType {
  const CoachScopeType._();

  static const String conversation = 'conversation';
  static const String partner = 'partner';
}

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

  /// Maps a legacy typeId 17 [CoachChatResult] (conversation scope) 1:1.
  factory UnifiedCoachResult.fromCoachChatResult(CoachChatResult r) {
    return UnifiedCoachResult(
      id: r.id,
      conversationId: r.conversationId,
      partnerId: r.partnerId,
      question: r.question,
      mode: r.mode,
      headline: r.headline,
      answer: r.answer,
      userState: r.userState,
      nextStep: r.nextStep,
      suggestedLine: r.suggestedLine,
      boundaryReminder: r.boundaryReminder,
      needsReflection: r.needsReflection,
      reflectionQuestion: r.reflectionQuestion,
      generatedAt: r.generatedAt,
      provider: r.provider,
      modelUsed: r.modelUsed,
      responseType: r.responseType,
      sessionId: r.sessionId,
      userTruth: r.userTruth,
      rewriteDecision: r.rewriteDecision,
      rewriteReason: r.rewriteReason,
      costDeducted: r.costDeducted,
      frictionType: r.frictionType,
      earlierSummary: r.earlierSummary,
      earlierResultCount: r.earlierResultCount,
      scopeType: CoachScopeType.conversation,
      scopeId: r.conversationId,
      lifecyclePhase: null,
    );
  }

  /// Maps a legacy typeId 16 [CoachFollowUpResult] (partner scope,
  /// latest-only — one record per partner).
  ///
  /// - `observation` fills both [userState] and [answer]; `task` → [nextStep];
  ///   `phase` → [lifecyclePhase].
  /// - [id] is the stable synthetic key `legacy-followup-<partnerId>`.
  /// - [costDeducted] = 0 — decision D-6 neutral sentinel: the legacy record
  ///   never carried cost, so it must not be counted as a billed attempt.
  factory UnifiedCoachResult.fromFollowUpResult(CoachFollowUpResult r) {
    return UnifiedCoachResult(
      id: 'legacy-followup-${r.partnerId}',
      conversationId: null,
      partnerId: r.partnerId,
      question: '',
      mode: 'partnerFollowUp',
      headline: r.headline,
      answer: r.observation,
      userState: r.observation,
      nextStep: r.task,
      suggestedLine: r.suggestedLine,
      boundaryReminder: r.boundaryReminder,
      needsReflection: false,
      generatedAt: r.generatedAt,
      provider: 'legacy',
      modelUsed: r.modelUsed,
      costDeducted: 0,
      scopeType: CoachScopeType.partner,
      scopeId: r.partnerId,
      lifecyclePhase: r.phase,
    );
  }

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
