/// AnalyzeChat 串流 session 的 reactive 狀態模型（domain 值物件）：
/// phase、quota 429 明細與 immutable state。真相持有者是
/// StreamingAnalyzeNotifier；歷史 import 路徑（notifier 檔）以
/// re-export 相容。
library;

import '../errors/analysis_exceptions.dart';
import 'analysis_models.dart';
import 'analysis_recommendation_preview.dart';
import 'analysis_stream_content.dart';

/// Phases of the analyze flow.
///
/// Streaming-only path:
///   idle -> connecting(connecting) -> streamingReport(preview) -> done
/// Failure branches:
///   connecting -> failedBeforeRecommendation                 (no recommendation emitted)
///   streamingReport  -> failedAfterRecommendation                  (preview preserved, retry CTA)
enum StreamingAnalyzePhase {
  idle,
  connecting,
  failedBeforeRecommendation,
  streamingReport,
  done,
  failedAfterRecommendation,
}

/// Quota 不足明細。當 analyze 串流以 429 的
/// [DailyLimitExceededException] / [MonthlyLimitExceededException] 中止時
/// 鏡射進 [StreamingAnalysisState]，UI 據此渲染升級卡而非 generic retry 卡
/// （smoke P1 fix 2026-06-11：quota 429 絕不能顯示成「無法再重試」）。
class QuotaExceededInfo {
  final bool isMonthly;

  /// 剩餘則數（server 給的 remaining；缺時以 limit-used 推算）。
  final int? remaining;

  /// 本次分析需要的則數（server 429 payload 的 quotaNeeded，可能缺）。
  final int? quotaNeeded;

  const QuotaExceededInfo({
    required this.isMonthly,
    this.remaining,
    this.quotaNeeded,
  });

  /// 從 service 層 429 異常轉換；非 quota 異常回 null。
  static QuotaExceededInfo? fromException(Exception e) {
    if (e is MonthlyLimitExceededException) {
      return QuotaExceededInfo(
        isMonthly: true,
        remaining: e.remaining ?? _nonNegative(e.monthlyLimit - e.used),
        quotaNeeded: e.quotaNeeded,
      );
    }
    if (e is DailyLimitExceededException) {
      return QuotaExceededInfo(
        isMonthly: false,
        remaining: e.remaining ?? _nonNegative(e.dailyLimit - e.used),
        quotaNeeded: e.quotaNeeded,
      );
    }
    return null;
  }

  static int _nonNegative(int value) => value < 0 ? 0 : value;
}

/// Immutable orchestrator state. Carries the streaming preview + final result,
/// plus the cached [analysisRunId] used by [StreamingAnalyzeNotifier.retryStream]
/// so the server can match the run without re-charging quota (invariant I1).
class StreamingAnalysisState {
  final StreamingAnalyzePhase phase;
  final AnalysisRecommendationPreview? recommendationPreview;
  final AnalysisResult? result;
  final String? analysisRunId;
  final String? recommendationPreviewErrorMessage;
  final String? recommendationPreviewErrorCode;
  final String? streamErrorMessage;
  final String? streamErrorCode;
  final String? streamProgressLabel;
  final String? streamProgressDetail;
  final List<AnalysisStreamContent> streamContents;
  final int retriesRemaining;
  final int? conversationMessageCount;
  final int? previousAnalyzedCount;
  final int? analyzedMessageCount;
  final String? conversationContentRevision;

  /// 非 null 表示這次失敗是額度不足（429），UI 必須走升級卡分流。
  final QuotaExceededInfo? quotaExceeded;

  const StreamingAnalysisState({
    required this.phase,
    this.recommendationPreview,
    this.result,
    this.analysisRunId,
    this.recommendationPreviewErrorMessage,
    this.recommendationPreviewErrorCode,
    this.streamErrorMessage,
    this.streamErrorCode,
    this.streamProgressLabel,
    this.streamProgressDetail,
    this.streamContents = const [],
    this.retriesRemaining = 0,
    this.conversationMessageCount,
    this.previousAnalyzedCount,
    this.analyzedMessageCount,
    this.conversationContentRevision,
    this.quotaExceeded,
  });

  const StreamingAnalysisState.idle() : this(phase: StreamingAnalyzePhase.idle);

  /// Sentinel used by [copyWith] to distinguish "not provided" from "set to
  /// null". Without this, `param ?? this.param` silently ignores explicit nulls,
  /// which prevents clearing nullable error/result fields after a retry. See
  /// invariant I-P2-a in the Phase 3 Codex review.
  static const Object _unset = Object();

  StreamingAnalysisState copyWith({
    StreamingAnalyzePhase? phase,
    Object? recommendationPreview = _unset,
    Object? result = _unset,
    Object? analysisRunId = _unset,
    Object? recommendationPreviewErrorMessage = _unset,
    Object? recommendationPreviewErrorCode = _unset,
    Object? streamErrorMessage = _unset,
    Object? streamErrorCode = _unset,
    Object? streamProgressLabel = _unset,
    Object? streamProgressDetail = _unset,
    List<AnalysisStreamContent>? streamContents,
    int? retriesRemaining,
    Object? conversationMessageCount = _unset,
    Object? previousAnalyzedCount = _unset,
    Object? analyzedMessageCount = _unset,
    Object? conversationContentRevision = _unset,
    Object? quotaExceeded = _unset,
  }) {
    return StreamingAnalysisState(
      phase: phase ?? this.phase,
      recommendationPreview: identical(recommendationPreview, _unset)
          ? this.recommendationPreview
          : recommendationPreview as AnalysisRecommendationPreview?,
      result:
          identical(result, _unset) ? this.result : result as AnalysisResult?,
      analysisRunId: identical(analysisRunId, _unset)
          ? this.analysisRunId
          : analysisRunId as String?,
      recommendationPreviewErrorMessage:
          identical(recommendationPreviewErrorMessage, _unset)
              ? this.recommendationPreviewErrorMessage
              : recommendationPreviewErrorMessage as String?,
      recommendationPreviewErrorCode:
          identical(recommendationPreviewErrorCode, _unset)
              ? this.recommendationPreviewErrorCode
              : recommendationPreviewErrorCode as String?,
      streamErrorMessage: identical(streamErrorMessage, _unset)
          ? this.streamErrorMessage
          : streamErrorMessage as String?,
      streamErrorCode: identical(streamErrorCode, _unset)
          ? this.streamErrorCode
          : streamErrorCode as String?,
      streamProgressLabel: identical(streamProgressLabel, _unset)
          ? this.streamProgressLabel
          : streamProgressLabel as String?,
      streamProgressDetail: identical(streamProgressDetail, _unset)
          ? this.streamProgressDetail
          : streamProgressDetail as String?,
      streamContents: streamContents ?? this.streamContents,
      retriesRemaining: retriesRemaining ?? this.retriesRemaining,
      conversationMessageCount: identical(conversationMessageCount, _unset)
          ? this.conversationMessageCount
          : conversationMessageCount as int?,
      previousAnalyzedCount: identical(previousAnalyzedCount, _unset)
          ? this.previousAnalyzedCount
          : previousAnalyzedCount as int?,
      analyzedMessageCount: identical(analyzedMessageCount, _unset)
          ? this.analyzedMessageCount
          : analyzedMessageCount as int?,
      conversationContentRevision:
          identical(conversationContentRevision, _unset)
              ? this.conversationContentRevision
              : conversationContentRevision as String?,
      quotaExceeded: identical(quotaExceeded, _unset)
          ? this.quotaExceeded
          : quotaExceeded as QuotaExceededInfo?,
    );
  }
}
