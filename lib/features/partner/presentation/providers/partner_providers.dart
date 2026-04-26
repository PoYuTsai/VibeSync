// lib/features/partner/presentation/providers/partner_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../conversation/data/providers/conversation_providers.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../data/repositories/partner_repository.dart';
import '../../domain/entities/partner.dart';
import '../../domain/extensions/partner_aggregates.dart';

/// Single instance for the app lifecycle. Construction is cheap (just box
/// references), no auth dependency.
final partnerRepositoryProvider = Provider<PartnerRepository>((ref) {
  return PartnerRepository();
});

/// Single Partner by id. Returns null if absent (deleted / merged away).
final partnerByIdProvider = Provider.family<Partner?, String>((ref, id) {
  final repo = ref.watch(partnerRepositoryProvider);
  return repo.getById(id);
});

/// Owner-scoped Partner list. Auth scope binding ensures account swaps
/// rebuild the list (login_screen invalidates authConversationScopeProvider).
final partnerListProvider = Provider<List<Partner>>((ref) {
  final userId = ref.watch(authConversationScopeProvider).valueOrNull;
  if (userId == null) return const <Partner>[];
  final repo = ref.watch(partnerRepositoryProvider);
  return repo.listByOwner(userId);
});

/// Conversations belonging to a specific Partner.
///
/// **Narrow contract (HS-A2-1)**: This provider does NOT watch the global
/// `conversationsProvider`; cross-partner writes don't fan out to other
/// partners' aggregates. The provider re-evaluates only when:
///   - the controller invalidates `conversationsByPartnerProvider(partnerId)`
///     for THIS partnerId, OR
///   - the auth scope changes (account swap).
final conversationsByPartnerProvider =
    Provider.family<List<Conversation>, String>((ref, partnerId) {
  ref.watch(authConversationScopeProvider);
  final repo = ref.watch(conversationRepositoryProvider);
  return repo.listByPartner(partnerId);
});

/// Aggregated Partner view for the detail screen + AI prompt summary.
final partnerAggregateProvider =
    Provider.family<PartnerAggregateView, String>((ref, partnerId) {
  final partner = ref.watch(partnerByIdProvider(partnerId));
  final conversations = ref.watch(conversationsByPartnerProvider(partnerId));
  if (partner == null) return PartnerAggregateView.empty();
  return partner.aggregateOver(conversations);
});
