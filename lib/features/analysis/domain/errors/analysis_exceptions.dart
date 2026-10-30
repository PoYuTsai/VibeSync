/// analyze-chat 系列請求的共用錯誤模型（domain 層錯誤契約）。
///
/// 歷史 import 路徑 `data/services/analysis_exceptions.dart` 與
/// `analysis_service.dart` barrel 以 re-export 相容。
library;

import '../../../subscription/presentation/quota_copy.dart';

enum AnalysisErrorAction {
  retry,
  relogin,
  rescreenshot,
  shortenInput,
  upgrade,
  wait,
  addIncomingMessage,

  /// 最低 App 版本閘門擋下：只能去更新，重送只會再被擋一次。
  updateApp,
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

/// 伺服器的最低 App 版本閘門擋下這次分析（Eric 2026-10-18）：HTTP 426，或串流
/// analysis.error 帶 APP_UPDATE_REQUIRED。不是內容錯誤、也不能重試；伺服器擋在
/// 扣費之前，這次沒有扣額度。
class AppUpdateRequiredException extends AnalysisException {
  static const errorCode = 'APP_UPDATE_REQUIRED';
  static const userMessage = '這個版本已經停止支援，請到 App Store 更新到最新版。';

  AppUpdateRequiredException()
      : super(
          userMessage,
          code: errorCode,
          suggestedAction: AnalysisErrorAction.updateApp,
        );
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
          // 台灣早上 8 點恢復（不是「明天」，Onboarding 第 3 步）。這裡拿不到目前
          // 方案，不提升級：升級由接著打開的付費頁或錯誤卡的提示負責。
          '今日額度已用完，$kDailyQuotaResetLine。',
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
          // 先講什麼時候恢復（Onboarding 第 3 步）。這裡拿不到目前方案，不提升級：
          // 升級由接著打開的付費頁負責（Essential 不能再升級）。
          '本月額度已用完，$kMonthlyQuotaResetLine。',
          code: 'MONTHLY_LIMIT_EXCEEDED',
          suggestedAction: AnalysisErrorAction.upgrade,
        );
}
