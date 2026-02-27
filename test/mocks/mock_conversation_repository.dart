// test/mocks/mock_conversation_repository.dart
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

/// In-memory mock of ConversationRepository for testing
class MockConversationRepository {
  final Map<String, Conversation> _conversations = {};

  MockConversationRepository([List<Conversation>? initialConversations]) {
    if (initialConversations != null) {
      for (final conv in initialConversations) {
        _conversations[conv.id] = conv;
      }
    }
  }

  List<Conversation> getAllConversations() {
    return _conversations.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Conversation? getConversation(String id) {
    return _conversations[id];
  }

  Future<Conversation> createConversation({
    required String name,
    required List<Message> messages,
  }) async {
    final conversation = Conversation(
      id: 'test-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      messages: messages,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _conversations[conversation.id] = conversation;
    return conversation;
  }

  Future<void> updateConversation(Conversation conversation) async {
    _conversations[conversation.id] = conversation;
  }

  Future<void> deleteConversation(String id) async {
    _conversations.remove(id);
  }

  List<Message> parseMessages(String text) {
    final lines = text.split('\n');
    final messages = <Message>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final isFromMe = trimmed.startsWith('我:') || trimmed.startsWith('我：');
      final isFromThem = trimmed.startsWith('她:') ||
          trimmed.startsWith('她：') ||
          trimmed.startsWith('他:') ||
          trimmed.startsWith('他：');

      if (!isFromMe && !isFromThem) continue;

      final colonIndex =
          trimmed.contains(':') ? trimmed.indexOf(':') : trimmed.indexOf('：');
      if (colonIndex == -1) continue;

      final content = trimmed.substring(colonIndex + 1).trim();
      if (content.isEmpty) continue;

      messages.add(Message(
        id: '${messages.length}',
        content: content,
        isFromMe: isFromMe,
        timestamp: DateTime.now(),
      ));
    }

    return messages;
  }
}
