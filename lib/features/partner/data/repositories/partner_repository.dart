// lib/features/partner/data/repositories/partner_repository.dart
import 'package:hive_ce/hive_ce.dart';
import '../../../../core/services/storage_service.dart';
import '../../../conversation/domain/entities/conversation.dart';
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
class PartnerRepository {
  PartnerRepository({
    Box<Partner>? box,
    Box<Conversation>? conversationBox,
  })  : _box = box ?? StorageService.partnersBox,
        _injectedConversationBox = conversationBox;

  final Box<Partner> _box;
  final Box<Conversation>? _injectedConversationBox;

  // Lazy so callers that never invoke `merge` (e.g. the A1 migration path
  // and its tests) don't pay for opening the conversations box.
  Box<Conversation> get _conversationBox =>
      _injectedConversationBox ?? StorageService.conversationsBox;

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
}
