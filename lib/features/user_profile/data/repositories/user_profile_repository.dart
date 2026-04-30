import 'package:hive_ce/hive_ce.dart';

import '../../../../core/services/storage_service.dart';
import '../../domain/entities/user_profile.dart';

/// Per-account local store for the global About Me profile.
///
/// Storage key is `profile:<ownerUserId>` — one record per Supabase account.
/// Switching accounts on the same device must not leak About Me across
/// users; see `user_profile_repository_test.dart` privacy tests.
///
/// Box is encrypted by the same AES key used for Conversation / Partner.
class UserProfileRepository {
  UserProfileRepository({Box<UserProfile>? box})
      : _box = box ?? StorageService.userProfileBox;

  final Box<UserProfile> _box;

  static String _keyFor(String ownerUserId) {
    if (ownerUserId.isEmpty) {
      throw ArgumentError('ownerUserId must not be empty');
    }
    return 'profile:$ownerUserId';
  }

  Future<UserProfile?> load(String ownerUserId) async =>
      _box.get(_keyFor(ownerUserId));

  Future<void> save(UserProfile profile, String ownerUserId) async {
    await _box.put(_keyFor(ownerUserId), profile);
  }

  Future<void> clear(String ownerUserId) async {
    await _box.delete(_keyFor(ownerUserId));
  }
}
