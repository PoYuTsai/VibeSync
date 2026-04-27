// test/widget/features/conversation/_fakes/recording_conversation_write_controller.dart
//
// Hermetic test double for ConversationWriteController. Captures partnerId
// passed to create() so PR-A widget tests can assert Phase 2's chain
// without Hive/Supabase. save() is no-op since downstream state is not
// under test in PR-A.
import 'package:vibesync/features/conversation/data/providers/conversation_write_controller.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

class RecordingConversationWriteController extends ConversationWriteController {
  bool createCalled = false;
  String? capturedPartnerId;
  String? capturedName;
  int capturedMessageCount = 0;

  @override
  Future<Conversation> create({
    required String name,
    required List<Message> messages,
    String? partnerId,
  }) async {
    createCalled = true;
    capturedPartnerId = partnerId;
    capturedName = name;
    capturedMessageCount = messages.length;
    return Conversation(
      id: 'fake-conv-id',
      name: name,
      messages: messages,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      partnerId: partnerId,
    );
  }

  @override
  Future<void> save(Conversation c, {String? previousPartnerId}) async {
    // no-op for hermetic widget test
  }
}
