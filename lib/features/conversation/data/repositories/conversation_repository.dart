// lib/features/conversation/data/repositories/conversation_repository.dart
import 'package:uuid/uuid.dart';
import '../../../../core/services/storage_service.dart';
import '../services/memory_service.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/message.dart';

class ConversationRepository {
  ConversationRepository({MemoryService? memoryService})
      : _memoryService = memoryService ?? MemoryService();

  final _uuid = const Uuid();
  final MemoryService _memoryService;

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
      currentRound: _calculateRoundCount(messages),
    );

    await StorageService.conversationsBox.put(conversation.id, conversation);
    return conversation;
  }

  Future<void> updateConversation(Conversation conversation) async {
    conversation.currentRound = _calculateRoundCount(conversation.messages);
    await _maybeGenerateSummary(conversation);
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

  /// Create messages from a list of maps (for chat-style input)
  List<Message> createMessagesFromList(List<Map<String, dynamic>> messageList) {
    return messageList.map((m) => Message(
      id: _uuid.v4(),
      content: m['content'] as String,
      isFromMe: m['isFromMe'] as bool,
      timestamp: DateTime.now(),
    )).toList();
  }

  int _calculateRoundCount(List<Message> messages) {
    return messages.where((message) => !message.isFromMe).length;
  }

  Future<void> _maybeGenerateSummary(Conversation conversation) async {
    final summarizedRounds = conversation.summaries
            ?.fold<int>(0, (total, summary) => total + summary.roundsCovered) ??
        0;
    final availableOlderRounds = conversation.currentRound -
        summarizedRounds -
        MemoryService.maxRecentRounds;

    if (availableOlderRounds < MemoryService.minRoundsPerSummary) {
      return;
    }

    final fromRound = summarizedRounds;
    final toRound = summarizedRounds + availableOlderRounds;
    if (toRound <= fromRound) {
      return;
    }

    final summary = await _memoryService.generateSummary(
      conversation,
      fromRound,
      toRound,
    );

    if (summary.roundsCovered <= 0 || summary.content.trim().isEmpty) {
      return;
    }

    final alreadyCovered = conversation.summaries?.any(
          (existing) =>
              existing.roundsCovered == summary.roundsCovered &&
              existing.content == summary.content,
        ) ??
        false;
    if (alreadyCovered) {
      return;
    }

    conversation.addSummary(summary);
  }
}
