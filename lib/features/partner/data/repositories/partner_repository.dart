// lib/features/partner/data/repositories/partner_repository.dart
import 'package:hive_ce/hive_ce.dart';
import '../../../../core/services/storage_service.dart';
import '../../domain/entities/partner.dart';

/// Thin Hive-backed CRUD facade for `Partner` entities.
///
/// A1 only exposes the surface that the migration uses:
/// - [upsertIfAbsent] — idempotency primitive: same `partnerId` second time
///   in is a no-op, never overwrites a row that the migration already wrote.
/// - [getById]
///
/// Full CRUD + `merge()` lands in A2 once the Partner-first UI exists.
class PartnerRepository {
  PartnerRepository({Box<Partner>? box})
      : _box = box ?? StorageService.partnersBox;

  final Box<Partner> _box;

  Partner? getById(String id) => _box.get(id);

  /// Inserts [partner] only if no partner with the same id exists.
  /// Returns `true` if inserted, `false` if a row already existed.
  Future<bool> upsertIfAbsent(Partner partner) async {
    if (_box.containsKey(partner.id)) return false;
    await _box.put(partner.id, partner);
    return true;
  }
}
