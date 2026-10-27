import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/message_calculator.dart';
import '../../../conversation/domain/entities/message.dart';
import '../../../conversation/domain/entities/session_context.dart';

import '../providers/analysis_providers.dart';
import '../services/analysis_service.dart';
import '../services/analyze_stream_client.dart';
import '../../domain/entities/analysis_models.dart';
import '../../domain/entities/analysis_recommendation_preview.dart';
import '../../domain/entities/guide_v3_result.dart';
import '../../domain/entities/previous_round_context.dart';

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
  final SessionContext? analyzedSessionContext;

  /// 非 null 表示這次失敗是額度不足（429），UI 必須走升級卡分流。
  final QuotaExceededInfo? quotaExceeded;

  /// v3（任務卡）：這個 run 是新流程（started 帶 guideVersion）。續看的 started
  /// 不帶，所以只會從 false 變 true，不會被續看清掉。
  final bool isGuideV3Run;

  /// v3 局面判讀；扣費成功後才送，跟第一張卡一起到。
  final GuideV3Read? guideV3Read;

  /// v3 已送到的任務卡（照 slot），到了就能複製；done 時換成最終結果的卡。
  final List<GuideV3Card> guideV3Cards;

  /// v3 最終結果；v2 的最終結果在 [result]。兩者不會同時非 null。
  final GuideV3Result? guideV3Result;

  /// v3 已送到的「為什麼這樣回」（slot → 說明；兩段式實驗才有）。done 的結果不帶，done 時
  /// 併進 [guideV3Result]，跟卡一起存檔。
  final Map<int, String> guideV3CardExplains;

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
    this.analyzedSessionContext,
    this.quotaExceeded,
    this.isGuideV3Run = false,
    this.guideV3Read,
    this.guideV3Cards = const [],
    this.guideV3Result,
    this.guideV3CardExplains = const {},
  });

  const StreamingAnalysisState.idle() : this(phase: StreamingAnalyzePhase.idle);

  /// 用戶已經看到 v3 的判讀或卡（失敗時要留著、續看不能清掉）。
  bool get hasShownGuideV3 => guideV3Read != null || guideV3Cards.isNotEmpty;

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
    Object? analyzedSessionContext = _unset,
    Object? quotaExceeded = _unset,
    bool? isGuideV3Run,
    Object? guideV3Read = _unset,
    List<GuideV3Card>? guideV3Cards,
    Object? guideV3Result = _unset,
    Map<int, String>? guideV3CardExplains,
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
      analyzedSessionContext: identical(analyzedSessionContext, _unset)
          ? this.analyzedSessionContext
          : analyzedSessionContext as SessionContext?,
      quotaExceeded: identical(quotaExceeded, _unset)
          ? this.quotaExceeded
          : quotaExceeded as QuotaExceededInfo?,
      isGuideV3Run: isGuideV3Run ?? this.isGuideV3Run,
      guideV3Read: identical(guideV3Read, _unset)
          ? this.guideV3Read
          : guideV3Read as GuideV3Read?,
      guideV3Cards: guideV3Cards ?? this.guideV3Cards,
      guideV3Result: identical(guideV3Result, _unset)
          ? this.guideV3Result
          : guideV3Result as GuideV3Result?,
      guideV3CardExplains: guideV3CardExplains ?? this.guideV3CardExplains,
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

/// v3（任務卡）的等待句（Eric 2026-10-18）：v3 沒有關係階段、投入分數，只講讀對話
/// 與決定這輪怎麼回；伺服器讀完會送「看完了，正在寫回覆」接手。
const List<(String, String)> _guideV3PreludeProgress = <(String, String)>[
  (
    '正在讀這段對話',
    '看你們聊到哪、她最後怎麼接。',
  ),
  (
    '正在看她現在冷還熱',
    '再決定這輪該回、先等，還是收尾。',
  ),
  (
    '還在看',
    '對話比較長時會久一點。',
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
  PreviousRoundContext? _cachedPreviousRound;
  int? _cachedPayloadCharCount;

  /// 這個 run（generation）已經收回過跟進提醒：判讀與 done 都會檢查，只叫一次。
  int? _followUpSilencedGeneration;

  // 續接同一個 run 時保留用戶已看到的卡片（F12）。伺服器續接分兩種：run 還在
  // 跑或已完成，只會重播最終的 done，不會再送卡片；run 已失敗則重跑一次，
  // 會送出整組新卡片。所以舊卡留到新卡片的第一個內容事件才整批換掉，
  // 避免同一組卡出現兩次。
  bool _replaceKeptStreamContents = false;

  /// ADR #19 規格 #8：最近一次 [start] 實際送出 payload 的計費字數（F04：
  /// 不含最後面他傳的、上限內的那幾則）。分析成功後由 screen 持久化為
  /// conversation.lastAnalyzedCharCount（baseline 必須對應送出的
  /// requestMessages，不是完成時 repository 裡的最新 messages）。只分析最後
  /// 2000 字（Onboarding 第 15 步）送的是尾段，這裡是呼叫端給的整段計費字數。
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
    int? nextCharBaseline,
    OverchargeConfirmationPayload? confirmedOvercharge,
    int? conversationMessageCount,
    int? analyzedMessageCount,
    String? conversationContentRevision,
    String? conversationPartnerId,
    bool? isReconnectContext,
    PreviousRoundContext? previousRound,
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
    _cachedPreviousRound = previousRound;
    // ADR #19 規格 #8：baseline 對應這次送出的 requestMessages 的計費字數；
    // F04：最後面他傳的（上限內）不算費，也不進 baseline（照伺服器）。
    // 只分析最後 2000 字（Onboarding 第 15 步）送的是尾段：基準照呼叫端給的整段
    // 計費字數，跳過的那段下次不再算錢，尾段也不會再算一次。
    _cachedPayloadCharCount = nextCharBaseline ??
        MessageCalculator.countPayloadChars(
          MessageCalculator.billingMessagesForAnalysis(messages),
        );
    _replaceKeptStreamContents = false;

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
      analyzedSessionContext: sessionContext,
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
      previousRound: previousRound,
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
    PreviousRoundContext? previousRound,
    int automaticRecoveryAttempt = 0,
  }) async {
    final localProgress = _startLocalStreamPreludeProgress(
      generation: generation,
      conversationMessageCount: conversationMessageCount,
      analyzedMessageCount: analyzedMessageCount,
    );
    final stopLocalProgress = localProgress.stop;
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
        previousRound: previousRound,
      ))) {
        // v3 新分析的 started 沒有字：本地輪播接著跑、換成 v3 的句子，等伺服器
        // 送進度、判讀或卡才停（Eric 2026-10-18：不要停在「開始完整分析」）。
        final guideV3Started =
            update.kind == AnalysisStreamUpdateKind.started &&
                update.guideVersion != null;
        if (!guideV3Started) stopLocalProgress();
        if (generation != _generation) return;

        switch (update.kind) {
          case AnalysisStreamUpdateKind.started:
          case AnalysisStreamUpdateKind.progress:
            state = state.copyWith(
              phase:
                  state.recommendationPreview == null && !state.hasShownGuideV3
                      ? StreamingAnalyzePhase.connecting
                      : StreamingAnalyzePhase.streamingReport,
              analysisRunId: update.runId ?? state.analysisRunId,
              streamProgressLabel:
                  guideV3Started ? state.streamProgressLabel : update.label,
              streamProgressDetail:
                  guideV3Started ? state.streamProgressDetail : update.detail,
              conversationMessageCount: conversationMessageCount,
              analyzedMessageCount: analyzedMessageCount,
              isGuideV3Run: state.isGuideV3Run || update.guideVersion != null,
            );
            if (guideV3Started) localProgress.publishNow();
            break;
          case AnalysisStreamUpdateKind.guideV3Read:
            final read = update.guideV3Read;
            if (read == null) break;
            _silenceFollowUpIfNeeded(
              read.decision,
              partnerId: conversationPartnerId,
              generation: generation,
            );
            state = state.copyWith(
              phase: StreamingAnalyzePhase.streamingReport,
              analysisRunId: update.runId ?? state.analysisRunId,
              streamErrorMessage: null,
              streamErrorCode: null,
              streamProgressLabel: update.label,
              streamProgressDetail: null,
              retriesRemaining: 0,
              conversationMessageCount: conversationMessageCount,
              analyzedMessageCount: analyzedMessageCount,
              quotaExceeded: null,
              isGuideV3Run: true,
              guideV3Read: read,
            );
            break;
          case AnalysisStreamUpdateKind.guideV3Card:
            final card = update.guideV3Card;
            if (card == null) break;
            // 同一個 slot 只留第一次送到的（伺服器不會重送；保險）。
            final cards = state.guideV3Cards.any((c) => c.slot == card.slot)
                ? state.guideV3Cards
                : ([...state.guideV3Cards, card]
                  ..sort((a, b) => a.slot.compareTo(b.slot)));
            state = state.copyWith(
              phase: StreamingAnalyzePhase.streamingReport,
              analysisRunId: update.runId ?? state.analysisRunId,
              streamErrorMessage: null,
              streamErrorCode: null,
              streamProgressLabel: update.label,
              streamProgressDetail: null,
              retriesRemaining: 0,
              conversationMessageCount: conversationMessageCount,
              analyzedMessageCount: analyzedMessageCount,
              quotaExceeded: null,
              isGuideV3Run: true,
              guideV3Cards: List<GuideV3Card>.unmodifiable(cards),
            );
            break;
          case AnalysisStreamUpdateKind.guideV3CardExplain:
            final explain = update.guideV3CardExplain;
            // 同一張只留第一次送到的（伺服器不會重送；保險）。
            if (explain == null ||
                state.guideV3CardExplains.containsKey(explain.card)) {
              break;
            }
            state = state.copyWith(
              guideV3CardExplains: Map<int, String>.unmodifiable({
                ...state.guideV3CardExplains,
                explain.card: explain.text,
              }),
            );
            break;
          case AnalysisStreamUpdateKind.content:
            final content = update.content;
            if (content == null) break;
            final previousContents = _replaceKeptStreamContents
                ? const <AnalysisStreamContent>[]
                : state.streamContents;
            _replaceKeptStreamContents = false;
            state = state.copyWith(
              phase: StreamingAnalyzePhase.streamingReport,
              analysisRunId: update.runId ?? state.analysisRunId,
              streamErrorMessage: null,
              streamErrorCode: null,
              streamProgressLabel: update.label ?? content.title,
              streamProgressDetail: update.detail ?? content.body,
              streamContents: List<AnalysisStreamContent>.unmodifiable(
                <AnalysisStreamContent>[
                  ...previousContents,
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
            final guideV3Result = update.guideV3Result;
            if (guideV3Result != null) {
              // 判讀中途讀不懂時，決定只在最終結果裡。
              _silenceFollowUpIfNeeded(
                guideV3Result.decision,
                partnerId: conversationPartnerId,
                generation: generation,
              );
              // 續看重組只帶回第一張卡：這個 run 畫面上已經送到的卡補回來，
              // 不讓用戶看過的卡消失（存檔也存合併後的）。「為什麼這樣回」done 不帶，
              // 收到的一起併進去存。
              final merged = (guideV3Result.recovered
                      ? guideV3Result.withShownCards(state.guideV3Cards)
                      : guideV3Result)
                  .withCardExplains(state.guideV3CardExplains);
              state = state.copyWith(
                phase: StreamingAnalyzePhase.done,
                result: null,
                analysisRunId: update.runId ?? state.analysisRunId,
                streamErrorMessage: null,
                streamErrorCode: null,
                streamProgressLabel: null,
                streamProgressDetail: null,
                retriesRemaining: 0,
                conversationMessageCount: conversationMessageCount,
                analyzedMessageCount: analyzedMessageCount,
                quotaExceeded: null,
                isGuideV3Run: true,
                guideV3Read: merged.read,
                guideV3Cards: merged.cards,
                guideV3Result: merged,
              );
              return;
            }
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
        final hasShownContents = state.streamContents.isNotEmpty;
        final hasPartialResult = state.recommendationPreview != null ||
            hasShownContents ||
            state.hasShownGuideV3;
        // v3 的 run 續看只重播最終結果、不重生，已送到的卡一直留著。
        _replaceKeptStreamContents = hasShownContents;
        state = state.copyWith(
          phase: hasPartialResult
              ? StreamingAnalyzePhase.streamingReport
              : StreamingAnalyzePhase.connecting,
          analysisRunId: resumeRunId,
          streamErrorMessage: null,
          streamErrorCode: null,
          streamProgressLabel: '連線中斷，正在取回分析結果',
          streamProgressDetail: '會接續原本的分析，不會重新扣除額度。',
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
          previousRound: previousRound,
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
      final hasShownGuideV3 = state.hasShownGuideV3;
      final hasRecoverableRun = state.analysisRunId != null &&
          quotaExceeded == null &&
          _shouldKeepRunRetryable(e);
      final retriesRemaining = quotaExceeded != null
          ? 0
          : _streamRetriesRemaining(
              e,
              hasRecommendation: recommendationPreview != null ||
                  hasStreamContent ||
                  hasShownGuideV3 ||
                  hasRecoverableRun,
            );

      if (recommendationPreview != null ||
          hasStreamContent ||
          hasShownGuideV3 ||
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
        analyzedSessionContext: sessionContext,
        quotaExceeded: quotaExceeded,
      );
    } finally {
      stopLocalProgress();
    }
  }

  /// v3 判成關心（自傷、未成年）或停（她拒絕或封鎖）就收回這位對象的 48 小時跟進提醒（P1 安全
  /// 修正；主審第 1 輪 finding 1）。在 notifier 這裡做，不靠分析頁的存檔回呼：離開分析頁之後
  /// 才到的結果也收得回。一個 run 只叫一次；best-effort，失敗不影響分析。
  void _silenceFollowUpIfNeeded(
    GuideV3Decision decision, {
    required String? partnerId,
    required int generation,
  }) {
    if (!decision.silencesFollowUp) return;
    final id = partnerId?.trim();
    if (id == null || id.isEmpty) return;
    if (_followUpSilencedGeneration == generation) return;
    _followUpSilencedGeneration = generation;
    try {
      unawaited(
        ref.read(analysisFollowUpSilencerProvider)(id).catchError(
              (Object error) =>
                  debugPrint('FollowUp silence after v3 read failed: $error'),
            ),
      );
    } catch (error) {
      debugPrint('FollowUp silence after v3 read failed: $error');
    }
  }

  /// 伺服器還沒送字時的本地輪播。[publishNow]：馬上換下一句並重新計時（v3 的
  /// started 一到就換成 v3 的句子，從第一句開始）。
  ({void Function() stop, void Function() publishNow})
      _startLocalStreamPreludeProgress({
    required int generation,
    int? conversationMessageCount,
    int? analyzedMessageCount,
  }) {
    var stopped = false;
    var tick = 0;
    var guideV3 = false;
    Timer? timer;

    void publish() {
      if (stopped || generation != _generation) return;
      final current = state;
      if (current.phase != StreamingAnalyzePhase.connecting ||
          current.recommendationPreview != null) {
        return;
      }

      if (current.isGuideV3Run && !guideV3) {
        guideV3 = true;
        tick = 0;
      }
      final steps = guideV3 ? _guideV3PreludeProgress : _streamPreludeProgress;
      final step = steps[tick % steps.length];
      tick += 1;
      state = current.copyWith(
        streamProgressLabel: step.$1,
        streamProgressDetail: step.$2,
        conversationMessageCount: conversationMessageCount,
        analyzedMessageCount: analyzedMessageCount,
      );
    }

    void schedule() {
      timer?.cancel();
      timer = Timer.periodic(
        _streamPreludeProgressInterval,
        (_) => publish(),
      );
    }

    scheduleMicrotask(publish);
    schedule();

    return (
      stop: () {
        stopped = true;
        timer?.cancel();
      },
      publishNow: () {
        if (stopped) return;
        publish();
        schedule();
      },
    );
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
  /// Cards the user already saw stay on screen until the retried run sends
  /// its first content event, which replaces them (see
  /// [_replaceKeptStreamContents]).
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
    _replaceKeptStreamContents = state.streamContents.isNotEmpty;

    state = state.copyWith(
      phase: StreamingAnalyzePhase.streamingReport,
      streamErrorMessage: null,
      streamErrorCode: null,
      retriesRemaining: 0,
      conversationMessageCount: _cachedConversationMessageCount,
      previousAnalyzedCount: _cachedPreviousAnalyzedCount,
      analyzedMessageCount: _cachedAnalyzedMessageCount,
      conversationContentRevision: _cachedConversationContentRevision,
      conversationPartnerId: _cachedConversationPartnerId,
      isReconnectContext: _cachedIsReconnectContext,
      analyzedSessionContext: _cachedSessionContext,
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
      previousRound: _cachedPreviousRound,
    );
  }
}
