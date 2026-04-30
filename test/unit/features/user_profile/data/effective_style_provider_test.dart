import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/user_profile/data/providers/partner_style_providers.dart';
import 'package:vibesync/features/user_profile/data/providers/user_profile_providers.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_style_repository.dart';
import 'package:vibesync/features/user_profile/data/repositories/user_profile_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

class _FakeUserProfileRepo implements UserProfileRepository {
  final Map<String, UserProfile> byOwner = {};

  @override
  Future<UserProfile?> load(String uid) async => byOwner[uid];

  @override
  Future<void> save(UserProfile profile, String uid) async {
    byOwner[uid] = profile;
  }

  @override
  Future<void> clear(String uid) async => byOwner.remove(uid);
}

void main() {
  late Directory tmp;
  late Box<PartnerStyleOverride> box;
  late PartnerStyleRepository styleRepo;
  late _FakeUserProfileRepo userRepo;

  const uid = 'user-a';

  setUpAll(() {
    if (!Hive.isAdapterRegistered(PartnerStyleOverrideAdapter().typeId)) {
      Hive.registerAdapter(PartnerStyleOverrideAdapter());
    }
    if (!Hive.isAdapterRegistered(InteractionStyleAdapter().typeId)) {
      Hive.registerAdapter(InteractionStyleAdapter());
    }
    if (!Hive.isAdapterRegistered(PracticeGoalAdapter().typeId)) {
      Hive.registerAdapter(PracticeGoalAdapter());
    }
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('effective_style_provider');
    Hive.init(tmp.path);
    box = await Hive.openBox<PartnerStyleOverride>(
      'pso_${DateTime.now().microsecondsSinceEpoch}',
    );
    styleRepo = PartnerStyleRepository(box: box);
    userRepo = _FakeUserProfileRepo();
  });

  tearDown(() async {
    await box.close();
    await tmp.delete(recursive: true);
  });

  ProviderContainer makeContainer() => ProviderContainer(overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(styleRepo),
        userProfileRepositoryProvider.overrideWithValue(userRepo),
        authUserProfileScopeProvider.overrideWith((ref) => Stream.value(uid)),
      ]);

  final ts = DateTime.utc(2026, 5, 1);

  test('falls back to global when no partner override', () async {
    userRepo.byOwner[uid] = UserProfile.create(
      interactionStyle: InteractionStyle.steady,
      practiceGoals: const [PracticeGoal.softInvite],
      notes: 'global notes',
      updatedAt: ts,
    );
    final container = makeContainer();
    addTearDown(container.dispose);

    // Settle async deps so the family resolver can read .valueOrNull.
    await container.read(authUserProfileScopeProvider.future);
    await container.read(userProfileControllerProvider.future);
    await container.read(partnerStyleOverrideProvider('p1').future);

    final eff = container.read(effectiveStyleProvider('p1'));
    expect(eff.interactionStyle, InteractionStyle.steady);
    expect(eff.practiceGoals, [PracticeGoal.softInvite]);
    expect(eff.notes, 'global notes');
  });

  test('partner override takes precedence per-field', () async {
    userRepo.byOwner[uid] = UserProfile.create(
      interactionStyle: InteractionStyle.steady,
      practiceGoals: const [PracticeGoal.softInvite],
      notes: 'global notes',
      updatedAt: ts,
    );
    await styleRepo.save(PartnerStyleOverride.create(
      partnerId: 'p1',
      interactionStyle: InteractionStyle.humorous,
      updatedAt: ts,
    ));
    final container = makeContainer();
    addTearDown(container.dispose);

    await container.read(authUserProfileScopeProvider.future);
    await container.read(userProfileControllerProvider.future);
    await container.read(partnerStyleOverrideProvider('p1').future);

    final eff = container.read(effectiveStyleProvider('p1'));
    expect(eff.interactionStyle, InteractionStyle.humorous);
    expect(eff.practiceGoals, [PracticeGoal.softInvite]);
    expect(eff.notes, 'global notes');
  });

  test('saving a new override invalidates effective style', () async {
    userRepo.byOwner[uid] = UserProfile.create(
      interactionStyle: InteractionStyle.steady,
      updatedAt: ts,
    );
    final container = makeContainer();
    addTearDown(container.dispose);

    await container.read(authUserProfileScopeProvider.future);
    await container.read(userProfileControllerProvider.future);
    await container.read(partnerStyleOverrideProvider('p1').future);

    final before = container.read(effectiveStyleProvider('p1'));
    expect(before.interactionStyle, InteractionStyle.steady);

    await container
        .read(partnerStyleOverrideProvider('p1').notifier)
        .save(PartnerStyleOverride.create(
          partnerId: 'p1',
          interactionStyle: InteractionStyle.gentle,
          updatedAt: ts,
        ));

    final after = container.read(effectiveStyleProvider('p1'));
    expect(after.interactionStyle, InteractionStyle.gentle);
  });

  test('returns all-null when global and partner are both empty', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    await container.read(authUserProfileScopeProvider.future);
    await container.read(userProfileControllerProvider.future);
    await container.read(partnerStyleOverrideProvider('p1').future);

    final eff = container.read(effectiveStyleProvider('p1'));
    expect(eff.interactionStyle, isNull);
    expect(eff.practiceGoals, isEmpty);
    expect(eff.notes, isNull);
  });
}
