// 開場救星兩段式的流程控制器（附件 §9.1／§9.2）：管理編輯→分析→補充→生成→
// 結果／可重試錯誤／到期，不在 screen 堆互相牽動的布林值。
//
// 三個識別碼各自獨立：analysisRequestId 隨對方資料＋初稿指紋鑄造（斷線重試沿用）、
// sessionId 由伺服器發、generationId 隨「本次完整回答」指紋鑄造（同回答重試沿用，
// 改回答或明確重抽才換新）。每個操作帶序號與帳號快照：舊結果晚回或切換帳號後
// 回來的結果一律丟棄，不寫畫面、不寫草稿（F17／帳號隔離）。

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../domain/opener_flow_models.dart';
import '../services/opener_request_session.dart';
import '../services/opener_result_cache_service.dart';
import '../services/opener_service.dart';

enum OpenerFlowPhase {
  /// 編輯對方資料（含「這次想聊的內容」初稿）。
  editing,
  analyzing,

  /// 看分析、選方向、補一句或略過；按「生成回覆」才進第二段。
  contributing,
  generating,
  result,

  /// 分析到期：可看已存結果，不能再生成；用戶明確重新分析才開新局。
  expired,
}

/// 額度與 RevenueCat 提示（伺服器仍是權威）。
class OpenerTierHint {
  const OpenerTierHint({this.expectedTier, this.revenueCatAppUserId});

  final String? expectedTier;
  final String? revenueCatAppUserId;
}

typedef OpenerTierHintResolver = Future<OpenerTierHint> Function();

/// 上一個失敗的操作：同 ID 重試用。
enum OpenerFlowFailedOperation { analyze, generate }

@immutable
class OpenerFlowState {
  const OpenerFlowState({
    this.phase = OpenerFlowPhase.editing,
    this.analysis,
    this.draft = const OpenerContributionDraft(),
    this.generation,
    this.error,
    this.flowError,
    this.quotaError,
    this.failedOperation,
    this.progress = const [],
    this.completedPhases = const {},
    this.flowUnsupported = false,
    this.draftId,
  });

  final OpenerFlowPhase phase;
  final OpenerAnalysis? analysis;
  final OpenerContributionDraft draft;
  final OpenerGeneration? generation;

  /// 使用者可見的錯誤文案；輸入內容不因錯誤消失。
  final String? error;
  final OpenerFlowException? flowError;

  /// 訂閱額度不足：由 screen 開 paywall（分析與回答都保留）。
  final OpenerQuotaExceededException? quotaError;
  final OpenerFlowFailedOperation? failedOperation;

  /// 串流進度（不含 heartbeat）。
  final List<String> progress;
  final Set<String> completedPhases;

  /// 伺服器不支援兩段式（舊 Edge／停用新局）：新局退回舊單段。
  final bool flowUnsupported;
  final String? draftId;

  bool get isBusy => phase == OpenerFlowPhase.analyzing || phase == OpenerFlowPhase.generating;

  bool get hasSession => analysis != null;

  /// 以 analysis 為準：每次生成成功都把伺服器回的 generationsUsed 寫回 analysis，
  /// 次數用完（409）也只更新 analysis，畫面才不會被舊結果的用量蓋掉。
  int get generationsRemaining => analysis?.generationsRemaining ?? 0;

  bool get canGenerateMore => generationsRemaining > 0 && phase != OpenerFlowPhase.expired;

  OpenerFlowState copyWith({
    OpenerFlowPhase? phase,
    OpenerAnalysis? analysis,
    bool clearAnalysis = false,
    OpenerContributionDraft? draft,
    OpenerGeneration? generation,
    bool clearGeneration = false,
    String? error,
    bool clearError = false,
    OpenerFlowException? flowError,
    OpenerQuotaExceededException? quotaError,
    OpenerFlowFailedOperation? failedOperation,
    bool clearFailedOperation = false,
    List<String>? progress,
    Set<String>? completedPhases,
    bool? flowUnsupported,
    String? draftId,
    bool clearDraftId = false,
  }) {
    return OpenerFlowState(
      phase: phase ?? this.phase,
      analysis: clearAnalysis ? null : (analysis ?? this.analysis),
      draft: draft ?? this.draft,
      generation: clearGeneration ? null : (generation ?? this.generation),
      error: clearError ? null : (error ?? this.error),
      flowError: clearError ? null : (flowError ?? this.flowError),
      quotaError: clearError ? null : (quotaError ?? this.quotaError),
      failedOperation: clearFailedOperation ? null : (failedOperation ?? this.failedOperation),
      progress: progress ?? this.progress,
      completedPhases: completedPhases ?? this.completedPhases,
      flowUnsupported: flowUnsupported ?? this.flowUnsupported,
      draftId: clearDraftId ? null : (draftId ?? this.draftId),
    );
  }
}

class OpenerFlowController extends ChangeNotifier {
  OpenerFlowController({
    required OpenerService service,
    required OpenerResultCacheService cache,
    required String? Function() ownerIdResolver,
    OpenerTierHintResolver? tierHintResolver,
    DateTime Function()? now,
    this.partnerId,
  })  : _service = service,
        _cache = cache,
        _ownerIdResolver = ownerIdResolver,
        _tierHintResolver = tierHintResolver ?? (() async => const OpenerTierHint()),
        _now = now ?? DateTime.now;

  final OpenerService _service;
  final OpenerResultCacheService _cache;
  final String? Function() _ownerIdResolver;
  final OpenerTierHintResolver _tierHintResolver;
  final DateTime Function() _now;
  final String? partnerId;

  final _analysisSession = OpenerRequestIdSession();
  final _generationSession = OpenerRequestIdSession();

  OpenerFlowState _state = const OpenerFlowState();
  OpenerFlowState get state => _state;

  int _opSeq = 0;
  bool _disposed = false;

  // 上一次分析的輸入（同 ID 重試用）。
  OpenerGenerationInput? _lastInput;
  String? _lastInitialNote;
  String? _lastSourceLabel;
  String? _lastInputPreview;
  String? _lastDisplayName;

  bool get isExpired {
    final analysis = _state.analysis;
    return analysis != null && analysis.isExpiredAt(_now());
  }

  void _set(OpenerFlowState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  /// 操作序號＋帳號快照：回來時任一不符＝結果作廢（不寫畫面、不寫草稿）。
  ({int seq, String? owner}) _beginOperation() {
    _opSeq += 1;
    return (seq: _opSeq, owner: _ownerIdResolver());
  }

  bool _isCurrent(({int seq, String? owner}) op) {
    if (_disposed || op.seq != _opSeq) return false;
    if (_ownerIdResolver() != op.owner) {
      _set(const OpenerFlowState(error: '帳號已切換，這次結果不套用；請重新分析。'));
      return false;
    }
    return true;
  }

  // ── 編輯 ────────────────────────────────────────────────────────────────

  /// 對方資料（截圖、自介、線索）改變：原分析失效，回到編輯（F15）。
  void resetForInputChange() {
    if (_state.phase == OpenerFlowPhase.editing && !_state.hasSession) return;
    _opSeq += 1; // 進行中的分析／生成回來一律作廢
    _set(OpenerFlowState(flowUnsupported: _state.flowUnsupported));
  }

  /// 用戶明確開始新的一局（到期／三組用完後）。
  void startNewSession() => resetForInputChange();

  // ── 第一段 ─────────────────────────────────────────────────────────────

  Future<void> analyze({
    required OpenerGenerationInput input,
    required String? initialNote,
    String? displayName,
    String? sourceLabel,
    String? inputPreview,
  }) async {
    if (_state.isBusy) return;
    _lastInput = input;
    _lastInitialNote = _blankToNull(initialNote);
    _lastDisplayName = displayName;
    _lastSourceLabel = sourceLabel;
    _lastInputPreview = inputPreview;
    await _runAnalyze();
  }

  Future<void> _runAnalyze() async {
    final input = _lastInput;
    if (input == null) return;
    final note = _lastInitialNote;
    final op = _beginOperation();
    _set(OpenerFlowState(
      phase: OpenerFlowPhase.analyzing,
      // 初稿就是同一份補充的起點：分析後帶進回答區，不要求重打。
      draft: OpenerContributionDraft(freeText: note ?? ''),
      flowUnsupported: _state.flowUnsupported,
    ));

    final hint = await _resolveHint();
    if (!_isCurrent(op)) return;
    final attempt = _analysisSession.beginAttempt(
      fingerprint: jsonEncode([
        OpenerRequestIdSession.fingerprintFor(
          images: input.images,
          name: input.name,
          bio: input.bio,
          interests: input.interests,
          meetingContext: input.meetingContext,
        ),
        note,
      ]),
    );
    try {
      final analysis = await _service.analyzeProfileStreaming(
        images: input.images,
        name: input.name,
        bio: input.bio,
        interests: input.interests,
        meetingContext: input.meetingContext,
        expectedTier: hint.expectedTier,
        revenueCatAppUserId: hint.revenueCatAppUserId,
        analysisRequestId: attempt.requestId,
        initialUserNote: note,
        onProgress: (label, phase) => _onProgress(op, label, phase),
      );
      if (!_isCurrent(op)) return;
      _analysisSession.markSuccess();
      _generationSession.markSuccess();
      _set(_state.copyWith(
        phase: OpenerFlowPhase.contributing,
        analysis: analysis,
        clearGeneration: true,
        clearError: true,
        clearFailedOperation: true,
        clearDraftId: true,
        progress: const [],
        completedPhases: const {},
      ));
    } on OpenerQuotaExceededException catch (e) {
      // 第一段不扣費，理論上不會發生；保守處理成可重試錯誤。
      if (!_isCurrent(op)) return;
      _set(_state.copyWith(phase: OpenerFlowPhase.editing, error: e.message, quotaError: e, failedOperation: OpenerFlowFailedOperation.analyze));
    } on OpenerFlowException catch (e) {
      if (!_isCurrent(op)) return;
      if (e.isUnsupported || e.isUnavailable) {
        _set(OpenerFlowState(
          phase: OpenerFlowPhase.editing,
          flowUnsupported: true,
          error: e.isUnavailable ? e.message : '這個版本先用一般生成（3 則）。',
          flowError: e,
        ));
        return;
      }
      _set(_state.copyWith(
        phase: OpenerFlowPhase.editing,
        error: e.message,
        flowError: e,
        failedOperation: e.retryable || e.isRateLimited ? OpenerFlowFailedOperation.analyze : null,
      ));
    } catch (e) {
      if (!_isCurrent(op)) return;
      _set(_state.copyWith(
        phase: OpenerFlowPhase.editing,
        error: _friendly(e),
        failedOperation: OpenerFlowFailedOperation.analyze,
      ));
    }
  }

  // ── 回答區 ─────────────────────────────────────────────────────────────

  void selectOption(String? optionId) {
    final current = _state.draft;
    final next = current.selectedOptionId == optionId
        ? current.copyWith(clearOption: true, skipped: false)
        : current.copyWith(selectedOptionId: optionId, skipped: false);
    _set(_state.copyWith(draft: next, clearError: true));
  }

  void setFreeText(String text) {
    if (text == _state.draft.freeText) return;
    var next = _state.draft.copyWith(freeText: text, skipped: false);
    // 明確矛盾：文字否定了已選線索 → 移除被否定的選擇（附件 §4.4）。
    final question = _state.analysis?.question;
    if (OpenerContributionConflict.optionNegatedByText(
      option: question?.optionById(next.selectedOptionId),
      cues: _state.analysis?.cues ?? const [],
      freeText: text,
    )) {
      next = next.copyWith(clearOption: true);
    }
    _set(_state.copyWith(draft: next, clearError: true));
  }

  /// 「略過，直接生成」：清空答案並標記略過，隨即進第二段。
  Future<void> skipAndGenerate() async {
    _set(_state.copyWith(draft: const OpenerContributionDraft(skipped: true), clearError: true));
    await generate();
  }

  /// 從結果回到回答區，保留上次的文字與選擇（附件 §4.6）。
  void adjustContribution() {
    if (_state.phase != OpenerFlowPhase.result && _state.phase != OpenerFlowPhase.expired) return;
    if (isExpired) {
      _set(_state.copyWith(phase: OpenerFlowPhase.expired, error: '這份分析已到期，重新分析後可再生成。'));
      return;
    }
    _set(_state.copyWith(phase: OpenerFlowPhase.contributing, clearError: true));
  }

  // ── 第二段 ─────────────────────────────────────────────────────────────

  /// 按「生成回覆」。[fresh] 為 true＝不改回答也要新的一次主動生成
  ///（新 generationId、占一組）；預設同回答只沿用同 ID（斷線重試取回同組）。
  Future<void> generate({bool fresh = false}) async {
    final analysis = _state.analysis;
    if (analysis == null || _state.isBusy) return;
    if (isExpired) {
      _set(_state.copyWith(phase: OpenerFlowPhase.expired, error: '這份分析已到期，重新分析後可再生成。'));
      return;
    }
    if (_state.generationsRemaining <= 0) {
      _set(_state.copyWith(error: '這局的三組回覆已用完；重新分析可開始新的一局（3 則）。'));
      return;
    }
    if (fresh) _generationSession.markSuccess();
    final contribution = _state.draft.toContribution(analysis.question);
    await _runGenerate(analysis, contribution);
  }

  Future<void> _runGenerate(OpenerAnalysis analysis, OpenerContribution contribution) async {
    final op = _beginOperation();
    _set(_state.copyWith(
      phase: OpenerFlowPhase.generating,
      clearError: true,
      clearFailedOperation: true,
      progress: const [],
      completedPhases: const {},
    ));
    final hint = await _resolveHint();
    if (!_isCurrent(op)) return;
    final attempt = _generationSession.beginAttempt(
      fingerprint: jsonEncode([analysis.sessionId, analysis.analysisRevision, contribution.toJson()]),
    );
    try {
      final generation = await _service.generateFromAnalysisStreaming(
        sessionId: analysis.sessionId,
        analysisRevision: analysis.analysisRevision,
        generationId: attempt.requestId,
        contribution: contribution,
        expectedTier: hint.expectedTier,
        revenueCatAppUserId: hint.revenueCatAppUserId,
        onProgress: (label, phase) => _onProgress(op, label, phase),
      );
      if (!_isCurrent(op)) return;
      _generationSession.markSuccess();
      final updatedAnalysis = analysis.copyWith(
        generationsUsed: generation.usage.generationsUsed,
        quotaCharged: analysis.quotaCharged || generation.usage.sessionChargedTotal > 0,
      );
      String? draftId;
      try {
        final draft = await _cache.saveDraft(
          result: generation.result,
          displayName: _lastDisplayName,
          sourceLabel: _lastSourceLabel,
          inputPreview: _lastInputPreview,
          partnerId: partnerId,
          flow: OpenerDraftFlow(
            analysis: updatedAnalysis,
            generation: generation,
            contributionDraft: _state.draft,
          ),
        );
        draftId = draft.id;
      } catch (_) {
        // 本機保存失敗不擋結果顯示。
      }
      if (!_isCurrent(op)) return;
      _set(_state.copyWith(
        phase: OpenerFlowPhase.result,
        analysis: updatedAnalysis,
        generation: generation,
        clearError: true,
        clearFailedOperation: true,
        draftId: draftId,
        progress: const [],
        completedPhases: const {},
      ));
    } on OpenerQuotaExceededException catch (e) {
      if (!_isCurrent(op)) return;
      _set(_state.copyWith(
        phase: OpenerFlowPhase.contributing,
        error: e.message,
        quotaError: e,
        failedOperation: OpenerFlowFailedOperation.generate,
      ));
    } on OpenerFlowException catch (e) {
      if (!_isCurrent(op)) return;
      if (e.isExpired) {
        _set(_state.copyWith(phase: OpenerFlowPhase.expired, error: e.message, flowError: e));
        return;
      }
      if (e.isSessionInvalid) {
        _set(_state.copyWith(phase: OpenerFlowPhase.editing, clearAnalysis: true, clearGeneration: true, error: e.message, flowError: e));
        return;
      }
      if (e.isLimitReached) {
        final capped = analysis.copyWith(generationsUsed: analysis.includedGenerationCount);
        _set(_state.copyWith(
          phase: _state.generation == null ? OpenerFlowPhase.contributing : OpenerFlowPhase.result,
          analysis: capped,
          error: e.message,
          flowError: e,
        ));
        return;
      }
      _set(_state.copyWith(
        phase: _state.generation == null ? OpenerFlowPhase.contributing : OpenerFlowPhase.result,
        error: e.message,
        flowError: e,
        failedOperation: OpenerFlowFailedOperation.generate,
      ));
    } catch (e) {
      if (!_isCurrent(op)) return;
      _set(_state.copyWith(
        phase: _state.generation == null ? OpenerFlowPhase.contributing : OpenerFlowPhase.result,
        error: _friendly(e),
        failedOperation: OpenerFlowFailedOperation.generate,
      ));
    }
  }

  /// 同一次操作重試（同 analysisRequestId／generationId）：斷線後取回同一結果。
  Future<void> retryLastOperation() async {
    switch (_state.failedOperation) {
      case OpenerFlowFailedOperation.analyze:
        await _runAnalyze();
      case OpenerFlowFailedOperation.generate:
        final analysis = _state.analysis;
        if (analysis == null) return;
        // 重試沿用送出時的回答：draft 若已被改過，指紋不同會自然鑄新 ID，
        // 那就是一次新的主動生成，不是重試——這裡用目前 draft 讓語意一致。
        await _runGenerate(analysis, _state.draft.toContribution(analysis.question));
      case null:
        return;
    }
  }

  // ── 草稿 ───────────────────────────────────────────────────────────────

  /// 回看兩段式草稿：回復帳號所屬的分析、回答與結果；到期只能看不能續生成。
  void restoreDraft(OpenerDraft draft) {
    final flow = draft.flow;
    if (flow == null) return;
    _opSeq += 1;
    _analysisSession.markSuccess();
    _generationSession.markSuccess();
    final expired = flow.analysis.isExpiredAt(_now());
    _set(OpenerFlowState(
      phase: expired ? OpenerFlowPhase.expired : OpenerFlowPhase.result,
      analysis: flow.analysis,
      generation: flow.generation,
      draft: flow.contributionDraft,
      draftId: draft.id,
      flowUnsupported: _state.flowUnsupported,
    ));
  }

  void _onProgress(({int seq, String? owner}) op, String label, String? phase) {
    if (_disposed || op.seq != _opSeq) return;
    if (phase == 'heartbeat') return;
    _set(_state.copyWith(
      progress: [..._state.progress, label],
      completedPhases: phase == null ? null : {..._state.completedPhases, phase},
    ));
  }

  Future<OpenerTierHint> _resolveHint() async {
    try {
      return await _tierHintResolver();
    } catch (_) {
      return const OpenerTierHint();
    }
  }

  static String _friendly(Object error) {
    const fallback = '開場暫時失敗，請稍後再試。';
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    final hasChinese = RegExp(r'[一-鿿]').hasMatch(message);
    return hasChinese && message.isNotEmpty ? message : fallback;
  }

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
