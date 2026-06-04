import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../../core/config/environment.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../conversation/domain/entities/message.dart';
import '../../../conversation/domain/entities/session_context.dart';
import '../../domain/entities/analysis_models.dart';
import '../../domain/entities/quick_analysis_result.dart';

class ImageData {
  final String data;
  final String mediaType;
  final int order;

  ImageData({
    required this.data,
    required this.mediaType,
    required this.order,
  });

  Map<String, dynamic> toJson() => {
        'data': data,
        'mediaType': mediaType,
        'order': order,
      };
}

enum AnalysisProgressStage {
  preparingPayload,
  uploadingRequest,
  awaitingAi,
}

class AnalysisProgressUpdate {
  final AnalysisProgressStage stage;
  final int imageCount;
  final Duration elapsed;
  final int? requestBodyBytes;

  const AnalysisProgressUpdate({
    required this.stage,
    required this.imageCount,
    required this.elapsed,
    this.requestBodyBytes,
  });
}

class AnalysisTelemetry {
  final String? requestType;
  final int imageCount;
  final int requestBodyBytes;
  final Duration payloadPreparationDuration;
  final Duration roundTripDuration;
  final Duration? edgeAiDuration;
  final int? totalCompressedImageBytes;
  final bool cacheHit;
  final bool fallbackUsed;
  final int retryCount;
  final Duration? timeoutDuration;
  final bool? allowModelFallback;
  final String? contextMode;
  final int? inputMessageCount;
  final int? compiledMessageCount;
  final int? truncatedMessageCount;
  final int? openingMessagesUsed;
  final int? recentMessagesUsed;
  final bool conversationSummaryUsed;
  final String? recognizedClassification;
  final String? recognizedConfidence;
  final String? recognizedSideConfidence;
  final int? recognizedMessageCount;
  final int? uncertainSideCount;
  final int? continuityAdjustedCount;
  final int? groupedAdjustedCount;
  final int? layoutFirstAdjustedCount;
  final int? systemRowsRemovedCount;
  final int? quotedPreviewRemovedCount;
  final int? quotedPreviewAttachedCount;
  final int? overlapRemovedCount;
  final bool? shouldChargeQuota;
  final int? chargedMessageCount;
  final int? estimatedMessageCount;
  final String? quotaReason;

  const AnalysisTelemetry({
    this.requestType,
    required this.imageCount,
    required this.requestBodyBytes,
    required this.payloadPreparationDuration,
    required this.roundTripDuration,
    this.edgeAiDuration,
    this.totalCompressedImageBytes,
    this.cacheHit = false,
    this.fallbackUsed = false,
    this.retryCount = 0,
    this.timeoutDuration,
    this.allowModelFallback,
    this.contextMode,
    this.inputMessageCount,
    this.compiledMessageCount,
    this.truncatedMessageCount,
    this.openingMessagesUsed,
    this.recentMessagesUsed,
    this.conversationSummaryUsed = false,
    this.recognizedClassification,
    this.recognizedConfidence,
    this.recognizedSideConfidence,
    this.recognizedMessageCount,
    this.uncertainSideCount,
    this.continuityAdjustedCount,
    this.groupedAdjustedCount,
    this.layoutFirstAdjustedCount,
    this.systemRowsRemovedCount,
    this.quotedPreviewRemovedCount,
    this.quotedPreviewAttachedCount,
    this.overlapRemovedCount,
    this.shouldChargeQuota,
    this.chargedMessageCount,
    this.estimatedMessageCount,
    this.quotaReason,
  });

  Duration? get estimatedTransferDuration {
    if (edgeAiDuration == null) {
      return null;
    }

    final remainingMs =
        roundTripDuration.inMilliseconds - edgeAiDuration!.inMilliseconds;
    return Duration(milliseconds: remainingMs < 0 ? 0 : remainingMs);
  }
}

typedef AnalysisProgressCallback = void Function(
  AnalysisProgressUpdate update,
);

typedef AnalysisTelemetryCallback = void Function(
  AnalysisTelemetry telemetry,
);

enum AnalysisStreamUpdateKind {
  started,
  progress,
  content,
  recommendation,
  done,
}

enum AnalysisStreamContentKind {
  decision,
  replyOption,
  metrics,
  coachHint,
  reportSection,
}

class AnalysisStreamContent {
  final AnalysisStreamContentKind kind;
  final String title;
  final String body;
  final String? tag;
  final Map<String, dynamic> rawEvent;

  const AnalysisStreamContent({
    required this.kind,
    required this.title,
    required this.body,
    this.tag,
    required this.rawEvent,
  });

  static AnalysisStreamContent? fromEvent(Map<String, dynamic> event) {
    final type = _stringField(event['type']);
    switch (type) {
      case 'analysis.decision':
        return AnalysisStreamContent(
          kind: AnalysisStreamContentKind.decision,
          title: _stringField(event['nextStepTitle']) ?? '下一步策略',
          body: _joinNonEmpty([
            _stringField(event['nextStepBody']) ??
                _stringField(event['nextStep']),
            _prefix('建議', _stringField(event['doThis'])),
            _prefix('避免', _stringField(event['avoidThis'])),
          ]),
          rawEvent: event,
        );
      case 'analysis.reply_option':
        final style = _stringField(event['style']) ??
            _stringField(event['selectedStyle']);
        return AnalysisStreamContent(
          kind: AnalysisStreamContentKind.replyOption,
          title: '回覆選項：${_styleLabel(style)}',
          body: _joinNonEmpty([
            _stringField(event['message']),
            _prefix(
              '思路',
              _stringField(event['reason']) ?? _stringField(event['approach']),
            ),
            _prefix(
              '對應',
              _stringField(event['quotedContext']) ??
                  _stringField(event['sourceMessage']),
            ),
          ]),
          tag: style,
          rawEvent: event,
        );
      case 'analysis.metrics':
        final score = _numberField(
          event['heat'] ?? event['enthusiasmScore'] ?? event['score'],
        );
        final topicDepth = _recordField(event['topicDepth']);
        return AnalysisStreamContent(
          kind: AnalysisStreamContentKind.metrics,
          title: '互動指標',
          body: _joinNonEmpty([
            score == null ? null : '互動熱度：$score/100',
            _prefix(
              '話題深度',
              _stringField(topicDepth?['suggestion']) ??
                  _stringField(topicDepth?['current']),
            ),
          ]),
          rawEvent: event,
        );
      case 'analysis.coach_hint':
        final hint = event['coachActionHint'];
        return AnalysisStreamContent(
          kind: AnalysisStreamContentKind.coachHint,
          title: '教練提示',
          body: _stringify(hint) ??
              _joinNonEmpty([
                _stringField(event['title']),
                _stringField(event['message']),
                _stringField(event['body']),
              ]),
          rawEvent: event,
        );
      case 'analysis.report_section':
        final section = _stringField(event['section']);
        return AnalysisStreamContent(
          kind: AnalysisStreamContentKind.reportSection,
          title: _sectionLabel(section),
          body: _stringify(event['payload']) ??
              _stringify(event['content']) ??
              _stringField(event['message']) ??
              '',
          tag: section,
          rawEvent: event,
        );
      default:
        return null;
    }
  }

  static String _styleLabel(String? style) {
    switch (style) {
      case 'extend':
        return '延伸話題';
      case 'resonate':
        return '共鳴回應';
      case 'tease':
        return '輕鬆挑逗';
      case 'humor':
        return '幽默回覆';
      case 'coldRead':
        return '冷讀觀察';
      default:
        return '可用回覆';
    }
  }

  static String _sectionLabel(String? section) {
    switch (section) {
      case 'strategy':
        return '深度策略';
      case 'warnings':
        return '注意事項';
      case 'psychology':
        return '心理訊號';
      case 'topicDepth':
        return '話題深度';
      case 'gameStage':
        return '關係階段';
      default:
        return '完整分析段落';
    }
  }

  static String? _prefix(String label, String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return '$label：${value.trim()}';
  }

  static String _joinNonEmpty(Iterable<String?> values) {
    return values
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join('\n');
  }

  static String? _stringField(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static int? _numberField(dynamic value) {
    if (value is num && value.isFinite) return value.round();
    return null;
  }

  static Map<String, dynamic>? _recordField(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  static String? _stringify(dynamic value) {
    if (value == null) return null;
    if (value is String) return _stringField(value);
    if (value is List) {
      final joined = value
          .map(_stringify)
          .whereType<String>()
          .where((item) => item.trim().isNotEmpty)
          .join('\n');
      return joined.isEmpty ? null : joined;
    }
    if (value is Map) {
      final direct = _joinNonEmpty([
        _stringField(value['title']),
        _stringField(value['message']),
        _stringField(value['body']),
        _stringField(value['summary']),
        _stringField(value['suggestion']),
      ]);
      if (direct.isNotEmpty) return direct;
      return jsonEncode(value);
    }
    return value.toString();
  }
}

class AnalysisStreamUpdate {
  final AnalysisStreamUpdateKind kind;
  final String? runId;
  final String? label;
  final String? detail;
  final int? etaSeconds;
  final AnalysisStreamContent? content;
  final QuickAnalysisResult? quick;
  final AnalysisResult? result;
  final Map<String, dynamic>? rawEvent;

  const AnalysisStreamUpdate._({
    required this.kind,
    this.runId,
    this.label,
    this.detail,
    this.etaSeconds,
    this.content,
    this.quick,
    this.result,
    this.rawEvent,
  });

  const AnalysisStreamUpdate.started({
    String? runId,
    String? label,
    String? detail,
    int? etaSeconds,
    Map<String, dynamic>? rawEvent,
  }) : this._(
          kind: AnalysisStreamUpdateKind.started,
          runId: runId,
          label: label,
          detail: detail,
          etaSeconds: etaSeconds,
          rawEvent: rawEvent,
        );

  const AnalysisStreamUpdate.progress({
    String? runId,
    String? label,
    String? detail,
    int? etaSeconds,
    Map<String, dynamic>? rawEvent,
  }) : this._(
          kind: AnalysisStreamUpdateKind.progress,
          runId: runId,
          label: label,
          detail: detail,
          etaSeconds: etaSeconds,
          rawEvent: rawEvent,
        );

  const AnalysisStreamUpdate.content({
    required AnalysisStreamContent content,
    String? runId,
    String? label,
    String? detail,
    int? etaSeconds,
    Map<String, dynamic>? rawEvent,
  }) : this._(
          kind: AnalysisStreamUpdateKind.content,
          runId: runId,
          label: label,
          detail: detail,
          etaSeconds: etaSeconds,
          content: content,
          rawEvent: rawEvent,
        );

  const AnalysisStreamUpdate.recommendation({
    required QuickAnalysisResult quick,
    String? runId,
    String? label,
    String? detail,
    int? etaSeconds,
    Map<String, dynamic>? rawEvent,
  }) : this._(
          kind: AnalysisStreamUpdateKind.recommendation,
          runId: runId,
          label: label,
          detail: detail,
          etaSeconds: etaSeconds,
          quick: quick,
          rawEvent: rawEvent,
        );

  const AnalysisStreamUpdate.done({
    required AnalysisResult result,
    String? runId,
    String? label,
    String? detail,
    int? etaSeconds,
    Map<String, dynamic>? rawEvent,
  }) : this._(
          kind: AnalysisStreamUpdateKind.done,
          runId: runId,
          label: label,
          detail: detail,
          etaSeconds: etaSeconds,
          result: result,
          rawEvent: rawEvent,
        );
}

enum AnalysisErrorAction {
  retry,
  relogin,
  rescreenshot,
  shortenInput,
  upgrade,
  wait,
  addIncomingMessage,
}

void _debugLog(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}

bool _isReadableUserMessage(String message) {
  return message.contains(RegExp(r'[\u4e00-\u9fff]'));
}

AnalysisException _mapAnalysisHttpError({
  required int statusCode,
  required String? errorCode,
  required String rawMessage,
  required bool hasImages,
  required bool recognizeOnly,
  required bool hasUserDraft,
}) {
  final normalizedMessage = rawMessage.trim();
  final lowerMessage = normalizedMessage.toLowerCase();

  String recognitionUnsupportedMessage() {
    if (normalizedMessage.isEmpty) {
      return '這張圖目前不像可匯入的聊天截圖，請改傳完整聊天視窗後再試。';
    }

    if (_isReadableUserMessage(normalizedMessage)) {
      return normalizedMessage;
    }

    if (lowerMessage.contains('call log') ||
        lowerMessage.contains('system notification')) {
      return '這張圖看起來比較像通話紀錄或系統通知畫面。若這其實是聊天視窗，請保留標題列與完整訊息泡泡後再試。';
    }

    if (lowerMessage.contains('social feed') ||
        lowerMessage.contains('comment thread')) {
      return '這張圖看起來比較像社群貼文或留言串，不是一般雙人聊天截圖。請改傳聊天視窗後再試。';
    }

    return '這張圖目前不像可匯入的聊天截圖，請改傳完整聊天視窗後再試。';
  }

  switch (statusCode) {
    case 400:
      switch (errorCode) {
        case 'RECOGNITION_UNSUPPORTED':
          return AnalysisException(
            recognitionUnsupportedMessage(),
            code: errorCode,
            suggestedAction: AnalysisErrorAction.rescreenshot,
          );
        case 'RECOGNITION_FAILED':
          return AnalysisException(
            _isReadableUserMessage(normalizedMessage) &&
                    normalizedMessage.isNotEmpty
                ? normalizedMessage
                : '這張圖暫時辨識不穩，請換一張更清楚的截圖再試。',
            code: errorCode,
            suggestedAction: AnalysisErrorAction.rescreenshot,
          );
      }

      if (normalizedMessage == 'Messages cannot be empty') {
        return AnalysisException(
          '請先加入對話內容再分析。',
          code: 'EMPTY_MESSAGES',
          suggestedAction: AnalysisErrorAction.addIncomingMessage,
        );
      }

      if (normalizedMessage == 'Request body too large' ||
          normalizedMessage == 'Total image payload too large') {
        return AnalysisException(
          '這次上傳的內容太多或圖片太大，請減少張數或重新截圖後再試。',
          code: 'REQUEST_TOO_LARGE',
          suggestedAction: AnalysisErrorAction.shortenInput,
        );
      }

      if (normalizedMessage == 'Unsupported image type' ||
          lowerMessage.contains('unsupported image type')) {
        return AnalysisException(
          '目前不支援這種圖片格式，請改用一般截圖後再試。',
          code: 'UNSUPPORTED_IMAGE_TYPE',
          suggestedAction: AnalysisErrorAction.rescreenshot,
        );
      }

      if (normalizedMessage.contains('圖片格式錯誤') ||
          lowerMessage.contains('invalid image format')) {
        return AnalysisException(
          '圖片格式有誤，請重新截圖後再試。',
          code: 'INVALID_IMAGE_FORMAT',
          suggestedAction: AnalysisErrorAction.rescreenshot,
        );
      }

      if (normalizedMessage.contains('圖片順序錯誤') ||
          normalizedMessage.contains('圖片排序重複') ||
          lowerMessage.contains('invalid image order')) {
        return AnalysisException(
          '截圖順序有誤，請重新選擇圖片後再試。',
          code: 'INVALID_IMAGE_ORDER',
          suggestedAction: AnalysisErrorAction.rescreenshot,
        );
      }

      if (normalizedMessage.startsWith('userDraft too long')) {
        return AnalysisException(
          '你輸入的草稿太長了，請精簡後再試。',
          code: 'USER_DRAFT_TOO_LONG',
          suggestedAction: AnalysisErrorAction.shortenInput,
        );
      }

      if (normalizedMessage.startsWith('conversationSummary too long')) {
        return AnalysisException(
          '這段對話的上下文太長了，請精簡後再試。',
          code: 'CONTEXT_TOO_LONG',
          suggestedAction: AnalysisErrorAction.shortenInput,
        );
      }

      if (normalizedMessage ==
          'At least one incoming message is required for analysis') {
        return AnalysisException(
          '至少要有一則對方訊息才能開始分析。',
          code: 'NO_INCOMING_MESSAGE',
          suggestedAction: AnalysisErrorAction.addIncomingMessage,
        );
      }

      if (normalizedMessage ==
          'my_message mode requires the latest message to be from the user') {
        return AnalysisException(
          '「優化我說」需要最新一則是你自己發出的訊息。',
          code: 'INVALID_MY_MESSAGE_CONTEXT',
          suggestedAction: AnalysisErrorAction.retry,
        );
      }

      if (normalizedMessage == 'recognizeOnly requires images') {
        return AnalysisException(
          '請先選擇截圖再開始辨識。',
          code: 'IMAGES_REQUIRED',
          suggestedAction: AnalysisErrorAction.rescreenshot,
        );
      }

      return AnalysisException(
        hasImages
            ? '這次上傳的截圖內容有誤，請重新截圖後再試。'
            : hasUserDraft
                ? '這次送出的草稿內容有誤，請修改後再試。'
                : '這次送出的對話內容有誤，請檢查後再試。',
        code: errorCode ?? 'BAD_REQUEST',
        suggestedAction: hasImages
            ? AnalysisErrorAction.rescreenshot
            : AnalysisErrorAction.retry,
      );
    case 401:
      return AnalysisException(
        '登入狀態已失效，請重新登入後再試。',
        code: errorCode ?? 'UNAUTHORIZED',
        suggestedAction: AnalysisErrorAction.relogin,
      );
    case 403:
      if (errorCode == 'FEATURE_NOT_AVAILABLE') {
        return AnalysisException(
          '這個功能需要 Essential 方案才能使用。',
          code: errorCode,
          suggestedAction: AnalysisErrorAction.upgrade,
        );
      }
      return AnalysisException(
        '你目前沒有權限使用這個功能。',
        code: errorCode ?? 'FORBIDDEN',
        suggestedAction: AnalysisErrorAction.wait,
      );
    case 413:
      return AnalysisException(
        '這次上傳的內容太大，請減少張數或重新截圖後再試。',
        code: errorCode ?? 'PAYLOAD_TOO_LARGE',
        suggestedAction: AnalysisErrorAction.shortenInput,
      );
    case 502:
    case 503:
    case 504:
      return AnalysisException(
        hasImages
            ? recognizeOnly
                ? '截圖辨識服務目前較忙，請稍後再試。'
                : '圖片分析服務目前較忙，請稍後再試。'
            : hasUserDraft
                ? '訊息優化服務目前較忙，請稍後再試。'
                : '分析服務目前較忙，請稍後再試。',
        code: errorCode ?? 'UPSTREAM_UNAVAILABLE',
        suggestedAction: AnalysisErrorAction.wait,
      );
    default:
      return AnalysisException(
        hasImages
            ? recognizeOnly
                ? '截圖辨識暫時失敗，請稍後再試。'
                : '圖片分析暫時失敗，請稍後再試。'
            : hasUserDraft
                ? '訊息優化暫時失敗，請稍後再試。'
                : '分析暫時失敗，請稍後再試。',
        code: errorCode ?? 'UNKNOWN_HTTP_ERROR',
        suggestedAction: AnalysisErrorAction.retry,
      );
  }
}

AnalysisException _mapUnexpectedAnalysisError(
  Object error, {
  required bool hasImages,
  required bool recognizeOnly,
  required bool hasUserDraft,
}) {
  final errorMessage = error.toString();

  if (errorMessage.contains('Unauthorized') || errorMessage.contains('401')) {
    return AnalysisException(
      '登入狀態已失效，請重新登入後再試。',
      code: 'UNAUTHORIZED',
      suggestedAction: AnalysisErrorAction.relogin,
    );
  }

  if (errorMessage.contains('SocketException') ||
      errorMessage.contains('Connection refused')) {
    return AnalysisException(
      '網路連線不穩，請確認網路後再試。',
      code: 'NETWORK_ERROR',
      suggestedAction: AnalysisErrorAction.retry,
    );
  }

  if (errorMessage.contains('timeout') || errorMessage.contains('Timeout')) {
    return AnalysisException(
      hasImages
          ? recognizeOnly
              ? '截圖辨識花太久了，請稍後再試。'
              : '圖片分析花太久了，請稍後再試。'
          : hasUserDraft
              ? '訊息優化花太久了，請稍後再試。'
              : '分析花太久了，請稍後再試。',
      code: 'TIMEOUT',
      suggestedAction: AnalysisErrorAction.wait,
    );
  }

  return AnalysisException(
    hasImages
        ? recognizeOnly
            ? '截圖辨識暫時失敗，請稍後再試。'
            : '圖片分析暫時失敗，請稍後再試。'
        : hasUserDraft
            ? '訊息優化暫時失敗，請稍後再試。'
            : '分析暫時失敗，請稍後再試。',
    code: 'UNEXPECTED_ERROR',
    suggestedAction: AnalysisErrorAction.retry,
  );
}

class AnalysisService {
  static const Duration _streamConnectTimeout = Duration(seconds: 45);
  static const Duration _streamIdleTimeout = Duration(seconds: 120);

  final http.Client Function() _clientFactory;
  final String? Function() _accessTokenProvider;

  AnalysisService({
    http.Client Function()? clientFactory,
    String? Function()? accessTokenProvider,
  })  : _clientFactory = clientFactory ?? http.Client.new,
        _accessTokenProvider =
            accessTokenProvider ?? (() => SupabaseService.accessToken);

  Future<AnalysisResult> analyzeConversation(
    List<Message> messages, {
    List<Uint8List>? images,
    SessionContext? sessionContext,
    String? conversationSummary,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? knownContactName,
    String? userDraft,
    String? analyzeMode,
    bool recognizeOnly = false,
    int? previousAnalyzedCount,
    AnalysisProgressCallback? onProgress,
    AnalysisTelemetryCallback? onTelemetry,
  }) async {
    final sanitizedMessages = recognizeOnly
        ? messages.where((message) => message.id != 'placeholder').toList()
        : messages;

    if (sanitizedMessages.isEmpty && !recognizeOnly) {
      throw AnalysisException(
        '請先加入對話內容再分析。',
        code: 'EMPTY_MESSAGES',
        suggestedAction: AnalysisErrorAction.addIncomingMessage,
      );
    }

    const maxRetries = 2;
    const retriableCodes = <String>{
      'NETWORK_ERROR',
      'TIMEOUT',
      'UNEXPECTED_ERROR',
      'UPSTREAM_UNAVAILABLE',
    };

    Exception? lastError;

    _debugLog('[AnalysisService] analyzeConversation start');
    _debugLog(
      '[AnalysisService] messages: ${sanitizedMessages.length}, images: ${images?.length ?? 0}, recognizeOnly: $recognizeOnly',
    );

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        _debugLog(
          '[AnalysisService] attempt ${attempt + 1}/${maxRetries + 1}',
        );
        return await _doAnalyze(
          sanitizedMessages,
          images: images,
          sessionContext: sessionContext,
          conversationSummary: conversationSummary,
          partnerSummary: partnerSummary,
          effectiveStyleContext: effectiveStyleContext,
          knownContactName: knownContactName,
          userDraft: userDraft,
          analyzeMode: analyzeMode,
          recognizeOnly: recognizeOnly,
          previousAnalyzedCount: previousAnalyzedCount,
          onProgress: onProgress,
          onTelemetry: onTelemetry,
        );
      } catch (error) {
        _debugLog(
          '[AnalysisService] attempt ${attempt + 1} failed: ${error.runtimeType} - $error',
        );
        lastError = error is Exception ? error : Exception(error.toString());

        if (error is AnalysisException &&
            !retriableCodes.contains(error.code)) {
          rethrow;
        }

        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt + 1));
        }
      }
    }

    throw lastError ?? AnalysisException('分析暫時失敗，請稍後再試。');
  }

  Map<String, dynamic> _decodeResponseBody(http.Response response) {
    final body = response.body.trim();
    if (body.isEmpty) {
      return <String, dynamic>{};
    }

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
      return <String, dynamic>{'data': decoded};
    } on FormatException {
      final shortenedBody =
          body.length > 300 ? '${body.substring(0, 300)}...' : body;
      return <String, dynamic>{
        '_nonJson': true,
        '_rawBody': shortenedBody,
      };
    }
  }

  Map<String, dynamic>? _normalizeObject(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }

    return null;
  }

  Duration? _durationFromMilliseconds(dynamic value) {
    if (value is num) {
      return Duration(milliseconds: value.round());
    }

    return null;
  }

  Future<AnalysisResult> _doAnalyze(
    List<Message> messages, {
    List<Uint8List>? images,
    SessionContext? sessionContext,
    String? conversationSummary,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? knownContactName,
    String? userDraft,
    String? analyzeMode,
    required bool recognizeOnly,
    int? previousAnalyzedCount,
    AnalysisProgressCallback? onProgress,
    AnalysisTelemetryCallback? onTelemetry,
  }) async {
    final hasUserDraft = userDraft != null && userDraft.trim().isNotEmpty;
    final hasImages = images != null && images.isNotEmpty;

    try {
      final overallStartTime = DateTime.now();
      final imageCount = images?.length ?? 0;

      onProgress?.call(
        AnalysisProgressUpdate(
          stage: AnalysisProgressStage.preparingPayload,
          imageCount: imageCount,
          elapsed: Duration.zero,
        ),
      );

      List<Map<String, dynamic>>? imageDataList;
      if (hasImages) {
        imageDataList = images.asMap().entries.map((entry) {
          final base64Data = base64Encode(entry.value);
          return ImageData(
            data: base64Data,
            mediaType: 'image/jpeg',
            order: entry.key + 1,
          ).toJson();
        }).toList();
      }

      final timeout = hasImages
          ? const Duration(seconds: 120)
          : const Duration(seconds: 60);

      final accessToken = SupabaseService.accessToken;
      if (accessToken == null) {
        throw AnalysisException(
          '請先重新登入後再試。',
          code: 'UNAUTHORIZED',
          suggestedAction: AnalysisErrorAction.relogin,
        );
      }

      final requestBody = {
        'messages': messages
            .map(
              (message) => {
                'isFromMe': message.isFromMe,
                'content': message.content,
                if (message.quotedReplyPreview != null &&
                    message.quotedReplyPreview!.trim().isNotEmpty)
                  'quotedReplyPreview': message.quotedReplyPreview!.trim(),
                if (message.quotedReplyPreview != null &&
                    message.quotedReplyPreview!.trim().isNotEmpty &&
                    message.quotedReplyPreviewIsFromMe != null)
                  'quotedReplyPreviewIsFromMe':
                      message.quotedReplyPreviewIsFromMe,
              },
            )
            .toList(),
        if (imageDataList != null) 'images': imageDataList,
        if (sessionContext != null)
          'sessionContext': {
            'meetingContext': sessionContext.meetingContext.label,
            'duration': sessionContext.duration.label,
            'goal': sessionContext.goal.label,
          },
        if (conversationSummary != null &&
            conversationSummary.trim().isNotEmpty)
          'conversationSummary': conversationSummary.trim(),
        if (partnerSummary != null && partnerSummary.trim().isNotEmpty)
          'partnerSummary': partnerSummary.trim(),
        if (effectiveStyleContext != null &&
            effectiveStyleContext.trim().isNotEmpty)
          'effectiveStyleContext': effectiveStyleContext.trim(),
        if (knownContactName != null && knownContactName.trim().isNotEmpty)
          'knownContactName': knownContactName.trim(),
        if (hasUserDraft) 'userDraft': userDraft.trim(),
        if (analyzeMode != null) 'analyzeMode': analyzeMode,
        if (recognizeOnly) 'recognizeOnly': true,
        if (previousAnalyzedCount != null && previousAnalyzedCount > 0)
          'previousAnalyzedCount': previousAnalyzedCount,
      };

      final encodedRequestBody = jsonEncode(requestBody);
      final requestBodyBytes = utf8.encode(encodedRequestBody).length;
      final payloadPreparationDuration =
          DateTime.now().difference(overallStartTime);

      onProgress?.call(
        AnalysisProgressUpdate(
          stage: AnalysisProgressStage.uploadingRequest,
          imageCount: imageCount,
          elapsed: payloadPreparationDuration,
          requestBodyBytes: requestBodyBytes,
        ),
      );

      final httpClient = http.Client();
      try {
        final requestStartTime = DateTime.now();
        final awaitingAiTimer = Timer(const Duration(milliseconds: 700), () {
          onProgress?.call(
            AnalysisProgressUpdate(
              stage: AnalysisProgressStage.awaitingAi,
              imageCount: imageCount,
              elapsed: DateTime.now().difference(requestStartTime),
              requestBodyBytes: requestBodyBytes,
            ),
          );
        });

        try {
          final httpResponse = await httpClient
              .post(
                Uri.parse('${AppConfig.supabaseUrl}/functions/v1/analyze-chat'),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer $accessToken',
                  'apikey': AppConfig.supabaseAnonKey,
                },
                body: encodedRequestBody,
              )
              .timeout(timeout);

          awaitingAiTimer.cancel();

          final roundTripDuration = DateTime.now().difference(requestStartTime);
          final responseData = _decodeResponseBody(httpResponse);
          final telemetryData = _normalizeObject(responseData['telemetry']);

          onTelemetry?.call(
            AnalysisTelemetry(
              requestType: telemetryData?['requestType'] as String?,
              imageCount: imageCount,
              requestBodyBytes: requestBodyBytes,
              payloadPreparationDuration: payloadPreparationDuration,
              roundTripDuration: roundTripDuration,
              edgeAiDuration: _durationFromMilliseconds(
                telemetryData?['serverAiLatencyMs'],
              ),
              totalCompressedImageBytes:
                  telemetryData?['totalImageBytes'] is num
                      ? (telemetryData?['totalImageBytes'] as num).round()
                      : null,
              cacheHit: false,
              fallbackUsed: telemetryData?['fallbackUsed'] == true,
              retryCount: telemetryData?['retries'] is num
                  ? (telemetryData?['retries'] as num).round()
                  : 0,
              timeoutDuration: _durationFromMilliseconds(
                telemetryData?['timeoutMs'],
              ),
              allowModelFallback: telemetryData?['allowModelFallback'] as bool?,
              contextMode: telemetryData?['contextMode'] as String?,
              inputMessageCount: telemetryData?['inputMessageCount'] is num
                  ? (telemetryData?['inputMessageCount'] as num).round()
                  : null,
              compiledMessageCount:
                  telemetryData?['compiledMessageCount'] is num
                      ? (telemetryData?['compiledMessageCount'] as num).round()
                      : null,
              truncatedMessageCount:
                  telemetryData?['truncatedMessageCount'] is num
                      ? (telemetryData?['truncatedMessageCount'] as num).round()
                      : null,
              openingMessagesUsed: telemetryData?['openingMessagesUsed'] is num
                  ? (telemetryData?['openingMessagesUsed'] as num).round()
                  : null,
              recentMessagesUsed: telemetryData?['recentMessagesUsed'] is num
                  ? (telemetryData?['recentMessagesUsed'] as num).round()
                  : null,
              conversationSummaryUsed:
                  telemetryData?['conversationSummaryUsed'] == true,
              recognizedClassification:
                  telemetryData?['recognizedClassification'] as String?,
              recognizedConfidence:
                  telemetryData?['recognizedConfidence'] as String?,
              recognizedSideConfidence:
                  telemetryData?['recognizedSideConfidence'] as String?,
              recognizedMessageCount: telemetryData?['recognizedMessageCount']
                      is num
                  ? (telemetryData?['recognizedMessageCount'] as num).round()
                  : null,
              uncertainSideCount: telemetryData?['uncertainSideCount'] is num
                  ? (telemetryData?['uncertainSideCount'] as num).round()
                  : null,
              continuityAdjustedCount: telemetryData?['continuityAdjustedCount']
                      is num
                  ? (telemetryData?['continuityAdjustedCount'] as num).round()
                  : null,
              groupedAdjustedCount:
                  telemetryData?['groupedAdjustedCount'] is num
                      ? (telemetryData?['groupedAdjustedCount'] as num).round()
                      : null,
              layoutFirstAdjustedCount:
                  telemetryData?['layoutFirstAdjustedCount'] is num
                      ? (telemetryData?['layoutFirstAdjustedCount'] as num)
                          .round()
                      : null,
              systemRowsRemovedCount: telemetryData?['systemRowsRemovedCount']
                      is num
                  ? (telemetryData?['systemRowsRemovedCount'] as num).round()
                  : null,
              quotedPreviewRemovedCount:
                  telemetryData?['quotedPreviewRemovedCount'] is num
                      ? (telemetryData?['quotedPreviewRemovedCount'] as num)
                          .round()
                      : null,
              quotedPreviewAttachedCount:
                  telemetryData?['quotedPreviewAttachedCount'] is num
                      ? (telemetryData?['quotedPreviewAttachedCount'] as num)
                          .round()
                      : null,
              overlapRemovedCount: telemetryData?['overlapRemovedCount'] is num
                  ? (telemetryData?['overlapRemovedCount'] as num).round()
                  : null,
              shouldChargeQuota: telemetryData?['shouldChargeQuota'] as bool?,
              chargedMessageCount: telemetryData?['chargedMessageCount'] is num
                  ? (telemetryData?['chargedMessageCount'] as num).round()
                  : null,
              estimatedMessageCount:
                  telemetryData?['estimatedMessageCount'] is num
                      ? (telemetryData?['estimatedMessageCount'] as num).round()
                      : null,
              quotaReason: telemetryData?['quotaReason'] as String?,
            ),
          );

          final status = httpResponse.statusCode;
          if (responseData['_nonJson'] == true && status == 200) {
            throw AnalysisException(
              '伺服器回傳格式異常，請稍後再試。',
              code: 'INVALID_RESPONSE_FORMAT',
              suggestedAction: AnalysisErrorAction.retry,
            );
          }

          if (status != 200) {
            final errorCode = responseData['code'] as String?;
            final errorMessage = responseData['message'] as String? ??
                responseData['error'] as String? ??
                (responseData['_nonJson'] == true
                    ? '伺服器暫時無法正確回應，請稍後再試。'
                    : 'Analysis failed');

            if (status == 429) {
              final monthlyLimit = responseData['monthlyLimit'];
              final dailyLimit = responseData['dailyLimit'];
              final used = (responseData['used'] as num?)?.toInt() ?? 0;

              if (dailyLimit != null) {
                throw DailyLimitExceededException(
                  dailyLimit: (dailyLimit as num).toInt(),
                  used: used,
                );
              }

              if (monthlyLimit != null) {
                throw MonthlyLimitExceededException(
                  monthlyLimit: (monthlyLimit as num).toInt(),
                  used: used,
                );
              }
            }

            throw _mapAnalysisHttpError(
              statusCode: status,
              errorCode: errorCode,
              rawMessage: errorMessage,
              hasImages: hasImages,
              recognizeOnly: recognizeOnly,
              hasUserDraft: hasUserDraft,
            );
          }

          return AnalysisResult.fromJson(responseData);
        } finally {
          awaitingAiTimer.cancel();
        }
      } finally {
        httpClient.close();
      }
    } on TimeoutException {
      throw AnalysisException(
        hasImages
            ? recognizeOnly
                ? '截圖辨識花太久了，請稍後再試。'
                : '圖片分析花太久了，請稍後再試。'
            : hasUserDraft
                ? '訊息優化花太久了，請稍後再試。'
                : '分析花太久了，請稍後再試。',
        code: 'TIMEOUT',
        suggestedAction: AnalysisErrorAction.wait,
      );
    } catch (error) {
      if (error is AnalysisException) {
        rethrow;
      }

      throw _mapUnexpectedAnalysisError(
        error,
        hasImages: hasImages,
        recognizeOnly: recognizeOnly,
        hasUserDraft: hasUserDraft,
      );
    }
  }

  /// Two-stage analyze — quick phase.
  ///
  /// Posts `responseMode: 'quick'` to `analyze-chat`. Returns a [QuickAnalysisResult]
  /// carrying the `analysisRunId` that [analyzeFull] must echo.
  Future<QuickAnalysisResult> analyzeQuick({
    required List<Message> messages,
    SessionContext? sessionContext,
    String? conversationSummary,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? knownContactName,
    int? previousAnalyzedCount,
  }) async {
    final responseData = await _postTwoStageRequest(
      body: _buildTwoStageBody(
        responseMode: 'quick',
        analysisRunId: null,
        messages: messages,
        sessionContext: sessionContext,
        conversationSummary: conversationSummary,
        partnerSummary: partnerSummary,
        effectiveStyleContext: effectiveStyleContext,
        knownContactName: knownContactName,
        previousAnalyzedCount: previousAnalyzedCount,
      ),
      timeout: const Duration(seconds: 15),
    );
    try {
      return QuickAnalysisResult.fromJson(responseData);
    } on FormatException catch (_) {
      // Backend should not return a malformed 200, but if it does the user has
      // already been charged quick quota. Surface a coded error so the
      // notifier maps it to a quickFailed state and the UI offers retry rather
      // than rendering blank fields (I-P3).
      throw AnalysisException(
        '快速分析回應格式錯誤，請稍後再試。',
        code: 'INVALID_QUICK_RESPONSE',
      );
    }
  }

  /// Two-stage analyze — full phase.
  ///
  /// Echoes [analysisRunId] from a prior [analyzeQuick] so the server can match
  /// the run, validate conversation hash, and avoid double-charging quota (I1).
  /// Maps server `RUN_*` codes to [FullModeException] so the orchestrator can
  /// decide between user-facing retry CTA and a hard "重新分析" path.
  Future<AnalysisResult> analyzeFull({
    required String analysisRunId,
    required List<Message> messages,
    SessionContext? sessionContext,
    String? conversationSummary,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? knownContactName,
    int? previousAnalyzedCount,
  }) async {
    final responseData = await _postTwoStageRequest(
      body: _buildTwoStageBody(
        responseMode: 'full',
        analysisRunId: analysisRunId,
        messages: messages,
        sessionContext: sessionContext,
        conversationSummary: conversationSummary,
        partnerSummary: partnerSummary,
        effectiveStyleContext: effectiveStyleContext,
        knownContactName: knownContactName,
        previousAnalyzedCount: previousAnalyzedCount,
      ),
      timeout: const Duration(seconds: 60),
      onErrorResponse: _mapFullModeError,
    );
    return AnalysisResult.fromJson(_extractFullResultPayload(responseData));
  }

  Stream<AnalysisStreamUpdate> analyzeStream({
    String? analysisRunId,
    required List<Message> messages,
    SessionContext? sessionContext,
    String? conversationSummary,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? knownContactName,
    int? previousAnalyzedCount,
  }) async* {
    final accessToken = _accessTokenProvider();
    if (accessToken == null) {
      throw AnalysisException(
        '請重新登入後再分析。',
        code: 'UNAUTHORIZED',
        suggestedAction: AnalysisErrorAction.relogin,
      );
    }

    final client = _clientFactory();
    String? runId;
    int? etaSeconds;
    var sawTypedStreamEvent = false;
    var sawDone = false;

    try {
      final request = http.Request(
        'POST',
        Uri.parse('${AppConfig.supabaseUrl}/functions/v1/analyze-chat'),
      )
        ..headers.addAll({
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
          'apikey': AppConfig.supabaseAnonKey,
        })
        ..body = jsonEncode(
          _buildTwoStageBody(
            responseMode: 'stream',
            analysisRunId: analysisRunId,
            messages: messages,
            sessionContext: sessionContext,
            conversationSummary: conversationSummary,
            partnerSummary: partnerSummary,
            effectiveStyleContext: effectiveStyleContext,
            knownContactName: knownContactName,
            previousAnalyzedCount: previousAnalyzedCount,
          ),
        );

      final response =
          await client.send(request).timeout(_streamConnectTimeout);

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        final responseData = _decodeResponseBody(
          http.Response(body, response.statusCode, headers: response.headers),
        );

        if (response.statusCode == 429) {
          final dailyLimit = responseData['dailyLimit'];
          final monthlyLimit = responseData['monthlyLimit'];
          final used = (responseData['used'] as num?)?.toInt() ?? 0;
          if (dailyLimit != null) {
            throw DailyLimitExceededException(
              dailyLimit: (dailyLimit as num).toInt(),
              used: used,
            );
          }
          if (monthlyLimit != null) {
            throw MonthlyLimitExceededException(
              monthlyLimit: (monthlyLimit as num).toInt(),
              used: used,
            );
          }
        }

        throw _mapAnalysisHttpError(
          statusCode: response.statusCode,
          errorCode: responseData['code'] as String?,
          rawMessage: (responseData['message'] as String?) ??
              (responseData['error'] as String?) ??
              'Streaming analysis failed.',
          hasImages: false,
          recognizeOnly: false,
          hasUserDraft: false,
        );
      }

      await for (final rawLine in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(_streamIdleTimeout)) {
        final line = rawLine.trim();
        if (line.isEmpty) continue;

        final event = _decodeStreamEventLine(line);
        final type = event['type'] as String?;

        if (type == null) {
          if (!sawTypedStreamEvent) {
            final resultPayload = _streamResultPayload(event);
            if (resultPayload != null) {
              sawDone = true;
              yield AnalysisStreamUpdate.done(
                result: _parseStreamAnalysisResult(resultPayload),
                rawEvent: event,
              );
              return;
            }
          }
          throw AnalysisException(
            '串流分析回傳格式異常，請重新分析。',
            code: 'INVALID_STREAM_RESPONSE',
            suggestedAction: AnalysisErrorAction.retry,
          );
        }

        sawTypedStreamEvent = true;
        runId = _stringField(event['runId']) ?? runId;
        etaSeconds = _intField(event['etaSeconds']) ?? etaSeconds;

        switch (type) {
          case 'analysis.started':
            yield AnalysisStreamUpdate.started(
              runId: runId,
              label: _stringField(event['label']) ?? '開始完整分析',
              detail: _stringField(event['detail']),
              etaSeconds: etaSeconds,
              rawEvent: event,
            );
            break;
          case 'analysis.progress':
            yield AnalysisStreamUpdate.progress(
              runId: runId,
              label: _stringField(event['label']) ?? '完整分析進行中',
              detail: _stringField(event['detail']),
              etaSeconds: etaSeconds,
              rawEvent: event,
            );
            break;
          case 'analysis.decision':
          case 'analysis.reply_option':
          case 'analysis.metrics':
          case 'analysis.coach_hint':
          case 'analysis.report_section':
            final content = AnalysisStreamContent.fromEvent(event);
            if (content == null || content.body.trim().isEmpty) {
              break;
            }
            yield AnalysisStreamUpdate.content(
              content: content,
              runId: runId,
              label: content.title,
              detail: content.body,
              etaSeconds: etaSeconds,
              rawEvent: event,
            );
            break;
          case 'analysis.recommendation':
            final quick = _streamRecommendationPreview(
              event,
              runId: runId,
              etaSeconds: etaSeconds,
            );
            yield AnalysisStreamUpdate.recommendation(
              quick: quick,
              runId: runId,
              label: '先產生建議回覆',
              detail: '完整分析仍在補齊脈絡與細節。',
              etaSeconds: etaSeconds,
              rawEvent: event,
            );
            break;
          case 'analysis.done':
            final finalResult = _streamDoneResultPayload(event);
            if (finalResult == null) {
              throw AnalysisException(
                '串流分析缺少完整結果，請重新分析。',
                code: 'INVALID_STREAM_DONE',
                suggestedAction: AnalysisErrorAction.retry,
              );
            }
            sawDone = true;
            yield AnalysisStreamUpdate.done(
              result: _parseStreamAnalysisResult(finalResult),
              runId: runId,
              label: '完整分析完成',
              etaSeconds: etaSeconds,
              rawEvent: event,
            );
            return;
          case 'analysis.error':
            final recoverable = event['recoverable'] != false;
            throw StreamModeException(
              _stringField(event['message']) ?? '完整分析串流中斷，請重新分析。',
              code: _stringField(event['code']) ?? 'STREAM_FAILED',
              recoverable: recoverable,
              retriesRemaining:
                  _intField(event['retriesRemaining']) ?? (recoverable ? 1 : 0),
              suggestedAction: recoverable
                  ? AnalysisErrorAction.retry
                  : AnalysisErrorAction.wait,
            );
          default:
            break;
        }
      }

      if (!sawDone) {
        throw AnalysisException(
          '完整分析串流尚未完成，請重新分析。',
          code: 'STREAM_INCOMPLETE',
          suggestedAction: AnalysisErrorAction.retry,
        );
      }
    } on TimeoutException {
      throw AnalysisException(
        '完整分析串流等待過久，請稍後重新分析。',
        code: 'TIMEOUT',
        suggestedAction: AnalysisErrorAction.wait,
      );
    } finally {
      client.close();
    }
  }

  Map<String, dynamic> _extractFullResultPayload(
    Map<String, dynamic> responseData,
  ) {
    final result = responseData['result'];
    if (result is Map<String, dynamic>) {
      return result;
    }
    if (result is Map) {
      return result.map((key, value) => MapEntry(key.toString(), value));
    }

    if (responseData['responseMode'] == 'full') {
      throw AnalysisException(
        '完整分析資料異常，請再試一次。',
        code: 'INVALID_FULL_RESPONSE',
        suggestedAction: AnalysisErrorAction.retry,
      );
    }

    return responseData;
  }

  Map<String, dynamic> _decodeStreamEventLine(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } on FormatException {
      // Fall through to the typed AnalysisException below.
    }

    throw AnalysisException(
      '串流分析回傳格式異常，請重新分析。',
      code: 'INVALID_STREAM_RESPONSE',
      suggestedAction: AnalysisErrorAction.retry,
    );
  }

  Map<String, dynamic>? _streamResultPayload(Map<String, dynamic> event) {
    final nestedResult = _normalizeObject(event['result']);
    if (nestedResult != null) return nestedResult;

    final looksLikeResult = event.containsKey('finalRecommendation') ||
        event.containsKey('replies') ||
        (event.containsKey('gameStage') && event.containsKey('enthusiasm'));
    return looksLikeResult ? event : null;
  }

  Map<String, dynamic>? _streamDoneResultPayload(Map<String, dynamic> event) {
    final finalResult = _normalizeObject(event['finalResult']);
    if (finalResult != null) return finalResult;

    final result = _normalizeObject(event['result']);
    if (result != null) return result;

    return _streamResultPayload(event);
  }

  AnalysisResult _parseStreamAnalysisResult(Map<String, dynamic> payload) {
    try {
      return AnalysisResult.fromJson(payload);
    } catch (_) {
      throw AnalysisException(
        '串流分析缺少完整結果，請重新分析。',
        code: 'INVALID_STREAM_RESULT',
        suggestedAction: AnalysisErrorAction.retry,
      );
    }
  }

  QuickAnalysisResult _streamRecommendationPreview(
    Map<String, dynamic> event, {
    required String? runId,
    required int? etaSeconds,
  }) {
    final message = _stringField(event['message']);
    if (message == null || message.isEmpty) {
      throw AnalysisException(
        '串流分析缺少建議回覆，請重新分析。',
        code: 'INVALID_STREAM_RECOMMENDATION',
        suggestedAction: AnalysisErrorAction.retry,
      );
    }

    final pick = _normalizeStreamPick(
      _stringField(event['selectedStyle']) ?? _stringField(event['style']),
    );
    final reason = _stringField(event['reason']) ?? '';

    return QuickAnalysisResult(
      analysisRunId:
          runId == null || runId.trim().isEmpty ? 'stream-preview' : runId,
      nextStep: reason.isNotEmpty ? reason : '先用這個方向回覆，完整分析正在完成。',
      pick: pick,
      recommendedReply: message,
      shortReason: reason,
      insufficientContext: false,
      confidence: 'high',
      estimatedFullSeconds: etaSeconds,
    );
  }

  String _normalizeStreamPick(String? value) {
    switch (value) {
      case 'extend':
      case 'resonate':
      case 'tease':
      case 'humor':
      case 'coldRead':
        return value!;
      default:
        return 'extend';
    }
  }

  String? _stringField(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  int? _intField(dynamic value) {
    if (value is num && value.isFinite) return value.round();
    return null;
  }

  Map<String, dynamic> _buildTwoStageBody({
    required String responseMode,
    String? analysisRunId,
    required List<Message> messages,
    SessionContext? sessionContext,
    String? conversationSummary,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? knownContactName,
    int? previousAnalyzedCount,
  }) {
    return {
      'responseMode': responseMode,
      if (analysisRunId != null) 'analysisRunId': analysisRunId,
      'messages': messages
          .map(
            (message) => {
              'isFromMe': message.isFromMe,
              'content': message.content,
              if (message.quotedReplyPreview != null &&
                  message.quotedReplyPreview!.trim().isNotEmpty)
                'quotedReplyPreview': message.quotedReplyPreview!.trim(),
              if (message.quotedReplyPreview != null &&
                  message.quotedReplyPreview!.trim().isNotEmpty &&
                  message.quotedReplyPreviewIsFromMe != null)
                'quotedReplyPreviewIsFromMe':
                    message.quotedReplyPreviewIsFromMe,
            },
          )
          .toList(),
      if (sessionContext != null)
        'sessionContext': {
          'meetingContext': sessionContext.meetingContext.label,
          'duration': sessionContext.duration.label,
          'goal': sessionContext.goal.label,
        },
      if (conversationSummary != null && conversationSummary.trim().isNotEmpty)
        'conversationSummary': conversationSummary.trim(),
      if (partnerSummary != null && partnerSummary.trim().isNotEmpty)
        'partnerSummary': partnerSummary.trim(),
      if (effectiveStyleContext != null &&
          effectiveStyleContext.trim().isNotEmpty)
        'effectiveStyleContext': effectiveStyleContext.trim(),
      if (knownContactName != null && knownContactName.trim().isNotEmpty)
        'knownContactName': knownContactName.trim(),
      if (previousAnalyzedCount != null && previousAnalyzedCount > 0)
        'previousAnalyzedCount': previousAnalyzedCount,
    };
  }

  Future<Map<String, dynamic>> _postTwoStageRequest({
    required Map<String, dynamic> body,
    required Duration timeout,
    Exception Function(int status, Map<String, dynamic> data)? onErrorResponse,
  }) async {
    final accessToken = _accessTokenProvider();
    if (accessToken == null) {
      throw AnalysisException(
        '請先重新登入後再試。',
        code: 'UNAUTHORIZED',
        suggestedAction: AnalysisErrorAction.relogin,
      );
    }

    final client = _clientFactory();
    try {
      final response = await client
          .post(
            Uri.parse('${AppConfig.supabaseUrl}/functions/v1/analyze-chat'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $accessToken',
              'apikey': AppConfig.supabaseAnonKey,
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);

      final responseData = _decodeResponseBody(response);
      final status = response.statusCode;

      if (responseData['_nonJson'] == true && status == 200) {
        throw AnalysisException(
          '伺服器回傳格式異常，請稍後再試。',
          code: 'INVALID_RESPONSE_FORMAT',
          suggestedAction: AnalysisErrorAction.retry,
        );
      }

      if (status == 200) {
        return responseData;
      }

      if (status == 429) {
        final dailyLimit = responseData['dailyLimit'];
        final monthlyLimit = responseData['monthlyLimit'];
        final used = (responseData['used'] as num?)?.toInt() ?? 0;
        if (dailyLimit != null) {
          throw DailyLimitExceededException(
            dailyLimit: (dailyLimit as num).toInt(),
            used: used,
          );
        }
        if (monthlyLimit != null) {
          throw MonthlyLimitExceededException(
            monthlyLimit: (monthlyLimit as num).toInt(),
            used: used,
          );
        }
      }

      if (onErrorResponse != null) {
        throw onErrorResponse(status, responseData);
      }

      throw AnalysisException(
        (responseData['message'] as String?) ??
            (responseData['error'] as String?) ??
            '分析暫時失敗，請稍後再試。',
        code: responseData['code'] as String?,
        suggestedAction: AnalysisErrorAction.retry,
      );
    } on TimeoutException {
      throw AnalysisException(
        '分析花太久了，請稍後再試。',
        code: 'TIMEOUT',
        suggestedAction: AnalysisErrorAction.wait,
      );
    } finally {
      client.close();
    }
  }

  Exception _mapFullModeError(int status, Map<String, dynamic> data) {
    final code = (data['code'] as String?) ?? (data['error'] as String?);
    final retriesRemainingRaw = data['retriesRemaining'];
    final retriesRemaining =
        retriesRemainingRaw is num ? retriesRemainingRaw.toInt() : 0;

    switch (code) {
      case 'RUN_EXPIRED':
        return FullModeException(
          '分析記錄已過期，請重新分析。',
          code: 'RUN_EXPIRED',
          retriesRemaining: 0,
          suggestedAction: AnalysisErrorAction.retry,
        );
      case 'RUN_CONVERSATION_MISMATCH':
        return FullModeException(
          '對話內容已變動，請重新分析。',
          code: 'RUN_CONVERSATION_MISMATCH',
          retriesRemaining: 0,
          suggestedAction: AnalysisErrorAction.retry,
        );
      case 'RUN_RETRY_EXHAUSTED':
        return FullModeException(
          '完整分析已達重試上限，請重新分析。',
          code: 'RUN_RETRY_EXHAUSTED',
          retriesRemaining: 0,
          suggestedAction: AnalysisErrorAction.retry,
        );
      default:
        return FullModeException(
          (data['message'] as String?) ?? '完整分析失敗，可以重試。',
          code: code ?? 'FULL_FAILED',
          retriesRemaining: retriesRemaining,
          suggestedAction: AnalysisErrorAction.retry,
        );
    }
  }
}

class AnalysisException implements Exception {
  final String message;
  final String? code;
  final AnalysisErrorAction? suggestedAction;

  AnalysisException(
    this.message, {
    this.code,
    this.suggestedAction,
  });

  @override
  String toString() => 'AnalysisException: $message';
}

class StreamModeException extends AnalysisException {
  final bool recoverable;
  final int retriesRemaining;

  StreamModeException(
    super.message, {
    super.code,
    super.suggestedAction,
    required this.recoverable,
    required this.retriesRemaining,
  });
}

class DailyLimitExceededException extends AnalysisException {
  final int dailyLimit;
  final int used;

  DailyLimitExceededException({
    required this.dailyLimit,
    required this.used,
  }) : super(
          'Daily limit exceeded',
          code: 'DAILY_LIMIT_EXCEEDED',
          suggestedAction: AnalysisErrorAction.wait,
        );
}

class MonthlyLimitExceededException extends AnalysisException {
  final int monthlyLimit;
  final int used;

  MonthlyLimitExceededException({
    required this.monthlyLimit,
    required this.used,
  }) : super(
          'Monthly limit exceeded',
          code: 'MONTHLY_LIMIT_EXCEEDED',
          suggestedAction: AnalysisErrorAction.upgrade,
        );
}

/// Raised when the two-stage `full` phase fails on the server.
///
/// [retriesRemaining] is 0 for terminal failures (`RUN_EXPIRED`,
/// `RUN_CONVERSATION_MISMATCH`, `RUN_RETRY_EXHAUSTED`) and matches the server
/// budget for generic 502 `FULL_FAILED`. The orchestrator uses it to decide
/// whether to surface a retry CTA or force "重新分析".
class FullModeException extends AnalysisException {
  final int retriesRemaining;

  FullModeException(
    super.message, {
    super.code,
    super.suggestedAction,
    required this.retriesRemaining,
  });
}
