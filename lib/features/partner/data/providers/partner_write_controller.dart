import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../conversation/data/providers/conversation_providers.dart';
import '../../presentation/providers/partner_providers.dart';

/// Single invalidation owner for partner-level writes — mirrors Phase 1's
/// `ConversationWriteController` for the conversation domain.
///
/// Why this exists despite the Phase 3 design doc §5 implying
/// "repo triggers invalidation": `PartnerRepository` has no Riverpod `Ref`,
/// so after `merge()` the Hive state is correct but provider caches stay
/// stale until something forces a re-read. This controller closes that gap.
///
/// Phase 4 will extend this with `delete()` / `update()`. Same invalidation
/// surface, different repo call.
class PartnerWriteController extends Notifier<void> {
  @override
  void build() {
    // Stateless write coordinator.
  }

  Future<void> merge({
    required String fromId,
    required String toId,
  }) async {
    if (fromId == toId) return;
    final repo = ref.read(partnerRepositoryProvider);
    try {
      await repo.merge(fromId: fromId, toId: toId);
    } finally {
      // Repo merge is multi-step Hive I/O. If it throws after a partial write,
      // invalidate anyway so the UI reflects the real local state.
      _invalidateMergeScopes(fromId, toId);
    }
  }

  void _invalidatePartner(String id) {
    ref.invalidate(partnerByIdProvider(id));
    ref.invalidate(partnerAggregateProvider(id));
  }

  void _invalidatePartnerScopedConversations(String id) {
    ref.invalidate(conversationsByPartnerProvider(id));
  }

  void _invalidateMergeScopes(String fromId, String toId) {
    _invalidatePartner(fromId);
    _invalidatePartner(toId);
    _invalidatePartnerScopedConversations(fromId);
    _invalidatePartnerScopedConversations(toId);
    ref.invalidate(partnerListProvider);
    // A2 transition contract — retired in the post-A2 cleanup PR once
    // reportDataProvider migrates off the global feed.
    ref.invalidate(conversationsProvider);
  }
}

final partnerWriteControllerProvider =
    NotifierProvider<PartnerWriteController, void>(
  PartnerWriteController.new,
);
