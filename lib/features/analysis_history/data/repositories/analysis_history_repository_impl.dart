import 'package:hive_ce/hive_ce.dart';

import '../../domain/entities/analysis_history_event.dart';
import '../../domain/repositories/analysis_history_repository.dart';

class AnalysisHistoryRepositoryImpl implements AnalysisHistoryRepository {
  AnalysisHistoryRepositoryImpl(this._box);

  /// 保留策略（設計拍板）：超過 500 筆刪最舊。
  static const maxEvents = 500;

  final Box<AnalysisHistoryEvent> _box;

  @override
  List<AnalysisHistoryEvent> listRecent({int? limit}) {
    return _sorted(_box.values, limit: limit);
  }

  @override
  List<AnalysisHistoryEvent> listByKind(
    AnalysisHistoryKind kind, {
    int? limit,
  }) {
    return _sorted(
      _box.values.where((event) => event.kind == kind),
      limit: limit,
    );
  }

  @override
  List<AnalysisHistoryEvent> listByConversation(
    String conversationId, {
    int? limit,
  }) {
    final normalized = AnalysisHistoryEvent.normalizeScope(conversationId);
    if (normalized == null) return const [];
    return _sorted(
      _box.values.where(
        (event) =>
            AnalysisHistoryEvent.normalizeScope(event.conversationId) ==
            normalized,
      ),
      limit: limit,
    );
  }

  @override
  Future<void> append(AnalysisHistoryEvent event) async {
    await _box.put(event.id, event);
    await _pruneIfNeeded();
  }

  @override
  Future<void> clearAll() async {
    await _box.clear();
  }

  Future<void> _pruneIfNeeded() async {
    final overflow = _box.length - maxEvents;
    if (overflow <= 0) return;
    final entries = <MapEntry<dynamic, DateTime>>[];
    for (final key in _box.keys) {
      final event = _box.get(key);
      if (event != null) entries.add(MapEntry(key, event.createdAt));
    }
    entries.sort((a, b) => a.value.compareTo(b.value)); // 最舊在前
    await _box.deleteAll(
      entries.take(overflow).map((entry) => entry.key).toList(growable: false),
    );
  }

  static List<AnalysisHistoryEvent> _sorted(
    Iterable<AnalysisHistoryEvent> events, {
    int? limit,
  }) {
    final sorted = events.toList(growable: false)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (limit == null || limit >= sorted.length) return sorted;
    if (limit <= 0) return const [];
    return sorted.take(limit).toList(growable: false);
  }
}
