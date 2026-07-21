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
  // ignore: unused_field — read-bridge source, wired in Task 5.
  final Box<CoachFollowUpResult> _legacyFollowUpBox;
  final int keepPerScope;

  // ---------------------------------------------------------------------------
  // Scope-keyed unified store (Phase D)
  // ---------------------------------------------------------------------------

  @override
  List<UnifiedCoachResult> listByScope(String scopeType, String scopeId) {
    return _listUnifiedByScope(scopeType, scopeId);
  }

  @override
  UnifiedCoachResult? latestForScope(String scopeType, String scopeId) {
    final list = listByScope(scopeType, scopeId);
    return list.isEmpty ? null : list.first;
  }

  @override
  Future<void> putUnified(UnifiedCoachResult result) async {
    final previousLatest = latestForScope(result.scopeType, result.scopeId);
    final resultWithRollup = _carryForwardUnifiedRollup(result, previousLatest);
    await _unifiedBox.put(resultWithRollup.id, resultWithRollup);
    await _trimScope(result.scopeType, result.scopeId);
  }

  @override
  Future<void> deleteScope(String scopeType, String scopeId) async {
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
      ..sort((a, b) => b.generatedAt.compareTo(a.generatedAt));
    return list;
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
  // Legacy conversation-keyed interface (redirected to unified in Task 6)
  // ---------------------------------------------------------------------------

  @override
  List<CoachChatResult> listByConversation(String conversationId) {
    final list = _legacyChatBox.values
        .where((result) => result.conversationId == conversationId)
        .toList()
      ..sort((a, b) => b.generatedAt.compareTo(a.generatedAt));
    return list;
  }

  @override
  CoachChatResult? latestForConversation(String conversationId) {
    final list = listByConversation(conversationId);
    return list.isEmpty ? null : list.first;
  }

  @override
  Future<void> put(CoachChatResult result) async {
    final previousLatest = latestForConversation(result.conversationId);
    final resultWithRollup = _carryForwardLegacyRollup(result, previousLatest);
    await _legacyChatBox.put(resultWithRollup.id, resultWithRollup);
    await _trimConversation(result.conversationId);
  }

  CoachChatResult _carryForwardLegacyRollup(
    CoachChatResult result,
    CoachChatResult? previousLatest,
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

  Future<void> _trimConversation(String conversationId) async {
    final list = listByConversation(conversationId);
    if (list.length <= keepPerScope) return;
    final keep = list.take(keepPerScope).toList(growable: false);
    final stale = list.skip(keepPerScope).toList(growable: false);
    await _rollupStaleLegacyResults(keep.first, keep, stale);
    await Future.wait(stale.map((result) => _legacyChatBox.delete(result.id)));
  }

  Future<void> _rollupStaleLegacyResults(
    CoachChatResult latest,
    List<CoachChatResult> keep,
    List<CoachChatResult> stale,
  ) async {
    if (stale.isEmpty) return;

    final lines = <String>[
      for (final result in keep.reversed)
        if (result.earlierSummary?.trim().isNotEmpty == true)
          result.earlierSummary!.trim(),
      for (final result in stale.reversed)
        _summarizeResult(UnifiedCoachResult.fromCoachChatResult(result)),
    ].where((line) => line.trim().isNotEmpty).toList(growable: false);

    final summary = _truncateSummary(_dedupeLines(lines).join('\n'));
    final count = keep.fold<int>(
          0,
          (max, result) =>
              result.earlierResultCount > max ? result.earlierResultCount : max,
        ) +
        stale.length;
    await _legacyChatBox.put(
      latest.id,
      latest.copyWith(
        earlierSummary: summary,
        earlierResultCount: count,
      ),
    );
  }

  @override
  Future<void> deleteConversation(String conversationId) async {
    final ids = _legacyChatBox.values
        .where((result) => result.conversationId == conversationId)
        .map((result) => result.id)
        .toList();
    await Future.wait(ids.map(_legacyChatBox.delete));
  }

  @override
  Future<void> clearAll() => _legacyChatBox.clear();
}
