import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/user_profile/data/repositories/user_profile_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

void main() {
  late Directory tmp;
  late Box<UserProfile> box;
  late UserProfileRepository repo;

  setUpAll(() async {
    if (!Hive.isAdapterRegistered(UserProfileAdapter().typeId)) {
      Hive.registerAdapter(UserProfileAdapter());
      Hive.registerAdapter(InteractionStyleAdapter());
      Hive.registerAdapter(PracticeGoalAdapter());
      Hive.registerAdapter(TopicSeedAdapter());
    }
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('user_profile_repo_test');
    Hive.init(tmp.path);
    box = await Hive.openBox<UserProfile>(
        'test_repo_${DateTime.now().microsecondsSinceEpoch}');
    repo = UserProfileRepository(box: box);
  });

  tearDown(() async {
    await box.close();
    await tmp.delete(recursive: true);
  });

  const userA = 'user-a-uuid';
  const userB = 'user-b-uuid';

  test('load() returns null when box is empty', () async {
    expect(await repo.load(userA), isNull);
  });

  test('save() then load() returns same profile for same owner', () async {
    final p = UserProfile.create(
      interactionStyle: InteractionStyle.direct,
      updatedAt: DateTime.utc(2026, 4, 30),
    );
    await repo.save(p, userA);
    final loaded = await repo.load(userA);
    expect(loaded?.interactionStyle, InteractionStyle.direct);
  });

  test('save() overwrites previous profile for same owner', () async {
    await repo.save(
      UserProfile.create(
        interactionStyle: InteractionStyle.gentle,
        updatedAt: DateTime.utc(2026, 4, 29),
      ),
      userA,
    );
    await repo.save(
      UserProfile.create(
        interactionStyle: InteractionStyle.playful,
        updatedAt: DateTime.utc(2026, 4, 30),
      ),
      userA,
    );
    final loaded = await repo.load(userA);
    expect(loaded?.interactionStyle, InteractionStyle.playful);
  });

  test('clear() removes the profile for that owner', () async {
    await repo.save(
      UserProfile.create(
        interactionStyle: InteractionStyle.steady,
        updatedAt: DateTime.utc(2026, 4, 30),
      ),
      userA,
    );
    await repo.clear(userA);
    expect(await repo.load(userA), isNull);
  });

  test('clear() on empty box is no-op', () async {
    await repo.clear(userA);
    expect(await repo.load(userA), isNull);
  });

  // === Codex P1: privacy / trust boundary ===
  test('save() under owner A is invisible to owner B', () async {
    await repo.save(
      UserProfile.create(
        interactionStyle: InteractionStyle.gentle,
        practiceGoals: const [PracticeGoal.softInvite],
        notes: 'A 的私密 coach memo',
        updatedAt: DateTime.utc(2026, 4, 30),
      ),
      userA,
    );

    expect(await repo.load(userA), isNotNull);
    expect(await repo.load(userB), isNull,
        reason: 'B must NOT see A\'s About Me — privacy boundary');
  });

  test('clear(A) leaves B\'s profile intact', () async {
    await repo.save(
      UserProfile.create(
        interactionStyle: InteractionStyle.direct,
        updatedAt: DateTime.utc(2026, 4, 30),
      ),
      userA,
    );
    await repo.save(
      UserProfile.create(
        interactionStyle: InteractionStyle.humorous,
        updatedAt: DateTime.utc(2026, 4, 30),
      ),
      userB,
    );

    await repo.clear(userA);

    expect(await repo.load(userA), isNull);
    expect((await repo.load(userB))?.interactionStyle, InteractionStyle.humorous);
  });

  test('save rejects empty ownerUserId', () async {
    expect(
      () => repo.save(
        UserProfile.create(
          interactionStyle: InteractionStyle.steady,
          updatedAt: DateTime.utc(2026, 4, 30),
        ),
        '',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
