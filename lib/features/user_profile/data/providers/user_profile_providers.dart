import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/supabase_service.dart';
import '../../domain/entities/user_profile.dart';
import '../repositories/user_profile_repository.dart';

/// Mirrors `authConversationScopeProvider` (conversation_providers.dart:14)
/// — when the Supabase user changes, downstream providers automatically
/// rebuild against the new scope.
final authUserProfileScopeProvider = StreamProvider<String?>((ref) async* {
  yield SupabaseService.currentUser?.id;
  yield* SupabaseService.authStateChanges
      .map((authState) => authState.session?.user.id);
});

final userProfileRepositoryProvider = Provider<UserProfileRepository>((ref) {
  return UserProfileRepository();
});

final userProfileControllerProvider =
    AsyncNotifierProvider<UserProfileController, UserProfile?>(
  UserProfileController.new,
);

class UserProfileController extends AsyncNotifier<UserProfile?> {
  @override
  Future<UserProfile?> build() async {
    final uid = await ref.watch(authUserProfileScopeProvider.future);
    if (uid == null) return null;
    final repo = ref.read(userProfileRepositoryProvider);
    return repo.load(uid);
  }

  Future<void> save(UserProfile profile) async {
    final uid = await ref.read(authUserProfileScopeProvider.future);
    if (uid == null) {
      throw StateError('No authenticated user; cannot save About Me profile');
    }
    final repo = ref.read(userProfileRepositoryProvider);
    await repo.save(profile, uid);
    state = AsyncData(profile);
  }

  Future<void> clear() async {
    final uid = await ref.read(authUserProfileScopeProvider.future);
    if (uid == null) {
      throw StateError('No authenticated user; cannot clear About Me profile');
    }
    final repo = ref.read(userProfileRepositoryProvider);
    await repo.clear(uid);
    state = const AsyncData(null);
  }
}
