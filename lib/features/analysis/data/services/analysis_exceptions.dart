/// analyze-chat 系列請求的共用錯誤模型。
///
/// 由 `analysis_service.dart` re-export；既有呼叫端維持原 import 路徑。
library;

enum AnalysisErrorAction {
  retry,
  relogin,
  rescreenshot,
  shortenInput,
  upgrade,
  wait,
  addIncomingMessage,
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

  /// 429 payload 的 dailyRemaining（server 算好的剩餘則數），可能缺。
  final int? remaining;

  /// 429 payload 的 quotaNeeded（本次分析需要的則數），可能缺。
  final int? quotaNeeded;

  DailyLimitExceededException({
    required this.dailyLimit,
    required this.used,
    this.remaining,
    this.quotaNeeded,
  }) : super(
          '今日額度已用完，可以明天再試，或升級解鎖更多分析。',
          code: 'DAILY_LIMIT_EXCEEDED',
          suggestedAction: AnalysisErrorAction.wait,
        );
}

class MonthlyLimitExceededException extends AnalysisException {
  final int monthlyLimit;
  final int used;

  /// 429 payload 的 monthlyRemaining（server 算好的剩餘則數），可能缺。
  final int? remaining;

  /// 429 payload 的 quotaNeeded（本次分析需要的則數），可能缺。
  final int? quotaNeeded;

  MonthlyLimitExceededException({
    required this.monthlyLimit,
    required this.used,
    this.remaining,
    this.quotaNeeded,
  }) : super(
          '本月額度已用完，升級後可以繼續分析。',
          code: 'MONTHLY_LIMIT_EXCEEDED',
          suggestedAction: AnalysisErrorAction.upgrade,
        );
}
