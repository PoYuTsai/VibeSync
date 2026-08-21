import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../../core/config/environment.dart';
import '../../../../core/services/message_calculator.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../conversation/domain/entities/message.dart';
import '../../../conversation/domain/entities/session_context.dart';
import '../../domain/entities/analysis_models.dart';
import 'analysis_exceptions.dart';
import 'analysis_transport_support.dart';

export 'analysis_exceptions.dart';
export 'analysis_transport_support.dart' show OverchargeConfirmationPayload;
export 'analyze_stream_client.dart'
    show
        AnalysisStreamContent,
        AnalysisStreamContentKind,
        AnalysisStreamUpdate,
        AnalysisStreamUpdateKind;

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
  recognizingMessages,
  resolvingSpeakers,
  finalizingRecognition,
}

String analysisProgressStageLabel(AnalysisProgressStage stage) {
  switch (stage) {
    case AnalysisProgressStage.preparingPayload:
      return '準備圖片中';
    case AnalysisProgressStage.uploadingRequest:
      return '上傳圖片中';
    case AnalysisProgressStage.awaitingAi:
      return 'AI 讀取圖片中';
    case AnalysisProgressStage.recognizingMessages:
      return '辨識訊息內容中';
    case AnalysisProgressStage.resolvingSpeakers:
      return '校對說話者中';
    case AnalysisProgressStage.finalizingRecognition:
      return '整理辨識結果中';
  }
}

class AnalysisProgressMilestone {
  final Duration delay;
  final AnalysisProgressStage stage;

  const AnalysisProgressMilestone(this.delay, this.stage);
}

/// recognizeOnly 不傳輸中間分析內容，只在等待同一個 OCR
/// request 時送出輕量狀態。這些是用戶等待進度，不是伺服器承諾的
/// 精確百分比；response schema、quota 與 OCR 結果契約都不變。
const ocrRecognitionProgressMilestones = <AnalysisProgressMilestone>[
  AnalysisProgressMilestone(
    Duration(milliseconds: 700),
    AnalysisProgressStage.awaitingAi,
  ),
  AnalysisProgressMilestone(
    Duration(seconds: 4),
    AnalysisProgressStage.recognizingMessages,
  ),
  AnalysisProgressMilestone(
    Duration(seconds: 9),
    AnalysisProgressStage.resolvingSpeakers,
  ),
  AnalysisProgressMilestone(
    Duration(seconds: 15),
    AnalysisProgressStage.finalizingRecognition,
  ),
];

/// Client fences must outlive the Edge request-level model budgets (50s text,
/// 120s image) so parsing and quota settlement can finish before the socket is
/// closed locally.
const kAnalyzeTextRequestTimeout = Duration(seconds: 65);
const kAnalyzeImageRequestTimeout = Duration(seconds: 130);

/// The screen-level OCR fence wraps payload preparation as well as the HTTP
/// call, so it stays outside [kAnalyzeImageRequestTimeout].
const kAnalyzeOcrScreenTimeout = Duration(seconds: 135);

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

class AnalysisService {
  static const _retriableCodes = <String>{
    'NETWORK_ERROR',
    'TIMEOUT',
    'UNEXPECTED_ERROR',
    'UPSTREAM_UNAVAILABLE',
    'OPTIMIZE_MESSAGE_SETTLEMENT_RETRYABLE',
  };

  /// 只有具 durable requestId／原子結算的路徑可以背景重送。一般分析、
  /// my_message 與 OCR 都可能在 server 已扣額、response 回程斷線時收到
  /// NETWORK_ERROR/TIMEOUT；沒有冪等身份時自動重送會重複扣額。
  @visibleForTesting
  static bool isAutoRetriableAnalysisError({
    required String? code,
    required bool hasImages,
    required bool recognizeOnly,
    required bool hasDurableRequestId,
  }) {
    if (code == null || !_retriableCodes.contains(code)) {
      return false;
    }
    if (recognizeOnly || !hasDurableRequestId) {
      return false;
    }
    return true;
  }

  final http.Client Function() _clientFactory;
  final String? Function() _accessTokenProvider;
  final String? Function() _expectedTierProvider;
  final Future<String?> Function() _revenueCatAppUserIdProvider;

  AnalysisService({
    http.Client Function()? clientFactory,
    String? Function()? accessTokenProvider,
    String? Function()? expectedTierProvider,
    Future<String?> Function()? revenueCatAppUserIdProvider,
  })  : _clientFactory = clientFactory ?? http.Client.new,
        _accessTokenProvider =
            accessTokenProvider ?? (() => SupabaseService.accessToken),
        _expectedTierProvider =
            expectedTierProvider ?? defaultAnalysisExpectedTier,
        _revenueCatAppUserIdProvider =
            revenueCatAppUserIdProvider ?? defaultAnalysisRevenueCatAppUserId;

  Future<AnalysisResult> analyzeConversation(
    List<Message> messages, {
    List<Uint8List>? images,
    SessionContext? sessionContext,
    String? conversationSummary,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? knownContactName,
    String? userDraft,
    String? refineInstruction,
    String? refineAnchorText,
    String? requestId,
    String? analyzeMode,
    bool recognizeOnly = false,
    int? previousAnalyzedCount,
    int? previousAnalyzedCharCount,
    OverchargeConfirmationPayload? confirmedOvercharge,
    AnalysisProgressCallback? onProgress,
    AnalysisTelemetryCallback? onTelemetry,
  }) async {
    // Screenshot recognition is one independent batch. Existing conversation
    // rows are deliberately excluded so the Edge prompt cannot turn a batch
    // that is about to be replaced into `Existing Thread Context`.
    final sanitizedMessages = recognizeOnly ? const <Message>[] : messages;

    if (sanitizedMessages.isEmpty && !recognizeOnly) {
      throw AnalysisException(
        '請先加入對話內容再分析。',
        code: 'EMPTY_MESSAGES',
        suggestedAction: AnalysisErrorAction.addIncomingMessage,
      );
    }

    // OCR retries are manual and user-controlled. This is intentionally a
    // hard attempt cap as well as a retry-policy rule, so even unexpected
    // transport exceptions cannot start a second upload in the background.
    final maxRetries = recognizeOnly ? 0 : 2;
    final isOptimizeMessageRequest = !recognizeOnly &&
        (images == null || images.isEmpty) &&
        userDraft != null &&
        userDraft.trim().isNotEmpty &&
        analyzeMode != 'my_message';
    final logicalRequestId =
        isOptimizeMessageRequest ? (requestId ?? const Uuid().v4()) : null;

    Exception? lastError;

    analysisDebugLog('[AnalysisService] analyzeConversation start');
    analysisDebugLog(
      '[AnalysisService] messages: ${sanitizedMessages.length}, images: ${images?.length ?? 0}, recognizeOnly: $recognizeOnly',
    );

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        analysisDebugLog(
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
          refineInstruction: refineInstruction,
          refineAnchorText: refineAnchorText,
          requestId: logicalRequestId,
          analyzeMode: analyzeMode,
          recognizeOnly: recognizeOnly,
          previousAnalyzedCount: previousAnalyzedCount,
          previousAnalyzedCharCount: previousAnalyzedCharCount,
          confirmedOvercharge: confirmedOvercharge,
          onProgress: onProgress,
          onTelemetry: onTelemetry,
        );
      } catch (error) {
        analysisDebugLog(
          '[AnalysisService] attempt ${attempt + 1} failed: ${error.runtimeType} - $error',
        );
        lastError = error is Exception ? error : Exception(error.toString());

        final canAutoRetry = error is AnalysisException &&
            isAutoRetriableAnalysisError(
              code: error.code,
              hasImages: images != null && images.isNotEmpty,
              recognizeOnly: recognizeOnly,
              hasDurableRequestId: logicalRequestId != null,
            );
        if (!canAutoRetry) {
          rethrow;
        }

        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt + 1));
        }
      }
    }

    throw lastError ?? AnalysisException('分析暫時失敗，請稍後再試。');
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
    String? refineInstruction,
    String? refineAnchorText,
    String? requestId,
    String? analyzeMode,
    required bool recognizeOnly,
    int? previousAnalyzedCount,
    int? previousAnalyzedCharCount,
    OverchargeConfirmationPayload? confirmedOvercharge,
    AnalysisProgressCallback? onProgress,
    AnalysisTelemetryCallback? onTelemetry,
  }) async {
    final hasUserDraft = userDraft != null && userDraft.trim().isNotEmpty;
    // 空字串等同沒帶：只有非空指令才能進 payload，否則 server 端 input hash
    // 會與同一份草稿的純潤飾請求分岔，舊請求就 replay 不回來。
    final trimmedRefineInstruction = refineInstruction?.trim();
    final hasRefineInstruction =
        trimmedRefineInstruction != null && trimmedRefineInstruction.isNotEmpty;
    // 多輪漂移錨：只在微調時有意義；與 anchor==draft 時一樣省略（server
    // 端也會忽略）。刻意不進 fingerprint／input hash——同 draft＋指令＋脈絡
    // 幾乎必同 anchor，不值得為它毀掉 7 天窗內的 replay。
    final trimmedRefineAnchor = refineAnchorText?.trim();
    final hasRefineAnchor = hasRefineInstruction &&
        trimmedRefineAnchor != null &&
        trimmedRefineAnchor.isNotEmpty &&
        trimmedRefineAnchor != userDraft?.trim();
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

      final timeout =
          hasImages ? kAnalyzeImageRequestTimeout : kAnalyzeTextRequestTimeout;

      // 走注入的 provider（預設即 SupabaseService.accessToken），測試才能
      // 不初始化 Supabase 就打到 HTTP 層。
      final accessToken = _accessTokenProvider();
      if (accessToken == null) {
        throw AnalysisException(
          '請先重新登入後再試。',
          code: 'UNAUTHORIZED',
          suggestedAction: AnalysisErrorAction.relogin,
        );
      }

      final entitlementContext = await buildAnalysisEntitlementContext(
        expectedTierProvider: _expectedTierProvider,
        revenueCatAppUserIdProvider: _revenueCatAppUserIdProvider,
      );
      final requestBody = {
        'messages': messages.map(analysisMessagePayload).toList(),
        if (imageDataList != null) 'images': imageDataList,
        if (sessionContext != null)
          'sessionContext': {
            'meetingContext': sessionContext.meetingContext.label,
            'duration': sessionContext.duration.label,
            'goal': sessionContext.goal.label,
            if (sessionContext.analysisContextNote != null &&
                sessionContext.analysisContextNote!.trim().isNotEmpty)
              'analysisContextNote': sessionContext.analysisContextNote!.trim(),
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
        if (hasRefineInstruction) 'refineInstruction': trimmedRefineInstruction,
        if (hasRefineAnchor) 'refineAnchorText': trimmedRefineAnchor,
        if (requestId != null) 'requestId': requestId,
        if (analyzeMode != null) 'analyzeMode': analyzeMode,
        if (recognizeOnly) 'recognizeOnly': true,
        if (previousAnalyzedCount != null && previousAnalyzedCount > 0)
          'previousAnalyzedCount': previousAnalyzedCount,
        // ADR #19 定案 #6 capability contract：所有 analyze 請求必送。
        'billingProtocolVersion': MessageCalculator.billingProtocolVersion,
        if (previousAnalyzedCharCount != null && previousAnalyzedCharCount > 0)
          'previousAnalyzedCharCount': previousAnalyzedCharCount,
        if (confirmedOvercharge != null)
          'confirmedOvercharge': confirmedOvercharge.toJson(),
        if (entitlementContext.expectedTier != null)
          'expectedTier': entitlementContext.expectedTier,
        if (entitlementContext.revenueCatAppUserId != null)
          'revenueCatAppUserId': entitlementContext.revenueCatAppUserId,
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

      // 走注入的 factory（預設即 http.Client.new），測試才能攔截
      // recognizeOnly 的 HTTP 層。
      final httpClient = _clientFactory();
      try {
        final requestStartTime = DateTime.now();
        final progressMilestones = recognizeOnly && hasImages
            ? ocrRecognitionProgressMilestones
            : const <AnalysisProgressMilestone>[
                AnalysisProgressMilestone(
                  Duration(milliseconds: 700),
                  AnalysisProgressStage.awaitingAi,
                ),
              ];
        final progressTimers = progressMilestones
            .map(
              (milestone) => Timer(milestone.delay, () {
                onProgress?.call(
                  AnalysisProgressUpdate(
                    stage: milestone.stage,
                    imageCount: imageCount,
                    elapsed: DateTime.now().difference(requestStartTime),
                    requestBodyBytes: requestBodyBytes,
                  ),
                );
              }),
            )
            .toList(growable: false);

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

          for (final timer in progressTimers) {
            timer.cancel();
          }

          final roundTripDuration = DateTime.now().difference(requestStartTime);
          final responseData = decodeAnalysisResponseBody(httpResponse);
          final telemetryData =
              normalizeAnalysisJsonObject(responseData['telemetry']);

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
              '這次分析沒順利完成，請稍後再試。',
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
              final quotaException = quotaExceptionFrom429(responseData);
              if (quotaException != null) throw quotaException;
            }

            throw mapAnalysisHttpError(
              statusCode: status,
              errorCode: errorCode,
              rawMessage: errorMessage,
              hasImages: hasImages,
              recognizeOnly: recognizeOnly,
              hasUserDraft: hasUserDraft,
              hasRefineInstruction: hasRefineInstruction,
            );
          }

          return AnalysisResult.fromJson(responseData);
        } finally {
          for (final timer in progressTimers) {
            timer.cancel();
          }
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
                ? '${optimizeFlowLabel(hasRefineInstruction: hasRefineInstruction)}花太久了，請稍後再試。'
                : '分析花太久了，請稍後再試。',
        code: 'TIMEOUT',
        suggestedAction: AnalysisErrorAction.wait,
      );
    } catch (error) {
      if (error is AnalysisException) {
        rethrow;
      }

      throw mapUnexpectedAnalysisError(
        error,
        hasImages: hasImages,
        recognizeOnly: recognizeOnly,
        hasUserDraft: hasUserDraft,
        hasRefineInstruction: hasRefineInstruction,
      );
    }
  }
}
