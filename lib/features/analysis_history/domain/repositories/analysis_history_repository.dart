import '../entities/analysis_history_event.dart';

abstract class AnalysisHistoryRepository {
  /// newest-first（模板慣例）；報告頁要升序自己 reverse/sort。
  List<AnalysisHistoryEvent> listRecent({int? limit});

  List<AnalysisHistoryEvent> listByKind(AnalysisHistoryKind kind, {int? limit});

  List<AnalysisHistoryEvent> listByConversation(
    String conversationId, {
    int? limit,
  });

  /// 以 event.id 冪等寫入；新 id 是 append，相同 id 用於同一內容修訂重跑
  /// 的原地更新。寫入後超過上限（500）刪最舊。
  Future<void> append(AnalysisHistoryEvent event);

  Future<void> clearAll();

  /// Emits after the underlying local store changes. In-memory/test
  /// repositories can keep the default empty stream.
  Stream<void> watchChanges() => const Stream<void>.empty();
}
