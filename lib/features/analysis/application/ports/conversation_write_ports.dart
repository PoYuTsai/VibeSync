/// 持久化協調器對「對話讀寫／archive 標記」的窄 port。
/// data 層在 composition root（analysis_providers.dart）以 adapter 實作；
/// application 看不到 write controller、archive store 等具體型別。
library;

import '../../../conversation/domain/entities/conversation.dart';

/// 以 id 取當前對話（找不到回 null）。
typedef GetConversation = Conversation? Function(String conversationId);

/// 分析完成的 canonical 對話存檔：帶 expectedContentRevision 前置檢查
/// （內容已變時 adapter 底層的 write controller 會拒寫內容、只補標記）。
typedef PersistAnalysisCompletedConversation = Future<void> Function(
  Conversation conversation, {
  required String expectedContentRevision,
});

/// 內容變更語意的補償存檔（rollback 後把最新訊息存為 active）。
typedef PersistContentChangedConversation = Future<void> Function(
  Conversation conversation,
);

/// 明確寫 active archive 標記（補償存檔也失敗時的最後防線）。
typedef MarkConversationActive = Future<void> Function(
  Conversation conversation,
);

/// legacy snapshot 可還原性判定所需的 archive 標記快照。
class ArchiveMarkerSnapshot {
  final String? contentRevision;
  final bool isArchived;

  const ArchiveMarkerSnapshot({
    required this.contentRevision,
    required this.isArchived,
  });
}

/// 查對話的 archive 標記；沒有標記回 null。
typedef ArchiveMarkerLookup = ArchiveMarkerSnapshot? Function(
  Conversation conversation,
);
