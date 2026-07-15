import '../../domain/entities/analysis_record.dart';
import '../../domain/services/analysis_fragment_policy.dart';
import '../../../conversation/data/repositories/conversation_archive_store.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../repositories/analysis_record_store.dart';

/// Bridges legacy "current" records into the independent-fragment archive.
///
/// New successful fragments are promoted immediately. The union in [recordsFor]
/// keeps legacy one-shot analyses visible even before their screen has been
/// opened and repaired on this app version.
class AnalysisArchiveLifecycle {
  const AnalysisArchiveLifecycle._();

  /// Whether [record] is the only durable analysis for the complete canonical
  /// conversation content.
  ///
  /// New independent fragments satisfy this shape: one Conversation id, one
  /// full-span record, and an exact content revision. Legacy stacked
  /// conversations do not. Callers use the distinction conservatively when
  /// deciding whether deleting a record may also delete its Conversation and
  /// whether the old whole-conversation archive would only duplicate it.
  static bool isStandaloneFragmentRecord({
    required AnalysisRecord record,
    required Conversation conversation,
    required Iterable<AnalysisRecord> records,
  }) {
    final conversationOwner = conversation.ownerUserId?.trim();
    if (conversationOwner == null ||
        conversationOwner.isEmpty ||
        conversationOwner != record.ownerUserId ||
        !AnalysisFragmentPolicy.hasCompletedAnalysis(conversation) ||
        record.conversationId != conversation.id ||
        record.segmentStart != 0 ||
        record.segmentEnd != conversation.messages.length ||
        record.messages.length != conversation.messages.length ||
        record.analyzedContentRevision !=
            conversationContentRevision(conversation)) {
      return false;
    }

    final recordsForConversation = records
        .where((item) => item.conversationId == conversation.id)
        .toList(growable: false);
    return recordsForConversation.length == 1 &&
        recordsForConversation.single.id == record.id;
  }

  static bool hasStandaloneFragmentRecord({
    required Conversation conversation,
    required Iterable<AnalysisRecord> records,
  }) {
    for (final record in records) {
      if (isStandaloneFragmentRecord(
        record: record,
        conversation: conversation,
        records: records,
      )) {
        return true;
      }
    }
    return false;
  }

  static List<AnalysisRecord> recordsFor({
    required AnalysisRecordStore store,
    required String ownerUserId,
    required Iterable<Conversation> conversations,
  }) {
    final owner = ownerUserId.trim();
    final scopedConversations = conversations.toList(growable: false);
    if (owner.isEmpty || scopedConversations.isEmpty) return const [];

    final byId = <String, AnalysisRecord>{
      for (final record in store.listArchived(
        ownerUserId: owner,
        conversationIds: scopedConversations.map((item) => item.id),
      ))
        record.id: record,
    };
    for (final conversation in scopedConversations) {
      if (!AnalysisFragmentPolicy.hasCompletedAnalysis(conversation)) continue;
      final current = store.currentFor(
        ownerUserId: owner,
        conversationId: conversation.id,
      );
      if (current != null) byId[current.id] = current;
    }

    final records = byId.values.toList(growable: false)
      ..sort((a, b) {
        final byDate = b.createdAt.compareTo(a.createdAt);
        return byDate != 0 ? byDate : b.id.compareTo(a.id);
      });
    return List.unmodifiable(records);
  }

  static Future<bool> promoteCompletedCurrentRecords({
    required AnalysisRecordStore store,
    required String ownerUserId,
    required Iterable<Conversation> conversations,
  }) async {
    final owner = ownerUserId.trim();
    if (owner.isEmpty) return false;

    var accepted = true;
    for (final conversation in conversations) {
      if (!AnalysisFragmentPolicy.hasCompletedAnalysis(conversation)) continue;
      final current = store.currentFor(
        ownerUserId: owner,
        conversationId: conversation.id,
      );
      if (current == null) continue;
      final archived = await store.archiveCurrentRecord(
        ownerUserId: owner,
        conversationId: conversation.id,
      );
      accepted = archived && accepted;
    }
    return accepted;
  }
}
