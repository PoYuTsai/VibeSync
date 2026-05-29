import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../conversation/domain/entities/message.dart';
import '../../../conversation/domain/entities/session_context.dart';
import '../../domain/entities/analysis_models.dart';
import '../../domain/entities/quick_analysis_result.dart';
import '../providers/analysis_providers.dart';
import '../services/analysis_service.dart';

/// Phases of the two-stage analyze flow.
///
/// Transitions (happy path):
///   idle → runningQuick → quickReady → runningFull → fullReady
/// Failure branches:
///   runningQuick → quickFailed                  (no full attempted, no charge)
///   runningFull  → fullFailed                   (quick preserved, retry CTA)
enum TwoStagePhase {
  idle,
  runningQuick,
  quickReady,
  quickFailed,
  runningFull,
  fullReady,
  fullFailed,
}

/// Immutable orchestrator state. Carries quick + full results plus the cached
/// [analysisRunId] used by [TwoStageAnalyzeNotifier.retryFull] so the server
/// can match the run without re-charging quota (invariant I1).
class TwoStageAnalysisState {
  final TwoStagePhase phase;
  final QuickAnalysisResult? quick;
  final AnalysisResult? full;
  final String? analysisRunId;
  final String? quickErrorMessage;
  final String? quickErrorCode;
  final String? fullErrorMessage;
  final String? fullErrorCode;
  final int retriesRemaining;
  final int? conversationMessageCount;

  const TwoStageAnalysisState({
    required this.phase,
    this.quick,
    this.full,
    this.analysisRunId,
    this.quickErrorMessage,
    this.quickErrorCode,
    this.fullErrorMessage,
    this.fullErrorCode,
    this.retriesRemaining = 0,
    this.conversationMessageCount,
  });

  const TwoStageAnalysisState.idle() : this(phase: TwoStagePhase.idle);

  /// Sentinel used by [copyWith] to distinguish "not provided" from "set to
  /// null". Without this, `param ?? this.param` silently ignores explicit nulls,
  /// which prevents clearing nullable error/result fields after a retry. See
  /// invariant I-P2-a in the Phase 3 Codex review.
  static const Object _unset = Object();

  TwoStageAnalysisState copyWith({
    TwoStagePhase? phase,
    Object? quick = _unset,
    Object? full = _unset,
    Object? analysisRunId = _unset,
    Object? quickErrorMessage = _unset,
    Object? quickErrorCode = _unset,
    Object? fullErrorMessage = _unset,
    Object? fullErrorCode = _unset,
    int? retriesRemaining,
    Object? conversationMessageCount = _unset,
  }) {
    return TwoStageAnalysisState(
      phase: phase ?? this.phase,
      quick:
          identical(quick, _unset) ? this.quick : quick as QuickAnalysisResult?,
      full: identical(full, _unset) ? this.full : full as AnalysisResult?,
      analysisRunId: identical(analysisRunId, _unset)
          ? this.analysisRunId
          : analysisRunId as String?,
      quickErrorMessage: identical(quickErrorMessage, _unset)
          ? this.quickErrorMessage
          : quickErrorMessage as String?,
      quickErrorCode: identical(quickErrorCode, _unset)
          ? this.quickErrorCode
          : quickErrorCode as String?,
      fullErrorMessage: identical(fullErrorMessage, _unset)
          ? this.fullErrorMessage
          : fullErrorMessage as String?,
      fullErrorCode: identical(fullErrorCode, _unset)
          ? this.fullErrorCode
          : fullErrorCode as String?,
      retriesRemaining: retriesRemaining ?? this.retriesRemaining,
      conversationMessageCount: identical(conversationMessageCount, _unset)
          ? this.conversationMessageCount
          : conversationMessageCount as int?,
    );
  }
}

final twoStageAnalyzeProvider = NotifierProvider.autoDispose
    .family<TwoStageAnalyzeNotifier, TwoStageAnalysisState, String>(
  TwoStageAnalyzeNotifier.new,
);

/// Two-stage analyze orchestrator. Owns the quick → full state machine for a
/// single conversation. State survives navigation while in flight via
/// [Ref.keepAlive]; once the user starts an analysis the provider stays alive
/// for the rest of the app session (in-memory only; Phase 4 will persist).
class TwoStageAnalyzeNotifier
    extends AutoDisposeFamilyNotifier<TwoStageAnalysisState, String> {
  int _generation = 0;
  KeepAliveLink? _keepAliveLink;

  // Retry payload cached from the most recent [start] call. The notifier
  // outlives the screen via [Ref.keepAlive], so these fields survive screen
  // remount — [retryFull] then does not depend on screen-instance local state
  // (invariant I-P1-b). A second [start] overwrites them (I-P1-c).
  List<Message>? _cachedMessages;
  SessionContext? _cachedSessionContext;
  String? _cachedConversationSummary;
  String? _cachedPartnerSummary;
  String? _cachedEffectiveStyleContext;
  String? _cachedKnownContactName;
  int? _cachedPreviousAnalyzedCount;
  int? _cachedConversationMessageCount;

  @override
  TwoStageAnalysisState build(String conversationId) {
    return const TwoStageAnalysisState.idle();
  }

  AnalysisService get _service => ref.read(analysisServiceProvider);

  /// Run the full quick → full pipeline. Multiple concurrent calls supersede
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
    int? previousAnalyzedCount,
    int? conversationMessageCount,
  }) async {
    final myGen = ++_generation;
    _keepAliveLink ??= ref.keepAlive();

    // Cache the payload so retryFull can replay analyzeFull with the same
    // conversation hash even after the calling screen is disposed/remounted.
    _cachedMessages = List<Message>.unmodifiable(messages);
    _cachedSessionContext = sessionContext;
    _cachedConversationSummary = conversationSummary;
    _cachedPartnerSummary = partnerSummary;
    _cachedEffectiveStyleContext = effectiveStyleContext;
    _cachedKnownContactName = knownContactName;
    _cachedPreviousAnalyzedCount = previousAnalyzedCount;
    _cachedConversationMessageCount = conversationMessageCount;

    state = TwoStageAnalysisState(
      phase: TwoStagePhase.runningQuick,
      conversationMessageCount: conversationMessageCount,
    );

    final QuickAnalysisResult quick;
    try {
      quick = await _service.analyzeQuick(
        messages: messages,
        sessionContext: sessionContext,
        conversationSummary: conversationSummary,
        partnerSummary: partnerSummary,
        effectiveStyleContext: effectiveStyleContext,
        knownContactName: knownContactName,
        previousAnalyzedCount: previousAnalyzedCount,
      );
    } on Exception catch (e) {
      if (myGen != _generation) return;
      final message = e is AnalysisException ? e.message : '快速分析失敗，請稍後再試。';
      final code = e is AnalysisException ? e.code : null;
      state = TwoStageAnalysisState(
        phase: TwoStagePhase.quickFailed,
        quickErrorMessage: message,
        quickErrorCode: code,
        conversationMessageCount: conversationMessageCount,
      );
      return;
    }

    if (myGen != _generation) return;

    state = TwoStageAnalysisState(
      phase: TwoStagePhase.quickReady,
      quick: quick,
      analysisRunId: quick.analysisRunId,
      conversationMessageCount: conversationMessageCount,
    );

    await _runFull(
      generation: myGen,
      analysisRunId: quick.analysisRunId,
      messages: messages,
      sessionContext: sessionContext,
      conversationSummary: conversationSummary,
      partnerSummary: partnerSummary,
      effectiveStyleContext: effectiveStyleContext,
      knownContactName: knownContactName,
      previousAnalyzedCount: previousAnalyzedCount,
      conversationMessageCount: conversationMessageCount,
    );
  }

  /// Retry the full call with the cached [TwoStageAnalysisState.analysisRunId]
  /// and the payload captured by the most recent [start]. Does NOT call
  /// analyzeQuick and does NOT re-charge quick quota. No-op if there is no
  /// cached run (caller should invoke [start] instead).
  ///
  /// Caller passes no args so the retry survives screen remount — see
  /// invariant I-P1-b. The screen that triggered [start] may have been
  /// disposed by the time the user taps "重試"; the notifier itself owns the
  /// payload because it outlives the screen via [Ref.keepAlive].
  Future<void> retryFull() async {
    final runId = state.analysisRunId;
    final cachedMessages = _cachedMessages;
    if (runId == null || cachedMessages == null) return;
    final myGen = ++_generation;
    _keepAliveLink ??= ref.keepAlive();

    state = state.copyWith(
      phase: TwoStagePhase.runningFull,
      fullErrorMessage: null,
      fullErrorCode: null,
      retriesRemaining: 0,
      conversationMessageCount: _cachedConversationMessageCount,
    );

    await _runFull(
      generation: myGen,
      analysisRunId: runId,
      messages: cachedMessages,
      sessionContext: _cachedSessionContext,
      conversationSummary: _cachedConversationSummary,
      partnerSummary: _cachedPartnerSummary,
      effectiveStyleContext: _cachedEffectiveStyleContext,
      knownContactName: _cachedKnownContactName,
      previousAnalyzedCount: _cachedPreviousAnalyzedCount,
      conversationMessageCount: _cachedConversationMessageCount,
    );
  }

  Future<void> _runFull({
    required int generation,
    required String analysisRunId,
    required List<Message> messages,
    SessionContext? sessionContext,
    String? conversationSummary,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? knownContactName,
    int? previousAnalyzedCount,
    int? conversationMessageCount,
  }) async {
    if (generation != _generation) return;
    // Clear any stale error fields on every full attempt so invariants
    // I-P2-b/c hold even if a future call site forgets to clear (e.g. retryFull
    // already clears, but defense-in-depth makes the runningFull invariant
    // unconditional).
    state = state.copyWith(
      phase: TwoStagePhase.runningFull,
      fullErrorMessage: null,
      fullErrorCode: null,
      retriesRemaining: 0,
      conversationMessageCount: conversationMessageCount,
    );

    try {
      final full = await _service.analyzeFull(
        analysisRunId: analysisRunId,
        messages: messages,
        sessionContext: sessionContext,
        conversationSummary: conversationSummary,
        partnerSummary: partnerSummary,
        effectiveStyleContext: effectiveStyleContext,
        knownContactName: knownContactName,
        previousAnalyzedCount: previousAnalyzedCount,
      );
      if (generation != _generation) return;
      state = state.copyWith(
        phase: TwoStagePhase.fullReady,
        full: full,
        fullErrorMessage: null,
        fullErrorCode: null,
        retriesRemaining: 0,
        conversationMessageCount: conversationMessageCount,
      );
    } on FullModeException catch (e) {
      if (generation != _generation) return;
      state = state.copyWith(
        phase: TwoStagePhase.fullFailed,
        fullErrorMessage: e.message,
        fullErrorCode: e.code,
        retriesRemaining: e.retriesRemaining,
        conversationMessageCount: conversationMessageCount,
      );
    } on Exception catch (e) {
      if (generation != _generation) return;
      state = state.copyWith(
        phase: TwoStagePhase.fullFailed,
        fullErrorMessage: e is AnalysisException ? e.message : '完整分析失敗，可以重試。',
        fullErrorCode: e is AnalysisException ? e.code : null,
        retriesRemaining: 0,
        conversationMessageCount: conversationMessageCount,
      );
    }
  }
}
