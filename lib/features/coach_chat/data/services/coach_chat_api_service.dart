import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/environment.dart';
import '../../../../core/services/supabase_service.dart';
import '../../domain/entities/coach_chat_result.dart';
import '../../domain/entities/coach_scope.dart';

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

enum CoachChatProgressStage {
  request,
  generating,
  validating,
  retrying,
  finalizing,
}

class CoachChatProgressUpdate {
  final CoachChatProgressStage stage;
  final int? attempt;
  final int? maxAttempts;

  const CoachChatProgressUpdate({
    required this.stage,
    this.attempt,
    this.maxAttempts,
  });
}

typedef CoachChatProgressCallback = void Function(
  CoachChatProgressUpdate update,
);

typedef CoachChatProgressInvoker = Future<CoachChatInvokeResponse> Function(
  String functionName, {
  required Map<String, dynamic> body,
  required CoachChatProgressCallback onProgress,
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
  CoachChatApiService({
    CoachChatInvoker? invoker,
    CoachChatProgressInvoker? progressInvoker,
    http.Client Function()? clientFactory,
    String? Function()? accessTokenProvider,
    bool? progressStreamingEnabled,
  })  : _invoke = invoker ?? _defaultInvoker,
        _progressInvoker = progressInvoker,
        _clientFactory = clientFactory ?? http.Client.new,
        _accessTokenProvider =
            accessTokenProvider ?? (() => SupabaseService.accessToken),
        _useProgressStreaming = progressStreamingEnabled ??
            (progressInvoker != null ||
                (invoker == null && _defaultProgressStreamingEnabled));

  static const _defaultProgressStreamingEnabled = bool.fromEnvironment(
    'COACH_PROGRESS_STREAMING_ENABLED',
    defaultValue: true,
  );
  static const _progressMediaType = 'application/x-ndjson';
  // A new client can temporarily talk to an older buffered Edge revision
  // during rollout. That path may legitimately use all three 60-second model
  // attempts before response headers exist, so the header wait must cover the
  // old worst case. A timeout still fails once and never replays the request.
  static const defaultProgressConnectTimeout = Duration(minutes: 4);
  static const _idleTimeout = Duration(seconds: 120);

  final CoachChatInvoker _invoke;
  final CoachChatProgressInvoker? _progressInvoker;
  final http.Client Function() _clientFactory;
  final String? Function() _accessTokenProvider;
  final bool _useProgressStreaming;

  /// Phase E 新欄位皆選填、非 null 才進 body（缺席語意，server schema 是
  /// strict）：
  /// - [requestId]：UUID，server 端 lowercase 後做冪等鍵。
  /// - [scope]：非 null 時 wire `conversationId` 改用
  ///   [CoachScope.wireConversationId]；partner scope 並以 scope.id 覆寫
  ///   頂層 `partnerId`（server superRefine 要求兩者一致）。
  /// - [lifecyclePhase]：client 不驗值（server 是真相源）；目前合法值為
  ///   `chatStalled` / `prepareInvite` / `postDate`。
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
    CoachChatProgressCallback? onProgress,
    String? requestId,
    CoachScope? scope,
    String? lifecyclePhase,
  }) async {
    // scope 為真相源：partner scope 頂層 partnerId 一律覆寫成 scope.id，
    // 呼叫端沒傳也要補齊 superRefine 一致性。
    final effectivePartnerId =
        (scope != null && !scope.isConversation) ? scope.id : partnerId;
    final body = <String, dynamic>{
      'conversationId': scope?.wireConversationId ?? conversationId,
      if (effectivePartnerId != null) 'partnerId': effectivePartnerId,
      if (requestId != null) 'requestId': requestId,
      if (scope != null) 'scope': scope.toWireJson(),
      if (lifecyclePhase != null) 'lifecyclePhase': lifecyclePhase,
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

    late final CoachChatInvokeResponse response;
    if (_useProgressStreaming) {
      final requestedProgressCallback = onProgress ?? (_) {};
      void progressCallback(CoachChatProgressUpdate update) {
        _emitProgress(requestedProgressCallback, update);
      }

      final progressInvoker = _progressInvoker;
      response = progressInvoker != null
          ? await progressInvoker(
              'coach-chat',
              body: body,
              onProgress: progressCallback,
            )
          : await _invokeProgressHttp(
              'coach-chat',
              body: body,
              onProgress: progressCallback,
            );
    } else {
      response = await _invoke('coach-chat', body: body);
    }
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

  Future<CoachChatInvokeResponse> _invokeProgressHttp(
    String functionName, {
    required Map<String, dynamic> body,
    required CoachChatProgressCallback onProgress,
  }) async {
    final accessToken = _accessTokenProvider();
    if (accessToken == null || accessToken.trim().isEmpty) {
      return const CoachChatInvokeResponse(
        status: 401,
        data: {'error': 'unauthorized'},
      );
    }

    final client = _clientFactory();
    try {
      final request = http.Request(
        'POST',
        Uri.parse('${AppConfig.supabaseUrl}/functions/v1/$functionName'),
      )
        ..headers.addAll({
          'Content-Type': 'application/json',
          'Accept': _progressMediaType,
          'Authorization': 'Bearer $accessToken',
          'apikey': AppConfig.supabaseAnonKey,
        })
        ..body = jsonEncode(body);

      final response =
          await client.send(request).timeout(defaultProgressConnectTimeout);
      final contentType = response.headers['content-type']?.toLowerCase() ?? '';

      // Preflight/auth/quota failures keep their original HTTP status and JSON
      // body. An older Edge revision also returns JSON 200 here; accepting it is
      // the buffered compatibility path and must not trigger a second request.
      if (response.statusCode != 200 ||
          !contentType.contains(_progressMediaType)) {
        final raw = await response.stream.bytesToString().timeout(_idleTimeout);
        return CoachChatInvokeResponse(
          status: response.statusCode,
          data: _decodeJsonBody(raw),
        );
      }

      await for (final rawLine in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(_idleTimeout)) {
        final line = rawLine.trim();
        if (line.isEmpty) continue;
        final event = _decodeStreamEvent(line);
        switch (event['type']) {
          case 'coach.progress':
            final stage = _progressStageFromWire(event['stage']);
            if (stage == null) continue;
            onProgress(
              CoachChatProgressUpdate(
                stage: stage,
                attempt: _intFromWire(event['attempt']),
                maxAttempts: _intFromWire(event['maxAttempts']),
              ),
            );
            break;
          case 'coach.done':
            final result = event['result'];
            if (result is! Map) {
              throw CoachChatGenerationFailedException(
                'invalid_progress_stream: missing_result',
              );
            }
            return CoachChatInvokeResponse(
              status: 200,
              data: Map<String, dynamic>.from(result),
            );
          case 'coach.error':
            final error = event['error'];
            return CoachChatInvokeResponse(
              status: _intFromWire(event['status']) ?? 500,
              data: error is Map
                  ? Map<String, dynamic>.from(error)
                  : const {'error': 'unknown_error'},
            );
          default:
            throw CoachChatGenerationFailedException(
              'invalid_progress_stream: unknown_event',
            );
        }
      }
      throw CoachChatGenerationFailedException(
        'invalid_progress_stream: missing_terminal_event',
      );
    } on TimeoutException {
      throw CoachChatGenerationFailedException('timeout');
    } finally {
      client.close();
    }
  }

  dynamic _decodeJsonBody(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return <String, dynamic>{
        'error': raw.trim().isEmpty ? 'empty_response' : raw.trim(),
      };
    }
  }

  Map<String, dynamic> _decodeStreamEvent(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Mapped below to the same non-retriable client contract failure.
    }
    throw CoachChatGenerationFailedException(
      'invalid_progress_stream: malformed_event',
    );
  }

  CoachChatProgressStage? _progressStageFromWire(dynamic value) {
    return switch (value) {
      'request' => CoachChatProgressStage.request,
      'generating' => CoachChatProgressStage.generating,
      'validating' => CoachChatProgressStage.validating,
      'retrying' => CoachChatProgressStage.retrying,
      'finalizing' => CoachChatProgressStage.finalizing,
      _ => null,
    };
  }

  int? _intFromWire(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  void _emitProgress(
    CoachChatProgressCallback callback,
    CoachChatProgressUpdate update,
  ) {
    try {
      callback(update);
    } catch (_) {
      // Progress is best-effort UI state and must never abort a request that
      // may still produce and charge one validated formal answer.
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
