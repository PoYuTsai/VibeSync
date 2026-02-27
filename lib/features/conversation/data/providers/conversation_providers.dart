// lib/features/conversation/data/providers/conversation_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/conversation_repository.dart';
import '../../domain/entities/conversation.dart';

final conversationRepositoryProvider = Provider<ConversationRepository>((ref) {
  return ConversationRepository();
});

final conversationsProvider = Provider<List<Conversation>>((ref) {
  final repository = ref.watch(conversationRepositoryProvider);
  return repository.getAllConversations();
});
