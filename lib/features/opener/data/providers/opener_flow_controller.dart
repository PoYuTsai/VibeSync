// 開場救星兩段式的流程控制器（附件 §9.1／§9.2）：管理編輯→分析→補充→生成→
// 結果／可重試錯誤／到期，不在 screen 堆互相牽動的布林值。
//
// 三個識別碼各自獨立：analysisRequestId 隨對方資料＋初稿指紋鑄造（斷線重試沿用）、
// sessionId 由伺服器發、generationId 隨「本次完整回答」指紋鑄造（同回答重試沿用，
// 改回答或明確重抽才換新）。每個操作帶序號與帳號快照：舊結果晚回或切換帳號後
// 回來的結果一律丟棄，不寫畫面、不寫草稿（F17／帳號隔離）。

import 'dart:async';
import 'dart:convert';

import 'package:characters/characters.dart';
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

  /// R4b：補充超過 300 字時保留原文、顯示錯誤並阻止送出（不靜默截斷）。
  bool get freeTextTooLong => OpenerFlowState.isTooLong(draft.freeText);

  static bool isTooLong(String text) =>
      text.characters.length > OpenerFlowContract.freeTextMaxGraphemes;

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
  String? _lastInputFingerprint;

  // R2a：生成操作的送出快照（retry 沿用它，不是被改過的 draft）。
  OpenerPendingGeneration? _pendingGeneration;
  OpenerPendingGeneration? get pendingGeneration => _pendingGeneration;

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
    if (initialNote != null && OpenerFlowState.isTooLong(initialNote)) {
      _set(_state.copyWith(error: '這次想聊的內容最多 ${OpenerFlowContract.freeTextMaxGraphemes} 字，已保留你的文字，請縮短後再分析。'));
      return;
    }
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
    final fingerprint = jsonEncode([
      OpenerRequestIdSession.fingerprintFor(
        images: input.images,
        name: input.name,
        bio: input.bio,
        interests: input.interests,
        meetingContext: input.meetingContext,
      ),
      note,
    ]);
    _lastInputFingerprint = fingerprint;
    final attempt = _analysisSession.beginAttempt(fingerprint: fingerprint);
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
      _pendingGeneration = null;
      _analysisRequestIdForState = attempt.requestId;
      // R2a：分析完成就落地（stage=analyzed），離頁再回來能回到回答區。
      final draftId = await _persistFlow(
        existingDraftId: null,
        flow: OpenerDraftFlow(
          stage: OpenerDraftFlowStage.analyzed,
          analysis: analysis,
          contributionDraft: _state.draft,
          analysisRequestId: attempt.requestId,
          inputFingerprint: fingerprint,
        ),
      );
      if (!_isCurrent(op)) return;
      _set(_state.copyWith(
        phase: OpenerFlowPhase.contributing,
        analysis: analysis,
        clearGeneration: true,
        clearError: true,
        clearFailedOperation: true,
        clearDraftId: draftId == null,
        draftId: draftId,
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
    if (_state.freeTextTooLong) {
      _set(_state.copyWith(error: '補充最多 ${OpenerFlowContract.freeTextMaxGraphemes} 字，已保留你的文字，請縮短後再生成。'));
      return;
    }
    if (fresh) _generationSession.markSuccess();
    final contribution = _state.draft.toContribution(analysis.question);
    await _runGenerate(analysis, contribution);
  }

  Future<void> _runGenerate(
    OpenerAnalysis analysis,
    OpenerContribution contribution, {
    String? resumeGenerationId,
  }) async {
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
    final fingerprint = jsonEncode([analysis.sessionId, analysis.analysisRevision, contribution.toJson()]);
    if (resumeGenerationId != null) {
      _generationSession.adopt(requestId: resumeGenerationId, fingerprint: fingerprint);
    }
    final attempt = _generationSession.beginAttempt(fingerprint: fingerprint);
    // R2a：外部操作前先落地送出快照（ID＋回答＋階段）；伺服器結算後回應遺失，
    // 重開 App 仍能用原 generationId 取回同組結果，不會開新局再扣。
    final pending = OpenerPendingGeneration(generationId: attempt.requestId, contribution: contribution);
    _pendingGeneration = pending;
    final draftId = await _persistFlow(
      existingDraftId: _state.draftId,
      flow: OpenerDraftFlow(
        stage: OpenerDraftFlowStage.generating,
        analysis: analysis,
        contributionDraft: _state.draft,
        analysisRequestId: _lastAnalysisRequestId,
        inputFingerprint: _lastInputFingerprint,
        pendingGeneration: pending,
        generation: _state.generation,
      ),
    );
    if (!_isCurrent(op)) return;
    if (draftId != null && draftId != _state.draftId) _set(_state.copyWith(draftId: draftId));
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
      _pendingGeneration = null;
      final updatedAnalysis = analysis.copyWith(
        generationsUsed: generation.usage.generationsUsed,
        quotaCharged: analysis.quotaCharged || generation.usage.sessionChargedTotal > 0,
      );
      final savedId = await _persistFlow(
        existingDraftId: _state.draftId,
        result: generation.result,
        flow: OpenerDraftFlow(
          stage: OpenerDraftFlowStage.result,
          analysis: updatedAnalysis,
          contributionDraft: _state.draft,
          analysisRequestId: _lastAnalysisRequestId,
          inputFingerprint: _lastInputFingerprint,
          generation: generation,
        ),
      );
      if (!_isCurrent(op)) return;
      _set(_state.copyWith(
        phase: OpenerFlowPhase.result,
        analysis: updatedAnalysis,
        generation: generation,
        clearError: true,
        clearFailedOperation: true,
        draftId: savedId,
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
        // R2a：重試＝同一次操作，沿用送出時的快照（ID＋回答），不是目前被改過的
        // draft；「修改後新生成」是 generate(fresh:true) 這個明確動作。
        final pending = _pendingGeneration;
        if (pending == null) return;
        await _runGenerate(analysis, pending.contribution, resumeGenerationId: pending.generationId);
      case null:
        return;
    }
  }

  /// 恢復草稿後，若停在 generating（送出過、沒收到結果），用原 generationId 取回。
  Future<void> resumePendingGeneration() async {
    final analysis = _state.analysis;
    final pending = _pendingGeneration;
    if (analysis == null || pending == null || _state.isBusy) return;
    if (isExpired) {
      _set(_state.copyWith(phase: OpenerFlowPhase.expired, error: '這份分析已到期，重新分析後可再生成。'));
      return;
    }
    await _runGenerate(analysis, pending.contribution, resumeGenerationId: pending.generationId);
  }

  String? get _lastAnalysisRequestId => _state.analysis == null ? null : _analysisRequestIdForState;
  String? _analysisRequestIdForState;

  /// 同一份草稿隨階段更新（R2a）；保存失敗回 null、不擋畫面。
  Future<String?> _persistFlow({
    required String? existingDraftId,
    required OpenerDraftFlow flow,
    OpenerResult? result,
  }) async {
    try {
      if (existingDraftId != null) {
        final updated = await _cache.updateDraft(existingDraftId, result: result, flow: flow);
        if (updated != null) return updated.id;
      }
      final draft = await _cache.saveDraft(
        result: result,
        displayName: _lastDisplayName,
        sourceLabel: _lastSourceLabel,
        inputPreview: _lastInputPreview,
        partnerId: partnerId,
        flow: flow,
      );
      return draft.id;
    } catch (_) {
      return null;
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
    _analysisRequestIdForState = flow.analysisRequestId;
    _lastInputFingerprint = flow.inputFingerprint;
    _pendingGeneration = flow.stage == OpenerDraftFlowStage.generating ? flow.pendingGeneration : null;
    _lastDisplayName = draft.displayName;
    _lastSourceLabel = draft.sourceLabel;
    _lastInputPreview = draft.inputPreview;
    final expired = flow.analysis.isExpiredAt(_now());
    final phase = expired
        ? OpenerFlowPhase.expired
        : switch (flow.stage) {
            OpenerDraftFlowStage.analyzed => OpenerFlowPhase.contributing,
            // generating 由呼叫端接著 resumePendingGeneration()；先停在回答區。
            OpenerDraftFlowStage.generating => OpenerFlowPhase.contributing,
            OpenerDraftFlowStage.result => OpenerFlowPhase.result,
          };
    _set(OpenerFlowState(
      phase: phase,
      analysis: flow.analysis,
      generation: flow.generation,
      draft: flow.contributionDraft,
      draftId: draft.id,
      flowUnsupported: _state.flowUnsupported,
      failedOperation: _pendingGeneration != null ? OpenerFlowFailedOperation.generate : null,
    ));
  }

  /// 是否有送出過、尚未取得結果的生成（恢復後可直接取回）。
  bool get hasPendingGeneration => _pendingGeneration != null;

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
