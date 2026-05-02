import 'package:hive_ce/hive_ce.dart';

import '../../domain/entities/coach_follow_up_result.dart';
import '../../domain/repositories/coach_follow_up_repository.dart';

/// Hive-backed `CoachFollowUpRepository`. Box is keyed directly by
/// `partnerId` so `get` / `delete` are O(1) and `put` enforces latest-only
/// semantics implicitly (writing the same key overwrites).
///
/// The box itself is owned by `StorageService` (B14) — this impl just wraps
/// the typed `Box<CoachFollowUpResult>` so providers can inject a fake or
/// in-memory box in tests without touching Hive bootstrap.
class CoachFollowUpRepositoryImpl implements CoachFollowUpRepository {
  CoachFollowUpRepositoryImpl(this._box);

  final Box<CoachFollowUpResult> _box;

  @override
  CoachFollowUpResult? get(String partnerId) => _box.get(partnerId);

  @override
  Future<void> put(CoachFollowUpResult result) async {
    await _box.put(result.partnerId, result);
  }

  @override
  Future<void> delete(String partnerId) async {
    await _box.delete(partnerId);
  }

  @override
  Future<void> clearAll() async {
    await _box.clear();
  }
}
