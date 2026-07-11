import '../../../analysis_history/domain/entities/analysis_history_event.dart';
import '../../../conversation/data/repositories/conversation_archive_store.dart';
import '../../../conversation/domain/entities/conversation.dart';

typedef ConversationArchiveEntryLookup = ConversationArchiveEntry? Function(
  Conversation conversation,
);
typedef LatestAnalysisAtLookup = DateTime? Function(String conversationId);

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
    final explicit = entryFor(conversation);
    if (explicit?.status == ConversationArchiveStatus.active) {
      active.add(conversation);
      continue;
    }
    if (explicit?.status == ConversationArchiveStatus.archived) {
      archived.add(ArchivedConversation(
        conversation: conversation,
        archivedAt: explicit!.archivedAt!,
      ));
      continue;
    }

    final latestAnalysisAt = latestAnalysisAtFor(conversation.id);
    final snapshotIsPresent =
        conversation.lastAnalysisSnapshotJson?.trim().isNotEmpty == true;
    final analyzedAllMessages = conversation.lastAnalyzedMessageCount != null &&
        conversation.lastAnalyzedMessageCount == conversation.messages.length;
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

DateTime? latestAnalyzeEventAt(
  Iterable<AnalysisHistoryEvent> events,
) {
  DateTime? latest;
  for (final event in events) {
    if (event.kind != AnalysisHistoryKind.analyze) continue;
    if (latest == null || event.createdAt.isAfter(latest)) {
      latest = event.createdAt;
    }
  }
  return latest;
}
