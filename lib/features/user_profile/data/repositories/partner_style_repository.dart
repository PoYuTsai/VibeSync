import 'package:hive_ce/hive_ce.dart';

import '../../../../core/services/storage_service.dart';
import '../../domain/entities/partner_style_override.dart';

/// Per-partner local store for the Spec 2 style override.
///
/// Keyed directly by `partnerId` (no account prefix) — Partner storage is
/// device-local, so overrides follow the same scope. Account-clear is
/// covered by [StorageService.clearAll]; per-partner cleanup on partner
/// deletion is wired by `PartnerRepository.delete` (cascade).
class PartnerStyleRepository {
  PartnerStyleRepository({Box<PartnerStyleOverride>? box})
      : _box = box ?? StorageService.partnerStyleOverridesBox;

  final Box<PartnerStyleOverride> _box;

  Future<PartnerStyleOverride?> load(String partnerId) async =>
      _box.get(partnerId);

  /// Persists [override]. If [override] has no fields set ([isEmpty]),
  /// deletes the row instead so an "all-default" partner never leaves
  /// behind an empty record that would defeat the inline card's
  /// "沿用全域預設 / 已自訂風格" two-state subtitle.
  Future<void> save(PartnerStyleOverride override) async {
    if (override.isEmpty) {
      await _box.delete(override.partnerId);
    } else {
      await _box.put(override.partnerId, override);
    }
  }

  Future<void> delete(String partnerId) async {
    await _box.delete(partnerId);
  }

  Future<void> clearAll() async {
    await _box.clear();
  }
}
