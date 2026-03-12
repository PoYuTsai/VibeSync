// lib/features/analysis/data/services/analysis_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../../../core/services/supabase_service.dart';
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
    if (messages.isEmpty) {
      throw AnalysisException('Messages cannot be empty');
    }

    // 最多重試 2 次
    const maxRetries = 2;
    Exception? lastError;

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        return await _doAnalyze(
          messages,
          images: images,
          sessionContext: sessionContext,
          userDraft: userDraft,
          analyzeMode: analyzeMode,
          recognizeOnly: recognizeOnly,
        );
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        // 如果是 AnalysisException (非網路錯誤)，不重試
        if (e is AnalysisException &&
            !e.message.contains('Failed to fetch') &&
            !e.message.contains('連線') &&
            !e.message.contains('逾時')) {
          rethrow;
        }
        // 等待後重試
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt + 1));
        }
      }
    }
    throw lastError ?? AnalysisException('分析失敗');
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
      // 處理圖片轉換為 base64
      List<Map<String, dynamic>>? imageDataList;
      if (images != null && images.isNotEmpty) {
        imageDataList = images.asMap().entries.map((entry) {
          return ImageData(
            data: base64Encode(entry.value),
            mediaType: 'image/jpeg',
            order: entry.key + 1,
          ).toJson();
        }).toList();
      }

      // 有圖片時使用較長的 timeout（120 秒），否則 60 秒
      final hasImages = imageDataList != null && imageDataList.isNotEmpty;
      final timeout = hasImages
          ? const Duration(seconds: 120)
          : const Duration(seconds: 60);

      final response = await SupabaseService.invokeFunction(
        'analyze-chat',
        body: {
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
        },
        timeout: timeout,
      );

      if (response.status != 200) {
        final errorData = response.data as Map<String, dynamic>?;
        final errorMessage = errorData?['error'] as String? ?? 'Analysis failed';

        // Check for rate limit errors
        if (response.status == 429) {
          final monthlyLimit = errorData?['monthlyLimit'];
          final dailyLimit = errorData?['dailyLimit'];
          if (dailyLimit != null) {
            throw DailyLimitExceededException(
              dailyLimit: dailyLimit as int,
              used: errorData?['used'] as int? ?? 0,
            );
          }
          if (monthlyLimit != null) {
            throw MonthlyLimitExceededException(
              monthlyLimit: monthlyLimit as int,
              used: errorData?['used'] as int? ?? 0,
            );
          }
        }

        throw AnalysisException(errorMessage);
      }

      // 安全解析 JSON 回應
      try {
        final data = response.data;
        if (data == null) {
          throw AnalysisException('伺服器回應為空');
        }
        if (data is! Map<String, dynamic>) {
          throw AnalysisException('伺服器回應格式錯誤: ${data.runtimeType}');
        }
        return AnalysisResult.fromJson(data);
      } on AnalysisException {
        rethrow;
      } catch (parseError) {
        // 顯示詳細錯誤以便除錯
        throw AnalysisException('解析失敗: $parseError');
      }
    } on AnalysisException {
      rethrow;
    } on TimeoutException {
      throw AnalysisException('分析逾時，請稍後再試');
    } catch (e) {
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
