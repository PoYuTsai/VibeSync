// lib/features/partner/data/repositories/partner_repository.dart
import 'package:hive_ce/hive_ce.dart';
import '../../../../core/services/storage_service.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../../user_profile/data/repositories/partner_style_repository.dart';
import '../../domain/entities/partner.dart';

/// Hive-backed CRUD facade for `Partner` entities.
///
/// A1 surface (kept stable):
/// - [upsertIfAbsent] — idempotency primitive used by the migration.
/// - [getById]
///
/// A2 surface (added for Partner-first UI):
/// - [listByOwner] — owner-scoped query for the home Partner list.
/// - [merge] — re-points all conversations of `fromId` to `toId`, appends
///   the source partner's `customNote` into the target with a `[from <name>]`
///   tag, then deletes the source partner. No-op on same id; throws
///   `ArgumentError` if either side is missing (no partial state).
/// - [delete] — removes a partner row, but only after confirming zero
///   conversations still reference it. Throws
///   [PartnerHasConversationsException] otherwise; UI must surface this and
///   guide the user toward merge / reassign instead of cascade-delete.
/// - [update] — overwrites an existing partner row and bumps `updatedAt`.
///   Throws `ArgumentError` if the id is unknown (so a stale UI handle can't
///   silently resurrect a deleted partner).
class PartnerRepository {
  PartnerRepository({
    Box<Partner>? box,
    Box<Conversation>? conversationBox,
    PartnerStyleRepository? styleRepo,
  })  : _box = box ?? StorageService.partnersBox,
        _injectedConversationBox = conversationBox,
        _injectedStyleRepo = styleRepo;

  final Box<Partner> _box;
  final Box<Conversation>? _injectedConversationBox;
  final PartnerStyleRepository? _injectedStyleRepo;

  // Lazy so callers that never invoke `merge` (e.g. the A1 migration path
  // and its tests) don't pay for opening the conversations box.
  Box<Conversation> get _conversationBox =>
      _injectedConversationBox ?? StorageService.conversationsBox;

  // Lazy for the same reason — partner_style_overrides box only needs to be
  // open when delete() runs the Spec 2 cascade.
  PartnerStyleRepository get _styleRepo =>
      _injectedStyleRepo ?? PartnerStyleRepository();

  Partner? getById(String id) => _box.get(id);

  List<Partner> listByOwner(String ownerUserId) => _box.values
      .where((p) => p.ownerUserId == ownerUserId)
      .toList();

  /// Inserts [partner] only if no partner with the same id exists.
  /// Returns `true` if inserted, `false` if a row already existed.
  Future<bool> upsertIfAbsent(Partner partner) async {
    if (_box.containsKey(partner.id)) return false;
    await _box.put(partner.id, partner);
    return true;
  }

  Future<void> merge({
    required String fromId,
    required String toId,
  }) async {
    if (fromId == toId) return;

    final from = _box.get(fromId);
    final to = _box.get(toId);
    if (from == null || to == null) {
      throw ArgumentError(
        'PartnerRepository.merge: source ($fromId) or target ($toId) not found',
      );
    }

    final conversationsToMove = _conversationBox.values
        .where((c) => c.partnerId == fromId)
        .toList(growable: false);
    for (final c in conversationsToMove) {
      c.partnerId = toId;
      await c.save();
    }

    final fromNote = (from.customNote ?? '').trim();
    if (fromNote.isNotEmpty) {
      final tag = '[from ${from.name}]';
      final existing = (to.customNote ?? '').trim();
      to.customNote =
          existing.isEmpty ? '$tag $fromNote' : '$existing\n$tag $fromNote';
    }
    to.updatedAt = DateTime.now();
    await to.save();

    await _box.delete(fromId);
  }

  /// Overwrites the existing row for [partner.id] and bumps `updatedAt` to
  /// "now". Caller is responsible for any field-level validation (e.g. a
  /// non-empty name); this method only enforces existence so a stale UI
  /// handle can't silently resurrect a deleted partner.
  Future<void> update(Partner partner) async {
    if (!_box.containsKey(partner.id)) {
      throw ArgumentError(
        'PartnerRepository.update: partner ${partner.id} not found',
      );
    }
    partner.updatedAt = DateTime.now();
    await _box.put(partner.id, partner);
  }

  /// Deletes [partnerId] from the partners box, **only** when no conversation
  /// row still references it. Counts conversations directly from the box
  /// (not via `aggregate.totalRounds`) so a zero-round conversation still
  /// blocks the delete.
  ///
  /// On success, also cascades into the Spec 2 `PartnerStyleRepository` so
  /// per-partner style overrides do not survive a deleted partner. If the
  /// guard throws, no rows are touched (atomic-failure semantics).
  Future<void> delete(String partnerId) async {
    final convCount = _conversationBox.values
        .where((c) => c.partnerId == partnerId)
        .length;
    if (convCount > 0) {
      throw PartnerHasConversationsException(convCount);
    }
    await _box.delete(partnerId);
    await _styleRepo.delete(partnerId);
  }
}

/// Thrown by [PartnerRepository.delete] when the partner still has
/// conversations linked. Caller must surface this as informational UI and
/// guide the user toward merge / reassign instead of cascade-deleting.
class PartnerHasConversationsException implements Exception {
  PartnerHasConversationsException(this.conversationCount);
  final int conversationCount;

  @override
  String toString() =>
      'PartnerHasConversationsException(count=$conversationCount)';
}
