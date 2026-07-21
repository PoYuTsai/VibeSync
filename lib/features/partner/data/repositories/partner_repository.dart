// lib/features/partner/data/repositories/partner_repository.dart
import 'package:hive_ce/hive_ce.dart';
import '../../../../core/services/storage_service.dart';
import '../../../coach_chat/domain/entities/unified_coach_result.dart';
import '../../../coach_follow_up/data/repositories/coach_follow_up_repository_impl.dart';
import '../../../coach_follow_up/domain/repositories/coach_follow_up_repository.dart';
import '../../../coaching_memory/data/repositories/coaching_outcome_repository_impl.dart';
import '../../../coaching_memory/domain/repositories/coaching_outcome_repository.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../../opener/data/services/opener_result_cache_service.dart';
import '../../../user_profile/data/repositories/partner_data_quality_repository.dart';
import '../../../user_profile/data/repositories/partner_style_repository.dart';
import '../../domain/entities/partner.dart';
import '../services/partner_id_factory.dart';

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
///   tag, then deletes the source partner and cascades cleanup of its style
///   override (Spec 2), data-quality state (Spec 3), coach follow-up
///   card (Spec 5), and Phase D partner-scope unified coach rows.
///   Coaching outcome events and opener drafts are reassigned
///   to the target instead of deleted. The target partner's per-partner state
///   is never cloned or overwritten. No-op on same id; throws `ArgumentError`
///   if either side is missing (no partial state).
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
    PartnerDataQualityRepository? qualityRepo,
    CoachFollowUpRepository? followUpRepo,
    CoachingOutcomeRepository? outcomeRepo,
  })  : _box = box ?? StorageService.partnersBox,
        _injectedConversationBox = conversationBox,
        _injectedStyleRepo = styleRepo,
        _injectedQualityRepo = qualityRepo,
        _injectedFollowUpRepo = followUpRepo,
        _injectedOutcomeRepo = outcomeRepo;

  final Box<Partner> _box;
  final Box<Conversation>? _injectedConversationBox;
  final PartnerStyleRepository? _injectedStyleRepo;
  final PartnerDataQualityRepository? _injectedQualityRepo;
  final CoachFollowUpRepository? _injectedFollowUpRepo;
  final CoachingOutcomeRepository? _injectedOutcomeRepo;

  // Lazy so callers that never invoke `merge` (e.g. the A1 migration path
  // and its tests) don't pay for opening the conversations box.
  Box<Conversation> get _conversationBox =>
      _injectedConversationBox ?? StorageService.conversationsBox;

  // Lazy for the same reason — partner_style_overrides box only needs to be
  // open when delete() runs the Spec 2 cascade.
  PartnerStyleRepository get _styleRepo =>
      _injectedStyleRepo ?? PartnerStyleRepository();

  // Lazy for the same reason — partner_data_quality_states box only needs
  // to be open when delete() runs the Spec 3 cascade.
  PartnerDataQualityRepository get _qualityRepo =>
      _injectedQualityRepo ?? PartnerDataQualityRepository();

  // Lazy for the same reason — coach_follow_up_results box only needs to be
  // open when delete() runs the Spec 5 cascade (B15).
  CoachFollowUpRepository get _followUpRepo =>
      _injectedFollowUpRepo ??
      CoachFollowUpRepositoryImpl(StorageService.coachFollowUpResultsBox);

  CoachingOutcomeRepository get _outcomeRepo =>
      _injectedOutcomeRepo ??
      CoachingOutcomeRepositoryImpl(StorageService.coachingOutcomeEventsBox);

  // Stateless facade over the shared settings box — safe to construct per
  // cascade call, no injection seam needed (Batch 4 #1 opener draft cascade).
  OpenerResultCacheService get _openerDraftCache => OpenerResultCacheService();

  Partner? getById(String id) => _box.get(id);

  List<Partner> listByOwner(String ownerUserId) =>
      _box.values.where((p) => p.ownerUserId == ownerUserId).toList();

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

    await _outcomeRepo.reassignPartner(
        fromPartnerId: fromId, toPartnerId: toId);
    await _openerDraftCache.reassignDraftsPartner(
        fromPartnerId: fromId, toPartnerId: toId);
    await _box.delete(fromId);
    await _styleRepo.delete(fromId);
    await _qualityRepo.delete(fromId);
    await _followUpRepo.delete(fromId);
    await _deleteUnifiedPartnerRows(fromId);
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
  /// On success, also cascades into:
  ///   - Spec 2 `PartnerStyleRepository` — per-partner style overrides
  ///   - Spec 3 `PartnerDataQualityRepository` — name-pair confirmation state
  ///   - Spec 5 `CoachFollowUpRepository` — last generated follow-up card
  ///   - `CoachingOutcomeRepository` — per-partner outcome events
  ///   - `OpenerResultCacheService` — partner-scoped opener drafts
  ///   - Phase D `unified_coach_results` — partner-scope unified coach rows
  /// so none of those rows survive a deleted partner. If the guard throws,
  /// no rows are touched (atomic-failure semantics).
  Future<void> delete(String partnerId) async {
    final convCount =
        _conversationBox.values.where((c) => c.partnerId == partnerId).length;
    if (convCount > 0) {
      throw PartnerHasConversationsException(convCount);
    }
    await _box.delete(partnerId);
    await _styleRepo.delete(partnerId);
    await _qualityRepo.delete(partnerId);
    await _followUpRepo.delete(partnerId);
    await _outcomeRepo.deleteByPartner(partnerId);
    await _openerDraftCache.deleteDraftsForPartner(partnerId);
    await _deleteUnifiedPartnerRows(partnerId);
  }

  /// 教練統一 Phase D：unified box（typeId 26）的 partner-scope rows 跟著
  /// 刪對象／合併來源一起清，否則留下孤兒教練紀錄（隱私縫）。
  /// 比照 `_deleteCoachChatForConversation` 的守門 pattern：box 未開時跳過不炸。
  Future<void> _deleteUnifiedPartnerRows(String partnerId) async {
    if (!Hive.isBoxOpen('unified_coach_results')) {
      return;
    }
    final unifiedBox = StorageService.unifiedCoachResultsBox;
    final ids = unifiedBox.values
        .where(
          (r) => r.scopeType == CoachScopeType.partner && r.scopeId == partnerId,
        )
        .map((r) => r.id)
        .toList(growable: false);
    await Future.wait(ids.map(unifiedBox.delete));
  }

  /// Splits the conversations listed in [matchedConversationIds] off the
  /// partner [sourcePartnerId] onto a freshly-created partner with
  /// [newPartnerName]. Returns the new partner's id.
  ///
  /// Per Spec 3 §6.3 / §7.6:
  ///   - Source partner KEEPS its name, [PartnerStyleOverride], and
  ///     [PartnerDataQualityState] — confirmed "same person" pairs still
  ///     describe the source's history, even after some conversations move.
  ///   - The new partner gets NO style override (so it falls back to the
  ///     global "About Me" defaults — the inline card's "沿用全域預設" state)
  ///     and NO data-quality state (clean slate, no inherited confirmations).
  ///   - Mixed-name / ambiguous conversations stay on source — caller
  ///     pre-filters [matchedConversationIds] to contain only ids it is
  ///     confident about. This method does NO AI judgment and NO name-distance
  ///     filtering; it is a dumb mover, the caller decides what moves.
  ///   - Conversations whose `partnerId` no longer points at [sourcePartnerId]
  ///     are silently skipped (defensive against stale UI handles), so this
  ///     method is safe to retry.
  ///
  /// Throws `ArgumentError` when [matchedConversationIds] is empty (no-op
  /// guard — empty splits never make sense and almost always indicate a
  /// caller bug) or when the source partner is missing (so a stale UI
  /// handle can't silently create an orphaned partner).
  ///
  /// [idGenerator] is an optional test seam; production callers leave it
  /// `null` and get [PartnerIdFactory.generate] (UUID v4).
  Future<String> split({
    required String sourcePartnerId,
    required String newPartnerName,
    required List<String> matchedConversationIds,
    String Function()? idGenerator,
  }) async {
    if (matchedConversationIds.isEmpty) {
      throw ArgumentError(
        'PartnerRepository.split: matchedConversationIds must be non-empty',
      );
    }
    final source = _box.get(sourcePartnerId);
    if (source == null) {
      throw ArgumentError(
        'PartnerRepository.split: source partner $sourcePartnerId not found',
      );
    }

    final generate = idGenerator ?? PartnerIdFactory.generate;
    final newId = generate();
    final now = DateTime.now();
    final newPartner = Partner(
      id: newId,
      name: newPartnerName,
      ownerUserId: source.ownerUserId,
      createdAt: now,
      updatedAt: now,
    );
    await _box.put(newId, newPartner);

    for (final convId in matchedConversationIds) {
      final c = _conversationBox.get(convId);
      if (c != null && c.partnerId == sourcePartnerId) {
        c.partnerId = newId;
        await c.save();
      }
    }

    // Intentional non-cascade:
    //   - Style override stays on source (per design G3 — override describes
    //     the source's persona, the new partner starts on global defaults).
    //   - Data-quality state stays on source (per §7.6 — confirmed pairs still
    //     describe the source's history).
    return newId;
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
