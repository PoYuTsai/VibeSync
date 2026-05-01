import 'package:hive_ce/hive_ce.dart';

import '../../../../core/services/storage_service.dart';
import '../../domain/entities/partner_data_quality_state.dart';
import 'partner_data_quality_repo_view.dart';

/// Per-partner local store for the Spec 3 data-quality state (confirmed
/// "same person" name pairs).
///
/// Keyed directly by `partnerId` (no account prefix) — Partner storage is
/// device-local, so quality state follows the same scope. Account-clear is
/// covered by [StorageService.clearAll]; per-partner cleanup on partner
/// deletion will be wired by `PartnerRepository.delete` (cascade) in
/// Phase 3 Tasks 11–13.
///
/// This class implements [PartnerDataQualityRepoView] so it can be injected
/// directly into [PartnerContextResolver] without an adapter shim.
class PartnerDataQualityRepository implements PartnerDataQualityRepoView {
  PartnerDataQualityRepository({Box<PartnerDataQualityState>? injectedBox})
      : _injectedBox = injectedBox;

  final Box<PartnerDataQualityState>? _injectedBox;
  Box<PartnerDataQualityState> get _box =>
      _injectedBox ?? StorageService.partnerDataQualityStatesBox;

  /// Returns the stored state for [partnerId], or an empty placeholder if
  /// nothing is persisted yet. Never returns null so callers can treat the
  /// result uniformly.
  PartnerDataQualityState load(String partnerId) =>
      _box.get(partnerId) ??
      PartnerDataQualityState.empty(partnerId, updatedAt: DateTime.now());

  Future<void> save(PartnerDataQualityState state) async {
    await _box.put(state.partnerId, state);
  }

  Future<void> delete(String partnerId) async {
    await _box.delete(partnerId);
  }

  /// Records that the user confirmed [pair] is the same person under
  /// [partnerId]. Read-then-write via [PartnerDataQualityState.withConfirmed]
  /// so duplicate pairs are de-duped at the entity level.
  Future<void> markSamePerson(String partnerId, NamePair pair) async {
    final current = load(partnerId);
    final updated = current.withConfirmed(pair, at: DateTime.now());
    await save(updated);
  }

  /// Read-only flag check — used by [PartnerContextResolver].
  ///
  /// Phase 4 Task 16 (`dataQualityFlagProvider`) drives the real detection
  /// via the provider layer in `analysis_providers.dart`. Here we ALWAYS
  /// return `false` so Phase 1's gating tests continue to pass — the
  /// resolver currently treats every partner as "not flagged" until the
  /// provider-backed view is wired in Phase 4.
  @override
  bool isFlaggedUnresolved(String partnerId) {
    return false;
  }
}
