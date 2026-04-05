import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../../core/config/environment.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../conversation/domain/entities/message.dart';
import '../../../conversation/domain/entities/session_context.dart';
import '../../domain/entities/analysis_models.dart';

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
  Future<AnalysisResult> analyzeConversation(
    List<Message> messages, {
    List<Uint8List>? images,
    SessionContext? sessionContext,
    String? conversationSummary,
    String? knownContactName,
    String? userDraft,
    String? analyzeMode,
    bool recognizeOnly = false,
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
          knownContactName: knownContactName,
          userDraft: userDraft,
          analyzeMode: analyzeMode,
          recognizeOnly: recognizeOnly,
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
    String? knownContactName,
    String? userDraft,
    String? analyzeMode,
    required bool recognizeOnly,
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
        if (knownContactName != null && knownContactName.trim().isNotEmpty)
          'knownContactName': knownContactName.trim(),
        if (hasUserDraft) 'userDraft': userDraft.trim(),
        if (analyzeMode != null) 'analyzeMode': analyzeMode,
        if (recognizeOnly) 'recognizeOnly': true,
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
              groupedAdjustedCount: telemetryData?['groupedAdjustedCount'] is num
                  ? (telemetryData?['groupedAdjustedCount'] as num).round()
                  : null,
              layoutFirstAdjustedCount:
                  telemetryData?['layoutFirstAdjustedCount'] is num
                      ? (telemetryData?['layoutFirstAdjustedCount'] as num)
                          .round()
                      : null,
              systemRowsRemovedCount:
                  telemetryData?['systemRowsRemovedCount'] is num
                      ? (telemetryData?['systemRowsRemovedCount'] as num)
                          .round()
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
                      ? (telemetryData?['estimatedMessageCount'] as num)
                          .round()
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

              if (dailyLimit != null) {
                throw DailyLimitExceededException(
                  dailyLimit: dailyLimit as int,
                  used: responseData['used'] as int? ?? 0,
                );
              }

              if (monthlyLimit != null) {
                throw MonthlyLimitExceededException(
                  monthlyLimit: monthlyLimit as int,
                  used: responseData['used'] as int? ?? 0,
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
