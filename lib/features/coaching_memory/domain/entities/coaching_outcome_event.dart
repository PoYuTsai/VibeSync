import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';

part 'coaching_outcome_event.g.dart';

@HiveType(typeId: 19)
enum CoachingOutcomeSource {
  @HiveField(0)
  opener,
  @HiveField(1)
  analyze,
  @HiveField(2)
  coach,
}

@HiveType(typeId: 20)
enum CoachingUserAction {
  @HiveField(0)
  sentAsIs,
  @HiveField(1)
  editedAndSent,
  @HiveField(2)
  didNotSend,
  @HiveField(3)
  askedCoach,
  @HiveField(4)
  unknown,
}

@HiveType(typeId: 21)
enum CoachingOutcomeSignal {
  @HiveField(0)
  engaged,
  @HiveField(1)
  cold,
  @HiveField(2)
  noReply,
  @HiveField(3)
  negative,
  @HiveField(4)
  pending,
  @HiveField(5)
  unknown,
}

/// Local-only capture of what happened after a coach/analyze/opener suggestion.
///
/// This is deliberately an outcome event, not long-term strategy memory.
/// Strategy consolidation and prompt injection happen in later phases only
/// after these small events prove clean enough to trust.
@immutable
@HiveType(typeId: 18)
class CoachingOutcomeEvent {
  static const maxSuggestedMoveSummaryLength = 160;
  static const maxOutcomeTextPreviewLength = 240;
  static const maxUserNoteLength = 200;
  static const maxAdviceTypeLength = 48;

  @HiveField(0)
  final String id;

  @HiveField(1)
  final String? partnerId;

  @HiveField(2)
  final String? conversationId;

  @HiveField(3)
  final CoachingOutcomeSource source;

  @HiveField(4)
  final String? adviceId;

  @HiveField(5)
  final String? adviceType;

  @HiveField(6)
  final String suggestedMoveSummary;

  @HiveField(7)
  final CoachingUserAction userAction;

  @HiveField(8)
  final CoachingOutcomeSignal outcome;

  @HiveField(9)
  final String? outcomeTextPreview;

  @HiveField(10)
  final String? userNote;

  @HiveField(11)
  final DateTime createdAt;

  /// Permissive raw constructor for Hive rebuilds and trusted tests.
  /// UI/controller write paths should prefer [create] for trimming + bounds.
  const CoachingOutcomeEvent({
    required this.id,
    this.partnerId,
    this.conversationId,
    required this.source,
    this.adviceId,
    this.adviceType,
    required this.suggestedMoveSummary,
    required this.userAction,
    required this.outcome,
    this.outcomeTextPreview,
    this.userNote,
    required this.createdAt,
  });

  factory CoachingOutcomeEvent.create({
    required String id,
    String? partnerId,
    String? conversationId,
    required CoachingOutcomeSource source,
    String? adviceId,
    String? adviceType,
    required String suggestedMoveSummary,
    CoachingUserAction userAction = CoachingUserAction.unknown,
    CoachingOutcomeSignal outcome = CoachingOutcomeSignal.unknown,
    String? outcomeTextPreview,
    String? userNote,
    required DateTime createdAt,
  }) {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) {
      throw ArgumentError('CoachingOutcomeEvent.id must be non-empty');
    }

    final summary = suggestedMoveSummary.trim();
    if (summary.isEmpty) {
      throw ArgumentError(
        'CoachingOutcomeEvent.suggestedMoveSummary must be non-empty',
      );
    }
    _assertMax(
      summary,
      maxSuggestedMoveSummaryLength,
      'suggestedMoveSummary',
    );

    final normalizedAdviceType = _optionalTrim(adviceType);
    if (normalizedAdviceType != null) {
      _assertMax(normalizedAdviceType, maxAdviceTypeLength, 'adviceType');
    }

    final normalizedPreview = _optionalTrim(outcomeTextPreview);
    if (normalizedPreview != null) {
      _assertMax(
        normalizedPreview,
        maxOutcomeTextPreviewLength,
        'outcomeTextPreview',
      );
    }

    final normalizedNote = _optionalTrim(userNote);
    if (normalizedNote != null) {
      _assertMax(normalizedNote, maxUserNoteLength, 'userNote');
    }

    return CoachingOutcomeEvent(
      id: normalizedId,
      partnerId: _optionalTrim(partnerId),
      conversationId: _optionalTrim(conversationId),
      source: source,
      adviceId: _optionalTrim(adviceId),
      adviceType: normalizedAdviceType,
      suggestedMoveSummary: summary,
      userAction: userAction,
      outcome: outcome,
      outcomeTextPreview: normalizedPreview,
      userNote: normalizedNote,
      createdAt: createdAt,
    );
  }

  bool get isPartnerScoped => _optionalTrim(partnerId) != null;

  CoachingOutcomeEvent withPartnerId(String? nextPartnerId) {
    return CoachingOutcomeEvent(
      id: id,
      partnerId: _optionalTrim(nextPartnerId),
      conversationId: conversationId,
      source: source,
      adviceId: adviceId,
      adviceType: adviceType,
      suggestedMoveSummary: suggestedMoveSummary,
      userAction: userAction,
      outcome: outcome,
      outcomeTextPreview: outcomeTextPreview,
      userNote: userNote,
      createdAt: createdAt,
    );
  }

  static String? normalizeScope(String? value) => _optionalTrim(value);

  static String? _optionalTrim(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static void _assertMax(String value, int max, String fieldName) {
    if (value.length > max) {
      throw ArgumentError('$fieldName exceeds $max chars');
    }
  }
}
