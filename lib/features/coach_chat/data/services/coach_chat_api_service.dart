import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/coach_chat_result.dart';

class CoachChatMessage {
  final bool isFromMe;
  final String text;
  final DateTime? createdAt;

  const CoachChatMessage({
    required this.isFromMe,
    required this.text,
    this.createdAt,
  });
}

class CoachChatAnalysisSnapshot {
  final int? heatScore;
  final String? stage;
  final String? summary;
  final String? nextStep;
  final String? coachActionType;
  final List<String> keySignals;

  const CoachChatAnalysisSnapshot({
    this.heatScore,
    this.stage,
    this.summary,
    this.nextStep,
    this.coachActionType,
    this.keySignals = const [],
  });
}

class CoachChatPartnerHint {
  final String? name;
  final List<String> traits;

  const CoachChatPartnerHint({
    this.name,
    this.traits = const [],
  });
}

class CoachChatSessionTurn {
  final String role;
  final String kind;
  final String content;
  final DateTime? createdAt;

  const CoachChatSessionTurn({
    required this.role,
    required this.kind,
    required this.content,
    this.createdAt,
  });
}

typedef CoachChatInvoker = Future<CoachChatInvokeResponse> Function(
  String functionName, {
  required Map<String, dynamic> body,
});

class CoachChatInvokeResponse {
  final int status;
  final dynamic data;

  const CoachChatInvokeResponse({
    required this.status,
    this.data,
  });
}

class CoachChatApiException implements Exception {
  final String message;
  final int? status;
  CoachChatApiException(this.message, {this.status});

  @override
  String toString() => 'CoachChatApiException($status): $message';
}

class CoachChatQuotaExceededException implements Exception {
  final String message;
  final int? used;
  final int? limit;

  CoachChatQuotaExceededException(this.message, {this.used, this.limit});

  @override
  String toString() =>
      'CoachChatQuotaExceededException: $message (used=$used, limit=$limit)';
}

class CoachChatGenerationFailedException implements Exception {
  final String message;
  CoachChatGenerationFailedException(this.message);

  @override
  String toString() => 'CoachChatGenerationFailedException: $message';
}

const _bannedTokens = <String>[
  'PUA',
  '收割',
  '控住',
  '攻略',
  '壞女人',
  '高分妹',
  '玩咖',
];

const _visibleCardFields = <String>[
  'headline',
  'answer',
  'userTruth',
  'userState',
  'nextStep',
  'suggestedLine',
  'rewriteReason',
  'boundaryReminder',
  'reflectionQuestion',
];

class CoachChatApiService {
  CoachChatApiService({CoachChatInvoker? invoker})
      : _invoke = invoker ?? _defaultInvoker;

  final CoachChatInvoker _invoke;

  Future<CoachChatResult> ask({
    required String conversationId,
    required String? partnerId,
    String? sessionId,
    required String question,
    String? rawReplyDraft,
    List<CoachChatSessionTurn> activeSessionTurns = const [],
    bool forceAnswer = false,
    required List<CoachChatMessage> recentMessages,
    String? conversationSummary,
    CoachChatAnalysisSnapshot? analysisSnapshot,
    String? effectiveStyleContext,
    CoachChatPartnerHint? partnerHint,
    required bool dataQualityFlagged,
  }) async {
    final body = <String, dynamic>{
      'conversationId': conversationId,
      if (partnerId != null) 'partnerId': partnerId,
      if (sessionId != null && sessionId.trim().isNotEmpty)
        'sessionId': sessionId.trim(),
      'userQuestion': question.trim(),
      if (rawReplyDraft != null && rawReplyDraft.trim().isNotEmpty)
        'rawReplyDraft': rawReplyDraft.trim(),
      if (activeSessionTurns.isNotEmpty)
        'activeSessionTurns':
            activeSessionTurns.map(_sessionTurnToWire).toList(),
      if (forceAnswer) 'forceAnswer': true,
      'recentMessages': recentMessages.map(_messageToWire).toList(),
      if (conversationSummary != null && conversationSummary.trim().isNotEmpty)
        'conversationSummary': conversationSummary.trim(),
      if (analysisSnapshot != null)
        'analysisSnapshot': _analysisSnapshotToWire(analysisSnapshot),
      if (effectiveStyleContext != null &&
          effectiveStyleContext.trim().isNotEmpty)
        'effectiveStyleContext': effectiveStyleContext.trim(),
      if (partnerHint != null)
        'partnerHint': _partnerHintToWire(
          partnerHint,
          dataQualityFlagged: dataQualityFlagged,
        ),
      'dataQualityFlagged': dataQualityFlagged,
    };

    final response = await _invoke('coach-chat', body: body);
    switch (response.status) {
      case 200:
        return _parseSuccess(
          conversationId: conversationId,
          partnerId: partnerId,
          question: question.trim(),
          data: response.data,
        );
      case 429:
        final data = response.data;
        final asMap = data is Map ? data : const {};
        throw CoachChatQuotaExceededException(
          asMap['error']?.toString() ?? 'quota_exceeded',
          used: asMap['used'] is int ? asMap['used'] as int : null,
          limit: asMap['limit'] is int ? asMap['limit'] as int : null,
        );
      default:
        if (response.status >= 500) {
          throw CoachChatGenerationFailedException(
              _extractError(response.data));
        }
        throw CoachChatApiException(
          _extractError(response.data),
          status: response.status,
        );
    }
  }

  Map<String, dynamic> _messageToWire(CoachChatMessage message) {
    return <String, dynamic>{
      'sender': message.isFromMe ? 'me' : 'partner',
      'text': message.text.trim(),
      if (message.createdAt != null)
        'createdAt': message.createdAt!.toIso8601String(),
    };
  }

  Map<String, dynamic> _sessionTurnToWire(CoachChatSessionTurn turn) {
    return <String, dynamic>{
      'role': turn.role,
      'kind': turn.kind,
      'content': turn.content.trim(),
      if (turn.createdAt != null)
        'createdAt': turn.createdAt!.toIso8601String(),
    };
  }

  Map<String, dynamic> _analysisSnapshotToWire(
    CoachChatAnalysisSnapshot snapshot,
  ) {
    return <String, dynamic>{
      if (snapshot.heatScore != null) 'heatScore': snapshot.heatScore,
      if (snapshot.stage != null && snapshot.stage!.trim().isNotEmpty)
        'stage': snapshot.stage!.trim(),
      if (snapshot.summary != null && snapshot.summary!.trim().isNotEmpty)
        'summary': snapshot.summary!.trim(),
      if (snapshot.nextStep != null && snapshot.nextStep!.trim().isNotEmpty)
        'nextStep': snapshot.nextStep!.trim(),
      if (snapshot.coachActionType != null &&
          snapshot.coachActionType!.trim().isNotEmpty)
        'coachActionType': snapshot.coachActionType!.trim(),
      if (snapshot.keySignals.isNotEmpty)
        'keySignals': snapshot.keySignals
            .map((signal) => signal.trim())
            .where((signal) => signal.isNotEmpty)
            .take(8)
            .toList(),
    };
  }

  Map<String, dynamic> _partnerHintToWire(
    CoachChatPartnerHint hint, {
    required bool dataQualityFlagged,
  }) {
    return <String, dynamic>{
      if (hint.name != null && hint.name!.trim().isNotEmpty)
        'name': hint.name!.trim(),
      if (!dataQualityFlagged && hint.traits.isNotEmpty)
        'traits': hint.traits
            .map((trait) => trait.trim())
            .where((trait) => trait.isNotEmpty)
            .take(5)
            .toList(),
    };
  }

  CoachChatResult _parseSuccess({
    required String conversationId,
    required String? partnerId,
    required String question,
    required dynamic data,
  }) {
    if (data is! Map) {
      throw CoachChatGenerationFailedException('malformed_response: not_a_map');
    }
    final card = data['card'];
    if (card is! Map) {
      throw CoachChatGenerationFailedException(
          'malformed_response: missing_card');
    }
    final cardMap = Map<String, dynamic>.from(card);
    _assertCardSafe(cardMap);

    final mode = _requireString(cardMap, 'mode');
    final responseTypeValue = cardMap['responseType'];
    final responseType =
        responseTypeValue is String && responseTypeValue.isNotEmpty
            ? responseTypeValue
            : 'coachAnswer';
    final headline = _requireString(cardMap, 'headline');
    final answer = _requireString(cardMap, 'answer');
    final userState = _requireString(cardMap, 'userState');
    final frictionType = cardMap['frictionType'];
    final nextStep = _requireString(cardMap, 'nextStep');
    final boundaryReminder = _requireString(cardMap, 'boundaryReminder');
    final userTruth = cardMap['userTruth'];
    final rewriteDecision = cardMap['rewriteDecision'];
    final rewriteReason = cardMap['rewriteReason'];
    final costDeducted = cardMap['costDeducted'];
    final needsReflection = cardMap['needsReflection'];
    if (needsReflection is! bool) {
      throw CoachChatGenerationFailedException(
        'malformed_response: missing_needsReflection',
      );
    }
    final suggestedLine = cardMap['suggestedLine'];
    final reflectionQuestion = cardMap['reflectionQuestion'];
    final provider = data['provider'];
    final model = data['model'];
    final generatedAt = data['generatedAt'];
    if (provider is! String || provider.isEmpty) {
      throw CoachChatGenerationFailedException(
          'malformed_response: missing_provider');
    }
    if (model is! String || model.isEmpty) {
      throw CoachChatGenerationFailedException(
          'malformed_response: missing_model');
    }
    if (generatedAt is! String) {
      throw CoachChatGenerationFailedException(
        'malformed_response: missing_generatedAt',
      );
    }
    final parsedAt = DateTime.tryParse(generatedAt);
    if (parsedAt == null) {
      throw CoachChatGenerationFailedException(
          'malformed_response: bad_generatedAt');
    }

    return CoachChatResult(
      id: '$conversationId-${parsedAt.microsecondsSinceEpoch}',
      conversationId: conversationId,
      partnerId: partnerId,
      question: question,
      mode: mode,
      headline: headline,
      answer: answer,
      userTruth:
          userTruth is String && userTruth.trim().isNotEmpty ? userTruth : null,
      userState: userState,
      frictionType: frictionType is String && frictionType.trim().isNotEmpty
          ? frictionType
          : 'unclearIntent',
      nextStep: nextStep,
      suggestedLine: suggestedLine is String && suggestedLine.trim().isNotEmpty
          ? suggestedLine
          : null,
      rewriteDecision:
          rewriteDecision is String && rewriteDecision.trim().isNotEmpty
              ? rewriteDecision
              : null,
      rewriteReason: rewriteReason is String && rewriteReason.trim().isNotEmpty
          ? rewriteReason
          : null,
      boundaryReminder: boundaryReminder,
      needsReflection: needsReflection,
      reflectionQuestion:
          reflectionQuestion is String && reflectionQuestion.trim().isNotEmpty
              ? reflectionQuestion
              : null,
      generatedAt: parsedAt,
      provider: provider,
      modelUsed: model,
      responseType: responseType,
      sessionId: _stringOrNull(data['sessionId']),
      costDeducted: costDeducted is int ? costDeducted : 1,
    );
  }

  String? _stringOrNull(dynamic value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }

  String _requireString(Map<String, dynamic> map, String field) {
    final value = map[field];
    if (value is! String || value.trim().isEmpty) {
      throw CoachChatGenerationFailedException(
        'malformed_response: missing_$field',
      );
    }
    return value;
  }

  void _assertCardSafe(Map<String, dynamic> card) {
    for (final field in _visibleCardFields) {
      final value = card[field];
      if (value is! String) continue;
      for (final token in _bannedTokens) {
        if (value.contains(token)) {
          throw CoachChatGenerationFailedException(
            'banned_token: $token found in $field',
          );
        }
      }
    }
  }

  String _extractError(dynamic data) {
    if (data is Map && data['error'] != null) return data['error'].toString();
    return 'unknown_error';
  }
}

Future<CoachChatInvokeResponse> _defaultInvoker(
  String fn, {
  required Map<String, dynamic> body,
}) async {
  final res = await Supabase.instance.client.functions.invoke(fn, body: body);
  return CoachChatInvokeResponse(status: res.status, data: res.data);
}
