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
  final int imageCount;
  final int requestBodyBytes;
  final Duration payloadPreparationDuration;
  final Duration roundTripDuration;
  final Duration? edgeAiDuration;
  final int? totalCompressedImageBytes;

  const AnalysisTelemetry({
    required this.imageCount,
    required this.requestBodyBytes,
    required this.payloadPreparationDuration,
    required this.roundTripDuration,
    this.edgeAiDuration,
    this.totalCompressedImageBytes,
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
  Future<AnalysisResult> analyzeConversation(
    List<Message> messages, {
    List<Uint8List>? images,
    SessionContext? sessionContext,
    String? conversationSummary,
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
      throw AnalysisException('Messages cannot be empty');
    }

    const maxRetries = 2;
    Exception? lastError;

    debugPrint('[AnalysisService] analyzeConversation start');
    debugPrint(
      '[AnalysisService] messages: ${sanitizedMessages.length}, images: ${images?.length ?? 0}, recognizeOnly: $recognizeOnly',
    );

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        debugPrint(
            '[AnalysisService] attempt ${attempt + 1}/${maxRetries + 1}');
        return await _doAnalyze(
          sanitizedMessages,
          images: images,
          sessionContext: sessionContext,
          conversationSummary: conversationSummary,
          userDraft: userDraft,
          analyzeMode: analyzeMode,
          recognizeOnly: recognizeOnly,
          onProgress: onProgress,
          onTelemetry: onTelemetry,
        );
      } catch (error) {
        debugPrint(
          '[AnalysisService] attempt ${attempt + 1} failed: ${error.runtimeType} - $error',
        );
        lastError = error is Exception ? error : Exception(error.toString());

        if (error is AnalysisException &&
            !error.message.contains('Failed to fetch') &&
            !error.message.contains('timeout') &&
            !error.message.contains('逾時')) {
          rethrow;
        }

        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt + 1));
        }
      }
    }

    throw lastError ?? AnalysisException('分析失敗');
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
    String? userDraft,
    String? analyzeMode,
    required bool recognizeOnly,
    AnalysisProgressCallback? onProgress,
    AnalysisTelemetryCallback? onTelemetry,
  }) async {
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
      if (images != null && images.isNotEmpty) {
        imageDataList = images.asMap().entries.map((entry) {
          final base64Data = base64Encode(entry.value);
          return ImageData(
            data: base64Data,
            mediaType: 'image/jpeg',
            order: entry.key + 1,
          ).toJson();
        }).toList();
      }

      final hasImages = imageDataList != null && imageDataList.isNotEmpty;
      final timeout = hasImages
          ? const Duration(seconds: 120)
          : const Duration(seconds: 60);

      final accessToken = SupabaseService.accessToken;
      if (accessToken == null) {
        throw AnalysisException('請先重新登入後再試');
      }

      final requestBody = {
        'messages': messages
            .map(
              (message) => {
                'isFromMe': message.isFromMe,
                'content': message.content,
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
        if (conversationSummary != null && conversationSummary.trim().isNotEmpty)
          'conversationSummary': conversationSummary.trim(),
        if (userDraft != null && userDraft.trim().isNotEmpty)
          'userDraft': userDraft.trim(),
        if (analyzeMode != null) 'analyzeMode': analyzeMode,
        if (recognizeOnly) 'recognizeOnly': true,
      };

      final encodedRequestBody = jsonEncode(requestBody);
      final requestBodyBytes = encodedRequestBody.length;
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
            ),
          );

          final status = httpResponse.statusCode;
          if (responseData['_nonJson'] == true && status == 200) {
            throw AnalysisException('伺服器回傳了非 JSON 內容，請稍後再試');
          }

          if (status != 200) {
            final errorCode = responseData['code'] as String?;
            final errorMessage = responseData['message'] as String? ??
                responseData['error'] as String? ??
                (responseData['_nonJson'] == true
                    ? '伺服器回傳了無法解析的內容'
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

            if (errorCode == 'RECOGNITION_FAILED') {
              throw AnalysisException(errorMessage);
            }

            throw AnalysisException(errorMessage);
          }

          return AnalysisResult.fromJson(responseData);
        } finally {
          awaitingAiTimer.cancel();
        }
      } finally {
        httpClient.close();
      }
    } on TimeoutException {
      throw AnalysisException('分析逾時，請稍後再試');
    } catch (error) {
      final errorMessage = error.toString();

      if (errorMessage.contains('Unauthorized') ||
          errorMessage.contains('401')) {
        throw AnalysisException('登入狀態已失效，請重新登入後再試');
      }

      if (errorMessage.contains('SocketException') ||
          errorMessage.contains('Connection refused')) {
        throw AnalysisException('網路連線失敗，請檢查網路後重試');
      }

      if (errorMessage.contains('timeout') ||
          errorMessage.contains('Timeout')) {
        throw AnalysisException('分析逾時，請稍後再試');
      }

      if (error is AnalysisException) {
        rethrow;
      }

      throw AnalysisException(
        '分析失敗 (${error.runtimeType}): $errorMessage',
      );
    }
  }
}

class AnalysisException implements Exception {
  final String message;

  AnalysisException(this.message);

  @override
  String toString() => 'AnalysisException: $message';
}

class DailyLimitExceededException extends AnalysisException {
  final int dailyLimit;
  final int used;

  DailyLimitExceededException({
    required this.dailyLimit,
    required this.used,
  }) : super('Daily limit exceeded');
}

class MonthlyLimitExceededException extends AnalysisException {
  final int monthlyLimit;
  final int used;

  MonthlyLimitExceededException({
    required this.monthlyLimit,
    required this.used,
  }) : super('Monthly limit exceeded');
}
