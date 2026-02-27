// lib/features/conversation/data/repositories/conversation_repository.dart
import 'package:uuid/uuid.dart';
import '../../../../core/services/storage_service.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/message.dart';

class ConversationRepository {
  final _uuid = const Uuid();

  List<Conversation> getAllConversations() {
    return StorageService.conversationsBox.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Conversation? getConversation(String id) {
    return StorageService.conversationsBox.get(id);
  }

  Future<Conversation> createConversation({
    required String name,
    required List<Message> messages,
  }) async {
    final now = DateTime.now();
    final conversation = Conversation(
      id: _uuid.v4(),
      name: name,
      messages: messages,
      createdAt: now,
      updatedAt: now,
    );

    await StorageService.conversationsBox.put(conversation.id, conversation);
    return conversation;
  }

  Future<void> updateConversation(Conversation conversation) async {
    conversation.updatedAt = DateTime.now();
    await conversation.save();
  }

  Future<void> deleteConversation(String id) async {
    await StorageService.conversationsBox.delete(id);
  }

  Future<void> deleteAll() async {
    await StorageService.conversationsBox.clear();
  }

  List<Message> parseMessages(String rawText) {
    final lines = rawText.trim().split('\n');
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

      final content = trimmed.substring(2).trim();
      if (content.isEmpty) continue;

      messages.add(Message(
        id: _uuid.v4(),
        content: content,
        isFromMe: isFromMe,
        timestamp: DateTime.now(),
      ));
    }

    return messages;
  }
}
