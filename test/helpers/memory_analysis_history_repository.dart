import 'package:vibesync/features/analysis_history/domain/entities/analysis_history_event.dart';
import 'package:vibesync/features/analysis_history/domain/repositories/analysis_history_repository.dart';

class MemoryAnalysisHistoryRepository implements AnalysisHistoryRepository {
  final events = <AnalysisHistoryEvent>[];

  @override
  Future<void> append(AnalysisHistoryEvent event) async {
    events.add(event);
  }

  @override
  Future<void> clearAll() async => events.clear();

  @override
  List<AnalysisHistoryEvent> listRecent({int? limit}) => _limit(
        events.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
        limit,
      );

  @override
  List<AnalysisHistoryEvent> listByKind(AnalysisHistoryKind kind,
          {int? limit}) =>
      _limit(listRecent().where((e) => e.kind == kind).toList(), limit);

  @override
  List<AnalysisHistoryEvent> listByConversation(String conversationId,
      {int? limit}) {
    final normalized = AnalysisHistoryEvent.normalizeScope(conversationId);
    if (normalized == null) return const [];
    return _limit(
      listRecent()
          .where((e) =>
              AnalysisHistoryEvent.normalizeScope(e.conversationId) ==
              normalized)
          .toList(),
      limit,
    );
  }

  static List<AnalysisHistoryEvent> _limit(
      List<AnalysisHistoryEvent> list, int? limit) {
    if (limit == null || limit >= list.length) return list;
    if (limit <= 0) return const [];
    return list.take(limit).toList();
  }
}
