// lib/features/conversation/data/providers/conversation_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/supabase_service.dart';
import '../repositories/conversation_repository.dart';
import '../services/memory_service.dart';
import '../../domain/entities/conversation.dart';

final conversationRepositoryProvider = Provider<ConversationRepository>((ref) {
  return ConversationRepository(
    memoryService: ref.watch(memoryServiceProvider),
  );
});

final authConversationScopeProvider = StreamProvider<String?>((ref) async* {
  yield SupabaseService.currentUser?.id;
  yield* SupabaseService.authStateChanges.map(
    (authState) => authState.session?.user.id,
  );
});

final conversationsProvider = Provider<List<Conversation>>((ref) {
  ref.watch(authConversationScopeProvider);
  final repository = ref.watch(conversationRepositoryProvider);
  return repository.getAllConversations();
});

/// Provider to get a single conversation by ID (for easier testing)
final conversationProvider =
    Provider.family<Conversation?, String>((ref, id) {
  ref.watch(authConversationScopeProvider);
  final repository = ref.watch(conversationRepositoryProvider);
  return repository.getConversation(id);
});
