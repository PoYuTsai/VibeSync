import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/user_profile/data/providers/user_profile_providers.dart';
import 'package:vibesync/features/user_profile/data/repositories/user_profile_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

class _FakeRepo implements UserProfileRepository {
  final Map<String, UserProfile> byOwner = {};
  int saveCount = 0;
  int clearCount = 0;
  bool throwOnSave = false;

  @override
  Future<UserProfile?> load(String ownerUserId) async => byOwner[ownerUserId];

  @override
  Future<void> save(UserProfile profile, String ownerUserId) async {
    if (throwOnSave) throw Exception('boom');
    byOwner[ownerUserId] = profile;
    saveCount++;
  }

  @override
  Future<void> clear(String ownerUserId) async {
    byOwner.remove(ownerUserId);
    clearCount++;
  }
}

ProviderContainer _container({
  required _FakeRepo repo,
  required String? uid,
}) {
  return ProviderContainer(overrides: [
    userProfileRepositoryProvider.overrideWithValue(repo),
    authUserProfileScopeProvider.overrideWith((ref) => Stream.value(uid)),
  ]);
}

void main() {
  const userA = 'user-a-uuid';
  const userB = 'user-b-uuid';

  test('initial load with empty repo emits null state', () async {
    final repo = _FakeRepo();
    final c = _container(repo: repo, uid: userA);
    addTearDown(c.dispose);

    final state = await c.read(userProfileControllerProvider.future);
    expect(state, isNull);
  });

  test('save() persists per-owner profile and updates state', () async {
    final repo = _FakeRepo();
    final c = _container(repo: repo, uid: userA);
    addTearDown(c.dispose);

    await c.read(userProfileControllerProvider.future);
    await c.read(userProfileControllerProvider.notifier).save(
          UserProfile.create(
            interactionStyle: InteractionStyle.humorous,
            updatedAt: DateTime.utc(2026, 4, 30),
          ),
        );

    expect(repo.saveCount, 1);
    expect(repo.byOwner[userA]?.interactionStyle, InteractionStyle.humorous);
    expect(repo.byOwner[userB], isNull);
    expect(c.read(userProfileControllerProvider).value?.interactionStyle,
        InteractionStyle.humorous);
  });

  test('clear() removes profile for current owner only', () async {
    final repo = _FakeRepo();
    repo.byOwner[userA] = UserProfile.create(
      interactionStyle: InteractionStyle.steady,
      updatedAt: DateTime.utc(2026, 4, 29),
    );
    repo.byOwner[userB] = UserProfile.create(
      interactionStyle: InteractionStyle.playful,
      updatedAt: DateTime.utc(2026, 4, 29),
    );

    final c = _container(repo: repo, uid: userA);
    addTearDown(c.dispose);

    await c.read(userProfileControllerProvider.future);
    await c.read(userProfileControllerProvider.notifier).clear();

    expect(repo.byOwner[userA], isNull);
    expect(repo.byOwner[userB], isNotNull,
        reason: 'clearing A must not touch B');
    expect(c.read(userProfileControllerProvider).value, isNull);
  });

  test('save failure surfaces as exception, state preserved', () async {
    final repo = _FakeRepo()..throwOnSave = true;
    final c = _container(repo: repo, uid: userA);
    addTearDown(c.dispose);

    await c.read(userProfileControllerProvider.future);
    await expectLater(
      c.read(userProfileControllerProvider.notifier).save(
            UserProfile.create(
              interactionStyle: InteractionStyle.gentle,
              updatedAt: DateTime.utc(2026, 4, 30),
            ),
          ),
      throwsException,
    );
  });

  test('save() throws StateError when no authenticated user', () async {
    final repo = _FakeRepo();
    final c = _container(repo: repo, uid: null);
    addTearDown(c.dispose);

    await c.read(userProfileControllerProvider.future);
    await expectLater(
      c.read(userProfileControllerProvider.notifier).save(
            UserProfile.create(
              interactionStyle: InteractionStyle.gentle,
              updatedAt: DateTime.utc(2026, 4, 30),
            ),
          ),
      throwsA(isA<StateError>()),
    );
  });
}
