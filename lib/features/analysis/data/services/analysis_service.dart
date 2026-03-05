// lib/features/analysis/data/services/analysis_service.dart
import 'dart:async';
import 'dart:io';

import '../../../../core/services/supabase_service.dart';
import '../../../conversation/domain/entities/message.dart';
import '../../../conversation/domain/entities/session_context.dart';
import '../../domain/entities/analysis_models.dart';

/// Service for analyzing conversations via Supabase Edge Function
class AnalysisService {
  /// Analyze a conversation and get AI suggestions
  ///
  /// If [userDraft] is provided, AI will also optimize the user's message draft.
  /// If [analyzeMode] is "my_message", AI will provide topic continuation suggestions.
  /// Throws [AnalysisException] if the analysis fails
  Future<AnalysisResult> analyzeConversation(
    List<Message> messages, {
    SessionContext? sessionContext,
    String? userDraft,
    String? analyzeMode, // "normal" | "my_message"
  }) async {
    if (messages.isEmpty) {
      throw AnalysisException('Messages cannot be empty');
    }

    try {
      final response = await SupabaseService.invokeFunction(
        'analyze-chat',
        body: {
          'messages': messages
              .map((m) => {
                    'isFromMe': m.isFromMe,
                    'content': m.content,
                  })
              .toList(),
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
        },
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

      return AnalysisResult.fromJson(response.data as Map<String, dynamic>);
    } on AnalysisException {
      rethrow;
    } on TimeoutException {
      throw AnalysisException('分析逾時，請稍後再試');
    } on SocketException {
      throw AnalysisException('網路連線失敗，請檢查網路');
    } catch (e) {
      // 提供更詳細的錯誤資訊
      final errorStr = e.toString();
      if (errorStr.contains('SocketException') || errorStr.contains('Connection')) {
        throw AnalysisException('網路連線失敗，請檢查網路');
      }
      if (errorStr.contains('timeout') || errorStr.contains('Timeout')) {
        throw AnalysisException('分析逾時，請稍後再試');
      }
      if (errorStr.contains('FunctionException')) {
        throw AnalysisException('伺服器忙碌中，請稍後再試');
      }
      throw AnalysisException('分析失敗: ${e.runtimeType}');
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
