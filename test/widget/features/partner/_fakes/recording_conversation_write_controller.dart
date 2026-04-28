// test/widget/features/partner/_fakes/recording_conversation_write_controller.dart
//
// Hermetic test double for ConversationWriteController scoped to PR-B's
// reassign flow. Captures save() args (the conversation reference + the
// previousPartnerId hint) so widget tests can assert the dual-side
// invalidate contract from Phase 1 without Hive / Supabase.
//
// Phase 4 cleanup: unify with PR-A's
// `test/widget/features/conversation/_fakes/recording_conversation_write_controller.dart`.
// Two parallel fakes is intentional for now — PR-A only needed `create`,
// PR-B needs `save(previousPartnerId:)`.
import 'package:vibesync/features/conversation/data/providers/conversation_write_controller.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

class RecordingConversationWriteController extends ConversationWriteController {
  bool saveCalled = false;
  Conversation? savedConversation;
  String? savedPartnerIdAtCallTime;
  String? savedPreviousPartnerId;
  Object? throwOnSave;
  bool deleteCalled = false;
  Conversation? deletedConversation;
  Object? throwOnDelete;

  @override
  Future<void> save(Conversation c, {String? previousPartnerId}) async {
    saveCalled = true;
    savedConversation = c;
    // capture partnerId at the moment of the call — caller mutates it
    // back on failure, so we can't trust it after await returns.
    savedPartnerIdAtCallTime = c.partnerId;
    savedPreviousPartnerId = previousPartnerId;
    if (throwOnSave != null) throw throwOnSave!;
  }

  @override
  Future<void> delete(Conversation c) async {
    deleteCalled = true;
    deletedConversation = c;
    if (throwOnDelete != null) throw throwOnDelete!;
  }

  @override
  Future<Conversation> create({
    required String name,
    required List<Message> messages,
    String? partnerId,
  }) async {
    return Conversation(
      id: 'fake',
      name: name,
      messages: messages,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      partnerId: partnerId,
    );
  }
}
