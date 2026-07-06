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
  final String? code;

  CoachChatQuotaExceededException(
    this.message, {
    this.used,
    this.limit,
    this.code,
  });

  @override
  String toString() =>
      'CoachChatQuotaExceededException: $message (code=$code, used=$used, limit=$limit)';
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
    List<String> outcomeInsightLines = const [],
    required bool dataQualityFlagged,
  }) async {
    final body = <String, dynamic>{
      'conversationId': conversationId,
      if (partnerId != null) 'partnerId': partnerId,
      if (sessionId != null && sessionId.trim().isNotEmpty)
        'sessionId': sessionId.trim(),
      'userQuestion': _clampForWire(question.trim(), 240),
      if (rawReplyDraft != null && rawReplyDraft.trim().isNotEmpty)
        'rawReplyDraft': _clampForWire(rawReplyDraft.trim(), 240),
      if (activeSessionTurns.isNotEmpty)
        'activeSessionTurns':
            activeSessionTurns.map(_sessionTurnToWire).toList(),
      if (forceAnswer) 'forceAnswer': true,
      'recentMessages': recentMessages.map(_messageToWire).toList(),
      if (conversationSummary != null && conversationSummary.trim().isNotEmpty)
        'conversationSummary': _clampForWire(conversationSummary.trim(), 500),
      if (analysisSnapshot != null)
        'analysisSnapshot': _analysisSnapshotToWire(analysisSnapshot),
      if (effectiveStyleContext != null &&
          effectiveStyleContext.trim().isNotEmpty)
        'effectiveStyleContext': _clampForWire(
          effectiveStyleContext.trim(),
          500,
        ),
      if (partnerHint != null)
        'partnerHint': _partnerHintToWire(
          partnerHint,
          dataQualityFlagged: dataQualityFlagged,
        ),
      if (outcomeInsightLines.isNotEmpty)
        'outcomeInsightLines': _outcomeInsightLinesToWire(outcomeInsightLines),
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
        final error = asMap['error']?.toString();
        // server per-user 模型限流不是訂閱額度：絕不 throw quota 例外
        // （那會開 paywall），走 ApiException 讓 UI 顯示「稍等再試」。
        if (asMap['code'] == 'MODEL_RATE_LIMITED') {
          throw CoachChatApiException(
            asMap['message']?.toString() ?? '請求太頻繁，請稍後再試。',
            status: 429,
          );
        }
        throw CoachChatQuotaExceededException(
          asMap['message']?.toString() ?? error ?? 'quota_exceeded',
          used: asMap['used'] is int ? asMap['used'] as int : null,
          limit: asMap['limit'] is int ? asMap['limit'] as int : null,
          code: _quotaCodeFrom(error ?? asMap['code']?.toString()),
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

  String? _quotaCodeFrom(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    if (normalized.contains('daily')) return 'DAILY_LIMIT_EXCEEDED';
    if (normalized.contains('monthly')) return 'MONTHLY_LIMIT_EXCEEDED';
    return null;
  }

  // server RequestSchema 是 strict＋硬長度上限，任一欄位超標整包 400；
  // 送出前一律照 schema clamp（截斷補省略號，總長不超過上限）。
  static String _clampForWire(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    return '${value.substring(0, maxLength - 1).trimRight()}…';
  }

  // 近期教練建議結果洞察（來自 CoachingOutcomeDigest.statisticalInsightLines）。
  // server schema 為 z.array(z.string().max(120)).max(6)，送出前照上限
  // 逐行截斷、去空白行，避免整包 400。含對象回覆原文/筆記的欄位絕不進這裡
  // ——localInsightLines 只含去識別化的統計句。
  List<String> _outcomeInsightLinesToWire(List<String> lines) {
    return lines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) => _clampForWire(line, 120))
        .take(6)
        .toList();
  }

  Map<String, dynamic> _messageToWire(CoachChatMessage message) {
    return <String, dynamic>{
      'sender': message.isFromMe ? 'me' : 'partner',
      'text': _clampForWire(message.text.trim(), 500),
      if (message.createdAt != null)
        'createdAt': message.createdAt!.toIso8601String(),
    };
  }

  Map<String, dynamic> _sessionTurnToWire(CoachChatSessionTurn turn) {
    return <String, dynamic>{
      'role': turn.role,
      'kind': turn.kind,
      'content': _clampForWire(turn.content.trim(), 500),
      if (turn.createdAt != null)
        'createdAt': turn.createdAt!.toIso8601String(),
    };
  }

  Map<String, dynamic> _analysisSnapshotToWire(
    CoachChatAnalysisSnapshot snapshot,
  ) {
    return <String, dynamic>{
      if (snapshot.heatScore != null)
        'heatScore': snapshot.heatScore!.clamp(0, 100),
      if (snapshot.stage != null && snapshot.stage!.trim().isNotEmpty)
        'stage': _clampForWire(snapshot.stage!.trim(), 40),
      if (snapshot.summary != null && snapshot.summary!.trim().isNotEmpty)
        'summary': _clampForWire(snapshot.summary!.trim(), 220),
      if (snapshot.nextStep != null && snapshot.nextStep!.trim().isNotEmpty)
        'nextStep': _clampForWire(snapshot.nextStep!.trim(), 220),
      if (snapshot.coachActionType != null &&
          snapshot.coachActionType!.trim().isNotEmpty)
        'coachActionType': _clampForWire(snapshot.coachActionType!.trim(), 80),
      if (snapshot.keySignals.isNotEmpty)
        'keySignals': snapshot.keySignals
            .map((signal) => signal.trim())
            .where((signal) => signal.isNotEmpty)
            .map((signal) => _clampForWire(signal, 80))
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
        'name': _clampForWire(hint.name!.trim(), 80),
      if (!dataQualityFlagged && hint.traits.isNotEmpty)
        'traits': hint.traits
            .map((trait) => trait.trim())
            .where((trait) => trait.isNotEmpty)
            .map((trait) => _clampForWire(trait, 40))
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
