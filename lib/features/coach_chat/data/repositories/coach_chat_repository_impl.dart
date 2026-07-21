import 'package:hive_ce/hive_ce.dart';

import '../../../coach_follow_up/domain/entities/coach_follow_up_result.dart';
import '../../domain/entities/coach_chat_result.dart';
import '../../domain/entities/unified_coach_result.dart';
import '../../domain/repositories/coach_chat_repository.dart';

/// Phase D unified coach repository.
///
/// New writes land only in the unified box (typeId 26). The legacy boxes —
/// typeId 17 `CoachChatResult` and typeId 16 `CoachFollowUpResult` — are
/// read-only bridge sources (design D-5): merged at read time, never written,
/// never migrated, never deleted here.
class CoachChatRepositoryImpl implements CoachChatRepository {
  CoachChatRepositoryImpl(
    this._unifiedBox,
    this._legacyChatBox,
    this._legacyFollowUpBox, {
    this.keepPerScope = 10,
  });

  final Box<UnifiedCoachResult> _unifiedBox;
  final Box<CoachChatResult> _legacyChatBox;
  final Box<CoachFollowUpResult> _legacyFollowUpBox;
  final int keepPerScope;

  // ---------------------------------------------------------------------------
  // Scope-keyed unified store (Phase D)
  // ---------------------------------------------------------------------------

  /// Merged read (D-5 read-bridge): unified rows plus mapped legacy rows.
  /// Legacy boxes are only ever read — on id collision the unified row wins.
  @override
  List<UnifiedCoachResult> listByScope(String scopeType, String scopeId) {
    assert(
      _isKnownScopeType(scopeType),
      'Unknown scopeType "$scopeType" — must be "conversation" or "partner"',
    );
    final merged = <String, UnifiedCoachResult>{};
    if (scopeType == CoachScopeType.conversation) {
      for (final legacy in _legacyChatBox.values) {
        if (legacy.conversationId != scopeId) continue;
        final mapped = UnifiedCoachResult.fromCoachChatResult(legacy);
        merged[mapped.id] = mapped;
      }
    } else if (scopeType == CoachScopeType.partner) {
      final legacy = _legacyFollowUpBox.get(scopeId);
      if (legacy != null) {
        final mapped = UnifiedCoachResult.fromFollowUpResult(legacy);
        merged[mapped.id] = mapped;
      }
    }
    for (final result in _listUnifiedByScope(scopeType, scopeId)) {
      merged[result.id] = result;
    }
    final list = merged.values.toList()..sort(_compareNewestFirst);
    return list;
  }

  @override
  UnifiedCoachResult? latestForScope(String scopeType, String scopeId) {
    final list = listByScope(scopeType, scopeId);
    return list.isEmpty ? null : list.first;
  }

  @override
  Future<void> putUnified(UnifiedCoachResult result) async {
    assert(
      _isKnownScopeType(result.scopeType),
      'Unknown scopeType "${result.scopeType}" — '
      'must be "conversation" or "partner"',
    );
    final previousLatest = latestForScope(result.scopeType, result.scopeId);
    final resultWithRollup = _carryForwardUnifiedRollup(result, previousLatest);
    await _unifiedBox.put(resultWithRollup.id, resultWithRollup);
    await _trimScope(result.scopeType, result.scopeId);
  }

  @override
  Future<void> deleteScope(String scopeType, String scopeId) async {
    assert(
      _isKnownScopeType(scopeType),
      'Unknown scopeType "$scopeType" — must be "conversation" or "partner"',
    );
    final ids = _unifiedBox.values
        .where((r) => r.scopeType == scopeType && r.scopeId == scopeId)
        .map((r) => r.id)
        .toList(growable: false);
    await Future.wait(ids.map(_unifiedBox.delete));
  }

  /// Unified-box-only scope listing, newest first. Trim/rollup must key off
  /// this (not the merged [listByScope]) because legacy rows are read-only and
  /// must never be counted against [keepPerScope] nor deleted.
  List<UnifiedCoachResult> _listUnifiedByScope(
    String scopeType,
    String scopeId,
  ) {
    final list = _unifiedBox.values
        .where((r) => r.scopeType == scopeType && r.scopeId == scopeId)
        .toList()
      ..sort(_compareNewestFirst);
    return list;
  }

  static bool _isKnownScopeType(String scopeType) =>
      scopeType == CoachScopeType.conversation ||
      scopeType == CoachScopeType.partner;

  /// 排序主鍵 generatedAt 新到舊；同刻以 id 升冪當次要鍵，確保每次讀取
  /// 順序確定（review M-1 — Dart List.sort 不保證 stable）。
  static int _compareNewestFirst(UnifiedCoachResult a, UnifiedCoachResult b) {
    final byGeneratedAt = b.generatedAt.compareTo(a.generatedAt);
    return byGeneratedAt != 0 ? byGeneratedAt : a.id.compareTo(b.id);
  }

  UnifiedCoachResult _carryForwardUnifiedRollup(
    UnifiedCoachResult result,
    UnifiedCoachResult? previousLatest,
  ) {
    if (result.earlierSummary?.trim().isNotEmpty == true ||
        previousLatest == null ||
        previousLatest.earlierSummary?.trim().isNotEmpty != true) {
      return result;
    }
    return result.copyWith(
      earlierSummary: previousLatest.earlierSummary,
      earlierResultCount: previousLatest.earlierResultCount,
    );
  }

  Future<void> _trimScope(String scopeType, String scopeId) async {
    final list = _listUnifiedByScope(scopeType, scopeId);
    if (list.length <= keepPerScope) return;
    final keep = list.take(keepPerScope).toList(growable: false);
    final stale = list.skip(keepPerScope).toList(growable: false);
    await _rollupStaleResults(keep.first, keep, stale);
    await Future.wait(stale.map((result) => _unifiedBox.delete(result.id)));
  }

  Future<void> _rollupStaleResults(
    UnifiedCoachResult latest,
    List<UnifiedCoachResult> keep,
    List<UnifiedCoachResult> stale,
  ) async {
    if (stale.isEmpty) return;

    final lines = <String>[
      for (final result in keep.reversed)
        if (result.earlierSummary?.trim().isNotEmpty == true)
          result.earlierSummary!.trim(),
      for (final result in stale.reversed) _summarizeResult(result),
    ].where((line) => line.trim().isNotEmpty).toList(growable: false);

    final summary = _truncateSummary(_dedupeLines(lines).join('\n'));
    final count = keep.fold<int>(
          0,
          (max, result) =>
              result.earlierResultCount > max ? result.earlierResultCount : max,
        ) +
        stale.length;
    await _unifiedBox.put(
      latest.id,
      latest.copyWith(
        earlierSummary: summary,
        earlierResultCount: count,
      ),
    );
  }

  List<String> _dedupeLines(List<String> lines) {
    final seen = <String>{};
    final result = <String>[];
    for (final line in lines) {
      final normalized = line.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (normalized.isEmpty || !seen.add(normalized)) continue;
      result.add(line.trim());
    }
    return result;
  }

  String _summarizeResult(UnifiedCoachResult result) {
    final parts = <String>[
      '問「${result.question}」',
      result.headline,
      '先做：${result.nextStep}',
      if (result.suggestedLine?.trim().isNotEmpty == true)
        '建議句：${result.suggestedLine!.trim()}',
    ];
    return '- ${parts.join('；')}';
  }

  String _truncateSummary(String summary) {
    const maxLength = 900;
    final trimmed = summary.trim();
    if (trimmed.length <= maxLength) return trimmed;
    return trimmed.substring(trimmed.length - maxLength).trimLeft();
  }

  // ---------------------------------------------------------------------------
  // Legacy conversation-keyed interface — thin views over the unified store.
  // Kept so Phase E ships with zero UI changes.
  // ---------------------------------------------------------------------------

  @override
  List<CoachChatResult> listByConversation(String conversationId) {
    return listByScope(CoachScopeType.conversation, conversationId)
        .map(_toConversationView)
        .toList(growable: false);
  }

  @override
  CoachChatResult? latestForConversation(String conversationId) {
    final list = listByConversation(conversationId);
    return list.isEmpty ? null : list.first;
  }

  @override
  Future<void> put(CoachChatResult result) {
    return putUnified(UnifiedCoachResult.fromCoachChatResult(result));
  }

  @override
  Future<void> deleteConversation(String conversationId) {
    return deleteScope(CoachScopeType.conversation, conversationId);
  }

  /// Clears the unified store only. Legacy boxes are read-only here —
  /// their cleanup is owned by `StorageService.clearAll` and the existing
  /// delete paths (design D-5).
  @override
  Future<void> clearAll() async {
    await _unifiedBox.clear();
  }

  /// 1:1 reverse mapping to the legacy view. `scopeType` / `scopeId` /
  /// `lifecyclePhase` are dropped; a null `conversationId` falls back to
  /// `scopeId` (never happens in practice for conversation scope).
  CoachChatResult _toConversationView(UnifiedCoachResult result) {
    return CoachChatResult(
      id: result.id,
      conversationId: result.conversationId ?? result.scopeId,
      partnerId: result.partnerId,
      question: result.question,
      mode: result.mode,
      headline: result.headline,
      answer: result.answer,
      userState: result.userState,
      nextStep: result.nextStep,
      suggestedLine: result.suggestedLine,
      boundaryReminder: result.boundaryReminder,
      needsReflection: result.needsReflection,
      reflectionQuestion: result.reflectionQuestion,
      generatedAt: result.generatedAt,
      provider: result.provider,
      modelUsed: result.modelUsed,
      responseType: result.responseType,
      sessionId: result.sessionId,
      userTruth: result.userTruth,
      rewriteDecision: result.rewriteDecision,
      rewriteReason: result.rewriteReason,
      costDeducted: result.costDeducted,
      frictionType: result.frictionType,
      earlierSummary: result.earlierSummary,
      earlierResultCount: result.earlierResultCount,
    );
  }
}
