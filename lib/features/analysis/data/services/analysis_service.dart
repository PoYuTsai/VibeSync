// lib/features/analysis/data/services/analysis_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../../core/services/supabase_service.dart';
import '../../../../core/config/environment.dart';
import '../../../conversation/domain/entities/message.dart';
import '../../../conversation/domain/entities/session_context.dart';
import '../../domain/entities/analysis_models.dart';

/// 圖片資料類別 (用於 API 傳輸)
class ImageData {
  final String data; // base64
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

/// Service for analyzing conversations via Supabase Edge Function
class AnalysisService {
  /// Analyze a conversation and get AI suggestions
  ///
  /// If [images] is provided, AI will use Claude Vision to recognize and analyze screenshots.
  /// If [userDraft] is provided, AI will also optimize the user's message draft.
  /// If [analyzeMode] is "my_message", AI will provide topic continuation suggestions.
  /// Throws [AnalysisException] if the analysis fails
  Future<AnalysisResult> analyzeConversation(
    List<Message> messages, {
    List<Uint8List>? images,
    SessionContext? sessionContext,
    String? userDraft,
    String? analyzeMode, // "normal" | "my_message"
    bool recognizeOnly = false, // 純識別模式：只識別截圖，不做完整分析
  }) async {
    final sanitizedMessages = recognizeOnly
        ? messages.where((message) => message.id != 'placeholder').toList()
        : messages;

    if (sanitizedMessages.isEmpty && !recognizeOnly) {
      throw AnalysisException('Messages cannot be empty');
    }

    // 最多重試 2 次
    const maxRetries = 2;
    Exception? lastError;

    debugPrint('[AnalysisService] analyzeConversation 開始');
    debugPrint('[AnalysisService] messages: ${sanitizedMessages.length}, images: ${images?.length ?? 0}, recognizeOnly: $recognizeOnly');

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        debugPrint('[AnalysisService] 嘗試 ${attempt + 1}/${maxRetries + 1}');
        return await _doAnalyze(
          sanitizedMessages,
          images: images,
          sessionContext: sessionContext,
          userDraft: userDraft,
          analyzeMode: analyzeMode,
          recognizeOnly: recognizeOnly,
        );
      } catch (e) {
        debugPrint('[AnalysisService] 嘗試 ${attempt + 1} 失敗: ${e.runtimeType} - $e');
        lastError = e is Exception ? e : Exception(e.toString());
        // 如果是 AnalysisException (非網路錯誤)，不重試
        if (e is AnalysisException &&
            !e.message.contains('Failed to fetch') &&
            !e.message.contains('連線') &&
            !e.message.contains('逾時')) {
          debugPrint('[AnalysisService] 不可重試的錯誤，直接拋出');
          rethrow;
        }
        // 等待後重試
        if (attempt < maxRetries) {
          debugPrint('[AnalysisService] 等待 ${attempt + 1}s 後重試...');
          await Future.delayed(Duration(seconds: attempt + 1));
        }
      }
    }
    debugPrint('[AnalysisService] 所有重試失敗');
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
      final shortenedBody = body.length > 300 ? '${body.substring(0, 300)}...' : body;
      return <String, dynamic>{
        '_nonJson': true,
        '_rawBody': shortenedBody,
      };
    }
  }

  Future<AnalysisResult> _doAnalyze(
    List<Message> messages, {
    List<Uint8List>? images,
    SessionContext? sessionContext,
    String? userDraft,
    String? analyzeMode,
    bool recognizeOnly = false,
  }) async {
    try {
      debugPrint('[AnalysisService] _doAnalyze 開始');
      debugPrint('[AnalysisService] recognizeOnly: $recognizeOnly');
      debugPrint('[AnalysisService] images: ${images?.length ?? 0}');

      // 處理圖片轉換為 base64
      List<Map<String, dynamic>>? imageDataList;
      if (images != null && images.isNotEmpty) {
        debugPrint('[AnalysisService] 開始轉換圖片為 base64...');
        imageDataList = images.asMap().entries.map((entry) {
          final base64Data = base64Encode(entry.value);
          debugPrint('[AnalysisService] 圖片 ${entry.key + 1}: ${(base64Data.length / 1024).toStringAsFixed(1)}KB (base64)');
          return ImageData(
            data: base64Data,
            mediaType: 'image/jpeg',
            order: entry.key + 1,
          ).toJson();
        }).toList();
        debugPrint('[AnalysisService] 圖片轉換完成');
      }

      // 有圖片時使用較長的 timeout（120 秒），否則 60 秒
      final hasImages = imageDataList != null && imageDataList.isNotEmpty;
      final timeout = hasImages
          ? const Duration(seconds: 120)
          : const Duration(seconds: 60);

      debugPrint('[AnalysisService] 呼叫 Edge Function (timeout: ${timeout.inSeconds}s)...');
      final requestStartTime = DateTime.now();

      // 使用直接 HTTP 請求而非 Supabase SDK，避免連線狀態問題
      final accessToken = SupabaseService.accessToken;
      if (accessToken == null) {
        throw AnalysisException('請重新登入');
      }

      final requestBody = {
        'messages': messages
            .map((m) => {
                  'isFromMe': m.isFromMe,
                  'content': m.content,
                })
            .toList(),
        if (imageDataList != null) 'images': imageDataList,
        if (sessionContext != null)
          'sessionContext': {
            'meetingContext': sessionContext.meetingContext.label,
            'duration': sessionContext.duration.label,
            'goal': sessionContext.goal.label,
          },
        if (userDraft != null && userDraft.trim().isNotEmpty)
          'userDraft': userDraft.trim(),
        if (analyzeMode != null)
          'analyzeMode': analyzeMode,
        if (recognizeOnly)
          'recognizeOnly': true,
      };

      debugPrint('[AnalysisService] Request body size: ${jsonEncode(requestBody).length} bytes');

      // 使用 http package 直接發送請求
      final httpClient = http.Client();
      try {
        final httpResponse = await httpClient.post(
          Uri.parse('${AppConfig.supabaseUrl}/functions/v1/analyze-chat'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $accessToken',
            'apikey': AppConfig.supabaseAnonKey,
          },
          body: jsonEncode(requestBody),
        ).timeout(timeout);

        final requestElapsed = DateTime.now().difference(requestStartTime).inSeconds;
        debugPrint('[AnalysisService] HTTP 回應，耗時: ${requestElapsed}s');
        debugPrint('[AnalysisService] 狀態碼: ${httpResponse.statusCode}');

        // 轉換為類似 FunctionResponse 的格式
        final responseData = _decodeResponseBody(httpResponse);
        final status = httpResponse.statusCode;

        if (responseData['_nonJson'] == true && status == 200) {
          throw AnalysisException('伺服器回應格式異常，請稍後再試');
        }

        if (status != 200) {
          final errorCode = responseData['code'] as String?;
          final errorMessage =
              responseData['message'] as String? ??
              responseData['error'] as String? ??
              (responseData['_nonJson'] == true
                  ? '伺服器暫時無法處理請求，請稍後再試'
                  : 'Analysis failed');

          // Check for rate limit errors
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

        // 安全解析 JSON 回應
        return AnalysisResult.fromJson(responseData);
      } finally {
        httpClient.close();
      }
    } on TimeoutException catch (e) {
      debugPrint('[AnalysisService] TimeoutException: $e');
      throw AnalysisException('分析逾時，請稍後再試');
    } catch (e) {
      debugPrint('[AnalysisService] 未知錯誤: ${e.runtimeType}');
      debugPrint('[AnalysisService] 錯誤詳情: $e');

      // 顯示完整錯誤訊息以便除錯
      final errorStr = e.toString();
      final errorType = e.runtimeType.toString();

      // 針對特定錯誤類型提供建議
      if (errorStr.contains('Unauthorized') || errorStr.contains('401')) {
        throw AnalysisException('登入已過期，請重新登入');
      }
      if (errorStr.contains('SocketException') || errorStr.contains('Connection refused')) {
        throw AnalysisException('網路連線失敗，請檢查網路');
      }
      if (errorStr.contains('timeout') || errorStr.contains('Timeout')) {
        throw AnalysisException('分析逾時，請稍後再試');
      }

      // 顯示完整錯誤以便除錯
      throw AnalysisException('錯誤 ($errorType): $errorStr');
    }
  }
}

/// Base exception for analysis errors
class AnalysisException implements Exception {
  final String message;

  AnalysisException(this.message);

  @override
  String toString() => 'AnalysisException: $message';
}

/// Thrown when daily message limit is exceeded
class DailyLimitExceededException extends AnalysisException {
  final int dailyLimit;
  final int used;

  DailyLimitExceededException({
    required this.dailyLimit,
    required this.used,
  }) : super('Daily limit exceeded');
}

/// Thrown when monthly message limit is exceeded
class MonthlyLimitExceededException extends AnalysisException {
  final int monthlyLimit;
  final int used;

  MonthlyLimitExceededException({
    required this.monthlyLimit,
    required this.used,
  }) : super('Monthly limit exceeded');
}
