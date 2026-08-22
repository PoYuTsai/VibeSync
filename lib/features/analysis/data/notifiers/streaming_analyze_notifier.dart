import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/message_calculator.dart';
import '../../../conversation/domain/entities/message.dart';
import '../../../conversation/domain/entities/session_context.dart';

import '../providers/analysis_providers.dart';
import '../services/analysis_service.dart';
import '../services/analyze_stream_client.dart';
import '../../domain/entities/analysis_models.dart';
import '../../domain/entities/analysis_recommendation_preview.dart';

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
  final String? conversationPartnerId;
  final bool? isReconnectContext;

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
    this.conversationPartnerId,
    this.isReconnectContext,
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
    Object? conversationPartnerId = _unset,
    Object? isReconnectContext = _unset,
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
      conversationPartnerId: identical(conversationPartnerId, _unset)
          ? this.conversationPartnerId
          : conversationPartnerId as String?,
      isReconnectContext: identical(isReconnectContext, _unset)
          ? this.isReconnectContext
          : isReconnectContext as bool?,
      quotaExceeded: identical(quotaExceeded, _unset)
          ? this.quotaExceeded
          : quotaExceeded as QuotaExceededInfo?,
    );
  }
}

const List<(String, String)> _streamPreludeProgress = <(String, String)>[
  (
    '正在送出完整分析請求',
    '正在把最新對話與脈絡送到分析端。',
  ),
  (
    '正在讀取對話脈絡',
    '正在整理對方訊號、你的回覆與上下文。',
  ),
  (
    '正在推演回覆策略',
    '正在判斷關係階段、對方這次的投入訊號與最適合的下一步。',
  ),
  (
    '完整分析仍在進行',
    '正在等待模型完成深度推理，請保持連線。',
  ),
];

const Duration _streamPreludeProgressInterval = Duration(seconds: 3);

final streamingAnalyzeProvider = NotifierProvider.autoDispose
    .family<StreamingAnalyzeNotifier, StreamingAnalysisState, String>(
  StreamingAnalyzeNotifier.new,
);

/// Streaming AnalyzeChat orchestrator for a single conversation. State
/// survives navigation while in flight via [Ref.keepAlive]; once the user
/// starts an analysis the provider stays alive for the rest of the app session
/// (in-memory only; durable run recovery lives on the server).
class StreamingAnalyzeNotifier
    extends AutoDisposeFamilyNotifier<StreamingAnalysisState, String> {
  int _generation = 0;
  KeepAliveLink? _keepAliveLink;

  // Retry payload cached from the most recent [start] call. The notifier
  // outlives the screen via [Ref.keepAlive], so these fields survive screen
  // remount -> [retryStream] then does not depend on screen-instance local state
  // (invariant I-P1-b). A second [start] overwrites them (I-P1-c).
  List<Message>? _cachedMessages;
  SessionContext? _cachedSessionContext;
  String? _cachedConversationSummary;
  String? _cachedPartnerSummary;
  String? _cachedEffectiveStyleContext;
  String? _cachedKnownContactName;
  String? _cachedPreviousStage;
  int? _cachedAnalysisFragmentStartIndex;
  int? _cachedPreviousAnalyzedCount;
  int? _cachedConversationMessageCount;
  int? _cachedAnalyzedMessageCount;
  String? _cachedConversationContentRevision;
  String? _cachedConversationPartnerId;
  bool? _cachedIsReconnectContext;
  int? _cachedPreviousAnalyzedCharCount;
  OverchargeConfirmationPayload? _cachedConfirmedOvercharge;
  int? _cachedPayloadCharCount;

  /// ADR #19 規格 #8：最近一次 [start] 實際送出 payload 的計費字數。
  /// 分析成功後由 screen 持久化為 conversation.lastAnalyzedCharCount
  /// （baseline 必須對應送出的 requestMessages，不是完成時 repository
  /// 裡的最新 messages）。
  int? get lastPayloadCharCount => _cachedPayloadCharCount;

  @override
  StreamingAnalysisState build(String conversationId) {
    return const StreamingAnalysisState.idle();
  }

  AnalyzeStreamClient get _client => ref.read(analyzeStreamClientProvider);

  /// Run the analysis pipeline. Multiple concurrent calls supersede
  /// older ones via a generation guard; results from stale generations are
  /// dropped before reaching [state] so a navigate-away-and-restart cannot
  /// leak an old payload over the current run.
  Future<void> start({
    required List<Message> messages,
    SessionContext? sessionContext,
    String? conversationSummary,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? knownContactName,
    String? previousStage,
    int? analysisFragmentStartIndex,
    int? previousAnalyzedCount,
    int? previousAnalyzedCharCount,
    OverchargeConfirmationPayload? confirmedOvercharge,
    int? conversationMessageCount,
    int? analyzedMessageCount,
    String? conversationContentRevision,
    String? conversationPartnerId,
    bool? isReconnectContext,
  }) async {
    final myGen = ++_generation;
    _keepAliveLink ??= ref.keepAlive();
    final effectiveAnalyzedMessageCount =
        analyzedMessageCount ?? conversationMessageCount ?? messages.length;

    // Cache the payload so retryStream can resume the same request after the
    // calling screen is disposed/remounted.
    _cachedMessages = List<Message>.unmodifiable(messages);
    _cachedSessionContext = sessionContext;
    _cachedConversationSummary = conversationSummary;
    _cachedPartnerSummary = partnerSummary;
    _cachedEffectiveStyleContext = effectiveStyleContext;
    _cachedKnownContactName = knownContactName;
    _cachedPreviousStage = previousStage;
    _cachedAnalysisFragmentStartIndex = analysisFragmentStartIndex;
    _cachedPreviousAnalyzedCount = previousAnalyzedCount;
    _cachedConversationMessageCount = conversationMessageCount;
    _cachedAnalyzedMessageCount = effectiveAnalyzedMessageCount;
    _cachedConversationContentRevision = conversationContentRevision;
    _cachedConversationPartnerId = conversationPartnerId;
    _cachedIsReconnectContext = isReconnectContext;
    _cachedPreviousAnalyzedCharCount = previousAnalyzedCharCount;
    _cachedConfirmedOvercharge = confirmedOvercharge;
    // ADR #19 規格 #8：baseline 對應這次送出的 requestMessages。
    _cachedPayloadCharCount = MessageCalculator.countPayloadChars(messages);

    state = StreamingAnalysisState(
      phase: StreamingAnalyzePhase.connecting,
      streamProgressLabel: '開始完整分析',
      streamProgressDetail: '正在建立串流連線。',
      conversationMessageCount: conversationMessageCount,
      previousAnalyzedCount: previousAnalyzedCount,
      analyzedMessageCount: effectiveAnalyzedMessageCount,
      conversationContentRevision: conversationContentRevision,
      conversationPartnerId: conversationPartnerId,
      isReconnectContext: isReconnectContext,
    );

    await _runStream(
      generation: myGen,
      messages: messages,
      sessionContext: sessionContext,
      conversationSummary: conversationSummary,
      partnerSummary: partnerSummary,
      effectiveStyleContext: effectiveStyleContext,
      knownContactName: knownContactName,
      previousStage: previousStage,
      analysisFragmentStartIndex: analysisFragmentStartIndex,
      previousAnalyzedCount: previousAnalyzedCount,
      previousAnalyzedCharCount: previousAnalyzedCharCount,
      confirmedOvercharge: confirmedOvercharge,
      conversationMessageCount: conversationMessageCount,
      analyzedMessageCount: effectiveAnalyzedMessageCount,
      conversationContentRevision: conversationContentRevision,
      conversationPartnerId: conversationPartnerId,
      isReconnectContext: isReconnectContext,
    );
  }

  Future<void> _runStream({
    required int generation,
    String? analysisRunId,
    required List<Message> messages,
    SessionContext? sessionContext,
    String? conversationSummary,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? knownContactName,
    String? previousStage,
    int? analysisFragmentStartIndex,
    int? previousAnalyzedCount,
    int? previousAnalyzedCharCount,
    OverchargeConfirmationPayload? confirmedOvercharge,
    int? conversationMessageCount,
    int? analyzedMessageCount,
    String? conversationContentRevision,
    String? conversationPartnerId,
    bool? isReconnectContext,
    int automaticRecoveryAttempt = 0,
  }) async {
    final stopLocalProgress = _startLocalStreamPreludeProgress(
      generation: generation,
      conversationMessageCount: conversationMessageCount,
      analyzedMessageCount: analyzedMessageCount,
    );
    try {
      await for (final update in _client.stream(AnalyzeStreamRequest(
        analysisRunId: analysisRunId,
        messages: messages,
        sessionContext: sessionContext,
        conversationSummary: conversationSummary,
        partnerSummary: partnerSummary,
        effectiveStyleContext: effectiveStyleContext,
        knownContactName: knownContactName,
        previousStage: previousStage,
        analysisFragmentStartIndex: analysisFragmentStartIndex,
        previousAnalyzedCount: previousAnalyzedCount,
        previousAnalyzedCharCount: previousAnalyzedCharCount,
        confirmedOvercharge: confirmedOvercharge,
      ))) {
        stopLocalProgress();
        if (generation != _generation) return;

        switch (update.kind) {
          case AnalysisStreamUpdateKind.started:
          case AnalysisStreamUpdateKind.progress:
            state = state.copyWith(
              phase: state.recommendationPreview == null
                  ? StreamingAnalyzePhase.connecting
                  : StreamingAnalyzePhase.streamingReport,
              analysisRunId: update.runId ?? state.analysisRunId,
              streamProgressLabel: update.label,
              streamProgressDetail: update.detail,
              conversationMessageCount: conversationMessageCount,
              analyzedMessageCount: analyzedMessageCount,
            );
            break;
          case AnalysisStreamUpdateKind.content:
            final content = update.content;
            if (content == null) break;
            state = state.copyWith(
              phase: StreamingAnalyzePhase.streamingReport,
              analysisRunId: update.runId ?? state.analysisRunId,
              streamErrorMessage: null,
              streamErrorCode: null,
              streamProgressLabel: update.label ?? content.title,
              streamProgressDetail: update.detail ?? content.body,
              streamContents: List<AnalysisStreamContent>.unmodifiable(
                <AnalysisStreamContent>[
                  ...state.streamContents,
                  content,
                ],
              ),
              retriesRemaining: 0,
              conversationMessageCount: conversationMessageCount,
              analyzedMessageCount: analyzedMessageCount,
              quotaExceeded: null,
            );
            break;
          case AnalysisStreamUpdateKind.recommendation:
            final recommendationPreview = update.recommendationPreview;
            if (recommendationPreview == null) break;
            state = state.copyWith(
              phase: StreamingAnalyzePhase.streamingReport,
              recommendationPreview: recommendationPreview,
              analysisRunId: recommendationPreview.analysisRunId,
              streamErrorMessage: null,
              streamErrorCode: null,
              streamProgressLabel: update.label,
              streamProgressDetail: update.detail,
              retriesRemaining: 0,
              conversationMessageCount: conversationMessageCount,
              analyzedMessageCount: analyzedMessageCount,
              quotaExceeded: null,
            );
            break;
          case AnalysisStreamUpdateKind.done:
            final result = update.result;
            if (result == null) {
              throw AnalysisException(
                '完整分析串流缺少結果，請重新分析。',
                code: 'INVALID_STREAM_RESULT',
                suggestedAction: AnalysisErrorAction.retry,
              );
            }
            state = state.copyWith(
              phase: StreamingAnalyzePhase.done,
              result: result,
              analysisRunId: update.runId ?? state.analysisRunId,
              streamErrorMessage: null,
              streamErrorCode: null,
              streamProgressLabel: null,
              streamProgressDetail: null,
              retriesRemaining: 0,
              conversationMessageCount: conversationMessageCount,
              analyzedMessageCount: analyzedMessageCount,
              quotaExceeded: null,
            );
            return;
        }
      }

      if (generation != _generation) return;
      throw AnalysisException(
        '完整分析串流尚未完成，請重新分析。',
        code: 'STREAM_INCOMPLETE',
        suggestedAction: AnalysisErrorAction.retry,
      );
    } on Exception catch (e) {
      if (generation != _generation) return;
      final resumeRunId = state.analysisRunId;
      if (resumeRunId != null &&
          automaticRecoveryAttempt < 2 &&
          _shouldAutomaticallyRecoverStream(e)) {
        stopLocalProgress();
        final hasPartialResult = state.recommendationPreview != null ||
            state.streamContents.isNotEmpty;
        state = state.copyWith(
          phase: hasPartialResult
              ? StreamingAnalyzePhase.streamingReport
              : StreamingAnalyzePhase.connecting,
          analysisRunId: resumeRunId,
          streamErrorMessage: null,
          streamErrorCode: null,
          streamProgressLabel: '連線中斷，正在取回分析結果',
          streamProgressDetail: '會接續原本的分析，不會重新扣除額度。',
          streamContents: const <AnalysisStreamContent>[],
          retriesRemaining: 0,
          conversationMessageCount: conversationMessageCount,
          analyzedMessageCount: analyzedMessageCount,
          quotaExceeded: null,
        );
        await _runStream(
          generation: generation,
          analysisRunId: resumeRunId,
          messages: messages,
          sessionContext: sessionContext,
          conversationSummary: conversationSummary,
          partnerSummary: partnerSummary,
          effectiveStyleContext: effectiveStyleContext,
          knownContactName: knownContactName,
          previousStage: previousStage,
          analysisFragmentStartIndex: analysisFragmentStartIndex,
          previousAnalyzedCount: previousAnalyzedCount,
          previousAnalyzedCharCount: previousAnalyzedCharCount,
          confirmedOvercharge: confirmedOvercharge,
          conversationMessageCount: conversationMessageCount,
          analyzedMessageCount: analyzedMessageCount,
          conversationContentRevision: conversationContentRevision,
          conversationPartnerId: conversationPartnerId,
          isReconnectContext: isReconnectContext,
          automaticRecoveryAttempt: automaticRecoveryAttempt + 1,
        );
        return;
      }
      final message = e is AnalysisException ? e.message : '完整分析暫時失敗，請重新分析。';
      final code = e is AnalysisException ? e.code : null;
      // Quota 429 走升級卡分流：retriesRemaining 強制 0（重試只會再撞 429），
      // 但 UI 不得渲染「無法再重試」——quotaExceeded 非 null 時改渲染升級卡。
      final quotaExceeded = QuotaExceededInfo.fromException(e);
      final recommendationPreview = state.recommendationPreview;
      final hasStreamContent = state.streamContents.isNotEmpty;
      final hasRecoverableRun = state.analysisRunId != null &&
          quotaExceeded == null &&
          _shouldKeepRunRetryable(e);
      final retriesRemaining = quotaExceeded != null
          ? 0
          : _streamRetriesRemaining(
              e,
              hasRecommendation: recommendationPreview != null ||
                  hasStreamContent ||
                  hasRecoverableRun,
            );

      if (recommendationPreview != null ||
          hasStreamContent ||
          hasRecoverableRun) {
        state = state.copyWith(
          phase: StreamingAnalyzePhase.failedAfterRecommendation,
          streamErrorMessage: message,
          streamErrorCode: code,
          streamProgressLabel: null,
          streamProgressDetail: null,
          retriesRemaining: retriesRemaining,
          conversationMessageCount: conversationMessageCount,
          analyzedMessageCount: analyzedMessageCount,
          quotaExceeded: quotaExceeded,
        );
        return;
      }

      state = StreamingAnalysisState(
        phase: StreamingAnalyzePhase.failedBeforeRecommendation,
        recommendationPreviewErrorMessage: message,
        recommendationPreviewErrorCode: code,
        conversationMessageCount: conversationMessageCount,
        previousAnalyzedCount: previousAnalyzedCount,
        analyzedMessageCount: analyzedMessageCount,
        conversationContentRevision: conversationContentRevision,
        conversationPartnerId: conversationPartnerId,
        isReconnectContext: isReconnectContext,
        quotaExceeded: quotaExceeded,
      );
    } finally {
      stopLocalProgress();
    }
  }

  void Function() _startLocalStreamPreludeProgress({
    required int generation,
    int? conversationMessageCount,
    int? analyzedMessageCount,
  }) {
    var stopped = false;
    var tick = 0;

    void publish() {
      if (stopped || generation != _generation) return;
      final current = state;
      if (current.phase != StreamingAnalyzePhase.connecting ||
          current.recommendationPreview != null) {
        return;
      }

      final step = _streamPreludeProgress[tick % _streamPreludeProgress.length];
      tick += 1;
      state = current.copyWith(
        streamProgressLabel: step.$1,
        streamProgressDetail: step.$2,
        conversationMessageCount: conversationMessageCount,
        analyzedMessageCount: analyzedMessageCount,
      );
    }

    scheduleMicrotask(publish);
    final timer = Timer.periodic(
      _streamPreludeProgressInterval,
      (_) => publish(),
    );

    return () {
      stopped = true;
      timer.cancel();
    };
  }

  int _streamRetriesRemaining(
    Exception error, {
    required bool hasRecommendation,
  }) {
    if (!hasRecommendation) return 0;
    if (error is StreamModeException) {
      if (!error.recoverable) return 0;
      return error.retriesRemaining > 0 ? error.retriesRemaining : 1;
    }
    if (error is AnalysisException) {
      if (error.code == 'STREAM_RUN_RETRY_UNAVAILABLE') return 0;
      if (error.suggestedAction == AnalysisErrorAction.retry ||
          error.suggestedAction == AnalysisErrorAction.wait) {
        return 1;
      }
    }
    return 0;
  }

  bool _shouldAutomaticallyRecoverStream(Exception error) {
    if (error is! AnalysisException) return false;
    if (error is StreamModeException && !error.recoverable) return false;
    return const <String>{
      'NETWORK_ERROR',
      'TIMEOUT',
      'STREAM_INCOMPLETE',
      'STREAM_RUN_RECOVERY_RETRY_READY',
    }.contains(error.code);
  }

  bool _shouldKeepRunRetryable(Exception error) {
    if (error is StreamModeException) return error.recoverable;
    if (error is! AnalysisException) return false;
    return const <String>{
      'NETWORK_ERROR',
      'TIMEOUT',
      'STREAM_INCOMPLETE',
    }.contains(error.code);
  }

  /// Resume the same streaming run with its cached
  /// [StreamingAnalysisState.analysisRunId] and request payload. It never
  /// changes transport or starts a non-stream path, and does not re-charge
  /// recommendation quota. No-op if there is no cached run.
  ///
  /// Caller passes no args so the retry survives screen remount; see
  /// invariant I-P1-b. The screen that triggered [start] may have been
  /// disposed by the time the user taps "重試"; the notifier itself owns the
  /// payload because it outlives the screen via [Ref.keepAlive].
  Future<void> retryStream() async {
    final runId = state.analysisRunId;
    final cachedMessages = _cachedMessages;
    if (runId == null || cachedMessages == null) return;
    final myGen = ++_generation;
    _keepAliveLink ??= ref.keepAlive();

    state = state.copyWith(
      phase: StreamingAnalyzePhase.streamingReport,
      streamErrorMessage: null,
      streamErrorCode: null,
      streamContents: const <AnalysisStreamContent>[],
      retriesRemaining: 0,
      conversationMessageCount: _cachedConversationMessageCount,
      previousAnalyzedCount: _cachedPreviousAnalyzedCount,
      analyzedMessageCount: _cachedAnalyzedMessageCount,
      conversationContentRevision: _cachedConversationContentRevision,
      conversationPartnerId: _cachedConversationPartnerId,
      isReconnectContext: _cachedIsReconnectContext,
      quotaExceeded: null,
    );

    await _runStream(
      generation: myGen,
      analysisRunId: runId,
      messages: cachedMessages,
      sessionContext: _cachedSessionContext,
      conversationSummary: _cachedConversationSummary,
      partnerSummary: _cachedPartnerSummary,
      effectiveStyleContext: _cachedEffectiveStyleContext,
      knownContactName: _cachedKnownContactName,
      previousStage: _cachedPreviousStage,
      analysisFragmentStartIndex: _cachedAnalysisFragmentStartIndex,
      previousAnalyzedCount: _cachedPreviousAnalyzedCount,
      previousAnalyzedCharCount: _cachedPreviousAnalyzedCharCount,
      confirmedOvercharge: _cachedConfirmedOvercharge,
      conversationMessageCount: _cachedConversationMessageCount,
      analyzedMessageCount: _cachedAnalyzedMessageCount,
      conversationContentRevision: _cachedConversationContentRevision,
      conversationPartnerId: _cachedConversationPartnerId,
      isReconnectContext: _cachedIsReconnectContext,
    );
  }
}
