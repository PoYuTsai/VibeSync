import 'package:hive_ce/hive_ce.dart';

import '../../domain/entities/coach_chat_result.dart';
import '../../domain/repositories/coach_chat_repository.dart';

class CoachChatRepositoryImpl implements CoachChatRepository {
  CoachChatRepositoryImpl(this._box, {this.keepPerConversation = 10});

  final Box<CoachChatResult> _box;
  final int keepPerConversation;

  @override
  List<CoachChatResult> listByConversation(String conversationId) {
    final list = _box.values
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
    final resultWithRollup = _carryForwardRollup(result, previousLatest);
    await _box.put(resultWithRollup.id, resultWithRollup);
    await _trimConversation(result.conversationId);
  }

  CoachChatResult _carryForwardRollup(
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
    if (list.length <= keepPerConversation) return;
    final keep = list.take(keepPerConversation).toList(growable: false);
    final stale = list.skip(keepPerConversation).toList(growable: false);
    await _rollupStaleResults(keep.first, keep, stale);
    await Future.wait(stale.map((result) => _box.delete(result.id)));
  }

  Future<void> _rollupStaleResults(
    CoachChatResult latest,
    List<CoachChatResult> keep,
    List<CoachChatResult> stale,
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
    await _box.put(
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

  String _summarizeResult(CoachChatResult result) {
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

  @override
  Future<void> deleteConversation(String conversationId) async {
    final ids = _box.values
        .where((result) => result.conversationId == conversationId)
        .map((result) => result.id)
        .toList();
    await Future.wait(ids.map(_box.delete));
  }

  @override
  Future<void> clearAll() => _box.clear();
}
