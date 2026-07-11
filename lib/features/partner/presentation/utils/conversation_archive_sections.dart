import '../../../analysis_history/domain/entities/analysis_history_event.dart';
import '../../../analysis_history/domain/repositories/analysis_history_repository.dart';
import '../../../conversation/data/repositories/conversation_archive_store.dart';
import '../../../conversation/domain/entities/conversation.dart';

typedef ConversationArchiveEntryLookup = ConversationArchiveEntry? Function(
  Conversation conversation,
);
typedef LatestAnalysisAtLookup = DateTime? Function(String conversationId);

/// Builds a per-render lazy index for markerless legacy conversations. The
/// history box is scanned at most once, only if a legacy lookup is needed.
/// Storage failures are cached as an empty index so every conversation fails
/// open without repeatedly touching the unavailable box.
LatestAnalysisAtLookup createLazyLatestAnalyzeAtLookup(
  AnalysisHistoryRepository Function() loadRepository,
) {
  Map<String, DateTime>? latestByConversation;

  void loadOnce() {
    if (latestByConversation != null) return;
    final index = <String, DateTime>{};
    latestByConversation = index;
    try {
      final events = loadRepository().listByKind(AnalysisHistoryKind.analyze);
      for (final event in events) {
        if (event.kind != AnalysisHistoryKind.analyze) continue;
        final conversationId =
            AnalysisHistoryEvent.normalizeScope(event.conversationId);
        if (conversationId == null) continue;
        final previous = index[conversationId];
        if (previous == null || event.createdAt.isAfter(previous)) {
          index[conversationId] = event.createdAt;
        }
      }
    } catch (_) {
      index.clear();
    }
  }

  return (conversationId) {
    loadOnce();
    final normalized = AnalysisHistoryEvent.normalizeScope(conversationId);
    return normalized == null ? null : latestByConversation![normalized];
  };
}

class ArchivedConversation {
  const ArchivedConversation({
    required this.conversation,
    required this.archivedAt,
  });

  final Conversation conversation;
  final DateTime archivedAt;
}

class ConversationArchiveSections {
  const ConversationArchiveSections({
    required this.active,
    required this.archived,
  });

  final List<Conversation> active;
  final List<ArchivedConversation> archived;
}

/// Explicit marker 是權威；無 marker 的舊資料只在四個證據完整時保守 seed：
/// snapshot 存在、分析訊息數吻合、analyze event 存在且不早於最後內容更新。
ConversationArchiveSections partitionConversationsByArchive(
  List<Conversation> conversations, {
  required ConversationArchiveEntryLookup entryFor,
  required LatestAnalysisAtLookup latestAnalysisAtFor,
}) {
  final active = <Conversation>[];
  final archived = <ArchivedConversation>[];

  for (final conversation in conversations) {
    final snapshotIsPresent =
        conversation.lastAnalysisSnapshotJson?.trim().isNotEmpty == true;
    final analyzedAllMessages = conversation.lastAnalyzedMessageCount != null &&
        conversation.lastAnalyzedMessageCount == conversation.messages.length;
    final explicit = entryFor(conversation);
    if (explicit?.status == ConversationArchiveStatus.active) {
      active.add(conversation);
      continue;
    }
    if (explicit?.status == ConversationArchiveStatus.archived) {
      final recordedRevision = explicit!.contentRevision;
      if (!snapshotIsPresent ||
          !analyzedAllMessages ||
          recordedRevision == null ||
          recordedRevision != conversationContentRevision(conversation)) {
        // A content save may succeed while its best-effort marker write fails,
        // or may race an older analysis completion. Missing legacy/corrupt and
        // mismatched markers are stale and must never hide the conversation.
        active.add(conversation);
        continue;
      }
      archived.add(ArchivedConversation(
        conversation: conversation,
        archivedAt: explicit.archivedAt!,
      ));
      continue;
    }

    final latestAnalysisAt = latestAnalysisAtFor(conversation.id);
    final historyCoversLatestContent = latestAnalysisAt != null &&
        !latestAnalysisAt.isBefore(conversation.updatedAt);
    if (snapshotIsPresent &&
        analyzedAllMessages &&
        historyCoversLatestContent) {
      archived.add(ArchivedConversation(
        conversation: conversation,
        archivedAt: latestAnalysisAt,
      ));
    } else {
      active.add(conversation);
    }
  }

  archived.sort((a, b) => b.archivedAt.compareTo(a.archivedAt));
  return ConversationArchiveSections(active: active, archived: archived);
}
