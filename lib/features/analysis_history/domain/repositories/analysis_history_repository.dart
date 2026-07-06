import '../entities/analysis_history_event.dart';

abstract class AnalysisHistoryRepository {
  /// newest-first（模板慣例）；報告頁要升序自己 reverse/sort。
  List<AnalysisHistoryEvent> listRecent({int? limit});

  List<AnalysisHistoryEvent> listByKind(AnalysisHistoryKind kind, {int? limit});

  List<AnalysisHistoryEvent> listByConversation(
    String conversationId, {
    int? limit,
  });

  /// append-only；寫入後超過上限（500）刪最舊。
  Future<void> append(AnalysisHistoryEvent event);

  Future<void> clearAll();
}
