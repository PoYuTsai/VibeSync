import 'package:hive_ce/hive_ce.dart';

import '../../../conversation/domain/entities/conversation.dart';
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

  @override
  Stream<void> watchChanges() => _box.watch().map((_) {});

  /// Persists the canonical partner scope onto legacy analyze events while the
  /// source conversation still exists. This must run after Partner migration.
  Future<int> backfillPartnerIds(Iterable<Conversation> conversations) async {
    final partnerByConversation = <String, String>{};
    for (final conversation in conversations) {
      final conversationId =
          AnalysisHistoryEvent.normalizeScope(conversation.id);
      final partnerId =
          AnalysisHistoryEvent.normalizeScope(conversation.partnerId);
      if (conversationId != null && partnerId != null) {
        partnerByConversation[conversationId] = partnerId;
      }
    }

    final updates = <dynamic, AnalysisHistoryEvent>{};
    for (final key in _box.keys) {
      final event = _box.get(key);
      if (event == null || event.kind != AnalysisHistoryKind.analyze) {
        continue;
      }
      final conversationId =
          AnalysisHistoryEvent.normalizeScope(event.conversationId);
      final partnerId = partnerByConversation[conversationId];
      final existingPartnerId =
          AnalysisHistoryEvent.normalizeScope(event.partnerId);
      if (partnerId != null && partnerId != existingPartnerId) {
        updates[key] = event.withPartnerId(partnerId);
      }
    }
    if (updates.isNotEmpty) await _box.putAll(updates);
    return updates.length;
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
