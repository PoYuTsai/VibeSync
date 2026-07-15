import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../analysis/data/providers/analysis_record_providers.dart';
import '../../../conversation/data/providers/conversation_providers.dart';
import '../../../user_profile/data/providers/data_quality_flag_provider.dart';
import '../../../user_profile/data/providers/partner_style_providers.dart';
import '../../domain/entities/partner.dart';
import '../../presentation/providers/partner_providers.dart';
import '../services/partner_id_factory.dart';

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
    final ownerUserId = ref.read(analysisRecordOwnerProvider)?.trim();
    final fromOwner = repo.getById(fromId)?.ownerUserId?.trim();
    final toOwner = repo.getById(toId)?.ownerUserId?.trim();
    final canMovePrivateMetadata = ownerUserId != null &&
        ownerUserId.isNotEmpty &&
        fromOwner == ownerUserId &&
        toOwner == ownerUserId;
    Object? operationError;
    StackTrace? operationStackTrace;
    try {
      await repo.merge(fromId: fromId, toId: toId);
    } catch (error, stackTrace) {
      operationError = error;
      operationStackTrace = stackTrace;
    }
    try {
      final primaryMergeCommitted =
          repo.getById(fromId) == null && repo.getById(toId) != null;
      if (canMovePrivateMetadata && primaryMergeCommitted) {
        await ref.read(analysisRecordStoreProvider).mergePartnerMetadata(
              ownerUserId: ownerUserId,
              fromPartnerId: fromId,
              toPartnerId: toId,
            );
      }
    } catch (error, stackTrace) {
      operationError ??= error;
      operationStackTrace ??= stackTrace;
    } finally {
      // Repo merge is multi-step Hive I/O. If it throws after a partial write,
      // invalidate anyway so the UI reflects the real local state.
      _invalidateMergeScopes(fromId, toId);
    }
    if (operationError != null) {
      Error.throwWithStackTrace(
        operationError,
        operationStackTrace ?? StackTrace.current,
      );
    }
  }

  /// Deletes [partner] via the repo, then invalidates partner-scoped caches.
  /// Mirrors merge's try/finally discipline so a thrown
  /// `PartnerHasConversationsException` still refreshes UI state. Unlike
  /// merge, this does NOT invalidate `conversationsProvider` — successful
  /// delete only happens at zero conversations, so the global feed is
  /// guaranteed unchanged.
  Future<void> delete(Partner partner) async {
    final repo = ref.read(partnerRepositoryProvider);
    final ownerUserId = ref.read(analysisRecordOwnerProvider)?.trim();
    final canRemovePrivateMetadata = ownerUserId != null &&
        ownerUserId.isNotEmpty &&
        partner.ownerUserId?.trim() == ownerUserId;
    Object? operationError;
    StackTrace? operationStackTrace;
    try {
      await repo.delete(partner.id);
    } catch (error, stackTrace) {
      operationError = error;
      operationStackTrace = stackTrace;
    }
    try {
      if (canRemovePrivateMetadata && repo.getById(partner.id) == null) {
        await ref.read(analysisRecordStoreProvider).removePartnerMetadata(
              ownerUserId: ownerUserId,
              partnerId: partner.id,
            );
      }
    } catch (error, stackTrace) {
      operationError ??= error;
      operationStackTrace ??= stackTrace;
    } finally {
      _invalidateDeleteScopes(partner.id);
    }
    if (operationError != null) {
      Error.throwWithStackTrace(
        operationError,
        operationStackTrace ?? StackTrace.current,
      );
    }
  }

  /// Renames [partner] to [newName] (whitespace trimmed). Throws
  /// [ArgumentError] when the trimmed name is empty so callers don't have to
  /// re-validate. Same try/finally discipline as merge/delete so partial
  /// failures still surface in the UI; no conversation-scope invalidation
  /// because a rename never mutates conversation rows.
  ///
  /// Builds a fresh [Partner] instead of mutating [partner] in place so a
  /// repo throw can't leak the new name through Riverpod's cached reference
  /// (HiveObject is shared by cache + box, so in-place mutation = silent
  /// global write before the persistence step).
  Future<void> updateName(Partner partner, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError(
        'PartnerWriteController.updateName: name must be non-empty',
      );
    }
    final repo = ref.read(partnerRepositoryProvider);
    final renamed = Partner(
      id: partner.id,
      name: trimmed,
      avatarPath: partner.avatarPath,
      createdAt: partner.createdAt,
      updatedAt: partner.updatedAt,
      ownerUserId: partner.ownerUserId,
      customNote: partner.customNote,
    );
    try {
      await repo.update(renamed);
    } finally {
      _invalidateRenameScopes(partner.id);
    }
  }

  /// Updates the partner-level free-form note used by PartnerSummaryBuilder.
  /// Empty / whitespace-only input clears the note. This is partner-scoped
  /// context, not per-conversation session context.
  Future<void> updateCustomNote(Partner partner, String note) async {
    final trimmed = note.trim();
    final repo = ref.read(partnerRepositoryProvider);
    final updated = Partner(
      id: partner.id,
      name: partner.name,
      avatarPath: partner.avatarPath,
      createdAt: partner.createdAt,
      updatedAt: partner.updatedAt,
      ownerUserId: partner.ownerUserId,
      customNote: trimmed.isEmpty ? null : trimmed,
    );
    try {
      await repo.update(updated);
    } finally {
      _invalidatePartnerNoteScopes(partner.id);
    }
  }

  /// Splits [sourcePartnerId] by reparenting [matchedConversationIds] to a
  /// fresh partner named [newPartnerName]. Same try/finally invalidation
  /// discipline as merge/delete so a thrown ArgumentError (empty list, missing
  /// source) still refreshes UI state.
  ///
  /// Spec 3 Phase 5 Task 21 — backs the "拆成新對象" banner action.
  Future<void> split({
    required String sourcePartnerId,
    required String newPartnerName,
    required List<String> matchedConversationIds,
  }) async {
    final repo = ref.read(partnerRepositoryProvider);
    String? newId;
    try {
      newId = await repo.split(
        sourcePartnerId: sourcePartnerId,
        newPartnerName: newPartnerName,
        matchedConversationIds: matchedConversationIds,
        idGenerator: PartnerIdFactory.generate,
      );
    } finally {
      _invalidateSplitScopes(sourcePartnerId, newId);
    }
  }

  void _invalidatePartner(String id) {
    ref.invalidate(partnerByIdProvider(id));
    ref.invalidate(partnerAggregateProvider(id));
  }

  void _invalidatePartnerScopedConversations(String id) {
    ref.invalidate(conversationsByPartnerProvider(id));
  }

  void _invalidatePartnerStyle(String id) {
    ref.invalidate(partnerStyleOverrideProvider(id));
    ref.invalidate(effectiveStyleProvider(id));
  }

  void _invalidateMergeScopes(String fromId, String toId) {
    _invalidatePartner(fromId);
    _invalidatePartner(toId);
    _invalidatePartnerScopedConversations(fromId);
    _invalidatePartnerScopedConversations(toId);
    _invalidatePartnerStyle(fromId);
    ref.invalidate(partnerListProvider);
    // A2 transition contract — retired in the post-A2 cleanup PR once
    // reportDataProvider migrates off the global feed.
    ref.invalidate(conversationsProvider);
  }

  void _invalidateDeleteScopes(String id) {
    _invalidatePartner(id);
    _invalidatePartnerScopedConversations(id);
    _invalidatePartnerStyle(id);
    ref.invalidate(partnerListProvider);
  }

  void _invalidateSplitScopes(String sourceId, String? newId) {
    _invalidatePartner(sourceId);
    _invalidatePartnerScopedConversations(sourceId);
    if (newId != null) {
      _invalidatePartner(newId);
      _invalidatePartnerScopedConversations(newId);
    }
    ref.invalidate(partnerListProvider);
    // A2 transition contract — same as merge.
    ref.invalidate(conversationsProvider);
    // Banner re-evaluates with one fewer conflicting candidate on source.
    ref.invalidate(dataQualityFlagProvider(sourceId));
  }

  void _invalidateRenameScopes(String id) {
    // Rename only mutates `partner.name` + `updatedAt`; conversation rows are
    // unchanged. Keep invalidation tight so the global feed and per-partner
    // conversation list don't re-query for nothing.
    _invalidatePartner(id);
    ref.invalidate(partnerListProvider);
  }

  void _invalidatePartnerNoteScopes(String id) {
    _invalidatePartner(id);
    ref.invalidate(partnerListProvider);
  }
}

final partnerWriteControllerProvider =
    NotifierProvider<PartnerWriteController, void>(
  PartnerWriteController.new,
);
